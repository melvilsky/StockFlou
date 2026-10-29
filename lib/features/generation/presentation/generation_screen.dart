import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:collection/collection.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_secure_bookmarks/macos_secure_bookmarks.dart';
import 'package:pool/pool.dart';
import 'package:uuid/uuid.dart';

import '../../../core/state/upload_queue_provider.dart';
import '../../../models/upload_job.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/metadata_service.dart';
import '../../../core/services/geocoding_service.dart';
import '../../../core/services/csv_metadata_service.dart';
import '../../../core/state/editorial_state_provider.dart';
import '../../../core/state/files_provider.dart';
import '../../../core/state/settings_provider.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/state/active_grid_selection_provider.dart';
import '../../folder_navigation/domain/folder_access.dart';
import '../../organization/application/organization_providers.dart';
import '../../organization_search/application/organization_search_providers.dart';

import 'video_player_widget.dart';
import '../../../core/state/workspaces_provider.dart';
import '../../../models/app_file.dart';
import '../../../models/generation_options.dart';
import '../../../models/workflow_status.dart';
import '../domain/generation_tags.dart';
import '../domain/metadata_generation_operation.dart';
import '../../../core/services/qc_checker.dart';
import '../../../core/state/active_stocks_provider.dart';
import '../../../core/state/workspace_command_provider.dart';
import '../../../models/qc_report.dart';
import '../../history/presentation/widgets/qc_report_dialog.dart';
import 'widgets/generation_editor_panel.dart';
import 'widgets/generation_scope_bar.dart';
import 'widgets/generation_widgets.dart';
import 'widgets/csv_import_preview_dialog.dart';

/// Mutex to ensure sequential dialog prompts from parallel queue tasks
class _AsyncMutex {
  Future<void>? _lock;

  Future<T> synchronized<T>(Future<T> Function() action) async {
    final completer = Completer<void>();
    final previousLock = _lock;
    _lock = completer.future;

    if (previousLock != null) {
      await previousLock;
    }

    try {
      return await action();
    } finally {
      completer.complete();
    }
  }
}

enum _StagedBatchChoice { apply, discard, stay }

class GenerationScreen extends ConsumerStatefulWidget {
  final ApiClient? apiClient;
  final Future<Map<String, dynamic>> Function({
    required String apiKey,
    required String filePath,
    required GenerationOptions options,
  })?
  generateMetadata;
  final Future<({double? lat, double? lon, DateTime? date, bool hasAudio})>
  Function(String filePath)?
  readExif;
  final Future<({String? city, String? country, String? state})> Function(
    double? lat,
    double? lon,
  )?
  resolveGeo;
  final Future<bool> Function({
    required String filePath,
    required String title,
    required String keywords,
    String? description,
  })?
  writeMetadata;
  final Future<({bool replace, bool applyToAll})?> Function(String filename)?
  showRegenerateDialog;
  final List<File>? initialLocalFiles;

  const GenerationScreen({
    super.key,
    this.apiClient,
    this.generateMetadata,
    this.readExif,
    this.resolveGeo,
    this.writeMetadata,
    this.showRegenerateDialog,
    this.initialLocalFiles,
  });

  @override
  ConsumerState<GenerationScreen> createState() => _GenerationScreenState();
}

