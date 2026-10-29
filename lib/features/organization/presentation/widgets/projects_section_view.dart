import '../../../../core/widgets/app_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/single_click_area.dart';
import '../../application/organization_providers.dart';
import '../dialogs/organization_confirm_delete_dialog.dart';
import '../dialogs/organization_name_dialog.dart';
import '../dialogs/project_folders_dialog.dart';
import 'collapsible_section_card.dart';

/// Виджет управления проектами для сайдбара.
///
/// Предоставляет:
/// - создание, переименование, удаление проектов (с подтверждением и гарантией сохранности файлов);
/// - закрепление и архивирование проектов;
/// - выбор активного проекта;
/// - просмотр и открытие подключённых папок проекта;
/// - вызов диалога настройки папок проекта;
/// - защиту от повторного нажатия во время активной операции;
/// - обработку ошибок с понятными сообщениями.
class ProjectsSectionView extends ConsumerStatefulWidget {
  final String? selectedProjectId;
  final ValueChanged<Project?>? onProjectSelected;
  final ValueChanged<String>? onFolderSelected;
  final Future<String?> Function()? directoryPicker;
  final bool initialExpanded;

  const ProjectsSectionView({
    super.key,
    this.selectedProjectId,
    this.onProjectSelected,
    this.onFolderSelected,
    this.directoryPicker,
    this.initialExpanded = true,
  });

  @override
  ConsumerState<ProjectsSectionView> createState() =>
      _ProjectsSectionViewState();
}

class _ProjectsSectionViewState extends ConsumerState<ProjectsSectionView> {
  bool _showArchived = false;
  bool _isOperating = false;

  void _showErrorSnackBar(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Ошибка операции с проектом: $error'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<void> _createProject() async {
    if (_isOperating) return;
    final name = await OrganizationNameDialog.show(
      context: context,
      title: 'Новый проект',
      label: 'Название проекта',
      confirmButtonText: 'Создать',
    );
    if (!mounted || name == null || name.isEmpty) return;

    setState(() => _isOperating = true);
    try {
      final project = await ref
          .read(projectsProvider.notifier)
          .createProject(name);
      if (!mounted) return;
      widget.onProjectSelected?.call(project);
    } catch (e) {
      _showErrorSnackBar(e);
    } finally {
      if (mounted) setState(() => _isOperating = false);
    }
  }

  Future<void> _renameProject(Project project) async {
    if (_isOperating) return;
    final newName = await OrganizationNameDialog.show(
      context: context,
      title: 'Переименовать проект',
      initialValue: project.name,
      label: 'Название проекта',
      confirmButtonText: 'Сохранить',
    );
    if (!mounted ||
        newName == null ||
        newName.isEmpty ||
        newName == project.name) {
      return;
    }

    setState(() => _isOperating = true);
    try {
      await ref
          .read(projectsProvider.notifier)
          .renameProject(project.id, newName);
    } catch (e) {
      _showErrorSnackBar(e);
    } finally {
      if (mounted) setState(() => _isOperating = false);
    }
  }

  Future<void> _togglePin(Project project) async {
    if (_isOperating) return;
    setState(() => _isOperating = true);
    try {
      await ref
          .read(projectsProvider.notifier)
          .setProjectPinned(project.id, pinned: !project.pinned);
    } catch (e) {
      _showErrorSnackBar(e);
    } finally {
      if (mounted) setState(() => _isOperating = false);
    }
  }

  Future<void> _toggleArchive(Project project) async {
    if (_isOperating) return;
    setState(() => _isOperating = true);
    try {
      await ref
          .read(projectsProvider.notifier)
          .setProjectArchived(project.id, archived: !project.archived);
    } catch (e) {
      _showErrorSnackBar(e);
    } finally {
      if (mounted) setState(() => _isOperating = false);
    }
  }

