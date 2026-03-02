import 'dart:async';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_secure_bookmarks/macos_secure_bookmarks.dart';
import 'package:pool/pool.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/metadata_service.dart';
import '../../../core/services/geocoding_service.dart';
import '../../../core/state/files_provider.dart';
import '../../../core/state/settings_provider.dart';
import '../../../core/constants/app_constants.dart';

import 'video_player_widget.dart';
import '../../../core/state/workspaces_provider.dart';
import '../../../models/app_file.dart';
import '../../../models/generation_options.dart';
import '../../../models/workflow_status.dart';
import 'widgets/generation_editorial_section.dart';
import 'widgets/generation_filter_bar.dart';
import 'widgets/generation_top_bar.dart';
import 'widgets/generation_tools_bar.dart';
import 'widgets/generation_widgets.dart';

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

class GenerationScreen extends ConsumerStatefulWidget {
  const GenerationScreen({super.key});

  @override
  ConsumerState<GenerationScreen> createState() => _GenerationScreenState();
}

class _GenerationScreenState extends ConsumerState<GenerationScreen> {
  final _apiClient = ApiClient();

  // Single selection for Inspector
  AppFile? _selectedExistingFile;
  File? _selectedLocalInspectorFile;

  // Local files not yet in DB
  final List<File> _localFiles = [];

  // Multi-selection
  final Set<String> _selectedPaths = {};

  bool _isLoading = false;
  int _batchTotal = 0;
  int _batchDone = 0;
  bool _isDragging = false;

  // Options
  final double _numKeywords = 15;
  final _titleController = TextEditingController();
  final _keywordsController = TextEditingController();
  final _batchTitleController = TextEditingController();
  final _batchKeywordsController = TextEditingController();

  /// Есть несохранённые изменения метаданных у выбранного файла.
  bool _metadataDirty = false;

  // Editorial
  bool _isEditorial = false;
  final _editorialCityController = TextEditingController();
  final _editorialCountryController = TextEditingController();
  final _cityFocusNode = FocusNode();
  final _countryFocusNode = FocusNode();
  DateTime? _editorialDate;

  /// Последний индекс для shift-click выделения
  int? _lastSelectedIndex;

  // Filters
  final _searchController = TextEditingController();
  String _searchQuery = '';

  /// 'all' | 'images' | 'videos'
  String _filterType = 'all';

  bool _isVideoPath(String path) => AppConstants.isVideo(path);

