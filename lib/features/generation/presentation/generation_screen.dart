import 'dart:io';
import 'package:collection/collection.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_secure_bookmarks/macos_secure_bookmarks.dart';
import 'package:pool/pool.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/metadata_service.dart';
import '../../../core/state/files_provider.dart';
import '../../../core/state/navigation_provider.dart';
import '../../../core/state/settings_provider.dart';
import '../../../core/state/workspaces_provider.dart';
import '../../../models/app_file.dart';
import '../../../models/generation_options.dart';

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
  double _numKeywords = 15;
  final _titleController = TextEditingController();
  final _keywordsController = TextEditingController();
  /// Есть несохранённые изменения метаданных у выбранного файла.
  bool _metadataDirty = false;

  /// На macOS: открытый security-scoped ресурс текущей рабочей области (держим доступ, чтобы миниатюры и чтение файлов работали).
  FileSystemEntity? _currentScopedResource;

  @override
  void dispose() {
    _releaseSecurityScopedResource();
    _titleController.dispose();
    _keywordsController.dispose();
    super.dispose();
  }

  Future<void> _releaseSecurityScopedResource() async {
    if (_currentScopedResource == null) return;
    try {
      await _secureBookmarks.stopAccessingSecurityScopedResource(_currentScopedResource!);
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
        scopeStarted = await _secureBookmarks.startAccessingSecurityScopedResource(entity);
        if (!scopeStarted || !await dir.exists()) {
          if (mounted) {
            setState(() => _localFiles.clear());
            _showError('Папка не найдена или нет доступа: $currentPath');
          }
          return;
        }
        _currentScopedResource = dir;
      } else {
        dir = Directory(currentPath);
        if (!await dir.exists()) {
          if (mounted) {
            setState(() => _localFiles.clear());
            _showError('Папка не найдена: $currentPath');
          }
          return;
        }
      }
      final imageExtensions = ['.jpg', '.jpeg', '.png'];
      final videoExtensions = ['.mp4', '.mov', '.avi', '.mkv', '.m4v'];
      final allExtensions = [...imageExtensions, ...videoExtensions];
      final dbFiles = ref.read(filesProvider).value ?? [];
      final sep = Platform.pathSeparator;
      final prefix = currentPath.endsWith(sep) ? currentPath : currentPath + sep;
      final dbPathsInWorkspace =
          dbFiles.where((f) => f.path == currentPath || f.path.startsWith(prefix)).map((f) => f.path).toSet();

      final List<FileSystemEntity> entities =
          await dir.list(recursive: false).toList();
      if (!mounted) return;
      final newLocal = <File>[];
      for (var entity in entities) {
        if (entity is File) {
          final path = entity.path;
          final ext = path.split('.').last.toLowerCase();
          if (allExtensions.contains('.$ext') && !dbPathsInWorkspace.contains(path)) {
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
      await Process.run(
        'open',
        [
          'x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles',
        ],
      );
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
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Инструкция:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
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
                        final appIdx = parts.indexWhere((e) => e.endsWith('.app'));
                        if (appIdx >= 0) {
                          appPath = parts.sublist(0, appIdx + 1).join(Platform.pathSeparator);
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
                              color: colorScheme.onSurface.withValues(alpha: 0.8),
                            ),
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            appPath,
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: colorScheme.onSurface.withValues(alpha: 0.7),
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

    await ref.read(settingsProvider.notifier).setWorkspacePath(directoryPath);
    await ref.read(workspacesProvider.notifier).addWorkspace(directoryPath);

    final dir = Directory(directoryPath);
    if (!await dir.exists()) {
      _showError('Selected folder does not exist: $directoryPath');
      return;
    }

    final imageExtensions = ['.jpg', '.jpeg', '.png'];
    final videoExtensions = ['.mp4', '.mov', '.avi', '.mkv', '.m4v'];
    final allExtensions = [...imageExtensions, ...videoExtensions];

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

  void _toggleSelection(String path, {AppFile? existing, File? local}) {
    setState(() {
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
        if (_selectedExistingFile?.path == path ||
            _selectedLocalInspectorFile?.path == path) {
          _selectedExistingFile = null;
          _selectedLocalInspectorFile = null;
          _clearResults();
        }
      } else {
        _selectedPaths.add(path);
        if (existing != null) {
          _selectedExistingFile = existing;
          _selectedLocalInspectorFile = null;
          _titleController.text = existing.metadataTitle ?? '';
          _keywordsController.text = existing.metadataKeywords ?? '';
          _metadataDirty = false;
        } else if (local != null) {
          _selectedLocalInspectorFile = local;
          _selectedExistingFile = null;
          _clearResults();
        }
      }
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

      setState(() {
        _titleController.text = fetchedTitle;
        _keywordsController.text = keywordsString;
        _metadataDirty = true;
      });

      // Save to DB
      final newFileId = _selectedExistingFile?.id ?? const Uuid().v4();
      final newFile = AppFile(
        id: newFileId,
        path: fileToProcess.path,
        filename: fileToProcess.path.split(Platform.pathSeparator).last,
        metadataTitle: fetchedTitle,
        metadataKeywords: keywordsString,
        createdAt:
            _selectedExistingFile?.createdAt ??
            DateTime.now().millisecondsSinceEpoch,
      );

      await ref.read(filesProvider.notifier).addFile(newFile);

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

            // Save/Update DB
            final existing = fileObj is AppFile ? fileObj : null;
            final newFile = AppFile(
              id: existing?.id ?? const Uuid().v4(),
              path: path,
              filename: path.split(Platform.pathSeparator).last,
              metadataTitle: fetchedTitle,
              metadataKeywords: keywordsString,
              createdAt:
                  existing?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
            );

            await ref.read(filesProvider.notifier).addFile(newFile);

            if (mounted) {
              setState(() {
                _batchDone++;
                // If this was the active selection, update controllers
                if (_selectedExistingFile?.path == path ||
                    _selectedLocalInspectorFile?.path == path) {
                  _titleController.text = fetchedTitle;
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

    if (_selectedExistingFile != null) {
      final updatedFile = AppFile(
        id: _selectedExistingFile!.id,
        path: _selectedExistingFile!.path,
        filename: _selectedExistingFile!.filename,
        metadataTitle: title,
        metadataKeywords: keywords,
        createdAt: _selectedExistingFile!.createdAt,
      );
      await ref.read(filesProvider.notifier).updateFile(updatedFile);
      setState(() {
        _selectedExistingFile = updatedFile;
      });

      // Also write to original file
      await MetadataService.writeMetadata(
        filePath: updatedFile.path,
        title: title,
        keywords: keywords,
      );

      setState(() => _metadataDirty = false);
      _showSuccess('Изменения сохранены в БД и в файл.');
    } else if (_selectedLocalInspectorFile != null) {
      final newFile = AppFile(
        id: const Uuid().v4(),
        path: _selectedLocalInspectorFile!.path,
        filename: _selectedLocalInspectorFile!.path
            .split(Platform.pathSeparator)
            .last,
        metadataTitle: title,
        metadataKeywords: keywords,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await ref.read(filesProvider.notifier).addFile(newFile);
      setState(() {
        _selectedExistingFile = newFile;
        _localFiles.removeWhere(
          (f) => f.path == _selectedLocalInspectorFile!.path,
        );
        _selectedLocalInspectorFile = null;
      });

      // Also write to original file
      await MetadataService.writeMetadata(
        filePath: newFile.path,
        title: title,
        keywords: keywords,
      );

      setState(() => _metadataDirty = false);
      _showSuccess('Файл добавлен в БД и метаданные записаны в файл.');
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
        final hasMeta = (f.metadataTitle != null && f.metadataTitle!.trim().isNotEmpty) ||
            (f.metadataKeywords != null && f.metadataKeywords!.trim().isNotEmpty);
        if (hasMeta) toSave.add(f);
      }
    }
    if (toSave.isEmpty) {
      if (mounted) _showSuccess('Нет файлов с метаданными для сохранения.');
      return;
    }
    int saved = 0;
    for (final f in toSave) {
      final ok = await MetadataService.writeMetadata(
        filePath: f.path,
        title: f.metadataTitle?.trim() ?? '',
        keywords: f.metadataKeywords?.trim() ?? '',
      );
      if (ok) saved++;
    }
    if (mounted) _showSuccess('Сохранить все: записано $saved из ${toSave.length} файлов.');
  }

  void _showSuccess(String message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isDark ? AppTheme.successColorDark : AppTheme.successColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildMultiSelectPanel(ColorScheme colorScheme) {
    final dbFiles = ref.read(filesProvider).value ?? [];
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
            const crossAxisCount = 3;
            const spacing = 6.0;
            final size = (constraints.maxWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: paths.map((path) {
                return SizedBox(
                  width: size,
                  height: size,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: _thumbnailForPath(context, path),
                  ),
                );
              }).toList(),
            );
          },
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
    final isVideo = ['.mp4', '.mov', '.avi', '.mkv', '.m4v']
        .any((e) => path.toLowerCase().endsWith(e));
    if (isVideo) {
      return Container(
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.videocam, color: cs.primary.withValues(alpha: 0.5)),
      );
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
    );
  }

  Widget _buildTopBar(ColorScheme colorScheme) {
    final workspacePath = ref.watch(workspacesProvider).currentPath;
    final folderName = workspacePath == null || workspacePath.isEmpty
        ? ''
        : workspacePath.split(Platform.pathSeparator).last;
    return ref.watch(filesProvider).when(
          data: (dbFiles) {
            final sep = Platform.pathSeparator;
            final dbCount = workspacePath == null || workspacePath.isEmpty
                ? 0
                : dbFiles
                    .where((f) =>
                        f.path == workspacePath ||
                        f.path.startsWith(workspacePath + sep))
                    .length;
            final total = dbCount + _localFiles.length;
            return Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
                border: Border(
                  bottom: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    folderName.isEmpty ? '—' : folderName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Text(
                    'Файлов: $total',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const Spacer(),
                  if (_isLoading && _batchTotal > 0)
                    Text(
                      'Обработка: $_batchDone / $_batchTotal',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                ],
              ),
            );
          },
          loading: () => Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.folder_outlined, size: 20, color: colorScheme.outline),
                const SizedBox(width: 10),
                Text(
                  folderName.isEmpty ? '—' : folderName,
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          error: (_, __) => const SizedBox.shrink(),
        );
  }

  Widget _buildToolsBar(ColorScheme colorScheme) {
    final workspaces = ref.watch(workspacesProvider);
    final dbFiles = ref.watch(filesProvider).value ?? [];
    final sep = Platform.pathSeparator;
    int saveAllCount = 0;
    for (final entry in workspaces.entries) {
      final wp = entry.path;
      final prefix = wp.endsWith(sep) ? wp : wp + sep;
      for (final f in dbFiles) {
        if (f.path != wp && !f.path.startsWith(prefix)) continue;
        final hasMeta = (f.metadataTitle != null && f.metadataTitle!.trim().isNotEmpty) ||
            (f.metadataKeywords != null && f.metadataKeywords!.trim().isNotEmpty);
        if (hasMeta) saveAllCount++;
      }
    }
    final hasSelection = _selectedExistingFile != null || _selectedLocalInspectorFile != null;
    final saveCount = (_metadataDirty && hasSelection) ? 1 : 0;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          Tooltip(
            message: _selectedPaths.isEmpty ? 'Выделить всё' : 'Снять выделение',
            child: IconButton(
              onPressed: () {
                final wp = ref.read(workspacesProvider).currentPath;
                final sep = Platform.pathSeparator;
                ref.read(filesProvider).whenData((dbFiles) {
                  final dbInWorkspace = wp == null || wp.isEmpty
                      ? <AppFile>[]
                      : dbFiles
                          .where((f) =>
                              f.path == wp || f.path.startsWith(wp + sep))
                          .toList();
                  _selectAll(dbInWorkspace, _localFiles);
                });
              },
              icon: Icon(
                _selectedPaths.isEmpty ? Icons.select_all : Icons.deselect,
                size: 22,
                color: colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'AI Tag — генерация тегов для выбранных',
            child: IconButton(
              onPressed: _selectedPaths.isEmpty
                  ? null
                  : () {
                      if (_selectedPaths.length > 1) {
                        _generateBatchAI();
                      } else {
                        _generateAI();
                      }
                    },
              icon: Icon(
                Icons.auto_awesome,
                size: 22,
                color: _selectedPaths.isEmpty
                    ? colorScheme.onSurface.withValues(alpha: 0.4)
                    : colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Снять выделение',
            child: IconButton(
              onPressed: _selectedPaths.isEmpty
                  ? null
                  : () {
                      setState(() {
                        _selectedPaths.clear();
                        _selectedExistingFile = null;
                        _selectedLocalInspectorFile = null;
                      });
                    },
              icon: Icon(
                Icons.delete_outline,
                size: 22,
                color: _selectedPaths.isEmpty
                    ? colorScheme.onSurface.withValues(alpha: 0.4)
                    : colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Сохранить все — метаданные всех рабочих областей
          Tooltip(
            message: 'Сохранить метаданные всех файлов во всех рабочих областях',
            child: FilledButton.icon(
              onPressed: saveAllCount > 0 ? _saveAllMetadata : null,
              icon: const Icon(Icons.save, size: 18),
              label: Text('Сохранить все ($saveAllCount)'),
              style: FilledButton.styleFrom(
                backgroundColor: saveAllCount > 0 ? colorScheme.primary : null,
                foregroundColor: saveAllCount > 0 ? colorScheme.onPrimary : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Сохранить — только выбранный файл с несохранёнными изменениями
          Tooltip(
            message: 'Сохранить метаданные выбранного файла в БД и в файл',
            child: FilledButton.icon(
              onPressed: saveCount > 0 ? _saveChanges : null,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: Text('Сохранить ($saveCount)'),
              style: FilledButton.styleFrom(
                backgroundColor: saveCount > 0 ? colorScheme.primaryContainer : null,
                foregroundColor: saveCount > 0 ? colorScheme.onPrimaryContainer : null,
              ),
            ),
          ),
        ],
      ),
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
        WidgetsBinding.instance.addPostFrameCallback((_) => _refreshCurrentWorkspace());
      }
    });

    return Row(
      children: [
        // Основная область: верхняя панель (папка + счётчик) + панель инструментов + сетка
        Expanded(
          child: Column(
            children: [
              _buildTopBar(colorScheme),
              _buildToolsBar(colorScheme),
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
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (e, _) =>
                              Center(child: Text('Failed to load files: $e')),
                          data: (dbFiles) {
                            final sep = Platform.pathSeparator;
                            final workspacePath =
                                ref.read(workspacesProvider).currentPath;
                            final dbFilesInWorkspace = workspacePath == null ||
                                    workspacePath.isEmpty
                                ? <AppFile>[]
                                : dbFiles.where((f) {
                                    final p = f.path;
                                    return p == workspacePath ||
                                        p.startsWith(workspacePath + sep);
                                  }).toList();

                            final currentLocalFiles = _localFiles
                                .where(
                                  (lf) => !dbFilesInWorkspace
                                      .any((df) => df.path == lf.path),
                                )
                                .toList();

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

                            if (dbFilesInWorkspace.isEmpty &&
                                currentLocalFiles.isEmpty) {
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
                                      icon: const Icon(Icons.add, size: 18),
                                      label: const Text('Добавить папку'),
                                    ),
                                  ],
                                ),
                              );
                            }

                            return GridView.builder(
                              padding: const EdgeInsets.all(24),
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 220,
                                    crossAxisSpacing: 16,
                                    mainAxisSpacing: 16,
                                    childAspectRatio: 0.85,
                                  ),
                              itemCount: currentLocalFiles.length +
                                  dbFilesInWorkspace.length,
                              itemBuilder: (context, index) {
                                if (index < currentLocalFiles.length) {
                                  final file = currentLocalFiles[index];
                                  return _GridCard(
                                    imagePath: file.path,
                                    filename: file.path
                                        .split(Platform.pathSeparator)
                                        .last,
                                    isTagged: false,
                                    isSelected: _selectedPaths.contains(
                                      file.path,
                                    ),
                                    onTap: () => _toggleSelection(
                                      file.path,
                                      local: file,
                                    ),
                                  );
                                }

                                final dbIdx = index - currentLocalFiles.length;
                                final appFile = dbFilesInWorkspace[dbIdx];
                                final isSelected = _selectedPaths.contains(
                                  appFile.path,
                                );
                                final isTagged =
                                    appFile.metadataKeywords != null &&
                                    appFile.metadataKeywords!.isNotEmpty;

                                return _GridCard(
                                  imagePath: appFile.path,
                                  filename: appFile.filename,
                                  isTagged: isTagged,
                                  isSelected: isSelected,
                                  onTap: () => _toggleSelection(
                                    appFile.path,
                                    existing: appFile,
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
                            color: colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      )
                    : _selectedPaths.length > 1
                        ? _buildMultiSelectPanel(colorScheme)
                        : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          // Image Preview
                          Container(
                            height: 180,
                            decoration: BoxDecoration(
                              color: colorScheme.outlineVariant,
                              borderRadius: BorderRadius.circular(8),
                              image: DecorationImage(
                                image: FileImage(
                                  File(
                                    _selectedLocalInspectorFile?.path ??
                                        _selectedExistingFile!.path,
                                  ),
                                ),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                        color: colorScheme.onSurface.withValues(
                                          alpha: 0.6,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Builder(
                                builder: (context) {
                                  final isDark = Theme.of(context).brightness == Brightness.dark;
                                  final isEmpty = _keywordsController.text.isEmpty;
                                  final bgColor = isEmpty
                                      ? AppTheme.warningColor.withValues(alpha: 0.2)
                                      : AppTheme.successColor.withValues(alpha: 0.2);
                                  final fgColor = isEmpty
                                      ? (isDark ? AppTheme.warningColorDark : AppTheme.warningColor)
                                      : (isDark ? AppTheme.successColorDark : AppTheme.successColor);
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: bgColor,
                                      borderRadius: BorderRadius.circular(4),
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

                          const SizedBox(height: 24),

                          // Metadata Form
                          _FormLabel('TITLE'),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _titleController,
                            decoration: _inputDecoration(context),
                            style: const TextStyle(fontSize: 14),
                            onChanged: (_) => setState(() => _metadataDirty = true),
                          ),

                          const SizedBox(height: 16),
                          _FormLabel('KEYWORDS'),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _isLoading ? null : _generateAI,
                                  icon: const Icon(Icons.auto_awesome, size: 18),
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

                          const SizedBox(height: 16),
                          _FormLabel('CATEGORIES'),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            value: 'Urban & Architecture',
                            decoration: _inputDecoration(context),
                            items: const [
                              DropdownMenuItem(
                                value: 'Urban & Architecture',
                                child: Text(
                                  'Urban & Architecture',
                                  style: TextStyle(fontSize: 14),
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'Nature',
                                child: Text(
                                  'Nature',
                                  style: TextStyle(fontSize: 14),
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'People',
                                child: Text(
                                  'People',
                                  style: TextStyle(fontSize: 14),
                                ),
                              ),
                            ],
                            onChanged: (v) {},
                          ),

                          const SizedBox(height: 24),
                          const Divider(),
                          const SizedBox(height: 16),

                          _FormLabel('STOCK STATUS'),
                          const SizedBox(height: 12),

                          _StockStatusCard(
                            code: 'AS',
                            label: 'Adobe Stock',
                            color: Colors.red,
                            isUploaded: false,
                          ),
                          const SizedBox(height: 8),
                          _StockStatusCard(
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

class _FormLabel extends StatelessWidget {
  final String text;
  const _FormLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
      ),
    );
  }
}

class _GridCard extends StatelessWidget {
  final String imagePath;
  final String filename;
  final bool isTagged;
  final bool isSelected;
  final VoidCallback onTap;

  const _GridCard({
    required this.imagePath,
    required this.filename,
    required this.isTagged,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primary.withValues(alpha: 0.05)
                : Colors.transparent,
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary.withValues(alpha: 0.3)
                  : Colors.transparent,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Builder(
                  builder: (context) {
                  final videoExtensions = [
                    '.mp4',
                    '.mov',
                    '.avi',
                    '.mkv',
                    '.m4v',
                  ];
                  final isVideo = videoExtensions.any(
                    (ext) => imagePath.toLowerCase().endsWith(ext),
                  );

                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: isSelected
                          ? Border.all(color: colorScheme.primary, width: 2)
                          : Border.all(color: colorScheme.outline),
                      color: isVideo
                          ? colorScheme.surfaceContainerHighest
                          : null,
                      image: isVideo
                          ? null
                          : DecorationImage(
                              image: FileImage(File(imagePath)),
                              fit: BoxFit.cover,
                            ),
                    ),
                    child: Stack(
                      children: [
                        if (isVideo)
                          Center(
                            child: Icon(
                              Icons.videocam,
                              size: 48,
                              color: colorScheme.primary.withValues(alpha: 0.5),
                            ),
                          ),
                        if (isSelected)
                          Align(
                            alignment: Alignment.topRight,
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Icon(
                                Icons.check_circle,
                                color: colorScheme.primary,
                                size: 20,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                  },
                ),
              ),
                const SizedBox(height: 8),
              Text(
                filename,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Builder(
                    builder: (context) {
                      final isDark = Theme.of(context).brightness == Brightness.dark;
                      final dotColor = isTagged
                          ? (isDark ? AppTheme.successColorDark : AppTheme.successColor)
                          : (isDark ? AppTheme.warningColorDark : AppTheme.warningColor);
                      return Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isTagged ? 'Tagged' : 'Untagged',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SideActionIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  const _SideActionIcon({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Opacity(
      opacity: isActive ? 1.0 : 0.4,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: isActive ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 24, color: colorScheme.primary),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }
}

class _StockStatusCard extends StatelessWidget {
  final String code;
  final String label;
  final Color color;
  final bool isUploaded;

  const _StockStatusCard({
    required this.code,
    required this.label,
    required this.color,
    required this.isUploaded,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.outlineVariant.withValues(alpha: 0.1)
            : Colors.grey.shade50,
        border: Border.all(color: colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  code,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Icon(
            isUploaded ? Icons.check_circle : Icons.check_circle_outline,
            color: isUploaded
                ? (isDark ? AppTheme.successColorDark : AppTheme.successColor)
                : colorScheme.onSurface.withValues(alpha: 0.3),
            size: 18,
          ),
        ],
      ),
    );
  }
}
