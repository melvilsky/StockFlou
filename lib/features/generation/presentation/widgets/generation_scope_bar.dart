import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../../../core/widgets/single_click_area.dart';
import '../../../../models/app_file.dart';
import '../../../../models/workflow_status.dart';

/// Сегмент состояния в контекстной строке.
///
/// Это представление существующих workflow-статусов, а не новая модель.
enum ScopeStatusSegment { all, newFiles, readyToUpload }

extension ScopeStatusSegmentX on ScopeStatusSegment {
  String get label {
    switch (this) {
      case ScopeStatusSegment.all:
        return 'Все';
      case ScopeStatusSegment.newFiles:
        return 'Новые';
      case ScopeStatusSegment.readyToUpload:
        return 'Готово';
    }
  }

  String get tooltip {
    switch (this) {
      case ScopeStatusSegment.all:
        return 'Все файлы текущей области';
      case ScopeStatusSegment.newFiles:
        return 'Новые: статус «new», включая файлы, ещё не добавленные в базу';
      case ScopeStatusSegment.readyToUpload:
        return 'Готово к загрузке: статус «ready_to_upload»';
    }
  }

  bool matches(AppFile file) {
    switch (this) {
      case ScopeStatusSegment.all:
        return true;
      case ScopeStatusSegment.newFiles:
        return file.workflowStatus == WorkflowStatus.newFile;
      case ScopeStatusSegment.readyToUpload:
        return file.workflowStatus == WorkflowStatus.readyToUpload;
    }
  }
}

/// Режим сортировки сетки.
enum GridSortMode { date, name, status }

extension GridSortModeX on GridSortMode {
  String get label {
    switch (this) {
      case GridSortMode.date:
        return 'По дате';
      case GridSortMode.name:
        return 'По имени';
      case GridSortMode.status:
        return 'По статусу';
    }
  }
}

/// Вторая строка workspace: контекст области, сегменты статуса,
/// счётчик выделения, переключатель вида, сортировка и фильтры.
class GenerationScopeBar extends StatelessWidget {
  final List<String> breadcrumb;
  final String breadcrumbTooltip;

  final int allCount;
  final int newCount;
  final int readyCount;
  final ScopeStatusSegment segment;
  final ValueChanged<ScopeStatusSegment> onSegmentChanged;

  final int selectedCount;
  final int hiddenSelectedCount;

  final bool isGridView;
  final ValueChanged<bool> onViewModeChanged;

  final GridSortMode sortMode;
  final ValueChanged<GridSortMode> onSortChanged;

  final String filterType;
  final ValueChanged<String> onFilterTypeChanged;
  final Set<String> activeTagFilters;
  final ValueChanged<Set<String>> onTagFiltersChanged;

  final int visibleCount;
  final VoidCallback onSelectAll;
  final VoidCallback? onRefresh;

  const GenerationScopeBar({
    super.key,
    required this.breadcrumb,
    required this.breadcrumbTooltip,
    required this.allCount,
    required this.newCount,
    required this.readyCount,
    required this.segment,
    required this.onSegmentChanged,
    required this.selectedCount,
    this.hiddenSelectedCount = 0,
    required this.isGridView,
    required this.onViewModeChanged,
    required this.sortMode,
    required this.onSortChanged,
    required this.filterType,
    required this.onFilterTypeChanged,
    this.activeTagFilters = const {},
    this.onTagFiltersChanged = _ignoreTags,
    required this.visibleCount,
    required this.onSelectAll,
    this.onRefresh,
  });

  static void _ignoreTags(Set<String> _) {}

