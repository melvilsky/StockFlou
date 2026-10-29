import '../../../../core/widgets/app_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/single_click_area.dart';
import '../../application/organization_providers.dart';
import '../dialogs/organization_confirm_delete_dialog.dart';
import '../dialogs/organization_name_dialog.dart';
import 'collapsible_section_card.dart';

/// Виджет управления коллекциями для сайдбара.
///
/// Предоставляет:
/// - создание, переименование и удаление коллекций;
/// - выбор активной коллекции;
/// - добавление выбранных материалов ([selectedFileIds]) в коллекцию;
/// - удаление выбранных материалов из коллекции (безопасно, только ссылки);
/// - очистку всей коллекции от ссылок;
/// - гарантию сохранности оригиналов файлов на диске при любых операциях;
/// - защиту от повторных нажатий и обработку асинхронных ошибок.
class CollectionsSectionView extends ConsumerStatefulWidget {
  final String? selectedCollectionId;
  final ValueChanged<Collection?>? onCollectionSelected;
  final List<String> selectedFileIds;
  final bool initialExpanded;

  const CollectionsSectionView({
    super.key,
    this.selectedCollectionId,
    this.onCollectionSelected,
    this.selectedFileIds = const [],
    this.initialExpanded = true,
  });

  @override
  ConsumerState<CollectionsSectionView> createState() =>
      _CollectionsSectionViewState();
}

