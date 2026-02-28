import 'dart:io';
import 'package:collection/collection.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pool/pool.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/metadata_service.dart';
import '../../../core/state/files_provider.dart';
import '../../../core/state/navigation_provider.dart';
import '../../../core/state/settings_provider.dart';
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

  @override
  void dispose() {
    _titleController.dispose();
    _keywordsController.dispose();
    super.dispose();
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

    // Automatically update workspace setting
    await ref.read(settingsProvider.notifier).setWorkspacePath(directoryPath);

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
      final List<FileSystemEntity> entities = dir.listSync(recursive: false);

      setState(() {
        for (var entity in entities) {
          if (entity is File) {
            final path = entity.path;
            final ext = path.split('.').last.toLowerCase();

            if (allExtensions.contains('.$ext')) {
              // Check if already in DB
              final existsInDb = dbFiles.any((f) => f.path == path);
              // Check if already in local
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

      _showSuccess('Changes saved to DB and File.');
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

      _showSuccess('New file saved and tagged.');
    }
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

    return Row(
      children: [
        // Left Action Panel
        Container(
          width: 72,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(right: BorderSide(color: colorScheme.outline)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 16),
              _SideActionIcon(
                icon: _selectedPaths.isEmpty
                    ? Icons.select_all
                    : Icons.deselect,
                label: _selectedPaths.isEmpty ? 'All' : 'None',
                onTap: () {
                  final filesState = ref.read(filesProvider);
                  filesState.whenData((dbFiles) {
                    _selectAll(dbFiles, _localFiles);
                  });
                },
              ),
              const SizedBox(height: 16),
              _SideActionIcon(
                icon: Icons.auto_awesome,
                label: 'AI Tag',
                isActive: _selectedPaths.isNotEmpty,
                onTap: () {
                  if (_selectedPaths.length > 1) {
                    _generateBatchAI();
                  } else {
                    _generateAI();
                  }
                },
              ),
              const SizedBox(height: 16),
              _SideActionIcon(
                icon: Icons.delete_outline,
                label: 'Clear',
                isActive: _selectedPaths.isNotEmpty,
                onTap: () {
                  setState(() {
                    _selectedPaths.clear();
                    _selectedExistingFile = null;
                    _selectedLocalInspectorFile = null;
                  });
                },
              ),
              const Spacer(),
              _SideActionIcon(
                icon: Icons.settings_outlined,
                label: 'Settings',
                onTap: () {
                  ref.read(navigationProvider.notifier).setIndex(4);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),

        // Main Content Area (Middle)
        Expanded(
          child: Column(
            children: [
              // Header Toolbar
              Container(
                height: 64,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  border: Border(
                    bottom: BorderSide(color: colorScheme.outline),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Breadcrumbs
                    Row(
                      children: [
                        Text(
                          'Workspace',
                          style: TextStyle(
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                        Text(
                          'Images',
                          style: TextStyle(
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                        Text(
                          'Library',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        if (_selectedPaths.isNotEmpty) ...[
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${_selectedPaths.length} selected',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    // Actions
                    Row(
                      children: [
                        if (_isLoading && _batchTotal > 0)
                          Padding(
                            padding: const EdgeInsets.only(right: 16),
                            child: Text(
                              'Processing: $_batchDone / $_batchTotal',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                        OutlinedButton.icon(
                          onPressed: _pickFile,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Import'),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: colorScheme.outline),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
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
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (e, _) =>
                              Center(child: Text('Failed to load files: $e')),
                          data: (dbFiles) {
                            // Filter local files that might have been added to DB in the meantime
                            final currentLocalFiles = _localFiles
                                .where(
                                  (lf) =>
                                      !dbFiles.any((df) => df.path == lf.path),
                                )
                                .toList();

                            if (dbFiles.isEmpty && currentLocalFiles.isEmpty) {
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
                                      'No images in workspace.',
                                      style: TextStyle(
                                        color: colorScheme.onSurface.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    OutlinedButton(
                                      onPressed: _pickFile,
                                      child: const Text('Select a File'),
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
                              itemCount:
                                  currentLocalFiles.length + dbFiles.length,
                              itemBuilder: (context, index) {
                                // Draw local drop file first
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

                                // Draw DB files
                                final dbIdx = index - currentLocalFiles.length;
                                final appFile = dbFiles[dbIdx];
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

        // Right Inspector Panel
        Container(
          width: 320,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(left: BorderSide(color: colorScheme.outline)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Inspector Header
              Container(
                height: 64,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: colorScheme.outlineVariant),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Inspector',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () {
                        setState(() {
                          _selectedExistingFile = null;
                          _selectedLocalInspectorFile = null;
                        });
                      },
                    ),
                  ],
                ),
              ),

              // Inspector Content
              Expanded(
                child:
                    (_selectedLocalInspectorFile == null &&
                        _selectedExistingFile == null)
                    ? Center(
                        child: Text(
                          'Select an image\nto view details.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      )
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
                          ),

                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _FormLabel('KEYWORDS'),
                              InkWell(
                                onTap: _generateAI,
                                child: Text(
                                  'GENERATE AI',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.primary,
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
                            style: const TextStyle(fontSize: 14, height: 1.5),
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

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Material(
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
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: isActive ? onTap : null,
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