  Future<void> _deleteProject(Project project) async {
    if (_isOperating) return;
    final confirmed = await OrganizationConfirmDeleteDialog.show(
      context: context,
      title: 'Удалить проект?',
      entityName: project.name,
      explanation:
          'Будет удалена только организационная запись проекта. '
          'Все подключённые папки, оригиналы файлов на диске, их метаданные '
          'и история загрузок останутся в полной сохранности.',
      confirmButtonText: 'Удалить проект',
    );
    if (!mounted || !confirmed) return;

    setState(() => _isOperating = true);
    try {
      if (widget.selectedProjectId == project.id) {
        widget.onProjectSelected?.call(null);
      }
      await ref.read(projectsProvider.notifier).deleteProject(project.id);
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
    final projectsAsync = ref.watch(projectsProvider);

    return projectsAsync.when(
      skipLoadingOnReload: true,
      loading:
          () => CollapsibleSectionCard(
            title: 'Проекты',
            icon: Icons.workspaces_outlined,
            initialExpanded: widget.initialExpanded,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
      error:
          (err, _) => CollapsibleSectionCard(
            title: 'Проекты',
            icon: Icons.workspaces_outlined,
            initialExpanded: widget.initialExpanded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Ошибка загрузки проектов: $err',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => ref.invalidate(projectsProvider),
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
      data: (allProjects) {
        final activeProjects = allProjects.where((p) => !p.archived).toList();
        final archivedProjects = allProjects.where((p) => p.archived).toList();

        // Сортировка: pinned первыми
        activeProjects.sort((a, b) {
          if (a.pinned != b.pinned) {
            return a.pinned ? -1 : 1;
          }
          return a.sortOrder.compareTo(b.sortOrder);
        });

        final visibleProjects = _showArchived ? allProjects : activeProjects;

        return CollapsibleSectionCard(
          title: 'Проекты',
          icon: Icons.workspaces_outlined,
          countBadge: activeProjects.length,
          initialExpanded: widget.initialExpanded,
          headerAction: Semantics(
            container: true,
            child: IconButton(
              key: const Key('create_project_header_button'),
              icon:
                  _isOperating
                      ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      )
                      : const Icon(Icons.add, size: 16),
              tooltip: 'Создать проект',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              onPressed: _isOperating ? null : _createProject,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (allProjects.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      Text(
                        'Нет проектов',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextButton.icon(
                        key: const Key('create_first_project_button'),
                        onPressed: _isOperating ? null : _createProject,
                        icon: const Icon(Icons.add, size: 14),
                        label: const Text('Создать первый проект'),
                        style: TextButton.styleFrom(
                          textStyle: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: visibleProjects.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (context, idx) {
                      final project = visibleProjects[idx];
                      final isSelected = widget.selectedProjectId == project.id;
                      final foldersAsync = ref.watch(
                        projectFoldersProvider(project.id),
                      );
                      final folderCount = foldersAsync.value?.length ?? 0;

                      return _buildProjectRow(
                        context: context,
                        project: project,
                        isSelected: isSelected,
                        folderCount: folderCount,
                        folders: foldersAsync.value ?? const [],
                      );
                    },
                  ),
                ),
                if (archivedProjects.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      setState(() {
                        _showArchived = !_showArchived;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _showArchived
                                ? Icons.archive
                                : Icons.archive_outlined,
                            size: 14,
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _showArchived
                                  ? 'Скрыть архив (${archivedProjects.length})'
                                  : 'Показать архив (${archivedProjects.length})',
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildProjectRow({
    required BuildContext context,
    required Project project,
    required bool isSelected,
    required int folderCount,
    required List<String> folders,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: SingleClickArea(
            onTap: () {
              if (isSelected) {
                widget.onProjectSelected?.call(null);
              } else {
                widget.onProjectSelected?.call(project);
              }
            },
            child: Semantics(
              selected: isSelected,
              button: true,
              label:
                  'Проект ${project.name}, папок: $folderCount, '
                  '${project.pinned ? "закреплён, " : ""}'
                  '${project.archived ? "в архиве" : "активен"}',
              child: InkWell(
                key: Key('project_row_${project.id}'),
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  if (isSelected) {
                    widget.onProjectSelected?.call(null);
                  } else {
                    widget.onProjectSelected?.call(project);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color:
                        isSelected
                            ? colorScheme.primary.withValues(alpha: 0.15)
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border:
                        isSelected
                            ? Border.all(
                              color: colorScheme.primary.withValues(alpha: 0.4),
                              width: 1,
                            )
                            : null,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        project.pinned
                            ? Icons.push_pin
                            : (project.archived
                                ? Icons.archive_outlined
                                : Icons.folder_special_outlined),
                        size: 16,
                        color:
                            project.pinned
                                ? colorScheme.primary
                                : (isSelected
                                    ? colorScheme.primary
                                    : colorScheme.onSurface.withValues(
                                      alpha: 0.7,
                                    )),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AppTooltip(
                          message: project.name,
                          child: Text(
                            project.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                              color:
                                  isSelected
                                      ? colorScheme.primary
                                      : (project.archived
                                          ? colorScheme.onSurface.withValues(
                                            alpha: 0.5,
                                          )
                                          : colorScheme.onSurface),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      if (folderCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$folderCount',
                            style: TextStyle(
                              fontSize: 10,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                        ),
                      _buildProjectMenu(project),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (isSelected) ...[
          Padding(
            padding: const EdgeInsets.only(left: 24, top: 4, bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (folders.isEmpty)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Нет папок',
                          style: TextStyle(
                            fontSize: 10,
                            color: colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      TextButton(
                        key: Key('project_attach_folder_button_${project.id}'),
                        onPressed:
                            _isOperating
                                ? null
                                : () => ProjectFoldersDialog.show(
                                  context: context,
                                  project: project,
                                  directoryPicker: widget.directoryPicker,
                                ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Подключить...',
                          style: TextStyle(fontSize: 10),
                        ),
                      ),
                    ],
                  )
                else
                  ...folders.map((folderPath) {
                    final segments = folderPath
                        .split('/')
                        .where((s) => s.isNotEmpty);
                    final folderName =
                        segments.isEmpty ? folderPath : segments.last;

                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        key: Key('project_folder_${project.id}_$folderPath'),
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => widget.onFolderSelected?.call(folderPath),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 2,
                            horizontal: 4,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.folder_open,
                                size: 14,
                                color: colorScheme.primary.withValues(
                                  alpha: 0.8,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: AppTooltip(
                                  message: folderPath,
                                  child: Text(
                                    folderName,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colorScheme.onSurface.withValues(
                                        alpha: 0.8,
                                      ),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildProjectMenu(Project project) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Semantics(
      container: true,
      child: PopupMenuButton<String>(
        key: Key('project_menu_button_${project.id}'),
        icon: Icon(
          Icons.more_vert,
          size: 16,
          color: colorScheme.onSurface.withValues(alpha: 0.5),
        ),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
        tooltip: 'Действия с проектом',
        enabled: !_isOperating,
        onSelected: (action) async {
          switch (action) {
            case 'folders':
              await ProjectFoldersDialog.show(
                context: context,
                project: project,
                directoryPicker: widget.directoryPicker,
              );
              break;
            case 'pin':
              await _togglePin(project);
              break;
            case 'rename':
              await _renameProject(project);
              break;
            case 'archive':
              await _toggleArchive(project);
              break;
            case 'delete':
              await _deleteProject(project);
              break;
          }
        },
        itemBuilder:
            (context) => [
              const PopupMenuItem(
                value: 'folders',
                child: Row(
                  children: [
                    Icon(Icons.folder_copy_outlined, size: 16),
                    SizedBox(width: 8),
                    Text('Папки проекта...'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'pin',
                child: Row(
                  children: [
                    Icon(
                      project.pinned ? Icons.push_pin_outlined : Icons.push_pin,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(project.pinned ? 'Открепить' : 'Закрепить'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'rename',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 16),
                    SizedBox(width: 8),
                    Text('Переименовать...'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'archive',
                child: Row(
                  children: [
                    Icon(
                      project.archived
                          ? Icons.unarchive_outlined
                          : Icons.archive_outlined,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(project.archived ? 'Вернуть из архива' : 'В архив'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Удалить проект...',
                      style: TextStyle(color: colorScheme.error),
                    ),
                  ],
                ),
              ),
            ],
      ),
    );
  }
}
