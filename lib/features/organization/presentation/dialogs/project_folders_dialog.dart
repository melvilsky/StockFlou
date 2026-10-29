import '../../../../core/widgets/app_tooltip.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/state/workspaces_provider.dart';
import '../../application/organization_providers.dart';
import 'organization_confirm_delete_dialog.dart';

/// Диалог выбора и управления подключёнными папками проекта.
///
/// Позволяет:
/// - просматривать список подключённых к проекту папок;
/// - добавлять папки из уже открытых рабочих областей в один клик;
/// - выбирать новую папку на диске через [directoryPicker];
/// - безопасно отключать папки от проекта с подтверждением (оригиналы на диске не удаляются);
/// - защищать от повторного нажатия и обрабатывать ошибки.
class ProjectFoldersDialog extends ConsumerStatefulWidget {
  final Project project;
  final Future<String?> Function()? directoryPicker;

  const ProjectFoldersDialog({
    super.key,
    required this.project,
    this.directoryPicker,
  });

  static Future<void> show({
    required BuildContext context,
    required Project project,
    Future<String?> Function()? directoryPicker,
  }) {
    return showDialog<void>(
      context: context,
      builder:
          (context) => ProjectFoldersDialog(
            project: project,
            directoryPicker: directoryPicker,
          ),
    );
  }

  @override
  ConsumerState<ProjectFoldersDialog> createState() =>
      _ProjectFoldersDialogState();
}

class _ProjectFoldersDialogState extends ConsumerState<ProjectFoldersDialog> {
  bool _isOperating = false;

  void _showErrorSnackBar(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Ошибка операции с папками проекта: $error'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  String _folderDisplayName(String path) {
    if (path == '/' || RegExp(r'^/+$').hasMatch(path)) {
      return 'Корень (/)';
    }
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) {
      return path;
    }
    return segments.last;
  }

  Future<void> _addFolder(String path) async {
    if (_isOperating) return;
    setState(() => _isOperating = true);
    try {
      await ref
          .read(projectFoldersProvider(widget.project.id).notifier)
          .addFolder(path);
    } catch (e) {
      _showErrorSnackBar(e);
    } finally {
      if (mounted) setState(() => _isOperating = false);
    }
  }

  Future<void> _removeFolder(String path, String name) async {
    if (_isOperating) return;
    final confirm = await OrganizationConfirmDeleteDialog.show(
      context: context,
      title: 'Исключить папку из проекта?',
      entityName: name,
      explanation:
          'Папка будет исключена из проекта. Все файлы и метаданные '
          'на диске останутся в сохранности.',
      confirmButtonText: 'Исключить',
    );
    if (!mounted || !confirm) return;

    setState(() => _isOperating = true);
    try {
      await ref
          .read(projectFoldersProvider(widget.project.id).notifier)
          .removeFolder(path);
    } catch (e) {
      _showErrorSnackBar(e);
    } finally {
      if (mounted) setState(() => _isOperating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final foldersAsync = ref.watch(projectFoldersProvider(widget.project.id));
    final workspaces = ref.watch(workspacesProvider);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.folder_copy_outlined,
            color: colorScheme.primary,
            size: 22,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Папки проекта: ${widget.project.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 420,
          maxWidth: 540,
          maxHeight: 460,
        ),
        child: foldersAsync.when(
          skipLoadingOnReload: true,
          loading:
              () => const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          error:
              (err, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Ошибка загрузки папок проекта: $err',
                      style: TextStyle(color: colorScheme.error),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed:
                          () => ref.invalidate(
                            projectFoldersProvider(widget.project.id),
                          ),
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
          data: (connectedFolders) {
            final unattachedWorkspaces =
                workspaces.entries
                    .map((e) => e.path)
                    .where((p) => !connectedFolders.contains(p))
                    .toList();

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.4,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: colorScheme.outline.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Проект логически связывает папки в единую серию. '
                            'Подключение и исключение папок не перемещает и не удаляет файлы на диске.',
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.7,
                              ),
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Подключённые папки (${connectedFolders.length})',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      FilledButton.tonalIcon(
                        key: const Key('project_folders_pick_button'),
                        onPressed:
                            _isOperating
                                ? null
                                : () async {
                                  final picker =
                                      widget.directoryPicker ??
                                      getDirectoryPath;
                                  final path = await picker();
                                  if (path != null && path.isNotEmpty) {
                                    await _addFolder(path);
                                  }
                                },
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Выбрать с диска'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (connectedFolders.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      alignment: Alignment.center,
                      child: Text(
                        'К этому проекту пока не подключено ни одной папки.',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    )
                  else
                    for (int idx = 0; idx < connectedFolders.length; idx++) ...[
                      if (idx > 0) const SizedBox(height: 4),
                      Builder(
                        builder: (context) {
                          final path = connectedFolders[idx];
                          final name = _folderDisplayName(path);

                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: colorScheme.outline.withValues(
                                  alpha: 0.15,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.folder_outlined,
                                  size: 18,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: AppTooltip(
                                    message: path,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          path,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: colorScheme.onSurface
                                                .withValues(alpha: 0.5),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Semantics(
                                  container: true,
                                  child: IconButton(
                                    key: Key(
                                      'project_remove_folder_${widget.project.id}_$idx',
                                    ),
                                    icon: Icon(
                                      Icons.close,
                                      size: 16,
                                      color: colorScheme.onSurface.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                                    tooltip:
                                        'Исключить папку из проекта (файлы останутся на диске)',
                                    onPressed:
                                        _isOperating
                                            ? null
                                            : () => _removeFolder(path, name),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  if (unattachedWorkspaces.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Быстрое добавление из рабочих областей:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children:
                          unattachedWorkspaces.map((path) {
                            final name = _folderDisplayName(path);
                            return ActionChip(
                              key: Key(
                                'project_quick_add_folder_${widget.project.id}_$path',
                              ),
                              avatar: const Icon(Icons.add, size: 14),
                              label: Text(name),
                              tooltip: 'Подключить $path к проекту',
                              onPressed:
                                  _isOperating ? null : () => _addFolder(path),
                            );
                          }).toList(),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        FilledButton(
          key: const Key('project_folders_close_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Готово'),
        ),
      ],
    );
  }
}