class _CollectionsSectionViewState
    extends ConsumerState<CollectionsSectionView> {
  bool _isOperating = false;

  void _showErrorSnackBar(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Ошибка операции с коллекцией: $error'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<void> _createCollection() async {
    if (_isOperating) return;
    final targetIds = List<String>.from(widget.selectedFileIds);

    final name = await OrganizationNameDialog.show(
      context: context,
      title: 'Новая коллекция',
      label: 'Название коллекции',
      confirmButtonText: 'Создать',
    );
    if (!mounted || name == null || name.isEmpty) return;

    setState(() => _isOperating = true);
    try {
      final collection = await ref
          .read(collectionsProvider.notifier)
          .createCollection(name);

      if (targetIds.isNotEmpty) {
        final notifier = ref.read(
          collectionFileIdsProvider(collection.id).notifier,
        );
        for (final id in targetIds) {
          await notifier.addFile(id);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Коллекция «${collection.name}» создана, добавлено файлов: ${targetIds.length}',
              ),
            ),
          );
        }
      }

      if (!mounted) return;
      widget.onCollectionSelected?.call(collection);
    } catch (e) {
      _showErrorSnackBar(e);
    } finally {
      if (mounted) setState(() => _isOperating = false);
    }
  }

  Future<void> _renameCollection(Collection collection) async {
    if (_isOperating) return;
    final newName = await OrganizationNameDialog.show(
      context: context,
      title: 'Переименовать коллекцию',
      initialValue: collection.name,
      label: 'Название коллекции',
      confirmButtonText: 'Сохранить',
    );
    if (!mounted ||
        newName == null ||
        newName.isEmpty ||
        newName == collection.name) {
      return;
    }

    setState(() => _isOperating = true);
    try {
      await ref
          .read(collectionsProvider.notifier)
          .renameCollection(collection.id, newName);
    } catch (e) {
      _showErrorSnackBar(e);
    } finally {
      if (mounted) setState(() => _isOperating = false);
    }
  }

  Future<void> _deleteCollection(Collection collection) async {
    if (_isOperating) return;
    final confirmed = await OrganizationConfirmDeleteDialog.show(
      context: context,
      title: 'Удалить коллекцию?',
      entityName: collection.name,
      explanation:
          'Будет удалена только организационная запись коллекции. '
          'Все оригинальные файлы на диске, их метаданные и история '
          'загрузок останутся в полной сохранности.',
      confirmButtonText: 'Удалить коллекцию',
    );
    if (!mounted || !confirmed) return;

    setState(() => _isOperating = true);
    try {
      if (widget.selectedCollectionId == collection.id) {
        widget.onCollectionSelected?.call(null);
      }
      await ref
          .read(collectionsProvider.notifier)
          .deleteCollection(collection.id);
    } catch (e) {
      _showErrorSnackBar(e);
    } finally {
      if (mounted) setState(() => _isOperating = false);
    }
  }

  Future<void> _clearCollection(Collection collection) async {
    if (_isOperating) return;
    final confirmed = await OrganizationConfirmDeleteDialog.show(
      context: context,
      title: 'Очистить коллекцию?',
      entityName: collection.name,
      explanation:
          'Из коллекции будут удалены все ссылки на файлы. '
          'Сами файлы на диске останутся нетронутыми.',
      confirmButtonText: 'Очистить',
    );
    if (!mounted || !confirmed) return;

    setState(() => _isOperating = true);
    try {
      await ref.read(collectionFileIdsProvider(collection.id).notifier).clear();
    } catch (e) {
      _showErrorSnackBar(e);
    } finally {
      if (mounted) setState(() => _isOperating = false);
    }
  }

  Future<void> _addSelectedToCollection(Collection collection) async {
    if (_isOperating) return;
    final targetIds = List<String>.from(widget.selectedFileIds);
    if (targetIds.isEmpty) return;

    setState(() => _isOperating = true);
    try {
      final notifier = ref.read(
        collectionFileIdsProvider(collection.id).notifier,
      );
      for (final id in targetIds) {
        await notifier.addFile(id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'В коллекцию «${collection.name}» добавлено файлов: ${targetIds.length}',
            ),
          ),
        );
      }
    } catch (e) {
      _showErrorSnackBar(e);
    } finally {
      if (mounted) setState(() => _isOperating = false);
    }
  }

  Future<void> _removeSelectedFromCollection(Collection collection) async {
    if (_isOperating) return;
    final targetIds = List<String>.from(widget.selectedFileIds);
    if (targetIds.isEmpty) return;

    final confirmed = await OrganizationConfirmDeleteDialog.show(
      context: context,
      title: 'Удалить выбранные из коллекции?',
      entityName: 'Коллекция «${collection.name}», файлов: ${targetIds.length}',
      explanation:
          'Из коллекции будут удалены только ссылки на выбранные материалы. '
          'Физические файлы на диске и их метаданные не будут изменены.',
      confirmButtonText: 'Исключить из коллекции',
    );
    if (!mounted || !confirmed) return;

    setState(() => _isOperating = true);
    try {
      final notifier = ref.read(
        collectionFileIdsProvider(collection.id).notifier,
      );
      for (final id in targetIds) {
        await notifier.removeFile(id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Из коллекции «${collection.name}» удалено ссылок: ${targetIds.length} (файлы на диске сохранены)',
            ),
          ),
        );
      }
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
    final collectionsAsync = ref.watch(collectionsProvider);

    return collectionsAsync.when(
      skipLoadingOnReload: true,
      loading:
          () => CollapsibleSectionCard(
            title: 'Коллекции',
            icon: Icons.collections_bookmark_outlined,
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
            title: 'Коллекции',
            icon: Icons.collections_bookmark_outlined,
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
                    'Ошибка загрузки коллекций: $err',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => ref.invalidate(collectionsProvider),
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
      data: (collections) {
        return CollapsibleSectionCard(
          title: 'Коллекции',
          icon: Icons.collections_bookmark_outlined,
          countBadge: collections.length,
          initialExpanded: widget.initialExpanded,
          headerAction: Semantics(
            container: true,
            child: IconButton(
              key: const Key('create_collection_header_button'),
              icon:
                  _isOperating
                      ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      )
                      : const Icon(Icons.add, size: 16),
              tooltip: 'Создать коллекцию',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              onPressed: _isOperating ? null : _createCollection,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (collections.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      Text(
                        'Нет коллекций',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextButton.icon(
                        key: const Key('create_first_collection_button'),
                        onPressed: _isOperating ? null : _createCollection,
                        icon: const Icon(Icons.add, size: 14),
                        label: const Text('Создать коллекцию'),
                        style: TextButton.styleFrom(
                          textStyle: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: collections.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (context, idx) {
                      final collection = collections[idx];
                      final isSelected =
                          widget.selectedCollectionId == collection.id;
                      final fileIdsAsync = ref.watch(
                        collectionFileIdsProvider(collection.id),
                      );
                      final fileCount = fileIdsAsync.value?.length ?? 0;

                      return _buildCollectionRow(
                        context: context,
                        collection: collection,
                        isSelected: isSelected,
                        fileCount: fileCount,
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCollectionRow({
    required BuildContext context,
    required Collection collection,
    required bool isSelected,
    required int fileCount,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: SingleClickArea(
        onTap: () {
          if (isSelected) {
            widget.onCollectionSelected?.call(null);
          } else {
            widget.onCollectionSelected?.call(collection);
          }
        },
        child: Semantics(
          selected: isSelected,
          button: true,
          label: 'Коллекция ${collection.name}, материалов: $fileCount',
          child: InkWell(
            key: Key('collection_row_${collection.id}'),
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              if (isSelected) {
                widget.onCollectionSelected?.call(null);
              } else {
                widget.onCollectionSelected?.call(collection);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                    Icons.collections_bookmark_outlined,
                    size: 16,
                    color:
                        isSelected
                            ? colorScheme.primary
                            : colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppTooltip(
                      message: collection.name,
                      child: Text(
                        collection.name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.normal,
                          color:
                              isSelected
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
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
                      '$fileCount',
                      style: TextStyle(
                        fontSize: 10,
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  _buildCollectionMenu(collection),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollectionMenu(Collection collection) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasSelection = widget.selectedFileIds.isNotEmpty;

    return Semantics(
      container: true,
      child: PopupMenuButton<String>(
        key: Key('collection_menu_button_${collection.id}'),
        icon: Icon(
          Icons.more_vert,
          size: 16,
          color: colorScheme.onSurface.withValues(alpha: 0.5),
        ),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
        tooltip: 'Действия с коллекцией',
        enabled: !_isOperating,
        onSelected: (action) async {
          switch (action) {
            case 'add_selected':
              await _addSelectedToCollection(collection);
              break;
            case 'remove_selected':
              await _removeSelectedFromCollection(collection);
              break;
            case 'rename':
              await _renameCollection(collection);
              break;
            case 'clear':
              await _clearCollection(collection);
              break;
            case 'delete':
              await _deleteCollection(collection);
              break;
          }
        },
        itemBuilder:
            (context) => [
              PopupMenuItem(
                value: 'add_selected',
                enabled: hasSelection,
                child: Row(
                  children: [
                    const Icon(Icons.add_photo_alternate_outlined, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      hasSelection
                          ? 'Добавить выбранные (${widget.selectedFileIds.length})'
                          : 'Добавить выбранные (нет выбора)',
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'remove_selected',
                enabled: hasSelection,
                child: Row(
                  children: [
                    const Icon(Icons.remove_circle_outline, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      hasSelection
                          ? 'Удалить выбранные (${widget.selectedFileIds.length})'
                          : 'Удалить выбранные (нет выбора)',
                    ),
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
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.clear_all, size: 16),
                    SizedBox(width: 8),
                    Text('Очистить коллекцию...'),
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
                      'Удалить коллекцию...',
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