  /// Применяет текущие фильтры к спискам файлов и возвращает отфильтрованные списки.
  ({List<File> locals, List<AppFile> db}) _applyFilters(
    List<File> locals,
    List<AppFile> db,
  ) {
    List<File> filteredLocals = locals;
    List<AppFile> filteredDb = db;

    // Type filter
    if (_filterType == 'images') {
      filteredLocals = filteredLocals
          .where((f) => !_isVideoPath(f.path))
          .toList();
      filteredDb = filteredDb.where((f) => !_isVideoPath(f.path)).toList();
    } else if (_filterType == 'videos') {
      filteredLocals = filteredLocals
          .where((f) => _isVideoPath(f.path))
          .toList();
      filteredDb = filteredDb.where((f) => _isVideoPath(f.path)).toList();
    }

    // Text search filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filteredLocals = filteredLocals.where((f) {
        final name = f.path.split(Platform.pathSeparator).last.toLowerCase();
        return name.contains(q);
      }).toList();
      filteredDb = filteredDb.where((f) {
        return f.filename.toLowerCase().contains(q);
      }).toList();
    }

    return (locals: filteredLocals, db: filteredDb);
  }

  /// На macOS: открытый security-scoped ресурс текущей рабочей области (держим доступ, чтобы миниатюры и чтение файлов работали).
  FileSystemEntity? _currentScopedResource;

  @override
  void dispose() {
    _releaseSecurityScopedResource();
    _titleController.dispose();
    _keywordsController.dispose();
    _batchTitleController.dispose();
    _batchKeywordsController.dispose();
    _searchController.dispose();
    _editorialCityController.dispose();
    _editorialCountryController.dispose();
    _cityFocusNode.dispose();
    _countryFocusNode.dispose();
    super.dispose();
  }

  Future<void> _releaseSecurityScopedResource() async {
    if (_currentScopedResource == null) return;
    try {
      await _secureBookmarks.stopAccessingSecurityScopedResource(
        _currentScopedResource!,
      );
    } catch (_) {}
    _currentScopedResource = null;
  }

  static final _secureBookmarks = SecureBookmarks();

  /// Загружает файлы текущей рабочей области из папки (без блокировки UI).
  /// На macOS при наличии security-scoped bookmark держит доступ открытым до смены папки/dispose,
  /// чтобы миниатюры (Image.file) и чтение файлов работали.
  Future<void> _loadCurrentWorkspaceFiles() async {
    final entry = ref.read(workspacesProvider).currentEntry;
    if (entry == null || entry.path.trim().isEmpty) {
      await _releaseSecurityScopedResource();
      if (mounted) setState(() => _localFiles.clear());
      return;
    }
    final currentPath = entry.path.trim();
    await _releaseSecurityScopedResource();
    try {
      Directory dir;
      bool scopeStarted = false;
      if (Platform.isMacOS && entry.bookmark != null) {
        final entity = await _secureBookmarks.resolveBookmark(
          entry.bookmark!,
          isDirectory: true,
        );
        dir = entity as Directory;
        scopeStarted = await _secureBookmarks
            .startAccessingSecurityScopedResource(entity);
        if (!scopeStarted || !await dir.exists()) {
          if (mounted) {
            setState(() => _localFiles.clear());
            _showError('Папка не найдена или нет доступа: $currentPath');
          }
          return;
        }
        _currentScopedResource = dir;
      } else {
        // Без bookmark: используем путь напрямую (сработает при Full Disk Access)
        dir = Directory(currentPath);
      }
      final allExtensions = [
        ...AppConstants.imageExtensions,
        ...AppConstants.videoExtensions,
      ];
      final dbFiles = ref.read(filesProvider).value ?? [];
      final sep = Platform.pathSeparator;
      final prefix = currentPath.endsWith(sep)
          ? currentPath
          : currentPath + sep;
      final dbPathsInWorkspace = dbFiles
          .where((f) => f.path == currentPath || f.path.startsWith(prefix))
          .map((f) => f.path)
          .toSet();

      final List<FileSystemEntity> entities = await dir
          .list(recursive: false)
          .toList();
      if (!mounted) return;
      final newLocal = <File>[];
      for (var entity in entities) {
        if (entity is File) {
          final path = entity.path;
          final ext = path.split('.').last.toLowerCase();
          if (allExtensions.contains('.$ext') &&
              !dbPathsInWorkspace.contains(path)) {
            newLocal.add(entity);
          }
        }
      }
      if (mounted) {
        setState(() {
          _localFiles.clear();
          _localFiles.addAll(newLocal);
        });
      }
    } catch (e) {
      if (mounted) {
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
                  '3. Если приложения Stock Flou нет в списке — нажмите «+» и выберите это приложение (stock_flou.app).\n'
                  '4. Включите переключатель рядом с Stock Flou.\n'
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
                        // .../stock_flou.app/Contents/MacOS/stock_flou -> show .../stock_flou.app
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

    if (directoryPath == null) {
      // User cancelled
      return;
    }

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
      final List<FileSystemEntity> entities = await dir
          .list(recursive: false)
          .toList();

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

  void _handleSelectAll() {
    final workspacePath = ref.read(workspacesProvider).currentPath;
    if (workspacePath == null || workspacePath.isEmpty) return;

    final dbFiles = ref.read(filesProvider).value ?? [];
    final sep = Platform.pathSeparator;
    final dbFilesInWorkspace = dbFiles.where((f) {
      final p = f.path;
      return p == workspacePath || p.startsWith(workspacePath + sep);
    }).toList();

    final currentLocalFiles = _localFiles
        .where((lf) => !dbFilesInWorkspace.any((df) => df.path == lf.path))
        .toList();

    // Применяем фильтры — выделяем только видимые элементы
    final filtered = _applyFilters(currentLocalFiles, dbFilesInWorkspace);
    _selectAll(filtered.db, filtered.locals);
  }

  void _toggleSelection(
    int index,
    String path,
    List<String> allPaths, {
    AppFile? existing,
    File? local,
  }) {
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
        // Shift+Click: добавить диапазон к текущему выделению
        final start = index < _lastSelectedIndex! ? index : _lastSelectedIndex!;
        final end = index > _lastSelectedIndex! ? index : _lastSelectedIndex!;

        for (int i = start; i <= end; i++) {
          final p = allPaths[i];
          if (!_selectedPaths.contains(p)) {
            _selectedPaths.add(p);
          }
        }
      } else {
        // Обычный клик: сбросить всё, выделить только этот элемент (фокус)
        _selectedPaths.clear();
        _selectedPaths.add(path);
      }

      // Всегда устанавливаем кликнутый элемент как активный для инспектора
      if (existing != null) {
        _selectedExistingFile = existing;
        _selectedLocalInspectorFile = null;
        _titleController.text = existing.metadataTitle ?? '';
        _keywordsController.text = existing.metadataKeywords ?? '';
        _isEditorial = existing.isEditorial;
        _metadataDirty = false;
      } else if (local != null) {
        _selectedLocalInspectorFile = local;
        _selectedExistingFile = null;
        _isEditorial = false;
        _clearResults();
      }
      // Загружаем editorial поля
      if (existing != null) {
        _editorialCityController.text = existing.editorialCity ?? '';
        _editorialCountryController.text = existing.editorialCountry ?? '';
        _editorialDate = existing.editorialDate != null
            ? DateTime.fromMillisecondsSinceEpoch(existing.editorialDate!)
            : null;
      } else {
        _editorialCityController.clear();
        _editorialCountryController.clear();
        _editorialDate = null;
      }

      // Если переходим в режим множественного выбора, очищаем батч-контроллеры
      if (_selectedPaths.length > 1) {
        _batchTitleController.clear();
        _batchKeywordsController.clear();
      }

      _lastSelectedIndex = index;
    });
  }

  void _selectAll(List<AppFile> dbFiles, List<File> localFiles) {
    setState(() {
      final totalCount = dbFiles.length + localFiles.length;
      if (_selectedPaths.length == totalCount) {
        _selectedPaths.clear();
        _selectedExistingFile = null;
        _selectedLocalInspectorFile = null;
      } else {
        for (final f in dbFiles) {
          _selectedPaths.add(f.path);
        }
        for (final f in localFiles) {
          _selectedPaths.add(f.path);
        }
      }
    });
  }

  void _clearResults() {
    _titleController.clear();
    _keywordsController.clear();
  }

  Future<void> _generateAI() async {
    final fileToProcess =
        _selectedLocalInspectorFile ??
        (_selectedExistingFile != null
            ? File(_selectedExistingFile!.path)
            : null);
    if (fileToProcess == null) return;

    final settings = ref.read(settingsProvider).value;
    if (settings == null ||
        settings.apiKey == null ||
        settings.apiKey!.isEmpty) {
      _showError('Configure API key in Settings first.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final options = GenerationOptions(
        numberOfKeywords: _numKeywords.toInt(),
        shortTitle: false,
      );

      final metadata = await _apiClient.generateMetadata(
        apiKey: settings.apiKey!,
        filePath: fileToProcess.path,
        options: options,
      );

      final fetchedTitle = metadata['title'] ?? '';
      final List<dynamic> fetchedKeywords = metadata['keywords'] ?? [];
      final keywordsString = fetchedKeywords.join(', ');

      // Если editorial — формируем prefix из EXIF и geocoding
      String finalTitle = fetchedTitle;
      if (_isEditorial) {
        // Загружаем EXIF если ещё не загружены
        if (_editorialDate == null ||
            (_editorialCityController.text.isEmpty &&
                _editorialCountryController.text.isEmpty)) {
          final exif = await MetadataService.readExifLocationAndDate(
            fileToProcess.path,
          );
          if (exif.date != null && _editorialDate == null) {
            _editorialDate = exif.date;
          }
          if (exif.lat != null &&
              exif.lon != null &&
              _editorialCityController.text.isEmpty) {
            final geo = await GeocodingService.resolve(exif.lat, exif.lon);
            if (geo.city != null) _editorialCityController.text = geo.city!;
            if (geo.country != null || geo.state != null) {
              _editorialCountryController.text = geo.state ?? geo.country ?? '';
            }
          }
        }
        final prefix = _formatEditorialPrefix();
        if (prefix.isNotEmpty) {
          finalTitle = '$prefix: $fetchedTitle';
        }
      }

      setState(() {
        _titleController.text = finalTitle;
        _keywordsController.text = keywordsString;
        _metadataDirty = true;
      });

      // Save to DB
      final newFileId = _selectedExistingFile?.id ?? const Uuid().v4();
      final newFile = AppFile(
        id: newFileId,
        path: fileToProcess.path,
        filename: fileToProcess.path.split(Platform.pathSeparator).last,
        metadataTitle: finalTitle,
        metadataKeywords: keywordsString,
        isEditorial: _isEditorial,
        editorialCity: _editorialCityController.text,
        editorialCountry: _editorialCountryController.text,
        editorialDate: _editorialDate?.millisecondsSinceEpoch,
        workflowStatus: WorkflowStatus.readyToUpload,
        createdAt:
            _selectedExistingFile?.createdAt ??
            DateTime.now().millisecondsSinceEpoch,
      );

      await ref.read(filesProvider.notifier).addFile(newFile);

      // Save to original file
      if (!AppConstants.isVideo(fileToProcess.path)) {
        await MetadataService.writeMetadata(
          filePath: fileToProcess.path,
          title: finalTitle,
          keywords: keywordsString,
        );
      }

      // Keep it selected
      setState(() {
        _selectedExistingFile = newFile;
        _selectedLocalInspectorFile = null;
        _localFiles.removeWhere((f) => f.path == fileToProcess.path);
      });
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _generateBatchAI() async {
    if (_selectedPaths.isEmpty) return;

    final settings = ref.read(settingsProvider).value;
    if (settings == null ||
        settings.apiKey == null ||
        settings.apiKey!.isEmpty) {
      _showError('Configure API key in Settings first.');
      return;
    }

    final dbFiles = ref.read(filesProvider).value ?? [];
    final selectedFiles = _selectedPaths.map((path) {
      final existing = dbFiles.firstWhereOrNull((f) => f.path == path);
      if (existing != null) return existing;
      return File(path);
    }).toList();

    setState(() {
      _isLoading = true;
      _batchTotal = selectedFiles.length;
      _batchDone = 0;
    });

    final dialogMutex = _AsyncMutex();
    bool?
    replaceAllDecision; // null = ask, true = replace all, false = skip all

    // Adaptive concurrency: Use up to 3 parallel requests for now
    final pool = Pool(3);
    final List<Future> tasks = [];

    for (final fileObj in selectedFiles) {
      tasks.add(
        pool.withResource(() async {
          try {
            final path = fileObj is AppFile
                ? fileObj.path
                : (fileObj as File).path;

            // Check if file already has tags
            final isAppFileWithTags =
                fileObj is AppFile &&
                (fileObj.metadataTitle?.isNotEmpty ?? false) &&
                (fileObj.metadataKeywords?.isNotEmpty ?? false);

            bool shouldGenerate = true;

            if (isAppFileWithTags) {
              if (replaceAllDecision == true) {
                shouldGenerate = true;
              } else if (replaceAllDecision == false) {
                shouldGenerate = false;
              } else {
                // Ask user sequentially using Mutex
                final filename = path.split(Platform.pathSeparator).last;
                final result = await dialogMutex.synchronized(() async {
                  // Double check if another worker just clicked 'Apply to all' while we were waiting
                  if (replaceAllDecision != null) return null;
                  return await _showRegenerateDialog(filename);
                });

                if (result == null) {
                  if (replaceAllDecision != null) {
                    if (replaceAllDecision == true) {
                      shouldGenerate = true;
                    } else if (replaceAllDecision == false) {
                      shouldGenerate = false;
                    }
                  } else {
                    shouldGenerate =
                        false; // default to skip if dialog was aborted
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
              if (mounted) {
                setState(() {
                  _batchDone++;
                  _selectedPaths.remove(path);
                });
              }
              return; // Skip this file
            }

            final options = GenerationOptions(
              numberOfKeywords: _numKeywords.toInt(),
              shortTitle: false,
            );

            final metadata = await _apiClient.generateMetadata(
              apiKey: settings.apiKey!,
              filePath: path,
              options: options,
            );

            final fetchedTitle = metadata['title'] ?? '';
            final List<dynamic> fetchedKeywords = metadata['keywords'] ?? [];
            final keywordsString = fetchedKeywords.join(', ');

            // Если включён Эдиториал, формируем префикс индивидуально для каждого файла
            String finalTitle = fetchedTitle;
            String? batchCity;
            String? batchCountry;
            ({double? lat, double? lon, DateTime? date, bool hasAudio})?
            batchExif;

            if (_isEditorial) {
              batchExif = await MetadataService.readExifLocationAndDate(path);
              String localCity = '';
              String localCountry = '';

              if (batchExif.lat != null && batchExif.lon != null) {
                final geo = await GeocodingService.resolve(
                  batchExif.lat,
                  batchExif.lon,
                );
                localCity = geo.city ?? '';
                localCountry = geo.state ?? geo.country ?? '';
              }

              batchCity = localCity;
              batchCountry = localCountry;

              final prefix = _buildEditorialPrefix(
                city: localCity,
                country: localCountry,
                date: batchExif.date,
              );
              if (prefix.isNotEmpty) {
                finalTitle = '$prefix: $fetchedTitle';
              }
            }

            // Save/Update DB
            final existing = fileObj is AppFile ? fileObj : null;
            final newFile = existing != null
                ? existing.copyWith(
                    metadataTitle: finalTitle,
                    metadataKeywords: keywordsString,
                    isEditorial: _isEditorial,
                    editorialCity: batchCity,
                    editorialCountry: batchCountry,
                    editorialDate: batchExif?.date?.millisecondsSinceEpoch,
                    workflowStatus: WorkflowStatus.readyToUpload,
                  )
                : AppFile(
                    id: const Uuid().v4(),
                    path: path,
                    filename: path.split(Platform.pathSeparator).last,
                    metadataTitle: finalTitle,
                    metadataKeywords: keywordsString,
                    isEditorial: _isEditorial,
                    editorialCity: batchCity,
                    editorialCountry: batchCountry,
                    editorialDate: batchExif?.date?.millisecondsSinceEpoch,
                    workflowStatus: WorkflowStatus.readyToUpload,
                    createdAt: DateTime.now().millisecondsSinceEpoch,
                  );

            await ref.read(filesProvider.notifier).addFile(newFile);

            if (!AppConstants.isVideo(path)) {
              await MetadataService.writeMetadata(
                filePath: path,
                title: finalTitle,
                keywords: keywordsString,
              );
            }

            if (mounted) {
              setState(() {
                _batchDone++;
                // If this was the active selection, update controllers
                if (_selectedExistingFile?.path == path ||
                    _selectedLocalInspectorFile?.path == path) {
                  // Обновляем UI поля инспектора на основе данных последнего обработанного файла
                  _titleController.text = finalTitle;
                  _keywordsController.text = keywordsString;
                  _selectedExistingFile = newFile;
                  _selectedLocalInspectorFile = null;
                  _metadataDirty = true;
                }
                // Remove from local files if it was there
                _localFiles.removeWhere((f) => f.path == path);
              });
            }
          } catch (e) {
            debugPrint('Batch error for $fileObj: $e');
          }
        }),
      );
    }

    await Future.wait(tasks);
    if (mounted) {
      setState(() {
        _isLoading = false;
        _selectedPaths.clear();
      });
      _showSuccess('Batch processing complete: $_batchDone/$_batchTotal');
    }
  }

  Future<void> _saveChanges() async {
    final title = _titleController.text.trim();
    final keywords = _keywordsController.text.trim();
    final batchTitle = _batchTitleController.text.trim();
    final batchKeywords = _batchKeywordsController.text.trim();

    if (_selectedPaths.length > 1) {
      int savedCount = 0;
      final dbFiles = ref.read(filesProvider).value ?? [];

      setState(() => _isLoading = true);
      try {
        for (final path in _selectedPaths) {
          final existing = dbFiles.firstWhereOrNull((f) => f.path == path);

          AppFile newFile;
          if (existing != null) {
            newFile = existing.copyWith(
              metadataTitle: batchTitle.isNotEmpty
                  ? batchTitle
                  : existing.metadataTitle,
              metadataKeywords: batchKeywords.isNotEmpty
                  ? batchKeywords
                  : existing.metadataKeywords,
              isEditorial: _isEditorial,
              editorialCity: _editorialCityController.text.isNotEmpty
                  ? _editorialCityController.text
                  : existing.editorialCity,
              editorialCountry: _editorialCountryController.text.isNotEmpty
                  ? _editorialCountryController.text
                  : existing.editorialCountry,
              editorialDate:
                  _editorialDate?.millisecondsSinceEpoch ??
                  existing.editorialDate,
              workflowStatus: WorkflowStatus.readyToUpload,
            );
            await ref.read(filesProvider.notifier).updateFile(newFile);
          } else {
            newFile = AppFile(
              id: const Uuid().v4(),
              path: path,
              filename: path.split(Platform.pathSeparator).last,
              metadataTitle: batchTitle,
              metadataKeywords: batchKeywords,
              isEditorial: _isEditorial,
              editorialCity: _editorialCityController.text,
              editorialCountry: _editorialCountryController.text,
              editorialDate: _editorialDate?.millisecondsSinceEpoch,
              workflowStatus: WorkflowStatus.readyToUpload,
              createdAt: DateTime.now().millisecondsSinceEpoch,
            );
            await ref.read(filesProvider.notifier).addFile(newFile);
          }

          if (!AppConstants.isVideo(path)) {
            await MetadataService.writeMetadata(
              filePath: path,
              title: newFile.metadataTitle ?? '',
              keywords: newFile.metadataKeywords ?? '',
            );
          }
          savedCount++;
        }

        if (mounted) {
          setState(() {
            _metadataDirty = false;
          });
          _showSuccess('Изменения сохранены для $savedCount файлов.');
        }
      } catch (e) {
        _showError('Batch save error: $e');
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    } else if (_selectedExistingFile != null) {
      final updatedFile = _selectedExistingFile!.copyWith(
        metadataTitle: title,
        metadataKeywords: keywords,
        isEditorial: _isEditorial,
        editorialCity: _editorialCityController.text,
        editorialCountry: _editorialCountryController.text,
        editorialDate: _editorialDate?.millisecondsSinceEpoch,
        workflowStatus: WorkflowStatus.readyToUpload,
      );
      await ref.read(filesProvider.notifier).updateFile(updatedFile);

      // Also write to original file if it's an image
      if (!AppConstants.isVideo(updatedFile.path)) {
        await MetadataService.writeMetadata(
          filePath: updatedFile.path,
          title: title,
          keywords: keywords,
        );
      }

      if (mounted) {
        setState(() {
          _selectedExistingFile = updatedFile;
          _metadataDirty = false;
        });
        _showSuccess('Изменения сохранены в БД и в файл.');
      }
    } else if (_selectedLocalInspectorFile != null) {
      final newFile = AppFile(
        id: const Uuid().v4(),
        path: _selectedLocalInspectorFile!.path,
        filename: _selectedLocalInspectorFile!.path
            .split(Platform.pathSeparator)
            .last,
        metadataTitle: title,
        metadataKeywords: keywords,
        isEditorial: _isEditorial,
        editorialCity: _editorialCityController.text,
        editorialCountry: _editorialCountryController.text,
        editorialDate: _editorialDate?.millisecondsSinceEpoch,
        workflowStatus: WorkflowStatus.readyToUpload,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await ref.read(filesProvider.notifier).addFile(newFile);

      // Also write to original file if it's an image
      if (!AppConstants.isVideo(newFile.path)) {
        await MetadataService.writeMetadata(
          filePath: newFile.path,
          title: title,
          keywords: keywords,
        );
      }

      if (mounted) {
        setState(() {
          _selectedExistingFile = newFile;
          _localFiles.removeWhere(
            (f) => f.path == _selectedLocalInspectorFile!.path,
          );
          _selectedLocalInspectorFile = null;
          _metadataDirty = false;
        });
        _showSuccess('Файл добавлен в БД и метаданные записаны в файл.');
      }
    }
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
      if (AppConstants.isVideo(f.path)) {
        // Just count as saved for the DB, since we don't write Exif to video files.
        saved++;
        continue;
      }
      final ok = await MetadataService.writeMetadata(
        filePath: f.path,
        title: f.metadataTitle?.trim() ?? '',
        keywords: f.metadataKeywords?.trim() ?? '',
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isDark
            ? AppTheme.successColorDark
            : AppTheme.successColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildMultiSelectPanel(ColorScheme colorScheme) {
    final paths = _selectedPaths.toList();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          'Выбрано: ${paths.length}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            const crossAxisCount = 5;
            const spacing = 6.0;
            const maxVisible = crossAxisCount * crossAxisCount;

            final size =
                (constraints.maxWidth - spacing * (crossAxisCount - 1)) /
                crossAxisCount;

            final isOverflow = paths.length > maxVisible;
            final limit = isOverflow ? maxVisible - 1 : paths.length;

            final children = <Widget>[];

            for (var i = 0; i < limit; i++) {
              children.add(
                SizedBox(
                  width: size,
                  height: size,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: _thumbnailForPath(context, paths[i]),
                  ),
                ),
              );
            }

            if (isOverflow) {
              final remaining = paths.length - limit;
              children.add(
                SizedBox(
                  width: size,
                  height: size,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _thumbnailForPath(context, paths[limit]),
                        Container(
                          color: Colors.black.withAlpha(
                            150,
                          ), // Semi-transparent black overlay
                          alignment: Alignment.center,
                          child: Text(
                            '+$remaining',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: children,
            );
          },
        ),
        GenerationEditorialSection(
          isMulti: true,
          selectedPaths: _selectedPaths,
          selectedExistingFile: _selectedExistingFile,
          selectedLocalInspectorPath: _selectedLocalInspectorFile?.path,
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 16),
        const GenerationFormLabel(
          'BATCH TITLE (оставьте пустым для сохранения текущего)',
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _titleController,
          decoration: _inputDecoration(context),
          style: const TextStyle(fontSize: 14),
          onChanged: (_) => setState(() => _metadataDirty = true),
        ),
        const SizedBox(height: 16),
        const GenerationFormLabel(
          'BATCH KEYWORDS (оставьте пустым для сохранения текущего)',
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _keywordsController,
          maxLines: 4,
          decoration: _inputDecoration(context),
          style: const TextStyle(fontSize: 14, height: 1.5),
          onChanged: (_) => setState(() => _metadataDirty = true),
        ),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: _isLoading ? null : _saveChanges,
          icon: const Icon(Icons.save, size: 18),
          label: Text('Сохранить изменения для ${paths.length} файлов'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Кнопка «AI Tag» в левой панели — генерация тегов для всех выбранных',
          style: TextStyle(
            fontSize: 11,
            color: colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  /// Миниатюра по пути файла. На macOS требует удержания security-scoped доступа
  /// для текущей рабочей области (_currentScopedResource в _loadCurrentWorkspaceFiles).
  Widget _thumbnailForPath(BuildContext context, String path) {
    final cs = Theme.of(context).colorScheme;
    final isVideo = [
      '.mp4',
      '.mov',
      '.avi',
      '.mkv',
      '.m4v',
    ].any((e) => path.toLowerCase().endsWith(e));
    if (isVideo) {
      return Container(
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.videocam, color: cs.primary.withValues(alpha: 0.5)),
      );
    }
    return Image.file(File(path), fit: BoxFit.cover);
  }

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String _formatEditorialDate(DateTime date) {
    return '${_months[date.month - 1]} ${date.day} ${date.year}';
  }

  /// Builds an editorial prefix: "CITY, COUNTRY - MONTH DAY YEAR"
  /// Can be called with explicit values (batch) or from form controllers.
  String _buildEditorialPrefix({
    required String city,
    required String country,
    required DateTime? date,
  }) {
    final datePart = date != null ? _formatEditorialDate(date) : '';
    final locationParts = <String>[];
    if (city.isNotEmpty) locationParts.add(city);
    if (country.isNotEmpty) locationParts.add(country);
    final location = locationParts.join(', ');

    if (location.isNotEmpty && datePart.isNotEmpty) {
      return '$location - $datePart';
    } else if (location.isNotEmpty) {
      return location;
    } else if (datePart.isNotEmpty) {
      return datePart;
    }
    return '';
  }

  /// Формирует editorial prefix из текущих контроллеров формы.
  String _formatEditorialPrefix() {
    return _buildEditorialPrefix(
      city: _editorialCityController.text.trim(),
      country: _editorialCountryController.text.trim(),
      date: _editorialDate,
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
                  onPressed: () => Navigator.of(
                    context,
                  ).pop((replace: false, applyToAll: applyToAll)),
                  child: const Text('Пропустить'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(
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

  void _showError(String message) {
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
    final colorScheme = Theme.of(context).colorScheme;
    final currentPath = ref.watch(workspacesProvider).currentPath;

    ref.listen(workspacesProvider, (prev, next) {
      if (prev?.currentPath != next.currentPath) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _loadCurrentWorkspaceFiles();
          setState(() {
            _selectedPaths.clear();
            _selectedExistingFile = null;
            _selectedLocalInspectorFile = null;
          });
        });
      }
    });
    ref.listen(refreshWorkspaceProvider, (prev, next) {
      if (next > 0 && currentPath != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _refreshCurrentWorkspace(),
        );
      }
    });

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true):
            _handleSelectAll,
        const SingleActivator(LogicalKeyboardKey.keyA, control: true):
            _handleSelectAll,
      },
      child: Focus(
        autofocus: true,
        child: Row(
          children: [
            // Основная область: верхняя панель (папка + счётчик) + панель инструментов + сетка
            Expanded(
              child: Column(
                children: [
                  GenerationTopBar(
                    localCount: _localFiles.length,
                    isLoading: _isLoading,
                    batchDone: _batchDone,
                    batchTotal: _batchTotal,
                  ),
                  GenerationToolsBar(
                    selectedPaths: _selectedPaths,
                    localFiles: _localFiles,
                    metadataDirty: _metadataDirty,
                    focusedPath:
                        _selectedExistingFile?.path ??
                        _selectedLocalInspectorFile?.path,
                    onSelectAll: () {
                      final wp = ref.read(workspacesProvider).currentPath;
                      final sep = Platform.pathSeparator;
                      ref.read(filesProvider).whenData((dbFiles) {
                        final dbInWorkspace = wp == null || wp.isEmpty
                            ? <AppFile>[]
                            : dbFiles
                                  .where(
                                    (f) =>
                                        f.path == wp ||
                                        f.path.startsWith(wp + sep),
                                  )
                                  .toList();
                        _selectAll(dbInWorkspace, _localFiles);
                      });
                    },
                    onGenerateAI: _generateAI,
                    onGenerateBatchAI: _generateBatchAI,
                    onSaveAll: _saveAllMetadata,
                    onSaveChanges: _saveChanges,
                  ),
                  GenerationFilterBar(
                    searchController: _searchController,
                    searchQuery: _searchQuery,
                    filterType: _filterType,
                    onSearchChanged: (value) =>
                        setState(() => _searchQuery = value),
                    onFilterChanged: (value) =>
                        setState(() => _filterType = value),
                  ),
                  // Grid Area
                  Expanded(
                    child: DropTarget(
                      onDragEntered: (_) => setState(() => _isDragging = true),
                      onDragExited: (_) => setState(() => _isDragging = false),
                      onDragDone: (details) {
                        setState(() => _isDragging = false);
                        if (details.files.isNotEmpty) {
                          final dbFiles = ref.read(filesProvider).value ?? [];

                          setState(() {
                            for (int i = 0; i < details.files.length; i++) {
                              final xFile = details.files[i];
                              final path = xFile.path;
                              final existingFile = dbFiles.firstWhereOrNull(
                                (f) => f.path == path,
                              );

                              if (existingFile != null) {
                                _selectedPaths.add(path);
                                // Set as active if it's the first or only one
                                if (i == 0) {
                                  _selectedExistingFile = existingFile;
                                  _selectedLocalInspectorFile = null;
                                  _titleController.text =
                                      existingFile.metadataTitle ?? '';
                                  _keywordsController.text =
                                      existingFile.metadataKeywords ?? '';
                                }
                              } else {
                                final newFile = File(path);
                                if (!_localFiles.any((f) => f.path == path)) {
                                  _localFiles.add(newFile);
                                }
                                _selectedPaths.add(path);
                                // Set as active if it's the first or only one
                                if (i == 0) {
                                  _selectedLocalInspectorFile = newFile;
                                  _selectedExistingFile = null;
                                  _clearResults();
                                }
                              }
                            }
                          });
                        }
                      },
                      child: Container(
                        color: _isDragging
                            ? colorScheme.primary.withValues(alpha: 0.05)
                            : null,
                        child: Builder(
                          builder: (context) {
                            final filesState = ref.watch(filesProvider);

                            return filesState.when(
                              loading: () => const Center(
                                child: CircularProgressIndicator(),
                              ),
                              error: (e, _) => Center(
                                child: Text('Failed to load files: $e'),
                              ),
                              data: (dbFiles) {
                                final sep = Platform.pathSeparator;
                                final workspacePath = ref
                                    .read(workspacesProvider)
                                    .currentPath;
                                final dbFilesInWorkspace =
                                    workspacePath == null ||
                                        workspacePath.isEmpty
                                    ? <AppFile>[]
                                    : dbFiles.where((f) {
                                        final p = f.path;
                                        return p == workspacePath ||
                                            p.startsWith(workspacePath + sep);
                                      }).toList();

                                final currentLocalFiles = _localFiles
                                    .where(
                                      (lf) => !dbFilesInWorkspace.any(
                                        (df) => df.path == lf.path,
                                      ),
                                    )
                                    .toList();

                                // Применяем фильтры
                                final filtered = _applyFilters(
                                  currentLocalFiles,
                                  dbFilesInWorkspace,
                                );
                                final filteredLocals = filtered.locals;
                                final filteredDb = filtered.db;

                                if (workspacePath == null ||
                                    workspacePath.isEmpty) {
                                  return Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.folder_open_outlined,
                                          size: 64,
                                          color: colorScheme.outline,
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'Выберите папку в списке слева\nили нажмите «Добавить папку»',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: colorScheme.onSurface
                                                .withValues(alpha: 0.6),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                if (filteredLocals.isEmpty &&
                                    filteredDb.isEmpty) {
                                  // Различаем: нет файлов вообще или фильтр пуст
                                  final totalUnfiltered =
                                      currentLocalFiles.length +
                                      dbFilesInWorkspace.length;
                                  if (totalUnfiltered == 0) {
                                    return Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.photo_library_outlined,
                                            size: 64,
                                            color: colorScheme.outline,
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            'В этой папке нет изображений.\nНажмите «Обновить» в левой панели.\nЕсли файлы есть — выдайте приложению доступ к диску\n(Системные настройки → Конфиденциальность → Полный доступ к диску).',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: colorScheme.onSurface
                                                  .withValues(alpha: 0.6),
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          OutlinedButton.icon(
                                            onPressed: _pickFile,
                                            icon: const Icon(
                                              Icons.add,
                                              size: 18,
                                            ),
                                            label: const Text('Добавить папку'),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  return Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.filter_list_off,
                                          size: 64,
                                          color: colorScheme.outline,
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'Нет файлов, подходящих под фильтр.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: colorScheme.onSurface
                                                .withValues(alpha: 0.6),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                // Объединяем все в один отсортированный список,
                                // чтобы позиция файла не менялась при переходе local → db
                                final List<
                                  ({
                                    String path,
                                    String filename,
                                    bool isTagged,
                                    AppFile? existing,
                                    File? local,
                                  })
                                >
                                allItems = [];

                                for (final f in filteredLocals) {
                                  allItems.add((
                                    path: f.path,
                                    filename: f.path
                                        .split(Platform.pathSeparator)
                                        .last,
                                    isTagged: false,
                                    existing: null,
                                    local: f,
                                  ));
                                }
                                for (final f in filteredDb) {
                                  allItems.add((
                                    path: f.path,
                                    filename: f.filename,
                                    isTagged:
                                        f.metadataKeywords != null &&
                                        f.metadataKeywords!.isNotEmpty,
                                    existing: f,
                                    local: null,
                                  ));
                                }

                                allItems.sort(
                                  (a, b) => a.filename.toLowerCase().compareTo(
                                    b.filename.toLowerCase(),
                                  ),
                                );

                                final allPaths = allItems
                                    .map((e) => e.path)
                                    .toList();

                                return GridView.builder(
                                  padding: const EdgeInsets.all(24),
                                  gridDelegate:
                                      const SliverGridDelegateWithMaxCrossAxisExtent(
                                        maxCrossAxisExtent: 220,
                                        crossAxisSpacing: 16,
                                        mainAxisSpacing: 16,
                                        childAspectRatio: 0.85,
                                      ),
                                  itemCount: allItems.length,
                                  itemBuilder: (context, index) {
                                    final item = allItems[index];
                                    return GenerationGridCard(
                                      imagePath: item.path,
                                      filename: item.filename,
                                      isTagged: item.isTagged,
                                      isSelected: _selectedPaths.contains(
                                        item.path,
                                      ),
                                      onTap: () => _toggleSelection(
                                        index,
                                        item.path,
                                        allPaths,
                                        existing: item.existing,
                                        local: item.local,
                                      ),
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Right Panel (IMS-style: miniatures when multi, one image + tags when single)
            Container(
              width: 320,
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(left: BorderSide(color: colorScheme.outline)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: colorScheme.outlineVariant),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _selectedPaths.isEmpty
                              ? 'Детали'
                              : _selectedPaths.length == 1
                              ? 'Изображение'
                              : 'Выбрано',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        if (_selectedPaths.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () {
                              setState(() {
                                _selectedPaths.clear();
                                _selectedExistingFile = null;
                                _selectedLocalInspectorFile = null;
                              });
                            },
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _selectedPaths.isEmpty
                        ? Center(
                            child: Text(
                              'Выберите изображение',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                          )
                        : _selectedPaths.length > 1 ||
                              (_selectedLocalInspectorFile == null &&
                                  _selectedExistingFile == null)
                        ? _buildMultiSelectPanel(colorScheme)
                        : ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              // Image/Video Preview
                              Builder(
                                builder: (context) {
                                  final previewPath =
                                      _selectedLocalInspectorFile?.path ??
                                      _selectedExistingFile?.path ??
                                      _selectedPaths.first;
                                  final isVideo =
                                      [
                                        '.mp4',
                                        '.mov',
                                        '.avi',
                                        '.mkv',
                                        '.m4v',
                                      ].any(
                                        (ext) => previewPath
                                            .toLowerCase()
                                            .endsWith(ext),
                                      );

                                  if (isVideo) {
                                    return Container(
                                      height: 180,
                                      width: double.infinity,
                                      clipBehavior: Clip.antiAlias,
                                      decoration: BoxDecoration(
                                        color:
                                            colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: FutureBuilder(
                                        future:
                                            MetadataService.readExifLocationAndDate(
                                              previewPath,
                                            ),
                                        builder: (context, snapshot) {
                                          final hasAudio =
                                              snapshot.data?.hasAudio ?? false;
                                          return VideoPlayerWidget(
                                            videoPath: previewPath,
                                            hasAudio: hasAudio,
                                          );
                                        },
                                      ),
                                    );
                                  }

                                  return Container(
                                    height: 180,
                                    decoration: BoxDecoration(
                                      color: colorScheme.outlineVariant,
                                      borderRadius: BorderRadius.circular(8),
                                      image: DecorationImage(
                                        image: FileImage(File(previewPath)),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (_selectedLocalInspectorFile?.path
                                                  .split(Platform.pathSeparator)
                                                  .last ??
                                              _selectedExistingFile!.filename),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          'Local File',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: colorScheme.onSurface
                                                .withValues(alpha: 0.6),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Builder(
                                    builder: (context) {
                                      final isDark =
                                          Theme.of(context).brightness ==
                                          Brightness.dark;
                                      final isEmpty =
                                          _keywordsController.text.isEmpty;
                                      final bgColor = isEmpty
                                          ? AppTheme.warningColor.withValues(
                                              alpha: 0.2,
                                            )
                                          : AppTheme.successColor.withValues(
                                              alpha: 0.2,
                                            );
                                      final fgColor = isEmpty
                                          ? (isDark
                                                ? AppTheme.warningColorDark
                                                : AppTheme.warningColor)
                                          : (isDark
                                                ? AppTheme.successColorDark
                                                : AppTheme.successColor);
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: bgColor,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          isEmpty ? 'Untagged' : 'Tagged',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: fgColor,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),

                              const SizedBox(height: 16),
                              GenerationEditorialSection(
                                isMulti: false,
                                selectedPaths: _selectedPaths,
                                selectedExistingFile: _selectedExistingFile,
                                selectedLocalInspectorPath:
                                    _selectedLocalInspectorFile?.path,
                              ),

                              // Metadata Form
                              const GenerationFormLabel('TITLE'),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _titleController,
                                decoration: _inputDecoration(context),
                                style: const TextStyle(fontSize: 14),
                                onChanged: (_) =>
                                    setState(() => _metadataDirty = true),
                              ),

                              const SizedBox(height: 16),
                              GenerationFormLabel('KEYWORDS'),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: _isLoading
                                          ? null
                                          : _generateAI,
                                      icon: const Icon(
                                        Icons.auto_awesome,
                                        size: 18,
                                      ),
                                      label: const Text('Генерация AI'),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: colorScheme.primary,
                                        foregroundColor: colorScheme.onPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _keywordsController,
                                maxLines: 4,
                                decoration: _inputDecoration(context),
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.5,
                                ),
                                onChanged: (_) =>
                                    setState(() => _metadataDirty = true),
                              ),
                              if (_isLoading)
                                const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: LinearProgressIndicator(),
                                ),

                              const SizedBox(height: 24),
                              const Divider(),
                              const SizedBox(height: 16),

                              GenerationFormLabel('STOCK STATUS'),
                              const SizedBox(height: 12),

                              GenerationStockStatusCard(
                                code: 'AS',
                                label: 'Adobe Stock',
                                color: Colors.red,
                                isUploaded: false,
                              ),
                              const SizedBox(height: 8),
                              GenerationStockStatusCard(
                                code: 'SS',
                                label: 'Shutterstock',
                                color: Colors.blue,
                                isUploaded: true,
                              ),

                              const SizedBox(height: 32),
                              FilledButton(
                                onPressed: _saveChanges,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(44),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text('Save Changes'),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      filled: true,
      fillColor: isDark ? colorScheme.outlineVariant : Colors.grey.shade50,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colorScheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colorScheme.primary),
      ),
      contentPadding: const EdgeInsets.all(12),
    );
  }
}