class _GenerationScreenState extends ConsumerState<GenerationScreen>
    with WidgetsBindingObserver {
  late final ApiClient _apiClient = widget.apiClient ?? ApiClient();
  bool _isDisposed = false;
  bool get _isLive => mounted && !_isDisposed;

  Future<Map<String, dynamic>> _callGenerateMetadata({
    required String apiKey,
    required String filePath,
    required GenerationOptions options,
  }) {
    if (widget.generateMetadata != null) {
      return widget.generateMetadata!(
        apiKey: apiKey,
        filePath: filePath,
        options: options,
      );
    }
    return _apiClient.generateMetadata(
      apiKey: apiKey,
      filePath: filePath,
      options: options,
    );
  }

  Future<({double? lat, double? lon, DateTime? date, bool hasAudio})> _readExif(
    String path,
  ) {
    if (widget.readExif != null) {
      return widget.readExif!(path);
    }
    return MetadataService.readExifLocationAndDate(path);
  }

  Future<({String? city, String? country, String? state})> _resolveGeo(
    double? lat,
    double? lon,
  ) {
    if (widget.resolveGeo != null) {
      return widget.resolveGeo!(lat, lon);
    }
    return GeocodingService.resolve(lat, lon);
  }

  Future<bool> _writeMetadata({
    required String filePath,
    required String title,
    required String keywords,
    String? description,
    String? city,
    String? country,
    DateTime? shootDate,
  }) {
    if (widget.writeMetadata != null) {
      return widget.writeMetadata!(
        filePath: filePath,
        title: title,
        keywords: keywords,
        description: description,
      );
    }
    return MetadataService.writeMetadata(
      filePath: filePath,
      title: title,
      keywords: keywords,
      description: description,
      city: city,
      country: country,
      shootDate: shootDate,
    );
  }

  Future<({bool replace, bool applyToAll})?> _handleShowRegenerateDialog(
    String filename,
  ) {
    if (widget.showRegenerateDialog != null) {
      return widget.showRegenerateDialog!(filename);
    }
    return _showRegenerateDialog(filename);
  }

  // Single selection for Inspector
  AppFile? _selectedExistingFile;
  File? _selectedLocalInspectorFile;

  // Local files not yet in DB
  late final List<File> _localFiles =
      widget.initialLocalFiles != null
          ? List.of(widget.initialLocalFiles!)
          : [];

  // Multi-selection
  final Set<String> _selectedPaths = {};

  bool _isLoading = false;
  int _batchTotal = 0;
  int _batchDone = 0;

  final ScrollController _gridScrollController = ScrollController();
  final FocusNode _gridFocusNode = FocusNode(debugLabel: 'Media grid');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Initial sync and restore search settings
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(organizationSearchSettingsProvider.notifier).restore();
      if (!mounted) return;
      ref.read(filesProvider.notifier).syncWithDisk();
      final currentScope = ref.read(organizationSearchSettingsProvider).scope;
      await _handleScopeChanged(currentScope);
      final savedOffset =
          ref.read(organizationSearchSettingsProvider).scrollOffset;
      if (savedOffset > 0 && _gridScrollController.hasClients) {
        _gridScrollController.jumpTo(
          savedOffset.clamp(
            0.0,
            _gridScrollController.position.maxScrollExtent,
          ),
        );
      }
    });
    _gridScrollController.addListener(() {
      if (_gridScrollController.hasClients) {
        ref
            .read(organizationSearchSettingsProvider.notifier)
            .setScrollOffset(_gridScrollController.offset);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(filesProvider.notifier).syncWithDisk();
      // Also potentially verify local files here
      _syncLocalFiles();
    }
  }

  void _syncLocalFiles() {
    // Optional companion method to pruning new (un-added) files if they were deleted
    setState(() {
      _localFiles.retainWhere((f) => f.existsSync());
      _selectedPaths.retainWhere((path) => File(path).existsSync());
      if (_selectedLocalInspectorFile != null &&
          !_selectedLocalInspectorFile!.existsSync()) {
        _selectedLocalInspectorFile = null;
      }
    });
    _syncGridSelectionToProvider();
  }

  Future<void> _handleExportCsv() async {
    final pathsToExport =
        _selectedPaths.isNotEmpty
            ? _selectedPaths.toList()
            : _localFiles.map((f) => f.path).toList();

    if (pathsToExport.isEmpty) return;

    final dbFiles = ref.read(filesProvider).value ?? [];

    // We export AppFile models. If a file is only local, create an empty AppFile for it.
    final filesToExport =
        pathsToExport.map((path) {
          final existing = dbFiles.firstWhereOrNull((dbf) => dbf.path == path);
          if (existing != null) return existing;
          return AppFile(
            id: const Uuid().v4(),
            path: path,
            filename: path.split(Platform.pathSeparator).last,
            workflowStatus: WorkflowStatus.newFile,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          );
        }).toList();

    const String fileName = 'metadata.csv';
    final result = await getSaveLocation(suggestedName: fileName);

    if (result == null) {
      return; // User canceled
    }

    setState(() => _isLoading = true);
    try {
      await CsvMetadataService.exportToFile(filesToExport, result.path);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('CSV сохранен: ${result.path}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка экспорта: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleImportCsv() async {
    const typeGroup = XTypeGroup(label: 'CSV Files', extensions: ['csv']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);

    if (file == null) return; // User canceled

    setState(() => _isLoading = true);
    try {
      final parsedData = await CsvMetadataService.importFromFile(file.path);

      if (mounted) {
        if (parsedData.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('CSV файл пуст или имеет неверный формат.'),
            ),
          );
          return;
        }

        // We will pass this to the dialog to preview changes.
        final performImport = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder:
              (ctx) => CsvImportPreviewDialog(
                parsedData: parsedData,
                dbFiles: ref.read(filesProvider).value ?? [],
              ),
        );

        if (performImport == true) {
          // The dialog applies the changes and saves them; we just refresh
          ref.invalidate(filesProvider);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Метаданные успешно импортированы!'),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка импорта CSV: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool _isDragging = false;

  final _titleController = TextEditingController();
  final _keywordsController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _contextController = TextEditingController();

  /// Есть несохранённые изменения метаданных у выбранного файла.
  bool _metadataDirty = false;

  /// Последний индекс для shift-click выделения
  int? _lastSelectedIndex;

  // Filters / представление
  /// 'all' | 'images' | 'videos'
  String _filterType = 'all';

  /// Active tag filters (OR logic — file must have at least one matching tag).
  Set<String> _activeTagFilters = {};
  ScopeStatusSegment _statusSegment = ScopeStatusSegment.all;
  GridSortMode _sortMode = GridSortMode.date;
  bool _isGridView = true;

  // Нижний общий редактор
  bool _editorCollapsedManual = false;
  double? _editorHeightOverride;
  bool _isSaving = false;
  int _editorDraftRevision = 0;

  /// Staged-черновик массового применения; нужен для защиты при смене
  /// выделения или области. `null` — изменений нет.
  BatchEditRequest? _pendingBatchRequest;
  bool _scopePromptOpen = false;

  bool _isVideoPath(String path) => AppConstants.isVideo(path);

  /// Синхронизирует текущее выделение сетки с [activeGridSelectionProvider].
  void _syncGridSelectionToProvider() {
    final catalogFiles = ref.read(allCatalogFilesProvider).value;
    final dbFiles =
        catalogFiles != null && catalogFiles.isNotEmpty
            ? catalogFiles
            : (ref.read(filesProvider).value ?? []);
    final selectedIds = <String>[];
    for (final path in _selectedPaths) {
      final existing = dbFiles.firstWhereOrNull((f) => f.path == path);
      if (existing != null) {
        selectedIds.add(existing.id);
      }
    }
    ref.read(activeGridSelectionProvider.notifier).setSelection(selectedIds);
  }

  /// In-memory хранилище черновиков для файлов с несохранёнными правками.
  /// Гарантирует абсолютную защиту от потери данных даже при временных сбоях БД.
  final Map<String, AppFile> _inMemoryDrafts = {};

  /// Сохраняет несохранённый черновик правок инспектора в БД и in-memory snapshot
  /// перед переходом между папками/источниками.
  /// Возвращает true при успехе фиксации (в БД или in-memory fallback).
  /// Не выполняет запись в EXIF на диск и не изменяет семантику WorkflowStatus/AI/QC.
  Future<bool> _preserveUnsavedDraft() async {
    final staged = _pendingBatchRequest;
    if (staged != null && staged.hasChanges) {
      _scopePromptOpen = true;
      final choice = await _showStagedBatchDialog(
        'Несохранённые изменения формы',
        'Есть неприменённые изменения для нескольких файлов. Что сделать перед сменой области?',
      );
      _scopePromptOpen = false;
      if (!mounted) return false;
      switch (choice) {
        case _StagedBatchChoice.apply:
          await _applyBatchChanges(staged);
          return mounted;
        case _StagedBatchChoice.discard:
          setState(() {
            _pendingBatchRequest = null;
            _editorDraftRevision++;
          });
          return true;
        case _StagedBatchChoice.stay:
        case null:
          return false;
      }
    }
    if (!_metadataDirty) return true;

    // Захватываем неизменяемый снимок всех редактируемых полей инспектора ДО первого await:
    final titleDraft = _titleController.text.trim();
    final keywordsDraft = _keywordsController.text.trim();
    final descDraft = _descriptionController.text.trim();
    final editorialSnapshot = ref.read(editorialStateProvider);

    final targetPath =
        _selectedExistingFile?.path ?? _selectedLocalInspectorFile?.path;
    if (targetPath == null) {
      _metadataDirty = false;
      return true;
    }

    // Читаем актуальное состояние каталога
    final dbFiles = ref.read(filesProvider).value ?? [];
    final currentRecord =
        (_selectedExistingFile?.id != null
            ? dbFiles.firstWhereOrNull((f) => f.id == _selectedExistingFile!.id)
            : null) ??
        dbFiles.firstWhereOrNull((f) => f.path == targetPath);

    // Подготавливаем обновленные теги:
    // сохраняем существующие, аккуратно синхронизируем ai_generated и editorial
    final baseTags = List<String>.from(currentRecord?.tags ?? const <String>[]);
    if (editorialSnapshot.isAI && !baseTags.contains(AppTags.aiGenerated)) {
      baseTags.add(AppTags.aiGenerated);
    } else if (!editorialSnapshot.isAI) {
      baseTags.remove(AppTags.aiGenerated);
    }
    if (editorialSnapshot.isEditorial &&
        !baseTags.contains(AppTags.editorial)) {
      baseTags.add(AppTags.editorial);
    } else if (!editorialSnapshot.isEditorial) {
      baseTags.remove(AppTags.editorial);
    }

    final draftFile =
        currentRecord != null
            ? currentRecord.copyWith(
              metadataTitle: titleDraft.isEmpty ? null : titleDraft,
              metadataKeywords: keywordsDraft.isEmpty ? null : keywordsDraft,
              metadataDescription: descDraft.isEmpty ? null : descDraft,
              isEditorial: editorialSnapshot.isEditorial,
              editorialCity: editorialSnapshot.city,
              editorialCountry: editorialSnapshot.country,
              editorialDate: editorialSnapshot.date?.millisecondsSinceEpoch,
              tags: baseTags,
            )
            : AppFile(
              // Переиспользуем существующий id по пути, если он есть, иначе создаем новый
              id: currentRecord?.id ?? const Uuid().v4(),
              path: targetPath,
              filename: targetPath.split(Platform.pathSeparator).last,
              metadataTitle: titleDraft.isEmpty ? null : titleDraft,
              metadataKeywords: keywordsDraft.isEmpty ? null : keywordsDraft,
              metadataDescription: descDraft.isEmpty ? null : descDraft,
              isEditorial: editorialSnapshot.isEditorial,
              editorialCity: editorialSnapshot.city,
              editorialCountry: editorialSnapshot.country,
              editorialDate: editorialSnapshot.date?.millisecondsSinceEpoch,
              workflowStatus: WorkflowStatus.newFile,
              createdAt: DateTime.now().millisecondsSinceEpoch,
              tags: baseTags,
            );

    // Немедленно фиксируем в in-memory snapshot ДО любого await:
    _inMemoryDrafts[targetPath] = draftFile;

    try {
      if (currentRecord != null) {
        await ref.read(filesProvider.notifier).updateFile(draftFile);
      } else {
        await ref.read(filesProvider.notifier).addFile(draftFile);
      }
      _metadataDirty = false;
      _selectedExistingFile = draftFile;
      _selectedLocalInspectorFile = null;
      _localFiles.removeWhere((f) => f.path == targetPath);
      return true;
    } catch (e) {
      debugPrint('GenerationScreen: ошибка сохранения черновика в БД: $e');
      // При сбое БД in-memory snapshot уже сохранён в _inMemoryDrafts[targetPath]!
      _metadataDirty = false;
      _selectedExistingFile = draftFile;
      _selectedLocalInspectorFile = null;
      return true;
    }
  }

  /// Фильтрует список файлов каталога [allFiles] под выбранную область [scope].
  List<AppFile> _resolveScopeDbFiles(
    SearchScope scope,
    List<AppFile> allFiles, {
    required List<String> projectFolders,
    required List<String> collectionFileIds,
    required List<String> selectionFileIds,
  }) {
    switch (scope.type) {
      case SearchScopeType.folder:
        final targetPath =
            scope.folderPath.isNotEmpty
                ? scope.folderPath
                : (ref.read(workspacesProvider).currentPath ?? '');
        if (targetPath.isEmpty) return const [];
        return allFiles
            .where(
              (f) => isPathInFolder(
                f.path,
                targetPath,
                includeSubfolders: scope.includeSubfolders,
              ),
            )
            .toList();

      case SearchScopeType.project:
        if (projectFolders.isEmpty) return const [];
        final seenIds = <String>{};
        final result = <AppFile>[];
        for (final f in allFiles) {
          for (final folder in projectFolders) {
            if (isPathInFolder(
              f.path,
              folder,
              includeSubfolders: scope.includeSubfolders,
            )) {
              if (seenIds.add(f.id)) {
                result.add(f);
              }
              break;
            }
          }
        }
        return result;

      case SearchScopeType.collection:
        final idMap = {for (final f in allFiles) f.id: f};
        final result = <AppFile>[];
        for (final id in collectionFileIds) {
          final f = idMap[id];
          if (f != null) result.add(f);
        }
        return result;

      case SearchScopeType.selection:
        final idMap = {for (final f in allFiles) f.id: f};
        final result = <AppFile>[];
        for (final id in selectionFileIds) {
          final f = idMap[id];
          if (f != null) result.add(f);
        }
        return result;

      case SearchScopeType.all:
        return allFiles;
    }
  }

  /// Применяет текущие фильтры к спискам файлов и возвращает отфильтрованные списки.
  /// Использует 4-полевой поиск SearchEngine: filename, metadataTitle, metadataKeywords, metadataDescription.
  ({List<File> locals, List<AppFile> db}) _applyFilters(
    List<File> locals,
    List<AppFile> db,
  ) {
    return _filterBySegment(_applyBaseFilters(locals, db), _statusSegment);
  }

  /// Сегмент «Все / Новые / Готово» — представление существующих статусов.
  /// Локальные файлы, ещё не добавленные в базу, считаются новыми.
  ({List<File> locals, List<AppFile> db}) _filterBySegment(
    ({List<File> locals, List<AppFile> db}) source,
    ScopeStatusSegment segment,
  ) {
    if (segment == ScopeStatusSegment.all) return source;
    return (
      locals: segment == ScopeStatusSegment.newFiles ? source.locals : <File>[],
      db: source.db.where((file) => segment.matches(file)).toList(),
    );
  }

  int _filteredCountFor(
    ScopeStatusSegment segment,
    List<File> locals,
    List<AppFile> db,
  ) {
    final base = _applyBaseFilters(locals, db);
    final filtered = _filterBySegment(base, segment);
    return filtered.locals.length + filtered.db.length;
  }

  /// Фильтры без учёта сегмента статуса: тип, поиск, criteria, теги.
  ({List<File> locals, List<AppFile> db}) _applyBaseFilters(
    List<File> locals,
    List<AppFile> db,
  ) {
    List<File> filteredLocals = locals;
    List<AppFile> filteredDb = db;

    final searchSettings = ref.read(organizationSearchSettingsProvider);
    final criteria = searchSettings.filters;

    // Type filter: объединяет локальный переключатель и criteria.mediaCategory
    final isImagesOnly =
        _filterType == 'images' ||
        criteria.mediaCategory == MediaCategoryFilter.image;
    final isVideosOnly =
        _filterType == 'videos' ||
        criteria.mediaCategory == MediaCategoryFilter.video;

    if (isImagesOnly) {
      filteredLocals =
          filteredLocals.where((f) => !_isVideoPath(f.path)).toList();
      filteredDb = filteredDb.where((f) => !_isVideoPath(f.path)).toList();
    } else if (isVideosOnly) {
      filteredLocals =
          filteredLocals.where((f) => _isVideoPath(f.path)).toList();
      filteredDb = filteredDb.where((f) => _isVideoPath(f.path)).toList();
    }

    // Text search filter по 4 мета-полям: filename, title, description, keywords
    final effectiveQuery = criteria.query;
    if (effectiveQuery.trim().isNotEmpty) {
      final q = effectiveQuery.trim().toLowerCase();
      filteredLocals =
          filteredLocals.where((f) {
            final name =
                f.path.split(Platform.pathSeparator).last.toLowerCase();
            return name.contains(q);
          }).toList();

      filteredDb =
          filteredDb.where((f) {
            if (f.filename.toLowerCase().contains(q)) return true;
            if (f.metadataTitle != null &&
                f.metadataTitle!.toLowerCase().contains(q)) {
              return true;
            }
            if (f.metadataDescription != null &&
                f.metadataDescription!.toLowerCase().contains(q)) {
              return true;
            }
            if (f.metadataKeywords != null &&
                f.metadataKeywords!.toLowerCase().contains(q)) {
              return true;
            }
            return false;
          }).toList();
    }

    // Criteria filters из SearchFilterCriteria (модуль 05):
    if (criteria.workflowStatuses != null &&
        criteria.workflowStatuses!.isNotEmpty) {
      filteredLocals = [];
      filteredDb =
          filteredDb
              .where(
                (f) => criteria.workflowStatuses!.contains(f.workflowStatus),
              )
              .toList();
    }
    if (criteria.hasKeywords != null) {
      filteredLocals = criteria.hasKeywords! ? [] : filteredLocals;
      filteredDb =
          filteredDb.where((f) {
            final hasK =
                f.metadataKeywords != null &&
                f.metadataKeywords!.trim().isNotEmpty;
            return hasK == criteria.hasKeywords!;
          }).toList();
    }
    if (criteria.isEditorial != null) {
      filteredLocals = [];
      filteredDb =
          filteredDb.where((f) {
            final isEd = f.isEditorial || f.tags.contains(AppTags.editorial);
            return isEd == criteria.isEditorial!;
          }).toList();
    }
    if (criteria.isAiGenerated != null) {
      filteredLocals = [];
      filteredDb =
          filteredDb.where((f) {
            final isAi = f.tags.contains(AppTags.aiGenerated);
            return isAi == criteria.isAiGenerated!;
          }).toList();
    }

    // Tag filter (OR logic: show files with ANY of the active tags).
    // Local files have no tags → hidden when tag filter is active.
    if (_activeTagFilters.isNotEmpty) {
      filteredLocals = [];
      filteredDb =
          filteredDb.where((f) {
            return f.tags.any((t) => _activeTagFilters.contains(t));
          }).toList();
    }

    return (locals: filteredLocals, db: filteredDb);
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _releaseSecurityScopedResource();
    _titleController.dispose();
    _keywordsController.dispose();
    _contextController.dispose();
    _gridScrollController.dispose();
    _gridFocusNode.dispose();
    super.dispose();
  }

  /// На macOS: открытые security-scoped ресурсы рабочих областей.
  final Map<String, Directory> _openScopedResources = {};

  Future<void> _releaseSecurityScopedResource() async {
    for (final dir in _openScopedResources.values) {
      try {
        await _secureBookmarks.stopAccessingSecurityScopedResource(dir);
      } catch (_) {}
    }
    _openScopedResources.clear();
  }

  /// Удерживает security-scoped доступ ко всем родительским корням,
  /// в которых находятся целевые файлы или папки [targetPath].
  Future<void> _ensureSecurityScopeForPath(String targetPath) async {
    if (!Platform.isMacOS) return;
    final workspaces = ref.read(workspacesProvider);
    for (final entry in workspaces.entries) {
      if (entry.bookmark == null || entry.bookmark!.isEmpty) continue;
      if (isPathInsideRoot(targetPath, entry.path)) {
        if (!_openScopedResources.containsKey(entry.path)) {
          try {
            final entity = await _secureBookmarks.resolveBookmark(
              entry.bookmark!,
              isDirectory: true,
            );
            if (entity is Directory) {
              final started = await _secureBookmarks
                  .startAccessingSecurityScopedResource(entity);
              if (started) {
                _openScopedResources[entry.path] = entity;
              }
            }
          } catch (e) {
            debugPrint('Failed to start security scope for ${entry.path}: $e');
          }
        }
      }
    }
  }

  /// Удерживает security-scoped доступ для списка путей (папок проекта или файлов коллекции).
  Future<void> _ensureSecurityScopeForPaths(Iterable<String> paths) async {
    if (!Platform.isMacOS) return;
    for (final p in paths) {
      await _ensureSecurityScopeForPath(p);
    }
  }

  int _loadRequestId = 0;
  static final _secureBookmarks = SecureBookmarks();

  /// Загружает файлы текущей рабочей области или указанных папок (без блокировки UI).
  /// Поддерживает рекурсивный обход при [includeSubfolders: true] (followLinks: false),
  /// а также сканирование всех подключённых папок проекта [additionalFolders].
  Future<void> _loadCurrentWorkspaceFiles({
    String? customPath,
    bool? includeSubfolders,
    List<String>? additionalFolders,
  }) async {
    final requestId = ++_loadRequestId;
    final entry = ref.read(workspacesProvider).currentEntry;
    final searchSettings = ref.read(organizationSearchSettingsProvider);
    final isRecursive =
        includeSubfolders ?? searchSettings.scope.includeSubfolders;

    final targetPath =
        (customPath != null && customPath.trim().isNotEmpty)
            ? customPath.trim()
            : entry?.path.trim();

    final foldersToScan = <String>[];
    if (targetPath != null && targetPath.isNotEmpty) {
      foldersToScan.add(targetPath);
    }
    if (additionalFolders != null && additionalFolders.isNotEmpty) {
      for (final f in additionalFolders) {
        if (!foldersToScan.contains(f)) {
          foldersToScan.add(f);
        }
      }
    }

    if (foldersToScan.isEmpty) {
      await _releaseSecurityScopedResource();
      if (mounted) setState(() => _localFiles.clear());
      return;
    }

    // Удерживаем security scope для всех корней сканирования
    await _ensureSecurityScopeForPaths(foldersToScan);
    if (requestId != _loadRequestId || !_isLive) return;

    try {
      final allExtensions = [
        ...AppConstants.imageExtensions,
        ...AppConstants.videoExtensions,
      ];
      final dbFiles = ref.read(filesProvider).value ?? [];

      final dbPathsInScope = <String>{};
      for (final f in dbFiles) {
        for (final folder in foldersToScan) {
          if (isPathInFolder(f.path, folder, includeSubfolders: isRecursive)) {
            dbPathsInScope.add(f.path);
            break;
          }
        }
      }

      final newLocal = <File>[];
      final seenLocalPaths = <String>{};

      for (final folderPath in foldersToScan) {
        if (requestId != _loadRequestId || !_isLive) return;
        final dir = Directory(folderPath);
        if (!await dir.exists()) continue;
        if (requestId != _loadRequestId || !_isLive) return;

        try {
          final stream = dir.list(recursive: isRecursive, followLinks: false);
          await for (final entity in stream) {
            if (requestId != _loadRequestId || !_isLive) return;
            if (entity is File) {
              final path = entity.path;
              final ext = path.split('.').last.toLowerCase();
              if (allExtensions.contains('.$ext') &&
                  !dbPathsInScope.contains(path) &&
                  seenLocalPaths.add(path)) {
                newLocal.add(entity);
              }
            }
          }
        } catch (e) {
          debugPrint('Error listing directory $folderPath: $e');
        }
      }

      if (mounted && requestId == _loadRequestId) {
        setState(() {
          _localFiles.clear();
          _localFiles.addAll(newLocal);
        });
      }
    } catch (e) {
      if (mounted && requestId == _loadRequestId) {
        setState(() => _localFiles.clear());
        final msg = e.toString();
        if (msg.contains('PathAccessException') ||
            msg.contains('Operation not permitted') ||
            msg.contains('errno = 1')) {
          _showDiskAccessRequiredDialog();
        } else {
          _showError('Нет доступа к папке или ошибка чтения: $e');
        }
      }
    }
  }

  /// Асинхронно переключает источники файлов (папка/проект/коллекция/отбор),
  /// удерживая безопасность macOS, сканируя локальные папки и сбрасывая выбор.
  Future<void> _handleScopeChanged(SearchScope nextScope) async {
    if (nextScope.type == SearchScopeType.folder) {
      final folderPath =
          nextScope.folderPath.isNotEmpty
              ? nextScope.folderPath
              : (ref.read(workspacesProvider).currentPath ?? '');
      if (folderPath.isNotEmpty) {
        await _loadCurrentWorkspaceFiles(
          customPath: folderPath,
          includeSubfolders: nextScope.includeSubfolders,
        );
      }
    } else if (nextScope.type == SearchScopeType.project &&
        nextScope.projectId.isNotEmpty) {
      final folders = await ref.read(
        projectFoldersProvider(nextScope.projectId).future,
      );
      await _ensureSecurityScopeForPaths(folders);
      await _loadCurrentWorkspaceFiles(
        additionalFolders: folders,
        includeSubfolders: nextScope.includeSubfolders,
      );
    } else if (nextScope.type == SearchScopeType.collection &&
        nextScope.collectionId.isNotEmpty) {
      final allFiles = ref.read(filesProvider).value ?? const [];
      final ids = await ref.read(
        collectionFileIdsProvider(nextScope.collectionId).future,
      );
      final paths = allFiles
          .where((f) => ids.contains(f.id))
          .map((f) => f.path);
      await _ensureSecurityScopeForPaths(paths);
    }
    if (mounted) {
      setState(() {
        _selectedPaths.clear();
        _selectedExistingFile = null;
        _selectedLocalInspectorFile = null;
      });
      _syncGridSelectionToProvider();
    }
  }

  /// Открывает системные настройки macOS в разделе «Полный доступ к диску».
  Future<void> _openFullDiskAccessSettings() async {
    if (!Platform.isMacOS) return;
    try {
      await Process.run('open', [
        'x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles',
      ]);
    } catch (_) {}
  }

  void _showDiskAccessRequiredDialog() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('Нет доступа к папке'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Чтобы приложение могло видеть файлы в выбранной папке, '
                  'нужно включить доступ в настройках macOS.',
                  style: TextStyle(color: colorScheme.onSurface, height: 1.4),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Инструкция:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  '1. Нажмите «Перейти в настройки» ниже.\n'
                  '2. Откроется «Конфиденциальность и безопасность» → «Полный доступ к диску».\n'
                  '3. Если приложения Stock Flow нет в списке — нажмите «+» и выберите это приложение (Stock Flow.app).\n'
                  '4. Включите переключатель рядом с Stock Flow.\n'
                  '5. При необходимости перезапустите приложение.',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurface.withValues(alpha: 0.9),
                    height: 1.45,
                  ),
                ),
                if (Platform.isMacOS) ...[
                  const SizedBox(height: 12),
                  Builder(
                    builder: (ctx) {
                      String appPath = '';
                      try {
                        final exe = Platform.resolvedExecutable;
                        final parts = exe.split(Platform.pathSeparator);
                        // .../Stock Flow.app/Contents/MacOS/Stock Flow -> show .../Stock Flow.app
                        final appIdx = parts.indexWhere(
                          (e) => e.endsWith('.app'),
                        );
                        if (appIdx >= 0) {
                          appPath = parts
                              .sublist(0, appIdx + 1)
                              .join(Platform.pathSeparator);
                        } else {
                          appPath = exe;
                        }
                      } catch (_) {}
                      if (appPath.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Путь к приложению (для кнопки «+»):',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.8,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            appPath,
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Закрыть'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                _openFullDiskAccessSettings();
              },
              icon: const Icon(Icons.settings, size: 18),
              label: const Text('Перейти в настройки'),
            ),
          ],
        );
      },
    );
  }

  /// Обновить список файлов текущей папки (кнопка «Обновить»).
  Future<void> _refreshCurrentWorkspace() async {
    await ref.read(filesProvider.future);
    await _loadCurrentWorkspaceFiles();
  }

  Future<void> _pickFile() async {
    String? directoryPath;
    try {
      directoryPath = await getDirectoryPath();
    } catch (e) {
      _showError('Failed to open folder picker: $e');
      return;
    }

    if (directoryPath == null) return;

    await ref.read(workspacesProvider.notifier).addWorkspace(directoryPath);

    final dir = Directory(directoryPath);
    if (!await dir.exists()) {
      _showError('Selected folder does not exist: $directoryPath');
      return;
    }

    final allExtensions = [
      ...AppConstants.imageExtensions,
      ...AppConstants.videoExtensions,
    ];

    final dbFiles = ref.read(filesProvider).value ?? [];
    int addedCount = 0;

    try {
      // Асинхронное чтение директории, чтобы не блокировать UI
      final List<FileSystemEntity> entities =
          await dir.list(recursive: false).toList();

      if (!mounted) return;
      setState(() {
        for (var entity in entities) {
          if (entity is File) {
            final path = entity.path;
            final ext = path.split('.').last.toLowerCase();

            if (allExtensions.contains('.$ext')) {
              final existsInDb = dbFiles.any((f) => f.path == path);
              final existsInLocal = _localFiles.any((f) => f.path == path);

              if (!existsInDb && !existsInLocal) {
                _localFiles.add(entity);
                addedCount++;
              }
            }
          }
        }
      });

      if (addedCount > 0) {
        _showSuccess('Imported $addedCount new files from $directoryPath');
      } else {
        _showSuccess('No new files found in $directoryPath');
      }
    } catch (e) {
      _showError('Failed to scan folder: $e');
    }
  }

  bool get _hasStagedBatch => _pendingBatchRequest?.hasChanges ?? false;

  void _toggleSelection(
    int index,
    String path,
    List<String> allPaths, {
    AppFile? existing,
    File? local,
  }) {
    // Цели применения уже зафиксированы: смена выделения во время записи
    // не должна менять адресатов операции.
    if (_isSaving) return;
    if (!_hasStagedBatch) {
      _applyToggleSelection(
        index,
        path,
        allPaths,
        existing: existing,
        local: local,
      );
      return;
    }
    _toggleSelectionWithPrompt(
      index,
      path,
      allPaths,
      existing: existing,
      local: local,
    );
  }

  Future<void> _toggleSelectionWithPrompt(
    int index,
    String path,
    List<String> allPaths, {
    AppFile? existing,
    File? local,
  }) async {
    if (!await _resolveStagedBatchBeforeSelectionChange()) return;
    if (!mounted) return;
    _applyToggleSelection(
      index,
      path,
      allPaths,
      existing: existing,
      local: local,
    );
  }

  void _applyToggleSelection(
    int index,
    String path,
    List<String> allPaths, {
    AppFile? existing,
    File? local,
  }) {
    _gridFocusNode.requestFocus();
    final isShiftPressed =
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftLeft,
        ) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftRight,
        );

    setState(() {
      if (isShiftPressed &&
          _lastSelectedIndex != null &&
          _lastSelectedIndex != index) {
        final start = index < _lastSelectedIndex! ? index : _lastSelectedIndex!;
        final end = index > _lastSelectedIndex! ? index : _lastSelectedIndex!;
        for (int i = start; i <= end; i++) {
          final p = allPaths[i];
          if (!_selectedPaths.contains(p)) {
            _selectedPaths.add(p);
          }
        }
      } else {
        _selectedPaths.clear();
        _selectedPaths.add(path);
      }
      _focusFileForInspector(path, existing: existing, local: local);
      _lastSelectedIndex = index;
    });
    _syncGridSelectionToProvider();
  }

  void _focusFileForInspector(String path, {AppFile? existing, File? local}) {
    if (_inMemoryDrafts.containsKey(path)) {
      final draft = _inMemoryDrafts[path]!;
      _selectedExistingFile = draft;
      _selectedLocalInspectorFile = null;
      _titleController.text = draft.metadataTitle ?? '';
      _keywordsController.text = draft.metadataKeywords ?? '';
      _descriptionController.text = draft.metadataDescription ?? '';
      _metadataDirty = false;
      ref.read(editorialStateProvider.notifier).syncFromFile(draft);
    } else if (existing != null) {
      _selectedExistingFile = existing;
      _selectedLocalInspectorFile = null;
      _titleController.text = existing.metadataTitle ?? '';
      _keywordsController.text = existing.metadataKeywords ?? '';
      _descriptionController.text = existing.metadataDescription ?? '';
      _metadataDirty = false;
      // Sync editorial state via provider
      ref.read(editorialStateProvider.notifier).syncFromFile(existing);
    } else if (local != null) {
      _selectedLocalInspectorFile = local;
      _selectedExistingFile = null;
      ref.read(editorialStateProvider.notifier).reset();
      _clearResults();
    }
  }

  void _selectAll(List<AppFile> dbFiles, List<File> localFiles) {
    if (_isSaving) return;
    if (_hasStagedBatch) {
      _selectAllWithPrompt(dbFiles, localFiles);
      return;
    }
    _applySelectAll(dbFiles, localFiles);
  }

  Future<void> _selectAllWithPrompt(
    List<AppFile> dbFiles,
    List<File> localFiles,
  ) async {
    if (!await _resolveStagedBatchBeforeSelectionChange()) return;
    if (!mounted) return;
    _applySelectAll(dbFiles, localFiles);
  }

  void _applySelectAll(List<AppFile> dbFiles, List<File> localFiles) {
    setState(() {
      _selectedPaths
        ..clear()
        ..addAll(dbFiles.map((f) => f.path))
        ..addAll(localFiles.map((f) => f.path));
      _lastSelectedIndex = null;
    });
    _syncGridSelectionToProvider();
  }

  void _clearSelection() {
    if (_isSaving) return;
    if (_hasStagedBatch) {
      _clearSelectionWithPrompt();
      return;
    }
    _applyClearSelection();
  }

  Future<void> _clearSelectionWithPrompt() async {
    if (!await _resolveStagedBatchBeforeSelectionChange()) return;
    if (!mounted) return;
    _applyClearSelection();
  }

  void _applyClearSelection() {
    setState(() {
      _selectedPaths.clear();
      _selectedExistingFile = null;
      _selectedLocalInspectorFile = null;
      _lastSelectedIndex = null;
    });
    _syncGridSelectionToProvider();
  }

  void _clearResults() {
    _titleController.clear();
    _keywordsController.clear();
  }

  Future<void> _generateAI() async {
    if (_isLoading) return;
    if (!_isLive) return;

    final fileToProcess =
        _selectedLocalInspectorFile ??
        (_selectedExistingFile != null
            ? File(_selectedExistingFile!.path)
            : null);
    if (fileToProcess == null) return;

    // Freeze the generation target before the first await: the result must be
    // applied to this exact material even if the user selects another file
    // while the request is running.
    final targetPath = fileToProcess.path;
    final existingFile = _selectedExistingFile;
    final targetId = existingFile?.id;

    final settings = await ref.read(settingsProvider.future);
    if (!_isLive) return;
    if (settings.apiKey == null || settings.apiKey!.isEmpty) {
      _showError('Configure API key in Settings first.');
      return;
    }

    // Freeze generation context before any await:
    final editorialSnapshot = ref.read(editorialStateProvider);
    final userContext = _contextController.text.trim();

    var opContext = MetadataGenerationContext(
      targetId: targetId,
      targetPath: targetPath,
      userContext: userContext,
      apiKey: settings.apiKey!,
      keywordCount: settings.defaultKeywordsCount,
      isEditorial: editorialSnapshot.isEditorial,
      city: editorialSnapshot.city,
      country: editorialSnapshot.country,
      date: editorialSnapshot.date,
    );

    setState(() => _isLoading = true);

    try {
      if (opContext.isEditorial) {
        // Load EXIF if not already present in the frozen snapshot
        if (opContext.date == null ||
            (opContext.city.isEmpty && opContext.country.isEmpty)) {
          final exif = await _readExif(targetPath);
          if (!_isLive) return;

          DateTime? newDate = opContext.date ?? exif.date;
          String newCity = opContext.city;
          String newCountry = opContext.country;

          if (exif.lat != null && exif.lon != null && newCity.isEmpty) {
            final geo = await _resolveGeo(exif.lat, exif.lon);
            if (!_isLive) return;
            if (geo.city != null) newCity = geo.city!;
            if (geo.country != null || geo.state != null) {
              newCountry = geo.country ?? geo.state ?? '';
            }
          }

          opContext = opContext.copyWith(
            date: newDate,
            city: newCity,
            country: newCountry,
          );
        }
      }

      final options = GenerationOptions(
        numberOfKeywords: opContext.keywordCount,
        shortTitle: false,
        contextAndInstructions: opContext.formattedUserContext,
      );

      final metadata = await _callGenerateMetadata(
        apiKey: opContext.apiKey,
        filePath: targetPath,
        options: options,
      );
      if (!_isLive) return;

      final fetchedTitle = metadata['title'] ?? '';
      final List<dynamic> fetchedKeywords = metadata['keywords'] ?? [];
      final keywordsString = fetchedKeywords.join(', ');
      final fetchedDescription = (metadata['description'] ?? '') as String;

      final finalTitle = opContext.formatFinalTitle(fetchedTitle);

      // Re-read current tags of THIS material from filesProvider, never from stale snapshot
      final dbFilesNow = ref.read(filesProvider).value ?? [];
      final currentRecord =
          (targetId != null
              ? dbFilesNow.firstWhereOrNull((f) => f.id == targetId)
              : null) ??
          dbFilesNow.firstWhereOrNull((f) => f.path == targetPath);
      if (targetId != null && currentRecord?.id != targetId) {
        throw StateError(
          'Исходный материал недоступен в каталоге. Обновите папку и повторите генерацию.',
        );
      }

      final updatedTags = tagsAfterMetadataGeneration(
        currentTags: currentRecord?.tags ?? const <String>[],
        isEditorial: opContext.isEditorial,
      );

      final newFile =
          currentRecord != null
              ? currentRecord.copyWith(
                metadataTitle: finalTitle,
                metadataKeywords: keywordsString,
                metadataDescription:
                    fetchedDescription.isEmpty ? null : fetchedDescription,
                isEditorial: opContext.isEditorial,
                editorialCity: opContext.city,
                editorialCountry: opContext.country,
                editorialDate: opContext.date?.millisecondsSinceEpoch,
                workflowStatus: WorkflowStatus.readyToUpload,
                tags: updatedTags,
              )
              : AppFile(
                id: const Uuid().v4(),
                path: targetPath,
                filename: targetPath.split(Platform.pathSeparator).last,
                metadataTitle: finalTitle,
                metadataKeywords: keywordsString,
                metadataDescription:
                    fetchedDescription.isEmpty ? null : fetchedDescription,
                isEditorial: opContext.isEditorial,
                editorialCity: opContext.city,
                editorialCountry: opContext.country,
                editorialDate: opContext.date?.millisecondsSinceEpoch,
                workflowStatus: WorkflowStatus.readyToUpload,
                createdAt:
                    existingFile?.createdAt ??
                    DateTime.now().millisecondsSinceEpoch,
                tags: updatedTags,
              );

      bool stillViewingTarget() {
        if (!_isLive) return false;
        if (targetId != null) {
          return _selectedExistingFile?.id == targetId &&
              _selectedExistingFile?.path == targetPath;
        }
        return _selectedLocalInspectorFile?.path == targetPath ||
            _selectedExistingFile?.path == targetPath;
      }

      if (stillViewingTarget()) {
        setState(() {
          _titleController.text = finalTitle;
          _keywordsController.text = keywordsString;
          _descriptionController.text = fetchedDescription;
          _metadataDirty = true;
        });
        ref.read(editorialStateProvider.notifier).syncFromFile(newFile);
      }

      await ref.read(filesProvider.notifier).addFile(newFile);
      if (!_isLive) return;

      // Save to original file
      if (!AppConstants.isVideo(targetPath)) {
        await _writeMetadata(
          filePath: targetPath,
          title: finalTitle,
          keywords: keywordsString,
          city: opContext.isEditorial ? opContext.city : null,
          country: opContext.isEditorial ? opContext.country : null,
          shootDate: opContext.isEditorial ? opContext.date : null,
        );
        if (!_isLive) return;
      }

      // Keep it selected only if the user is still looking at this material.
      if (stillViewingTarget()) {
        setState(() {
          _selectedExistingFile = newFile;
          _selectedLocalInspectorFile = null;
        });
      }
      if (_isLive) {
        setState(() {
          _localFiles.removeWhere((f) => f.path == targetPath);
        });
      }
    } catch (e) {
      if (_isLive) _showError(e.toString());
    } finally {
      if (_isLive) setState(() => _isLoading = false);
    }
  }

  Future<void> _generateBatchAI() async {
    if (_isLoading) return;
    if (!_isLive) return;
    if (_selectedPaths.isEmpty) return;

    final settings = await ref.read(settingsProvider.future);
    if (!_isLive) return;
    if (settings.apiKey == null || settings.apiKey!.isEmpty) {
      _showError('Configure API key in Settings first.');
      return;
    }

    // Freeze batch targets and settings before putting tasks into pool
    final dbFiles = ref.read(filesProvider).value ?? [];
    final batchTargetPaths = Set<String>.from(_selectedPaths);

    final editorialSnapshot = ref.read(editorialStateProvider);
    final batchUserContext = _contextController.text.trim();
    final batchApiKey = settings.apiKey!;
    final batchKeywordCount = settings.defaultKeywordsCount;
    final batchIsEditorial = editorialSnapshot.isEditorial;

    final List<MetadataGenerationContext> targetContexts = [];
    for (final path in batchTargetPaths) {
      final existing = dbFiles.firstWhereOrNull((f) => f.path == path);
      final fileCity = existing?.editorialCity?.trim() ?? '';
      final fileCountry = existing?.editorialCountry?.trim() ?? '';
      targetContexts.add(
        MetadataGenerationContext(
          targetId: existing?.id,
          targetPath: path,
          userContext: batchUserContext,
          apiKey: batchApiKey,
          keywordCount: batchKeywordCount,
          isEditorial: batchIsEditorial,
          city: fileCity.isNotEmpty ? fileCity : editorialSnapshot.city.trim(),
          country:
              fileCountry.isNotEmpty
                  ? fileCountry
                  : editorialSnapshot.country.trim(),
          date:
              existing?.editorialDate != null
                  ? DateTime.fromMillisecondsSinceEpoch(
                    existing!.editorialDate!,
                  )
                  : editorialSnapshot.date,
        ),
      );
    }

    setState(() {
      _isLoading = true;
      _batchTotal = targetContexts.length;
      _batchDone = 0;
    });

    final dialogMutex = _AsyncMutex();
    bool?
    replaceAllDecision; // null = ask, true = replace all, false = skip all
    int generatedCount = 0;
    int skippedCount = 0;
    final failures = <String, String>{};

    final pool = Pool(3);
    final List<Future> tasks = [];

    for (final initialContext in targetContexts) {
      tasks.add(
        pool.withResource(() async {
          if (!_isLive) return;
          final path = initialContext.targetPath;
          final initialId = initialContext.targetId;

          try {
            // Re-check current file in DB to see if it already has tags
            final dbFilesBeforeCheck = ref.read(filesProvider).value ?? [];
            final currentBeforeCheck =
                (initialId != null
                    ? dbFilesBeforeCheck.firstWhereOrNull(
                      (f) => f.id == initialId,
                    )
                    : null) ??
                dbFilesBeforeCheck.firstWhereOrNull((f) => f.path == path);

            final isAppFileWithTags =
                currentBeforeCheck != null &&
                (currentBeforeCheck.metadataTitle?.isNotEmpty ?? false) &&
                (currentBeforeCheck.metadataKeywords?.isNotEmpty ?? false);

            bool shouldGenerate = true;

            if (isAppFileWithTags) {
              if (replaceAllDecision == true) {
                shouldGenerate = true;
              } else if (replaceAllDecision == false) {
                shouldGenerate = false;
              } else {
                final filename = path.split(Platform.pathSeparator).last;
                final result = await dialogMutex.synchronized(() async {
                  if (!_isLive) return null;
                  if (replaceAllDecision != null) return null;
                  return await _handleShowRegenerateDialog(filename);
                });

                if (!_isLive) return;

                if (result == null) {
                  if (replaceAllDecision != null) {
                    shouldGenerate = replaceAllDecision == true;
                  } else {
                    shouldGenerate =
                        false; // default to skip if dialog was aborted or unmounted
                  }
                } else {
                  if (result.applyToAll) {
                    replaceAllDecision = result.replace;
                  }
                  shouldGenerate = result.replace;
                }
              }
            }

            if (!shouldGenerate) {
              skippedCount++;
              if (_isLive) {
                setState(() {
                  _batchDone++;
                  _selectedPaths.remove(path);
                });
              }
              return;
            }

            var opContext = initialContext;

            if (opContext.isEditorial &&
                (opContext.date == null ||
                    (opContext.city.isEmpty && opContext.country.isEmpty))) {
              final exif = await _readExif(path);
              if (!_isLive) return;

              final newDate = opContext.date ?? exif.date;
              var newCity = opContext.city;
              var newCountry = opContext.country;

              if (exif.lat != null && exif.lon != null && newCity.isEmpty) {
                final geo = await _resolveGeo(exif.lat, exif.lon);
                if (!_isLive) return;
                if (geo.city != null) newCity = geo.city!;
                if (geo.country != null || geo.state != null) {
                  newCountry = geo.country ?? geo.state ?? '';
                }
              }

              opContext = opContext.copyWith(
                date: newDate,
                city: newCity,
                country: newCountry,
              );
            }

            final options = GenerationOptions(
              numberOfKeywords: opContext.keywordCount,
              shortTitle: false,
              contextAndInstructions: opContext.formattedUserContext,
            );

            final metadata = await _callGenerateMetadata(
              apiKey: opContext.apiKey,
              filePath: path,
              options: options,
            );
            if (!_isLive) return;

            final fetchedTitle = metadata['title'] ?? '';
            final List<dynamic> fetchedKeywords = metadata['keywords'] ?? [];
            final keywordsString = fetchedKeywords.join(', ');
            final fetchedDescription =
                (metadata['description'] ?? '') as String;

            final finalTitle = opContext.formatFinalTitle(fetchedTitle);

            final dbFilesNow = ref.read(filesProvider).value ?? [];
            final currentRecord =
                (initialId != null
                    ? dbFilesNow.firstWhereOrNull((f) => f.id == initialId)
                    : null) ??
                dbFilesNow.firstWhereOrNull((f) => f.path == path);
            if (initialId != null && currentRecord?.id != initialId) {
              throw StateError(
                'Исходный материал недоступен в каталоге. Обновите папку и повторите генерацию.',
              );
            }

            final baseTags = tagsAfterMetadataGeneration(
              currentTags: currentRecord?.tags ?? const <String>[],
              isEditorial: opContext.isEditorial,
            );

            final newFile =
                currentRecord != null
                    ? currentRecord.copyWith(
                      metadataTitle: finalTitle,
                      metadataKeywords: keywordsString,
                      metadataDescription:
                          fetchedDescription.isEmpty
                              ? null
                              : fetchedDescription,
                      isEditorial: opContext.isEditorial,
                      editorialCity: opContext.city,
                      editorialCountry: opContext.country,
                      editorialDate: opContext.date?.millisecondsSinceEpoch,
                      workflowStatus: WorkflowStatus.readyToUpload,
                      tags: baseTags,
                    )
                    : AppFile(
                      id: const Uuid().v4(),
                      path: path,
                      filename: path.split(Platform.pathSeparator).last,
                      metadataTitle: finalTitle,
                      metadataKeywords: keywordsString,
                      metadataDescription:
                          fetchedDescription.isEmpty
                              ? null
                              : fetchedDescription,
                      isEditorial: opContext.isEditorial,
                      editorialCity: opContext.city,
                      editorialCountry: opContext.country,
                      editorialDate: opContext.date?.millisecondsSinceEpoch,
                      workflowStatus: WorkflowStatus.readyToUpload,
                      createdAt: DateTime.now().millisecondsSinceEpoch,
                      tags: baseTags,
                    );

            await ref.read(filesProvider.notifier).addFile(newFile);
            if (!_isLive) return;

            if (!AppConstants.isVideo(path)) {
              await _writeMetadata(
                filePath: path,
                title: finalTitle,
                keywords: keywordsString,
                city: opContext.isEditorial ? opContext.city : null,
                country: opContext.isEditorial ? opContext.country : null,
                shootDate: opContext.isEditorial ? opContext.date : null,
              );
              if (!_isLive) return;
            }

            generatedCount++;
            if (_isLive) {
              setState(() {
                _batchDone++;
                final isCurrentlyViewed =
                    (initialId != null &&
                        _selectedExistingFile?.id == initialId &&
                        _selectedExistingFile?.path == path) ||
                    (_selectedExistingFile?.path == path) ||
                    (_selectedLocalInspectorFile?.path == path);

                if (isCurrentlyViewed) {
                  _titleController.text = finalTitle;
                  _keywordsController.text = keywordsString;
                  _descriptionController.text = fetchedDescription;
                  _selectedExistingFile = newFile;
                  _selectedLocalInspectorFile = null;
                  _metadataDirty = true;
                  ref
                      .read(editorialStateProvider.notifier)
                      .syncFromFile(newFile);
                }
                _localFiles.removeWhere((f) => f.path == path);
              });
            }
          } catch (e) {
            failures[path] = e.toString();
            debugPrint('Batch error for $path: $e');
            if (_isLive) {
              setState(() {
                _batchDone++;
              });
            }
          }
        }),
      );
    }

    try {
      await Future.wait(tasks);
    } finally {
      await pool.close();
      if (_isLive) {
        setState(() {
          _isLoading = false;
          _selectedPaths.removeWhere(
            (path) =>
                batchTargetPaths.contains(path) && !failures.containsKey(path),
          );
          if (_selectedPaths.length == 1 &&
              failures.containsKey(_selectedPaths.single)) {
            final path = _selectedPaths.single;
            _focusFileForInspector(
              path,
              existing: ref
                  .read(filesProvider)
                  .value
                  ?.firstWhereOrNull((f) => f.path == path),
              local: File(path),
            );
          }
        });
        _syncGridSelectionToProvider();
        final summary =
            'Обработано $_batchDone/$_batchTotal: подготовлено: $generatedCount, '
            'пропущено: $skippedCount, ошибок: ${failures.length}';
        if (failures.isNotEmpty) {
          _showBatchGenerationErrors(summary, failures);
        } else {
          _showSuccess(summary);
        }
      }
    }
  }

  /// Сохраняет метаданные одного выбранного файла: существующего в БД или локального.
  Future<void> _saveChanges() async {
    if (_isSaving) return;
    final title = _titleController.text.trim();
    final keywords = _keywordsController.text.trim();
    final description = _descriptionController.text.trim();
    final editorial = ref.read(editorialStateProvider);

    String withEditorial(String base) {
      if (!editorial.isEditorial || base.isEmpty) return base;
      return _appendEditorialToTitle(
        title: base,
        city: editorial.city,
        country: editorial.country,
        date: editorial.date,
      );
    }

    setState(() => _isSaving = true);
    try {
      if (_selectedExistingFile != null) {
        final storedTitle = withEditorial(title);
        final updated = _selectedExistingFile!.copyWith(
          metadataTitle: storedTitle.isEmpty ? null : storedTitle,
          metadataKeywords: keywords.isEmpty ? null : keywords,
          metadataDescription: description.isEmpty ? null : description,
          isEditorial: editorial.isEditorial,
          editorialCity: editorial.city,
          editorialCountry: editorial.country,
          editorialDate: editorial.date?.millisecondsSinceEpoch,
          workflowStatus: WorkflowStatus.readyToUpload,
        );
        await ref.read(filesProvider.notifier).updateFile(updated);
        final fileExists = File(updated.path).existsSync();
        if (!AppConstants.isVideo(updated.path) && fileExists) {
          await _writeMetadata(
            filePath: updated.path,
            title: updated.metadataTitle ?? '',
            keywords: updated.metadataKeywords ?? '',
            description: updated.metadataDescription,
            city: editorial.isEditorial ? editorial.city : null,
            country: editorial.isEditorial ? editorial.country : null,
            shootDate: editorial.isEditorial ? editorial.date : null,
          );
        }
        if (!mounted) return;
        setState(() {
          _selectedExistingFile = updated;
          _metadataDirty = false;
        });
        _showSuccess(
          fileExists
              ? 'Изменения сохранены в БД и в файл.'
              : 'Файл на отключённом носителе. Изменения сохранены в базе данных.',
        );
      } else if (_selectedLocalInspectorFile != null) {
        final path = _selectedLocalInspectorFile!.path;
        final storedTitle = withEditorial(title);
        final newFile = AppFile(
          id: const Uuid().v4(),
          path: path,
          filename: path.split(Platform.pathSeparator).last,
          metadataTitle: storedTitle.isEmpty ? null : storedTitle,
          metadataKeywords: keywords.isEmpty ? null : keywords,
          metadataDescription: description.isEmpty ? null : description,
          isEditorial: editorial.isEditorial,
          editorialCity: editorial.city,
          editorialCountry: editorial.country,
          editorialDate: editorial.date?.millisecondsSinceEpoch,
          workflowStatus: WorkflowStatus.readyToUpload,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );
        await ref.read(filesProvider.notifier).addFile(newFile);
        if (!AppConstants.isVideo(path) && File(path).existsSync()) {
          await _writeMetadata(
            filePath: path,
            title: newFile.metadataTitle ?? '',
            keywords: newFile.metadataKeywords ?? '',
            description: newFile.metadataDescription,
            city: editorial.isEditorial ? editorial.city : null,
            country: editorial.isEditorial ? editorial.country : null,
            shootDate: editorial.isEditorial ? editorial.date : null,
          );
        }
        if (!mounted) return;
        setState(() {
          _selectedExistingFile = newFile;
          _metadataDirty = false;
          _localFiles.removeWhere((f) => f.path == path);
          _selectedLocalInspectorFile = null;
        });
        _showSuccess('Файл добавлен в БД и метаданные записаны в файл.');
      }
    } catch (e) {
      _showError('Не удалось сохранить изменения: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Применяет staged-черновик к снимку выделения.
  ///
  /// Цели и записи БД фиксируются до первого await: смена выделения во время
  /// операции не меняет адресатов. Незатронутые поля не перезаписываются.
  Future<void> _applyBatchChanges(BatchEditRequest request) async {
    if (_isSaving) return;
    final targets = List<String>.from(_selectedPaths);
    if (targets.isEmpty) return;
    final dbFiles = List<AppFile>.from(
      ref.read(filesProvider).value ?? const <AppFile>[],
    );

    setState(() => _isSaving = true);
    var saved = 0;
    final failed = <String, String>{};
    try {
      for (final path in targets) {
        try {
          final existing = dbFiles.firstWhereOrNull((f) => f.path == path);
          var title = existing?.metadataTitle;
          var description = existing?.metadataDescription;
          var keywords = existing?.metadataKeywords;
          var isEditorial = existing?.isEditorial ?? false;
          var city = existing?.editorialCity ?? '';
          var country = existing?.editorialCountry ?? '';
          var date = existing?.editorialDate;
          final tags = List<String>.from(existing?.tags ?? const <String>[]);

          if (request.titleTouched) {
            title = request.title.isEmpty ? null : request.title;
          }
          if (request.descriptionTouched) {
            description =
                request.description.isEmpty ? null : request.description;
          }
          if (request.keywordsMode == KeywordsApplyMode.replace) {
            final list = [...request.keywordsToAdd];
            keywords = list.isEmpty ? null : list.join(', ');
          } else if (request.keywordsToAdd.isNotEmpty ||
              request.keywordsToRemove.isNotEmpty) {
            final list = _parseKeywordList(keywords);
            for (final keyword in request.keywordsToAdd) {
              if (!list.contains(keyword)) list.add(keyword);
            }
            list.removeWhere(request.keywordsToRemove.contains);
            keywords = list.isEmpty ? null : list.join(', ');
          }
          if (request.editorial != null) {
            isEditorial = request.editorial!;
            if (isEditorial) {
              city = request.city;
              country = request.country;
              date = request.date?.millisecondsSinceEpoch;
              if (!tags.contains(AppTags.editorial)) {
                tags.add(AppTags.editorial);
              }
            } else {
              city = '';
              country = '';
              date = null;
              tags.remove(AppTags.editorial);
            }
          }
          if (request.aiTag != null) {
            if (request.aiTag!) {
              if (!tags.contains(AppTags.aiGenerated)) {
                tags.add(AppTags.aiGenerated);
              }
            } else {
              tags.remove(AppTags.aiGenerated);
            }
          }
          // Не дублировать город/страну при повторном применении:
          // добавляем подпись Editorial только когда заголовок реально меняется.
          // Город/страна/дата не должны менять непритронутый заголовок;
          // дополняем его только когда пользователь сам отредактировал title.
          if (isEditorial &&
              request.titleTouched &&
              title != null &&
              title.isNotEmpty &&
              (city.isNotEmpty || country.isNotEmpty || date != null)) {
            title = _appendEditorialToTitle(
              title: title,
              city: city,
              country: country,
              date: date == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(date),
            );
          }

          final AppFile updated;
          if (existing != null) {
            updated = existing.copyWith(
              metadataTitle: title,
              metadataKeywords: keywords,
              metadataDescription: description,
              isEditorial: isEditorial,
              editorialCity: city.isEmpty ? null : city,
              editorialCountry: country.isEmpty ? null : country,
              editorialDate: date,
              workflowStatus: WorkflowStatus.readyToUpload,
              tags: tags,
            );
            await ref.read(filesProvider.notifier).updateFile(updated);
          } else {
            updated = AppFile(
              id: const Uuid().v4(),
              path: path,
              filename: path.split(Platform.pathSeparator).last,
              metadataTitle: title,
              metadataKeywords: keywords,
              metadataDescription: description,
              isEditorial: isEditorial,
              editorialCity: city.isEmpty ? null : city,
              editorialCountry: country.isEmpty ? null : country,
              editorialDate: date,
              workflowStatus: WorkflowStatus.readyToUpload,
              createdAt: DateTime.now().millisecondsSinceEpoch,
              tags: tags,
            );
            await ref.read(filesProvider.notifier).addFile(updated);
          }

          if (!AppConstants.isVideo(path) && File(path).existsSync()) {
            await _writeMetadata(
              filePath: path,
              title: updated.metadataTitle ?? '',
              keywords: updated.metadataKeywords ?? '',
              description: updated.metadataDescription,
              city: isEditorial ? city : null,
              country: isEditorial ? country : null,
              shootDate:
                  isEditorial && date != null
                      ? DateTime.fromMillisecondsSinceEpoch(date)
                      : null,
            );
          }
          saved++;
        } catch (e) {
          failed[path.split(Platform.pathSeparator).last] = e.toString();
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _metadataDirty = false;
          if (failed.isEmpty) {
            _pendingBatchRequest = null;
            _editorDraftRevision++;
          }
        });
      }
    }
    if (!mounted) return;
    if (failed.isEmpty) {
      _showSuccess('Изменения применены к $saved файлам.');
    } else {
      _showBatchPartialResult(saved, failed);
    }
  }

  List<String> _parseKeywordList(String? value) {
    if (value == null) return <String>[];
    return value
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
  }

  void _showBatchPartialResult(int saved, Map<String, String> failed) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Частичный результат'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Сохранено файлов: $saved'),
                const SizedBox(height: 8),
                Text('Не удалось обработать: ${failed.length}'),
                const SizedBox(height: 8),
                for (final entry in failed.entries.take(8))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${entry.key}: ${entry.value}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                if (failed.length > 8)
                  Text(
                    '…и ещё ${failed.length - 8}',
                    style: const TextStyle(fontSize: 12),
                  ),
                const SizedBox(height: 12),
                const Text(
                  'Правки ошибочных файлов остались в форме — их можно повторить.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  /// Запускает существующую QC-проверку для выбранных файлов из базы.
  Future<void> _runQcForSelection() async {
    final dbFiles = ref.read(filesProvider).value ?? const <AppFile>[];
    final selected =
        dbFiles.where((f) => _selectedPaths.contains(f.path)).toList();
    if (selected.isEmpty) {
      _showError(
        'QC проверяет только файлы, добавленные в базу. Сохраните метаданные выбранных файлов.',
      );
      return;
    }
    final stocks = ref.read(activeStocksProvider);
    if (stocks.isEmpty) {
      _showError('Выберите активные стоки в разделе «Загрузки».');
      return;
    }
    final checker = QcChecker();
    final reports = <String, QcReport>{};
    for (final stockKey in stocks) {
      for (final file in selected) {
        final report = checker.validateFile(file, stockKey);
        if (!report.isClean) reports[file.id] = report;
      }
    }
    if (reports.isEmpty) {
      _showSuccess('QC не нашёл проблем у выбранных файлов.');
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => QcReportDialog(files: selected, reports: reports),
    );
  }

  /// Ставит выбранные файлы в существующую очередь загрузки.
  ///
  /// Использует существующий фильтр допуска и активные стоки; публикация
  /// не выполняется мгновенно, очередь обрабатывается как обычно.
  Future<void> _enqueueSelection() async {
    final dbFiles = ref.read(filesProvider).value ?? const <AppFile>[];
    final selected =
        dbFiles.where((f) => _selectedPaths.contains(f.path)).toList();
    if (selected.isEmpty) {
      _showError('Сначала сохраните метаданные выбранных файлов.');
      return;
    }
    final stocks = ref.read(activeStocksProvider);
    if (stocks.isEmpty) {
      _showError('Выберите активные стоки в разделе «Загрузки».');
      return;
    }
    final eligible =
        selected.where((f) => f.workflowStatus.canBeQueuedForUpload).toList();
    if (eligible.isEmpty) {
      _showError(
        'Нет файлов, готовых к очереди: нужен статус metadata_ready или ready_to_upload.',
      );
      return;
    }
    final queue = ref.read(uploadQueueProvider).value ?? const <UploadJob>[];
    final uploadedIds =
        queue
            .where((job) => job.status == UploadJobStatus.success)
            .map((job) => job.fileId)
            .toSet();
    final fresh =
        eligible.where((f) => !uploadedIds.contains(f.id)).toList();
    if (fresh.isEmpty) {
      _showError('Все выбранные файлы уже загружены на выбранные стоки.');
      return;
    }
    for (final stockKey in stocks) {
      await ref
          .read(uploadQueueProvider.notifier)
          .enqueueFiles(
            files: fresh,
            stockKey: stockKey,
            protocol: UploadProtocol.sftp,
          );
    }
    final skipped = eligible.length - fresh.length;
    _showSuccess(
      'Добавлено в очередь: ${fresh.length * stocks.length}'
      '${skipped > 0 ? ' · пропущено уже загруженных: $skipped' : ''}. '
      'Публикация не выполняется сразу.',
    );
  }

  /// Собирает общие/различные значения выделения для редактора.
  BatchFieldInfo _buildBatchInfo(List<String> paths) {
    final dbFiles = ref.read(filesProvider).value ?? const <AppFile>[];
    final byPath = {for (final file in dbFiles) file.path: file};
    final titles = <String>{};
    final descriptions = <String>{};
    final keywordSets = <String>{};
    final editorials = <bool>{};
    final ais = <bool>{};
    final cities = <String>{};
    final countries = <String>{};
    final dates = <int?>{};
    for (final path in paths) {
      final file = byPath[path];
      titles.add(file?.metadataTitle?.trim() ?? '');
      descriptions.add(file?.metadataDescription?.trim() ?? '');
      keywordSets.add(_parseKeywordList(file?.metadataKeywords).join(', '));
      editorials.add(file?.isEditorial ?? false);
      ais.add(file?.tags.contains(AppTags.aiGenerated) ?? false);
      cities.add(file?.editorialCity ?? '');
      countries.add(file?.editorialCountry ?? '');
      dates.add(file?.editorialDate);
    }
    String? commonString(Set<String> values) =>
        values.length == 1 && values.first.isNotEmpty ? values.first : null;
    final commonKeywords = keywordSets.length == 1
        ? _parseKeywordList(keywordSets.first)
        : const <String>[];
    final rawDate = dates.length == 1 ? dates.first : null;
    return BatchFieldInfo(
      count: paths.length,
      titleMixed: titles.length > 1,
      titleCommon: commonString(titles),
      descriptionMixed: descriptions.length > 1,
      descriptionCommon: commonString(descriptions),
      keywordsMixed: keywordSets.length > 1,
      keywordsCommon: commonKeywords,
      editorialMixed: editorials.length > 1,
      editorialCommon: editorials.length == 1 && editorials.first,
      cityCommon: cities.length == 1 ? cities.first : '',
      countryCommon: countries.length == 1 ? countries.first : '',
      dateCommon:
          rawDate == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(rawDate),
      aiMixed: ais.length > 1,
      aiCommon: ais.length == 1 && ais.first,
    );
  }

  /// Защищает staged-черновик при смене выделения.
  Future<bool> _resolveStagedBatchBeforeSelectionChange() async {
    final request = _pendingBatchRequest;
    if (request == null || !request.hasChanges) return true;
    final choice = await _showStagedBatchDialog(
      'Несохранённые изменения формы',
      'Есть неприменённые изменения для нескольких файлов. Применить их перед сменой выделения?',
    );
    if (!mounted) return false;
    switch (choice) {
      case _StagedBatchChoice.apply:
        await _applyBatchChanges(request);
        return mounted;
      case _StagedBatchChoice.discard:
        setState(() {
          _pendingBatchRequest = null;
          _editorDraftRevision++;
        });
        return true;
      case _StagedBatchChoice.stay:
      case null:
        return false;
    }
  }

  Future<_StagedBatchChoice?> _showStagedBatchDialog(
    String title,
    String message,
  ) {
    if (!mounted) return Future.value(null);
    return showDialog<_StagedBatchChoice>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_StagedBatchChoice.stay),
            child: const Text('Остаться'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_StagedBatchChoice.discard),
            child: const Text('Отбросить'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(_StagedBatchChoice.apply),
            child: const Text('Применить'),
          ),
        ],
      ),
    );
  }

  /// Сохраняет метаданные всех файлов во всех рабочих областях (только файлы с заполненными метаданными).
  Future<void> _saveAllMetadata() async {
    final workspaces = ref.read(workspacesProvider);
    final dbFiles = ref.read(filesProvider).value ?? [];
    if (dbFiles.isEmpty || workspaces.entries.isEmpty) {
      if (mounted) _showSuccess('Нет файлов с метаданными для сохранения.');
      return;
    }
    final sep = Platform.pathSeparator;
    final toSave = <AppFile>[];
    for (final entry in workspaces.entries) {
      final wp = entry.path;
      final prefix = wp.endsWith(sep) ? wp : wp + sep;
      for (final f in dbFiles) {
        if (f.path != wp && !f.path.startsWith(prefix)) continue;
        final hasMeta =
            (f.metadataTitle != null && f.metadataTitle!.trim().isNotEmpty) ||
            (f.metadataKeywords != null &&
                f.metadataKeywords!.trim().isNotEmpty);
        if (hasMeta) toSave.add(f);
      }
    }
    if (toSave.isEmpty) {
      if (mounted) _showSuccess('Нет файлов с метаданными для сохранения.');
      return;
    }
    int saved = 0;
    for (final f in toSave) {
      final title = metadataTitleForWrite(
        title: f.metadataTitle,
        isEditorial: f.isEditorial,
        city: f.editorialCity,
        country: f.editorialCountry,
        editorialDateMillis: f.editorialDate,
      );
      var current = f;
      if (title.isNotEmpty && title != (f.metadataTitle?.trim() ?? '')) {
        current = f.copyWith(metadataTitle: title);
        await ref.read(filesProvider.notifier).updateFile(current);
        if (_isLive &&
            (_selectedExistingFile?.id == current.id ||
                _selectedExistingFile?.path == current.path)) {
          setState(() {
            _selectedExistingFile = current;
            _titleController.text = title;
          });
          ref.read(editorialStateProvider.notifier).syncFromFile(current);
        }
      }
      if (AppConstants.isVideo(current.path)) {
        // Видео не получает EXIF, но город и страна уже в заголовке каталога.
        saved++;
        continue;
      }
      final ok = await MetadataService.writeMetadata(
        filePath: current.path,
        title: title,
        keywords: current.metadataKeywords?.trim() ?? '',
        description: current.metadataDescription?.trim(),
        city:
            current.isEditorial ? (current.editorialCity?.trim() ?? '') : null,
        country:
            current.isEditorial
                ? (current.editorialCountry?.trim() ?? '')
                : null,
        shootDate: _shootDateOf(current),
      );
      if (ok) saved++;
    }
    if (mounted) {
      _showSuccess(
        'Сохранить все: записано $saved из ${toSave.length} файлов.',
      );
    }
  }

  void _showSuccess(String message) {
    if (!_isLive) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isDark ? AppTheme.successColorDark : AppTheme.successColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  DateTime? _shootDateOf(AppFile file) {
    if (!file.isEditorial || file.editorialDate == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(file.editorialDate!);
  }

  /// Appends location and date to the end of the title
  /// following Adobe Stock editorial guidelines.
  String _appendEditorialToTitle({
    required String title,
    required String city,
    required String country,
    required DateTime? date,
  }) {
    return appendEditorialToTitle(
      title: title,
      city: city,
      country: country,
      date: date,
    );
  }

  Future<({bool replace, bool applyToAll})?> _showRegenerateDialog(
    String filename,
  ) async {
    bool applyToAll = false;
    return showDialog<({bool replace, bool applyToAll})>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Перегенерировать теги?'),
              content: SizedBox(
                width: 400, // Strict max width for better design
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Файл "$filename" уже содержит метаданные. Заменить их?',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 20),
                    InkWell(
                      onTap: () {
                        setState(() => applyToAll = !applyToAll);
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 4.0,
                          horizontal: 4.0,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: applyToAll,
                                onChanged: (val) {
                                  setState(() => applyToAll = val ?? false);
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Применить ко всем оставшимся файлам',
                              style: TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      () => Navigator.of(
                        context,
                      ).pop((replace: false, applyToAll: applyToAll)),
                  child: const Text('Пропустить'),
                ),
                FilledButton(
                  onPressed:
                      () => Navigator.of(
                        context,
                      ).pop((replace: true, applyToAll: applyToAll)),
                  child: const Text('Заменить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showBatchGenerationErrors(
    String summary,
    Map<String, String> failures,
  ) {
    final colors = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: SelectableText(
          'Атрибутация завершена с ошибками.\n$summary',
          style: TextStyle(color: colors.onErrorContainer),
        ),
        backgroundColor: colors.errorContainer,
        closeIconColor: colors.onErrorContainer,
        duration: const Duration(minutes: 60),
        showCloseIcon: true,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Подробности',
          textColor: colors.onErrorContainer,
          onPressed: () {
            if (!_isLive) return;
            showDialog<void>(
              context: context,
              builder:
                  (context) => AlertDialog(
                    title: const Text('Ошибки атрибутации'),
                    scrollable: true,
                    content: SizedBox(
                      width: 640,
                      child: SelectableText(
                        '$summary\n\n'
                        'Файлы с ошибками остались выделенными. '
                        'Для повторной обработки нажмите AI Tag.\n\n'
                        '${failures.entries.map((e) => '${e.key}\n${e.value}').join('\n\n')}',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Закрыть'),
                      ),
                    ],
                  ),
            );
          },
        ),
      ),
    );
  }

  void _showError(String message) {
    if (!_isLive) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: SelectableText('Error: $message'),
        backgroundColor: isDark ? AppTheme.errorColorDark : AppTheme.errorColor,
        duration: const Duration(minutes: 60),
        showCloseIcon: true,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final currentPath = ref.watch(workspacesProvider).currentPath;

    ref.listen(workspacesProvider, (prev, next) {
      if (prev?.currentPath != next.currentPath) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!await _preserveUnsavedDraft()) return;
          if (!mounted) return;
          final nextScope = SearchScope.folder(
            folderPath: next.currentPath ?? '',
            includeSubfolders: false,
          );
          ref
              .read(organizationSearchSettingsProvider.notifier)
              .setScope(nextScope);
          ref.read(organizationSearchSettingsProvider.notifier).persist();
          await _handleScopeChanged(nextScope);
        });
      }
    });

    ref.listen(organizationSearchSettingsProvider, (prev, next) {
      if (prev?.scope != next.scope) {
        final previousScope = prev?.scope;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (_scopePromptOpen) return;
          if (!await _preserveUnsavedDraft()) {
            if (previousScope != null && mounted) {
              ref
                  .read(organizationSearchSettingsProvider.notifier)
                  .setScope(previousScope);
            }
            return;
          }
          if (!mounted) return;
          await _handleScopeChanged(next.scope);
        });
      }
    });

    ref.listen(workspaceCommandProvider, (prev, next) {
      if (next == null || prev?.sequence == next.sequence) return;
      switch (next.command) {
        case WorkspaceCommand.importFiles:
          _addFilesFromPicker();
        case WorkspaceCommand.openFolder:
          _pickFile();
        case WorkspaceCommand.importCsv:
          _handleImportCsv();
        case WorkspaceCommand.refresh:
          _refreshCurrentWorkspace();
      }
    });

    final activeScope = ref.watch(organizationSearchSettingsProvider).scope;
    if (activeScope.type == SearchScopeType.project &&
        activeScope.projectId.isNotEmpty) {
      ref.listen(projectFoldersProvider(activeScope.projectId), (prev, next) {
        if (next.value != null && next.value != prev?.value) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _handleScopeChanged(activeScope);
          });
        }
      });
    }
    ref.listen(refreshWorkspaceProvider, (prev, next) {
      if (next > 0 && currentPath != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _refreshCurrentWorkspace(),
        );
      }
    });

    ref.listen(filesProvider, (prev, next) {
      final dbFiles = next.value ?? [];
      if (_selectedExistingFile != null) {
        final updatedFile = dbFiles.firstWhereOrNull(
          (f) => f.id == _selectedExistingFile!.id,
        );
        if (updatedFile != null && updatedFile != _selectedExistingFile) {
          setState(() {
            _selectedExistingFile = updatedFile;
            if (_selectedPaths.length == 1) {
              ref
                  .read(editorialStateProvider.notifier)
                  .syncFromFile(updatedFile);
            }
          });
        }
      }
    });

    final filesFromProvider = ref.watch(filesProvider).value ?? <AppFile>[];
    final scope = activeScope;

    final allCatalogAsync = ref.watch(allCatalogFilesProvider);
    final dbFiles =
        (allCatalogAsync.value != null && allCatalogAsync.value!.isNotEmpty)
            ? allCatalogAsync.value!
            : filesFromProvider;

    List<String> projectFolders = const [];
    List<String> collectionFileIds = const [];
    List<String> selectionFileIds = const [];

    if (scope.type == SearchScopeType.project && scope.projectId.isNotEmpty) {
      projectFolders =
          ref.watch(projectFoldersProvider(scope.projectId)).value ?? const [];
    } else if (scope.type == SearchScopeType.collection &&
        scope.collectionId.isNotEmpty) {
      collectionFileIds =
          ref.watch(collectionFileIdsProvider(scope.collectionId)).value ??
          const [];
    } else if (scope.type == SearchScopeType.selection) {
      selectionFileIds = ref.watch(selectionFileIdsProvider).value ?? const [];
    }

    final dbFilesInScope = _resolveScopeDbFiles(
      scope,
      dbFiles,
      projectFolders: projectFolders,
      collectionFileIds: collectionFileIds,
      selectionFileIds: selectionFileIds,
    );

    final currentLocalFiles =
        (scope.type == SearchScopeType.folder ||
                scope.type == SearchScopeType.all ||
                scope.type == SearchScopeType.project)
            ? _localFiles
                .where((lf) {
                  if (scope.type == SearchScopeType.project) {
                    return projectFolders.any(
                      (folder) => isPathInFolder(
                        lf.path,
                        folder,
                        includeSubfolders: scope.includeSubfolders,
                      ),
                    );
                  }
                  if (scope.type == SearchScopeType.folder) {
                    final targetPath =
                        scope.folderPath.isNotEmpty
                            ? scope.folderPath
                            : (ref.read(workspacesProvider).currentPath ?? '');
                    return isPathInFolder(
                      lf.path,
                      targetPath,
                      includeSubfolders: scope.includeSubfolders,
                    );
                  }
                  return true;
                })
                .where((lf) => !dbFilesInScope.any((df) => df.path == lf.path))
                .toList()
            : <File>[];

    final filtered = _applyFilters(currentLocalFiles, dbFilesInScope);
    final filteredLocals = filtered.locals;
    final filteredDb = filtered.db;

    final visiblePaths = <String>{
      for (final file in filteredDb) file.path,
      for (final file in filteredLocals) file.path,
    };
    final hiddenSelectedCount =
        _selectedPaths.where((path) => !visiblePaths.contains(path)).length;

    final batchInfo = _buildBatchInfo(_selectedPaths.toList());

    void selectAllVisible() => _selectAll(filteredDb, filteredLocals);

    return Shortcuts(
      shortcuts: const {
        SingleActivator(
          LogicalKeyboardKey.keyA,
          meta: true,
        ): SelectAllTextIntent(SelectionChangedCause.keyboard),
        SingleActivator(
          LogicalKeyboardKey.keyA,
          control: true,
        ): SelectAllTextIntent(SelectionChangedCause.keyboard),
      },
      child: Actions(
        actions: {
          SelectAllTextIntent: CallbackAction<SelectAllTextIntent>(
            onInvoke: (intent) {
              final editor =
                  FocusManager.instance.primaryFocus?.context
                      ?.findAncestorStateOfType<EditableTextState>();
              if (editor != null) {
                if (editor.widget.selectionEnabled) {
                  editor.selectAll(intent.cause);
                }
              } else {
                selectAllVisible();
              }
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: _gridFocusNode,
          autofocus: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final workspaceHeight = constraints.maxHeight;
              return Column(
            children: [
              GenerationScopeBar(
                breadcrumb: _scopeBreadcrumb(scope),
                breadcrumbTooltip: _scopeBreadcrumbTooltip(scope),
                allCount: _filteredCountFor(
                  ScopeStatusSegment.all,
                  currentLocalFiles,
                  dbFilesInScope,
                ),
                newCount: _filteredCountFor(
                  ScopeStatusSegment.newFiles,
                  currentLocalFiles,
                  dbFilesInScope,
                ),
                readyCount: _filteredCountFor(
                  ScopeStatusSegment.readyToUpload,
                  currentLocalFiles,
                  dbFilesInScope,
                ),
                segment: _statusSegment,
                onSegmentChanged:
                    (value) => setState(() => _statusSegment = value),
                selectedCount: _selectedPaths.length,
                hiddenSelectedCount: hiddenSelectedCount,
                isGridView: _isGridView,
                onViewModeChanged:
                    (value) => setState(() => _isGridView = value),
                sortMode: _sortMode,
                onSortChanged: (value) => setState(() => _sortMode = value),
                filterType: _filterType,
                onFilterTypeChanged: (value) {
                  setState(() => _filterType = value);
                  final category =
                      value == 'images'
                          ? MediaCategoryFilter.image
                          : (value == 'videos'
                              ? MediaCategoryFilter.video
                              : null);
                  ref
                      .read(organizationSearchSettingsProvider.notifier)
                      .updateFilters(
                        (filters) =>
                            filters.copyWith(mediaCategory: category),
                      );
                  ref
                      .read(organizationSearchSettingsProvider.notifier)
                      .persist();
                },
                activeTagFilters: _activeTagFilters,
                onTagFiltersChanged:
                    (updated) => setState(() => _activeTagFilters = updated),
                visibleCount: filteredDb.length + filteredLocals.length,
                onSelectAll: selectAllVisible,
                onRefresh: () => _refreshCurrentWorkspace(),
              ),
              Expanded(
                child: _buildGridArea(
                  palette: palette,
                  scope: scope,
                  filteredLocals: filteredLocals,
                  filteredDb: filteredDb,
                  unfilteredCount:
                      currentLocalFiles.length + dbFilesInScope.length,
                ),
              ),
              _buildEditorArea(
                palette,
                batchInfo,
                hiddenSelectedCount,
                workspaceHeight,
              ),
            ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ─── Контекст области ──────────────────────────────────────────────────────

  List<String> _scopeBreadcrumb(SearchScope scope) {
    switch (scope.type) {
      case SearchScopeType.folder:
        final path =
            scope.folderPath.isNotEmpty
                ? scope.folderPath
                : (ref.read(workspacesProvider).currentPath ?? '');
        if (path.isEmpty) return const ['Без области'];
        final parts =
            path
                .split(Platform.pathSeparator)
                .where((part) => part.isNotEmpty)
                .toList();
        if (parts.isEmpty) return [path];
        return [if (parts.length > 3) '…', ...parts.skip(parts.length > 3 ? parts.length - 3 : 0)];
      case SearchScopeType.project:
        final projects = ref.watch(projectsProvider).value ?? const [];
        final project =
            projects.firstWhereOrNull((p) => p.id == scope.projectId);
        return ['Проект', project?.name ?? 'без имени'];
      case SearchScopeType.collection:
        final collections = ref.watch(collectionsProvider).value ?? const [];
        final collection =
            collections.firstWhereOrNull((c) => c.id == scope.collectionId);
        return ['Коллекция', collection?.name ?? 'без имени'];
      case SearchScopeType.selection:
        return const ['Отбор'];
      case SearchScopeType.all:
        return const ['Все материалы'];
    }
  }

  String _scopeBreadcrumbTooltip(SearchScope scope) {
    switch (scope.type) {
      case SearchScopeType.folder:
        final path =
            scope.folderPath.isNotEmpty
                ? scope.folderPath
                : (ref.read(workspacesProvider).currentPath ?? '');
        return path.isEmpty ? 'Выберите папку в верхней панели' : path;
      case SearchScopeType.project:
        return 'Проект: ${_scopeBreadcrumb(scope).skip(1).join(' ')}';
      case SearchScopeType.collection:
        return 'Коллекция: ${_scopeBreadcrumb(scope).skip(1).join(' ')}';
      case SearchScopeType.selection:
        return 'Отбор — файлы, сохранённые пользователем';
      case SearchScopeType.all:
        return 'Все материалы во всех подключённых папках';
    }
  }

  // ─── Сетка ─────────────────────────────────────────────────────────────────

  Widget _buildGridArea({
    required AppPalette palette,
    required SearchScope scope,
    required List<File> filteredLocals,
    required List<AppFile> filteredDb,
    required int unfilteredCount,
  }) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (details) {
        setState(() => _isDragging = false);
        if (details.files.isEmpty) return;
        final dbFiles = ref.read(filesProvider).value ?? [];
        setState(() {
          for (var i = 0; i < details.files.length; i++) {
            final path = details.files[i].path;
            final existingFile = dbFiles.firstWhereOrNull(
              (f) => f.path == path,
            );
            if (existingFile != null) {
              _selectedPaths.add(path);
              if (i == 0) {
                _selectedExistingFile = existingFile;
                _selectedLocalInspectorFile = null;
                _titleController.text = existingFile.metadataTitle ?? '';
                _keywordsController.text = existingFile.metadataKeywords ?? '';
                _descriptionController.text =
                    existingFile.metadataDescription ?? '';
              }
            } else {
              final newFile = File(path);
              if (!_localFiles.any((f) => f.path == path)) {
                _localFiles.add(newFile);
              }
              _selectedPaths.add(path);
              if (i == 0) {
                _selectedLocalInspectorFile = newFile;
                _selectedExistingFile = null;
                _clearResults();
              }
            }
          }
        });
        _syncGridSelectionToProvider();
      },
      child: Container(
        color:
            _isDragging
                ? palette.selection.withValues(alpha: 0.06)
                : palette.canvas,
        child: Builder(
          builder: (context) {
            final filesState = ref.watch(filesProvider);
            return filesState.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Не удалось загрузить файлы: $e')),
              data: (filesFromProvider) {
                final workspacePath =
                    ref.read(workspacesProvider).currentPath;
                final isFolderScopeEmpty =
                    scope.type == SearchScopeType.folder &&
                    scope.folderPath.isEmpty &&
                    (workspacePath == null || workspacePath.isEmpty);

                if (isFolderScopeEmpty) {
                  return _buildEmptyState(
                    palette,
                    icon: Icons.folder_open_outlined,
                    message:
                        'Выберите папку в верхней панели\nили нажмите «Импорт» → «Открыть папку».',
                  );
                }

                if (filteredLocals.isEmpty && filteredDb.isEmpty) {
                  if (unfilteredCount == 0) {
                    return _buildEmptyState(
                      palette,
                      icon: switch (scope.type) {
                        SearchScopeType.project => Icons.business_center_outlined,
                        SearchScopeType.collection =>
                          Icons.collections_bookmark_outlined,
                        SearchScopeType.selection => Icons.check_box_outlined,
                        _ => Icons.photo_library_outlined,
                      },
                      message: switch (scope.type) {
                        SearchScopeType.project =>
                          'В этом проекте пока нет файлов.\nДобавьте папки к проекту в меню области.',
                        SearchScopeType.collection =>
                          'В этой коллекции пока нет материалов.\nВыделите файлы в сетке и нажмите «+ Выбранные» в меню области.',
                        SearchScopeType.selection =>
                          '«Отбор» пуст.\nВыделите файлы в сетке и нажмите «+ Выбранные» в секции «Отбор».',
                        _ =>
                          'В этой папке нет изображений.\nНажмите «Импорт» → «Открыть папку».\nЕсли файлы есть — выдайте приложению доступ к диску\n(Системные настройки → Конфиденциальность → Полный доступ к диску).',
                      },
                    );
                  }
                  return _buildEmptyState(
                    palette,
                    icon: Icons.filter_list_off,
                    message: 'Нет файлов, подходящих под фильтр.',
                  );
                }

                final items = _buildGridItems(filteredLocals, filteredDb);
                final allPaths = items.map((item) => item.path).toList();

                return Listener(
                  onPointerDown: (_) => _gridFocusNode.requestFocus(),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (!_isGridView) {
                        return _buildGridList(items, allPaths);
                      }
                      final columns = _gridColumns(constraints.maxWidth);
                      final available =
                          constraints.maxWidth - AppSizes.pagePadding * 2;
                      final cardWidth =
                          (available - AppSizes.gridGap * (columns - 1)) /
                          columns;
                      final itemHeight =
                          cardWidth / AppSizes.cardImageAspectRatio +
                          AppSizes.cardFooterMinHeight +
                          2;
                      return GridView.builder(
                        controller: _gridScrollController,
                        padding: const EdgeInsets.all(AppSizes.pagePadding),
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              crossAxisSpacing: AppSizes.gridGap,
                              mainAxisSpacing: AppSizes.gridGap,
                              mainAxisExtent: itemHeight,
                            ),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return GenerationGridCard(
                            imagePath: item.path,
                            filename: item.filename,
                            isSelected: _selectedPaths.contains(item.path),
                            isAccessible: item.isAccessible,
                            workflowStatus: item.workflowStatus,
                            tags: item.tags,
                            onTap:
                                () => _toggleSelection(
                                  index,
                                  item.path,
                                  allPaths,
                                  existing: item.existing,
                                  local: item.local,
                                ),
                            onOpenPreview: () => _showFullPreview(item.path),
                            onMenu:
                                () => _showCardMenu(
                                  context,
                                  item.path,
                                  allPaths,
                                  existing: item.existing,
                                  local: item.local,
                                ),
                          );
                        },
                      );
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  int _gridColumns(double availableWidth) {
    final available = availableWidth - AppSizes.pagePadding * 2;
    final columns =
        ((available + AppSizes.gridGap) /
                (AppSizes.preferredCardMinWidth + AppSizes.gridGap))
            .floor();
    return columns < 1 ? 1 : columns;
  }

  Widget _buildGridList(
    List<_GridItem> items,
    List<String> allPaths,
  ) {
    return ListView.separated(
      controller: _gridScrollController,
      padding: const EdgeInsets.all(AppSizes.pagePadding),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final item = items[index];
        return GenerationFileListTile(
          imagePath: item.path,
          filename: item.filename,
          isSelected: _selectedPaths.contains(item.path),
          isAccessible: item.isAccessible,
          workflowStatus: item.workflowStatus,
          tags: item.tags,
          onTap:
              () => _toggleSelection(
                index,
                item.path,
                allPaths,
                existing: item.existing,
                local: item.local,
              ),
          onOpenPreview: () => _showFullPreview(item.path),
          onMenu:
              () => _showCardMenu(
                context,
                item.path,
                allPaths,
                existing: item.existing,
                local: item.local,
              ),
        );
      },
    );
  }

  List<_GridItem> _buildGridItems(
    List<File> filteredLocals,
    List<AppFile> filteredDb,
  ) {
    final items = <_GridItem>[
      for (final file in filteredLocals)
        _GridItem(
          path: file.path,
          filename: file.path.split(Platform.pathSeparator).last,
          tags: const [],
          existing: null,
          local: file,
          isAccessible: true,
          workflowStatus: WorkflowStatus.newFile,
        ),
      for (final file in filteredDb)
        _GridItem(
          path: file.path,
          filename: file.filename,
          tags: file.tags,
          existing: file,
          local: null,
          isAccessible: File(file.path).existsSync(),
          workflowStatus: file.workflowStatus,
        ),
    ];
    switch (_sortMode) {
      case GridSortMode.name:
        items.sort(
          (a, b) =>
              a.filename.toLowerCase().compareTo(b.filename.toLowerCase()),
        );
      case GridSortMode.date:
        items.sort((a, b) {
          final aDate = a.existing?.createdAt ?? 0;
          final bDate = b.existing?.createdAt ?? 0;
          if (aDate != bDate) return bDate.compareTo(aDate);
          return a.filename.toLowerCase().compareTo(b.filename.toLowerCase());
        });
      case GridSortMode.status:
        items.sort((a, b) {
          final byStatus = a.workflowStatus.index.compareTo(
            b.workflowStatus.index,
          );
          if (byStatus != 0) return byStatus;
          return a.filename.toLowerCase().compareTo(b.filename.toLowerCase());
        });
    }
    return items;
  }

  Widget _buildEmptyState(
    AppPalette palette, {
    required IconData icon,
    required String message,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: palette.textMuted),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: palette.textMuted),
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Открыть папку'),
          ),
        ],
      ),
    );
  }

  // ─── Нижний редактор ───────────────────────────────────────────────────────

  Widget _buildEditorArea(
    AppPalette palette,
    BatchFieldInfo batchInfo,
    int hiddenSelectedCount,
    double workspaceHeight,
  ) {
    final maxByFraction = workspaceHeight * AppSizes.editorMaxHeightFraction;
    final maxEditor = math.min(
      maxByFraction,
      workspaceHeight -
          AppSizes.scopeBar -
          AppSizes.gridMinVisibleHeight,
    );
    final forceCollapsed = maxEditor < AppSizes.editorMinHeight;
    final isCollapsed =
        _selectedPaths.isEmpty || _editorCollapsedManual || forceCollapsed;
    if (isCollapsed) {
      if (_selectedPaths.isEmpty) {
        return const SizedBox(
          height: AppSizes.editorCollapsedHeight,
          child: _CollapsedEditorHint(),
        );
      }
      return SizedBox(
        height: AppSizes.editorCollapsedHeight,
        child: _CollapsedEditorBar(
          onExpand:
              () => forceCollapsed
                  ? _showEditorSheet(batchInfo, hiddenSelectedCount)
                  : setState(() => _editorCollapsedManual = false),
        ),
      );
    }
    final height = (_editorHeightOverride ?? AppSizes.editorDefaultHeight)
        .clamp(AppSizes.editorMinHeight, maxEditor);
    return SizedBox(
      height: height,
      child: _buildEditorPanel(
        batchInfo: batchInfo,
        hiddenSelectedCount: hiddenSelectedCount,
        height: height,
        onHeightChanged: (value) {
          setState(() {
            _editorHeightOverride = value.clamp(
              AppSizes.editorMinHeight,
              maxEditor,
            );
          });
        },
      ),
    );
  }

  Widget _buildEditorPanel({
    required BatchFieldInfo batchInfo,
    required int hiddenSelectedCount,
    required double height,
    required ValueChanged<double> onHeightChanged,
    bool inSheet = false,
  }) {
    return GenerationEditorPanel(
      selectedPaths: _selectedPaths.toList(),
      selectedFile: _selectedExistingFile,
      selectedLocalPath: _selectedLocalInspectorFile?.path,
      hiddenSelectedCount: hiddenSelectedCount,
      titleController: _titleController,
      descriptionController: _descriptionController,
      keywordsController: _keywordsController,
      metadataDirty: _metadataDirty,
      isBusy: _isLoading,
      isSaving: _isSaving,
      draftRevision: _editorDraftRevision,
      batchInfo: batchInfo,
      onClearSelection: _clearSelection,
      onSaveSingle: _saveChanges,
      onSingleChanged: () => setState(() => _metadataDirty = true),
      onApplyBatch: _applyBatchChanges,
      onBatchDraftChanged: (request) {
        _pendingBatchRequest = request;
      },
      onGenerateAI: _generateAI,
      onGenerateBatchAI: _generateBatchAI,
      onExportCsv: _handleExportCsv,
      onImportCsv: _handleImportCsv,
      onRunQc: _runQcForSelection,
      onQueue: _enqueueSelection,
      onSaveAllMetadata: _saveAllMetadata,
      collapsed: false,
      onCollapsedChanged: (value) async {
        if (value && !await _resolveStagedBatchBeforeSelectionChange()) {
          return;
        }
        if (!mounted) return;
        if (inSheet) {
          Navigator.of(context).pop();
          return;
        }
        setState(() => _editorCollapsedManual = value);
      },
      height: height,
      onHeightChanged: inSheet ? (_) {} : onHeightChanged,
    );
  }

  void _showEditorSheet(BatchFieldInfo batchInfo, int hiddenSelectedCount) {
    final size = MediaQuery.sizeOf(context);
    final height = (size.height * 0.75).clamp(
      AppSizes.editorMinHeight,
      760.0,
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppPalette.of(ctx).canvas,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.panel),
        ),
        child: SizedBox(
          width: math.min(size.width - 48, 1100),
          height: height,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.pagePadding,
                  AppSpacing.sm,
                  AppSpacing.xs,
                  0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Редактор метаданных',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppPalette.of(ctx).text,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Закрыть',
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _buildEditorPanel(
                  batchInfo: batchInfo,
                  hiddenSelectedCount: hiddenSelectedCount,
                  height: height,
                  onHeightChanged: (_) {},
                  inSheet: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Полный просмотр и меню карточки ───────────────────────────────────────

  void _showFullPreview(String path) {
    final isVideo = AppConstants.isVideo(path);
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final palette = AppPalette.of(ctx);
        return Dialog(
          backgroundColor: palette.canvas,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.panel),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080, maxHeight: 760),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSizes.pagePadding,
                    AppSpacing.sm,
                    AppSpacing.sm,
                    AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          path.split(Platform.pathSeparator).last,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: palette.text,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Закрыть',
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSizes.pagePadding,
                      0,
                      AppSizes.pagePadding,
                      AppSizes.pagePadding,
                    ),
                    child:
                        isVideo
                            ? VideoPlayerWidget(videoPath: path, hasAudio: false)
                            : Image.file(
                              File(path),
                              fit: BoxFit.contain,
                              errorBuilder:
                                  (_, __, ___) => Center(
                                    child: Text(
                                      'Файл недоступен',
                                      style: TextStyle(color: palette.textMuted),
                                    ),
                                  ),
                            ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCardMenu(
    BuildContext context,
    String path,
    List<String> allPaths, {
    AppFile? existing,
    File? local,
  }) async {
    final index = allPaths.indexOf(path);
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(path.split(Platform.pathSeparator).last),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop('preview'),
            child: const Text('Открыть полностью'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop('toggle'),
            child: Text(
              _selectedPaths.contains(path)
                  ? 'Снять выделение с файла'
                  : 'Выделить файл',
            ),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'preview') {
      _showFullPreview(path);
    } else if (action == 'toggle') {
      if (_selectedPaths.contains(path)) {
        setState(() => _selectedPaths.remove(path));
        _syncGridSelectionToProvider();
      } else {
        _toggleSelection(
          index < 0 ? 0 : index,
          path,
          allPaths,
          existing: existing,
          local: local,
        );
      }
    }
  }

  /// Добавляет отдельные файлы через системный файловый диалог.
  Future<void> _addFilesFromPicker() async {
    try {
      final files = await openFiles();
      if (files.isEmpty || !mounted) return;
      final dbFiles = ref.read(filesProvider).value ?? const <AppFile>[];
      var added = 0;
      setState(() {
        for (final picked in files) {
          final path = picked.path;
          final existsInDb = dbFiles.any((file) => file.path == path);
          final existsLocal = _localFiles.any((file) => file.path == path);
          if (existsInDb || existsLocal) continue;
          final extension = path.split('.').last.toLowerCase();
          if (!AppConstants.imageExtensions.contains('.$extension') &&
              !AppConstants.videoExtensions.contains('.$extension')) {
            continue;
          }
          _localFiles.add(File(path));
          added++;
        }
      });
      _showSuccess(
        added > 0 ? 'Добавлено файлов: $added' : 'Новых файлов не найдено',
      );
    } catch (e) {
      _showError('Не удалось добавить файлы: $e');
    }
  }
}

class _GridItem {
  final String path;
  final String filename;
  final List<String> tags;
  final AppFile? existing;
  final File? local;
  final bool isAccessible;
  final WorkflowStatus workflowStatus;

  const _GridItem({
    required this.path,
    required this.filename,
    required this.tags,
    required this.existing,
    required this.local,
    required this.isAccessible,
    required this.workflowStatus,
  });
}

class _CollapsedEditorHint extends StatelessWidget {
  const _CollapsedEditorHint();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.pagePadding),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.edit_note_outlined, size: 18, color: palette.textMuted),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Выберите файлы для редактирования',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: palette.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _CollapsedEditorBar extends StatelessWidget {
  final VoidCallback? onExpand;

  const _CollapsedEditorBar({required this.onExpand});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.pagePadding),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.edit_note_outlined, size: 18, color: palette.textMuted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Редактор свёрнут',
              style: TextStyle(fontSize: 13, color: palette.text),
            ),
          ),
          TextButton(
            onPressed: onExpand,
            child: const Text('Открыть редактор'),
          ),
        ],
      ),
    );
  }
}
