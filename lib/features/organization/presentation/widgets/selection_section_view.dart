import '../../../../core/widgets/app_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/single_click_area.dart';
import '../../application/organization_providers.dart';
import '../dialogs/organization_confirm_delete_dialog.dart';
import 'collapsible_section_card.dart';

/// Виджет управления «Отбором» (Selection) для сайдбара.
///
/// Предоставляет:
/// - отображение постоянного количества отобранных файлов (сохраняется между сессиями);
/// - переключение на просмотр файлов «Отбора» ([onOpenSelection]);
/// - добавление выбранных в текущей сетке материалов ([selectedFileIds]) в «Отбор»;
/// - удаление выбранных материалов из «Отбора» (только ссылки);
/// - безопасную очистку «Отбора» с подтверждением (оригиналы на диске не затрагиваются);
/// - защиту от повторных нажатий и обработку асинхронных ошибок.
class SelectionSectionView extends ConsumerStatefulWidget {
  final List<String> selectedFileIds;
  final bool isSelectedSource;
  final VoidCallback? onOpenSelection;
  final bool initialExpanded;

  const SelectionSectionView({
    super.key,
    this.selectedFileIds = const [],
    this.isSelectedSource = false,
    this.onOpenSelection,
    this.initialExpanded = true,
  });

  @override
  ConsumerState<SelectionSectionView> createState() =>
      _SelectionSectionViewState();
}

class _SelectionSectionViewState extends ConsumerState<SelectionSectionView> {
  bool _isOperating = false;

  void _showErrorSnackBar(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Ошибка операции с «Отбором»: $error'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<void> _addSelectedToSelection() async {
    if (_isOperating) return;
    final targetIds = List<String>.from(widget.selectedFileIds);
    if (targetIds.isEmpty) return;

    setState(() => _isOperating = true);
    try {
      final notifier = ref.read(selectionFileIdsProvider.notifier);
      for (final id in targetIds) {
        await notifier.addFile(id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'В «Отбор» добавлено материалов: ${targetIds.length}',
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

  Future<void> _removeSelectedFromSelection() async {
    if (_isOperating) return;
    final targetIds = List<String>.from(widget.selectedFileIds);
    if (targetIds.isEmpty) return;

    final confirmed = await OrganizationConfirmDeleteDialog.show(
      context: context,
      title: 'Удалить выбранные из «Отбора»?',
      entityName: 'Выбрано элементов: ${targetIds.length}',
      explanation:
          'Будут удалены ссылки на выбранные материалы из временного отбора. '
          'Оригиналы файлов на диске и метаданные останутся без изменений.',
      confirmButtonText: 'Исключить из отбора',
    );
    if (!mounted || !confirmed) return;

    setState(() => _isOperating = true);
    try {
      final notifier = ref.read(selectionFileIdsProvider.notifier);
      for (final id in targetIds) {
        await notifier.removeFile(id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Из «Отбора» удалено материалов: ${targetIds.length} (файлы на диске сохранены)',
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

  Future<void> _clearSelection(int count) async {
    if (_isOperating) return;
    final confirmed = await OrganizationConfirmDeleteDialog.show(
      context: context,
      title: 'Очистить «Отбор»?',
      entityName: 'Элементов в отборе: $count',
      explanation:
          'Будут очищены только сохранённые ссылки временного отбора. '
          'Все оригинальные файлы на диске, их метаданные и история '
          'загрузок останутся в полной сохранности.',
      confirmButtonText: 'Очистить отбор',
    );
    if (!mounted || !confirmed) return;

    setState(() => _isOperating = true);
    try {
      await ref.read(selectionFileIdsProvider.notifier).clear();
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
    final selectionAsync = ref.watch(selectionFileIdsProvider);

    return selectionAsync.when(
      skipLoadingOnReload: true,
      loading:
          () => CollapsibleSectionCard(
            title: 'Отбор',
            icon: Icons.filter_frames_outlined,
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
            title: 'Отбор',
            icon: Icons.filter_frames_outlined,
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
                    'Ошибка загрузки «Отбора»: $err',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => ref.invalidate(selectionFileIdsProvider),
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
      data: (fileIds) {
        final count = fileIds.length;
        final hasGridSelection = widget.selectedFileIds.isNotEmpty;

        return CollapsibleSectionCard(
          title: 'Отбор',
          icon: Icons.filter_frames_outlined,
          countBadge: count,
          initialExpanded: widget.initialExpanded,
          headerAction:
              count > 0
                  ? Semantics(
                    container: true,
                    child: IconButton(
                      key: const Key('clear_selection_header_button'),
                      icon: const Icon(Icons.clear_all, size: 16),
                      tooltip: 'Очистить «Отбор»',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
                      onPressed:
                          _isOperating ? null : () => _clearSelection(count),
                    ),
                  )
                  : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SingleClickArea(
                onTap: widget.onOpenSelection,
                child: Semantics(
                  selected: widget.isSelectedSource,
                  button: true,
                  label: 'Просмотреть «Отбор», материалов: $count',
                  child: InkWell(
                    key: const Key('open_selection_row'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: widget.onOpenSelection,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color:
                            widget.isSelectedSource
                                ? colorScheme.primary.withValues(alpha: 0.15)
                                : colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                        border:
                            widget.isSelectedSource
                                ? Border.all(
                                  color: colorScheme.primary.withValues(
                                    alpha: 0.4,
                                  ),
                                  width: 1,
                                )
                                : Border.all(
                                  color: colorScheme.outline.withValues(
                                    alpha: 0.15,
                                  ),
                                ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.auto_awesome_motion_outlined,
                            size: 18,
                            color:
                                widget.isSelectedSource
                                    ? colorScheme.primary
                                    : colorScheme.onSurface.withValues(
                                      alpha: 0.7,
                                    ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Просмотреть «Отбор»',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight:
                                    widget.isSelectedSource
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                color:
                                    widget.isSelectedSource
                                        ? colorScheme.primary
                                        : colorScheme.onSurface,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  widget.isSelectedSource
                                      ? colorScheme.primary
                                      : colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$count',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color:
                                    widget.isSelectedSource
                                        ? colorScheme.onPrimary
                                        : colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (hasGridSelection) ...[
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 30,
                        child: FilledButton.tonalIcon(
                          key: const Key('add_selected_to_selection_button'),
                          onPressed:
                              _isOperating ? null : _addSelectedToSelection,
                          icon: const Icon(
                            Icons.bookmark_add_outlined,
                            size: 14,
                          ),
                          label: Text(
                            '+ Выбранные (${widget.selectedFileIds.length})',
                            style: const TextStyle(fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      height: 30,
                      child: AppTooltip(
                        message: 'Удалить выбранные ссылки из «Отбора»',
                        child: OutlinedButton(
                          key: const Key(
                            'remove_selected_from_selection_button',
                          ),
                          onPressed:
                              _isOperating
                                  ? null
                                  : _removeSelectedFromSelection,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          child: const Icon(
                            Icons.remove_circle_outline,
                            size: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              Text(
                'Отбор сохраняется между сессиями до явной очистки. '
                'Очистка отбора не удаляет оригиналы с диска.',
                style: TextStyle(
                  fontSize: 10,
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                  height: 1.3,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