  int _countFor(ScopeStatusSegment value) {
    switch (value) {
      case ScopeStatusSegment.all:
        return allCount;
      case ScopeStatusSegment.newFiles:
        return newCount;
      case ScopeStatusSegment.readyToUpload:
        return readyCount;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: AppSizes.scopeBar),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.pagePadding,
        vertical: AppSpacing.sm,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          final compact =
              constraints.maxWidth < AppSizes.compactMinWidth * textScale;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildContextRow(context, palette),
                const SizedBox(height: AppSpacing.sm),
                _buildActionsRow(context, palette),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: _buildContextRow(context, palette)),
              const SizedBox(width: AppSpacing.md),
              _buildActionsRow(context, palette),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContextRow(BuildContext context, AppPalette palette) {
    return Row(
      children: [
        Expanded(child: _buildBreadcrumb(palette)),
        const SizedBox(width: AppSpacing.md),
        _buildSegments(palette),
        if (selectedCount > 0) ...[
          const SizedBox(width: AppSpacing.md),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: _buildSelectionCount(palette),
          ),
        ],
      ],
    );
  }

  Widget _buildBreadcrumb(AppPalette palette) {
    final label = breadcrumb.isEmpty ? 'Без области' : breadcrumb.last;
    return AppTooltip(
      message: breadcrumbTooltip.isEmpty
          ? (breadcrumb.isEmpty ? 'Выберите область в верхней панели' : breadcrumb.join(' / '))
          : breadcrumbTooltip,
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Icon(Icons.folder_outlined, size: 16, color: palette.textMuted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: palette.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegments(AppPalette palette) {
    return Container(
      height: AppSizes.controlHeight,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.field,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final value in ScopeStatusSegment.values)
            Flexible(child: _segmentButton(palette, value)),
        ],
      ),
    );
  }

  Widget _segmentButton(AppPalette palette, ScopeStatusSegment value) {
    final isActive = value == segment;
    return AppTooltip(
      message: value.tooltip,
      child: Semantics(
        button: true,
        selected: isActive,
        label: '${value.label}, файлов: ${_countFor(value)}',
        child: SingleClickArea(
          onTap: () => onSegmentChanged(value),
          child: AnimatedContainer(
            duration: AppMotion.stateChange,
            height: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isActive ? palette.surfaceRaised : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.chip),
              border: Border.all(
                color: isActive ? palette.controlBorder : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    value.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                      color: isActive ? palette.text : palette.textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs + 2),
                Text(
                  '${_countFor(value)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: isActive ? palette.text : palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionCount(AppPalette palette) {
    return Container(
      height: AppSizes.controlHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.selectionSurface,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 15, color: palette.text),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              hiddenSelectedCount > 0
                  ? 'Выбрано $selectedCount · из них скрыто: $hiddenSelectedCount'
                  : 'Выбрано $selectedCount',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: palette.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsRow(BuildContext context, AppPalette palette) {
    final compact =
        MediaQuery.textScalerOf(context).scale(1) > 1.05 ||
        MediaQuery.sizeOf(context).width < AppSizes.compactMinWidth;
    final children = <Widget>[
      AppTooltip(
        message: 'Выделить все видимые материалы',
        child: OutlinedButton.icon(
          onPressed: visibleCount > 0 ? onSelectAll : null,
          icon: const Icon(Icons.select_all, size: 18),
          label: const Text('Выделить всё'),
        ),
      ),
      _viewModeToggle(palette),
      _sortButton(palette),
      _filtersButton(palette),
      if (onRefresh != null)
        AppTooltip(
          message: 'Обновить область',
          child: IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, size: 18),
          ),
        ),
    ];
    if (compact) {
      return Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.end,
        children: children,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          children[i],
        ],
      ],
    );
  }

  Widget _viewModeToggle(AppPalette palette) {
    Widget item({required bool grid}) {
      final isActive = grid == isGridView;
      return AppTooltip(
        message: grid ? 'Сетка' : 'Список',
        child: Semantics(
          button: true,
          selected: isActive,
          child: SingleClickArea(
            onTap: () => onViewModeChanged(grid),
            child: AnimatedContainer(
              duration: AppMotion.stateChange,
              width: AppSizes.controlHeight,
              height: AppSizes.controlHeight - 2,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isActive ? palette.surfaceRaised : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: Icon(
                grid ? Icons.grid_view_rounded : Icons.view_list_outlined,
                size: 18,
                color: isActive ? palette.text : palette.textMuted,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: AppSizes.controlHeight,
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: palette.field,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [item(grid: true), item(grid: false)],
      ),
    );
  }

  Widget _sortButton(AppPalette palette) {
    return PopupMenuButton<GridSortMode>(
      tooltip: 'Сортировка: ${sortMode.label}',
      initialValue: sortMode,
      onSelected: onSortChanged,
      itemBuilder:
          (context) => [
            for (final mode in GridSortMode.values)
              PopupMenuItem(
                value: mode,
                child: Row(
                  children: [
                    Icon(
                      mode == sortMode
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 16,
                      color: mode == sortMode
                          ? palette.selection
                          : palette.textMuted,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Сортировка: ${mode.label}'),
                  ],
                ),
              ),
          ],
      child: Container(
        height: AppSizes.controlHeight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: palette.controlBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sort, size: 16, color: palette.textMuted),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Сортировка: ${sortMode.label}',
              style: TextStyle(fontSize: 12, color: palette.text),
            ),
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.expand_more, size: 16, color: palette.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _filtersButton(AppPalette palette) {
    final active =
        filterType != 'all' || activeTagFilters.isNotEmpty;
    return AppTooltip(
      message: 'Дополнительные фильтры',
      child: PopupMenuButton<String>(
        tooltip: 'Фильтры',
        onSelected: (value) {
          if (value == 'images' || value == 'videos' || value == 'all') {
            onFilterTypeChanged(value);
            return;
          }
          final next = Set<String>.from(activeTagFilters);
          if (next.contains(value)) {
            next.remove(value);
          } else {
            next.add(value);
          }
          onTagFiltersChanged(next);
        },
        itemBuilder:
            (context) => [
              _menuLabel('Тип файла', palette),
              _checkItem('all', 'Все типы', filterType == 'all', palette),
              _checkItem('images', 'Фото', filterType == 'images', palette),
              _checkItem('videos', 'Видео', filterType == 'videos', palette),
              const PopupMenuDivider(),
              _menuLabel('Теги', palette),
              _checkItem(
                AppTags.aiGenerated,
                'AI',
                activeTagFilters.contains(AppTags.aiGenerated),
                palette,
              ),
              _checkItem(
                AppTags.editorial,
                'Editorial',
                activeTagFilters.contains(AppTags.editorial),
                palette,
              ),
            ],
        child: Container(
          width: AppSizes.controlHeight,
          height: AppSizes.controlHeight,
          decoration: BoxDecoration(
            color: active ? palette.selectionSurface : palette.surfaceRaised,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(
              color: active ? palette.selection : palette.controlBorder,
            ),
          ),
          child: Icon(
            Icons.tune,
            size: 18,
            color: active ? palette.text : palette.textMuted,
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _checkItem(
    String value,
    String label,
    bool checked,
    AppPalette palette,
  ) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(
            checked ? Icons.check : Icons.remove,
            size: 16,
            color: checked ? palette.selection : palette.textMuted,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(label),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuLabel(String label, AppPalette palette) {
    return PopupMenuItem<String>(
      enabled: false,
      height: 28,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: palette.textMuted,
        ),
      ),
    );
  }
}
