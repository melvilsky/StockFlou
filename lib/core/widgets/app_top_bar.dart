import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../features/folder_navigation/domain/folder_access.dart';
import '../../features/folder_navigation/domain/folder_navigation_models.dart';
import '../../features/folder_navigation/presentation/folder_navigation_view.dart';
import '../../features/organization/presentation/organization_presentation.dart';
import '../../features/organization_search/application/organization_search_providers.dart';
import '../state/active_grid_selection_provider.dart';
import '../state/navigation_provider.dart';
import '../state/workspace_command_provider.dart';
import '../state/workspaces_provider.dart';
import '../theme/app_theme.dart';
import '../theme/design_tokens.dart';
import 'app_tooltip.dart';
import 'single_click_area.dart';
import 'workspaces_sidebar_block.dart';

/// Вкладки глобальной панели.
///
/// «Загрузки» и «История» открывают один и тот же экран истории с разным
/// начальным фильтром очереди; «Настройки» и «Аналитика» живут в overflow-меню.
enum ShellTab { files, uploads, history }

extension ShellTabX on ShellTab {
  String get label {
    switch (this) {
      case ShellTab.files:
        return 'Файлы';
      case ShellTab.uploads:
        return 'Загрузки';
      case ShellTab.history:
        return 'История';
    }
  }
}

/// Единственная глобальная верхняя панель приложения: wordmark, текущая
/// область (popover папок/проектов/коллекций/отбора), вкладки, поиск,
/// «Импорт» и overflow-меню.
///
/// Панель отвечает только за навигацию и общие действия: содержимое экранов
/// живёт ниже, в оболочке ([MainShell]).
class AppTopBar extends ConsumerStatefulWidget {
  const AppTopBar({
    super.key,
    required this.activeTab,
    required this.onTabSelected,
    required this.onOpenSettings,
    required this.onOpenAnalytics,
  });

  /// Активная вкладка; null — открыт раздел из overflow-меню.
  final ShellTab? activeTab;

  final ValueChanged<ShellTab> onTabSelected;

  /// Открыть настройки на конкретном разделе (общие/стоки).
  final ValueChanged<SettingsTab> onOpenSettings;

  final VoidCallback onOpenAnalytics;

  @override
  ConsumerState<AppTopBar> createState() => _AppTopBarState();
}

class _AppTopBarState extends ConsumerState<AppTopBar> {
  /// Место под системные кнопки macOS: titlebar скрыт, кнопки лежат поверх UI.
  static double get _trafficLightInset =>
      defaultTargetPlatform == TargetPlatform.macOS ? 78 : 0;

  /// Левый отступ панели: системная зона плюс обычный отступ страницы.
  static double get _barLeadingInset =>
      _trafficLightInset + AppSizes.pagePadding;

  static final Object _navTapGroup = Object();

  final OverlayPortalController _navController = OverlayPortalController();
  final LayerLink _navLink = LayerLink();
  final FocusNode _scopeFocusNode = FocusNode(debugLabel: 'AppTopBar.scope');
  final MenuController _importController = MenuController();
  final MenuController _overflowController = MenuController();

  bool _scopeHovered = false;
  bool _scopeFocused = false;

  bool get _navOpen => _navController.isShowing;

  @override
  void dispose() {
    _scopeFocusNode.dispose();
    super.dispose();
  }

  void _toggleNav() {
    if (_navOpen) {
      _closeNav();
    } else {
      setState(_navController.show);
    }
  }

  void _closeNav() {
    if (!_navOpen) return;
    setState(_navController.hide);
    // После закрытия верхнего transient-слоя фокус возвращается инициатору.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scopeFocusNode.requestFocus();
    });
  }

  /// Выбор области в popover: закрыть его и показать вкладку «Файлы».
  void _onAreaSelected() {
    _closeNav();
    if (widget.activeTab != ShellTab.files) {
      widget.onTabSelected(ShellTab.files);
    }
  }

  void _openSearchDialog() {
    showDialog<void>(context: context, builder: (_) => const _SearchDialog());
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final scope = _scopePresentation();

    return Container(
      height: AppSizes.appBar,
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(
          bottom: BorderSide(color: palette.border, width: AppStroke.normal),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          // Уже 1100 поиск сворачивается в иконку, «Импорт» — в иконку с меню.
          final compact = width < AppSizes.compactMinWidth;
          final areaWidth = compact ? 148.0 : (width >= 1440 ? 260.0 : 190.0);
          final searchMaxWidth = width >= 1440 ? 320.0 : 240.0;
          // При крупном масштабе текста панель не переполняется: вкладки
          // получают горизонтальную прокрутку, а поиск и импорт — иконки.
          final overflowRisk = _needsScrollableTabs(
            context,
            width,
            compact: compact,
            areaWidth: areaWidth,
          );
          final tabs = _buildTabs(palette, compact: compact);

          return Padding(
            padding: const EdgeInsets.only(right: AppSizes.pagePadding),
            child: Row(
              children: [
                _buildDragArea(palette),
                const SizedBox(width: AppSpacing.md),
                _buildScopeButton(palette, scope, areaWidth),
                const SizedBox(width: AppSpacing.md),
                if (overflowRisk)
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: tabs,
                      ),
                    ),
                  )
                else
                  tabs,
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _buildRightGroup(
                    palette,
                    compact: compact || overflowRisk,
                    searchMaxWidth: searchMaxWidth,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Будет ли строка панели шире доступной ширины при текущем масштабе текста.
  ///
  /// Ширины текстов измеряются [TextPainter], поэтому fallback включается
  /// именно тогда, когда суммарная ширина действительно не помещается.
  bool _needsScrollableTabs(
    BuildContext context,
    double width, {
    required bool compact,
    required double areaWidth,
  }) {
    final textScaler = MediaQuery.textScalerOf(context);
    double measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      final result = painter.width;
      painter.dispose();
      return result;
    }

    final wordmarkWidth =
        measure(
          'StockFlow',
          const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            height: 1.15,
            letterSpacing: -0.4,
          ),
        ) +
        AppSpacing.xs;
    final tabStyle = TextStyle(
      fontSize: compact ? 12 : 13,
      fontWeight: FontWeight.w600,
      height: 1.35,
    );
    final tabPadding = compact ? AppSpacing.sm : AppSpacing.md;
    var tabsWidth = 2 * 3.0; // padding контейнера вкладок
    for (final tab in ShellTab.values) {
      tabsWidth += 2 * tabPadding + measure(tab.label, tabStyle);
    }
    tabsWidth += 2 * 3.0; // промежутки между вкладками

    final importWidth =
        compact
            ? 0.0
            : measure(
                  'Импорт',
                  Theme.of(context).textTheme.labelLarge ??
                      const TextStyle(fontSize: 13),
                ) +
                78;
    // Минимальная ширина правой группы: три иконочные кнопки или поиск
    // в 100 px, «Импорт» и overflow.
    final rightMinWidth =
        compact
            ? 3 * AppSizes.iconHitArea + 2 * AppSpacing.sm
            : 100 + importWidth + AppSizes.iconHitArea + 2 * AppSpacing.sm;

    final needed =
        _barLeadingInset +
        wordmarkWidth +
        3 * AppSpacing.md +
        areaWidth +
        tabsWidth +
        rightMinWidth +
        AppSizes.pagePadding;
    return needed > width;
  }

  // ─── Wordmark / перетаскивание окна ────────────────────────────────────────

  Widget _buildDragArea(AppPalette palette) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) {
        windowManager.startDragging();
      },
      child: Padding(
        padding: EdgeInsets.only(
          left: _barLeadingInset,
          right: AppSpacing.xs,
          top: AppSpacing.sm,
          bottom: AppSpacing.sm,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          child: Text(
            'StockFlow',
            maxLines: 1,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              height: 1.15,
              letterSpacing: -0.4,
              color: palette.text,
            ),
          ),
        ),
      ),
    );
  }

  // ─── Текущая область + popover ─────────────────────────────────────────────

  _ScopePresentation _scopePresentation() {
    final scope = ref.watch(
      organizationSearchSettingsProvider.select((settings) => settings.scope),
    );
    final workspacePath = ref.watch(
      workspacesProvider.select((state) => state.currentPath),
    );

    switch (scope.type) {
      case SearchScopeType.folder:
        final path =
            scope.folderPath.isNotEmpty
                ? scope.folderPath
                : (workspacePath ?? '');
        if (path.trim().isEmpty) {
          return const _ScopePresentation(
            icon: Icons.folder_off_outlined,
            name: 'Без области',
            tooltip: 'Область не выбрана',
          );
        }
        return _ScopePresentation(
          icon: Icons.folder_outlined,
          name: workspaceDisplayName(path),
          tooltip: path,
        );
      case SearchScopeType.project:
        final projects = ref.watch(projectsProvider).value ?? const <Project>[];
        final project = projects.firstWhereOrNull(
          (item) => item.id == scope.projectId,
        );
        return _ScopePresentation(
          icon: Icons.business_center_outlined,
          name: project?.name ?? 'Проект',
          tooltip: project != null ? 'Проект: ${project.name}' : 'Проект',
        );
      case SearchScopeType.collection:
        final collections =
            ref.watch(collectionsProvider).value ?? const <Collection>[];
        final collection = collections.firstWhereOrNull(
          (item) => item.id == scope.collectionId,
        );
        return _ScopePresentation(
          icon: Icons.collections_bookmark_outlined,
          name: collection?.name ?? 'Коллекция',
          tooltip:
              collection != null
                  ? 'Коллекция: ${collection.name}'
                  : 'Коллекция',
        );
      case SearchScopeType.selection:
        return const _ScopePresentation(
          icon: Icons.check_box_outlined,
          name: 'Отбор',
          tooltip: 'Отбор файлов',
        );
      case SearchScopeType.all:
        return const _ScopePresentation(
          icon: Icons.all_inbox_outlined,
          name: 'Без области',
          tooltip: 'Область не выбрана: показаны все материалы',
        );
    }
  }

  Widget _buildScopeButton(
    AppPalette palette,
    _ScopePresentation scope,
    double width,
  ) {
    final backgroundColor =
        _navOpen
            ? palette.selectionSurface
            : _scopeHovered
            ? palette.surfaceHover
            : palette.surfaceRaised;
    final borderColor = _navOpen ? palette.selection : palette.controlBorder;

    return TapRegion(
      groupId: _navTapGroup,
      child: OverlayPortal(
        controller: _navController,
        overlayChildBuilder: (context) => _buildNavOverlay(context, palette),
        child: CompositedTransformTarget(
          link: _navLink,
          child: FocusableActionDetector(
            focusNode: _scopeFocusNode,
            onShowHoverHighlight:
                (value) => setState(() => _scopeHovered = value),
            onShowFocusHighlight:
                (value) => setState(() => _scopeFocused = value),
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  _toggleNav();
                  return null;
                },
              ),
            },
            child: Semantics(
              container: true,
              excludeSemantics: true,
              button: true,
              expanded: _navOpen,
              label: 'Область: ${scope.name}',
              hint: 'Открыть папки, проекты, коллекции и отбор',
              onTap: _toggleNav,
              child: SingleClickArea(
                onTap: _toggleNav,
                child: AppTooltip(
                  message: scope.tooltip,
                  child: AnimatedContainer(
                    duration: _motionDuration(context),
                    curve: AppMotion.easing,
                    width: width,
                    height: AppSizes.controlHeight,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      border: Border.all(
                        color: borderColor,
                        width: AppStroke.normal,
                      ),
                    ),
                    foregroundDecoration:
                        _scopeFocused
                            ? BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                AppRadius.control,
                              ),
                              border: Border.all(
                                color: palette.selection,
                                width: AppStroke.focus,
                              ),
                            )
                            : null,
                    child: Row(
                      children: [
                        Icon(
                          scope.icon,
                          size: 18,
                          color:
                              _navOpen ? palette.selection : palette.textMuted,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            scope.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              height: 1.35,
                              color: palette.text,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Icon(
                          Icons.expand_more,
                          size: 16,
                          color: palette.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavOverlay(BuildContext context, AppPalette palette) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
    return CompositedTransformFollower(
      link: _navLink,
      showWhenUnlinked: false,
      targetAnchor: Alignment.bottomLeft,
      followerAnchor: Alignment.topLeft,
      offset: const Offset(0, AppSpacing.sm),
      child: TapRegion(
        groupId: _navTapGroup,
        onTapOutside: (_) => _closeNav(),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): _closeNav,
          },
          child: Focus(
            autofocus: true,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 384,
                constraints: BoxConstraints(maxHeight: maxHeight),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(AppRadius.panel),
                  border: Border.all(
                    color: palette.border,
                    width: AppStroke.normal,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha:
                            Theme.of(context).brightness == Brightness.dark
                                ? 0.45
                                : 0.16,
                      ),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.panel),
                  child: _AppNavPopover(
                    onClose: _closeNav,
                    onSelected: _onAreaSelected,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Вкладки ───────────────────────────────────────────────────────────────

  Widget _buildTabs(AppPalette palette, {required bool compact}) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.field,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: palette.border, width: AppStroke.normal),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final tab in ShellTab.values) ...[
            if (tab != ShellTab.values.first) const SizedBox(width: 3),
            _TopBarTab(
              label: tab.label,
              compact: compact,
              isActive: widget.activeTab == tab,
              onTap: () => widget.onTabSelected(tab),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Поиск, импорт, overflow ───────────────────────────────────────────────

  Widget _buildRightGroup(
    AppPalette palette, {
    required bool compact,
    required double searchMaxWidth,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (compact)
          _IconAction(
            icon: Icons.search,
            label: 'Поиск',
            tooltip: 'Поиск по текущей области',
            onPressed: _openSearchDialog,
          )
        else
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: searchMaxWidth),
              child: const _SearchField(),
            ),
          ),
        const SizedBox(width: AppSpacing.sm),
        _buildImportMenu(palette, compact: compact),
        const SizedBox(width: AppSpacing.sm),
        _buildOverflowMenu(palette),
      ],
    );
  }

  Widget _buildImportMenu(AppPalette palette, {required bool compact}) {
    final onFilesTab = widget.activeTab == ShellTab.files;
    final tooltip =
        onFilesTab
            ? 'Импорт: добавить файлы, открыть папку или импортировать CSV'
            : 'Импорт доступен на вкладке «Файлы»';

    void emit(WorkspaceCommand command) {
      ref.read(workspaceCommandProvider.notifier).emit(command);
    }

    return MenuAnchor(
      controller: _importController,
      style: _anchorMenuStyle(palette),
      alignmentOffset: const Offset(0, AppSpacing.sm),
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.note_add_outlined, size: 18),
          onPressed:
              onFilesTab ? () => emit(WorkspaceCommand.importFiles) : null,
          child: const Text('Добавить файлы'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.folder_open_outlined, size: 18),
          onPressed:
              onFilesTab ? () => emit(WorkspaceCommand.openFolder) : null,
          child: const Text('Открыть папку'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.table_chart_outlined, size: 18),
          onPressed: onFilesTab ? () => emit(WorkspaceCommand.importCsv) : null,
          child: const Text('Импорт CSV'),
        ),
      ],
      builder: (context, controller, _) {
        void toggle() =>
            controller.isOpen ? controller.close() : controller.open();

        final Widget button =
            compact
                ? IconButton(
                  onPressed: onFilesTab ? toggle : null,
                  color: onFilesTab ? palette.primary : null,
                  icon: const Icon(Icons.file_upload_outlined, size: 18),
                )
                : FilledButton.icon(
                  onPressed: onFilesTab ? toggle : null,
                  icon: const Icon(Icons.file_upload_outlined, size: 18),
                  label: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Импорт'),
                      SizedBox(width: AppSpacing.xs),
                      Icon(Icons.expand_more, size: 16),
                    ],
                  ),
                );

        return AppTooltip(
          message: tooltip,
          child: Semantics(
            container: true,
            excludeSemantics: true,
            button: true,
            enabled: onFilesTab,
            label: 'Импорт',
            hint: onFilesTab ? null : tooltip,
            onTap: onFilesTab ? toggle : null,
            child: button,
          ),
        );
      },
    );
  }

  Widget _buildOverflowMenu(AppPalette palette) {
    return MenuAnchor(
      controller: _overflowController,
      style: _anchorMenuStyle(palette),
      alignmentOffset: const Offset(0, AppSpacing.sm),
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.settings_outlined, size: 18),
          onPressed: () {
            widget.onOpenSettings(SettingsTab.general);
          },
          child: const Text('Настройки'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.cloud_upload_outlined, size: 18),
          onPressed: () {
            widget.onOpenSettings(SettingsTab.stocks);
          },
          child: const Text('Стоки (FTP)'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.analytics_outlined, size: 18),
          onPressed: widget.onOpenAnalytics,
          child: const Text('Аналитика'),
        ),
      ],
      builder:
          (context, controller, _) => AppTooltip(
            message: 'Дополнительные разделы',
            child: Semantics(
              container: true,
              excludeSemantics: true,
              button: true,
              label: 'Дополнительные разделы',
              onTap:
                  () =>
                      controller.isOpen
                          ? controller.close()
                          : controller.open(),
              child: IconButton(
                onPressed:
                    () =>
                        controller.isOpen
                            ? controller.close()
                            : controller.open(),
                icon: const Icon(Icons.more_horiz, size: 20),
              ),
            ),
          ),
    );
  }

  MenuStyle _anchorMenuStyle(AppPalette palette) {
    return MenuStyle(
      backgroundColor: WidgetStatePropertyAll(palette.surfaceRaised),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll<double>(8),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          side: BorderSide(color: palette.border, width: AppStroke.normal),
        ),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(vertical: AppSpacing.xs),
      ),
    );
  }
}

Duration _motionDuration(BuildContext context) {
  return MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : AppMotion.hover;
}

/// Представление текущей области в кнопке панели.
class _ScopePresentation {
  const _ScopePresentation({
    required this.icon,
    required this.name,
    required this.tooltip,
  });

  final IconData icon;
  final String name;
  final String tooltip;
}

// ─── Вкладка ─────────────────────────────────────────────────────────────────

class _TopBarTab extends StatefulWidget {
  const _TopBarTab({
    required this.label,
    required this.isActive,
    required this.compact,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final bool compact;
  final VoidCallback onTap;

  @override
  State<_TopBarTab> createState() => _TopBarTabState();
}

class _TopBarTabState extends State<_TopBarTab> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final backgroundColor =
        widget.isActive
            ? palette.selectionSurface
            : _hovered
            ? palette.surfaceHover
            : Colors.transparent;

    return FocusableActionDetector(
      onShowHoverHighlight: (value) => setState(() => _hovered = value),
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: Semantics(
        container: true,
        excludeSemantics: true,
        button: true,
        selected: widget.isActive,
        label: widget.label,
        onTap: widget.onTap,
        child: SingleClickArea(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: _motionDuration(context),
            curve: AppMotion.easing,
            height: AppSizes.chipMinHeight + 2,
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? AppSpacing.sm : AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(AppRadius.chip),
              border: Border.all(
                color: widget.isActive ? palette.selection : Colors.transparent,
                width: AppStroke.normal,
              ),
            ),
            foregroundDecoration:
                _focused
                    ? BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                      border: Border.all(
                        color: palette.selection,
                        width: AppStroke.focus,
                      ),
                    )
                    : null,
            child: Center(
              child: Text(
                widget.label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: widget.compact ? 12 : 13,
                  fontWeight:
                      widget.isActive ? FontWeight.w600 : FontWeight.w500,
                  height: 1.35,
                  color: widget.isActive ? palette.text : palette.textMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Иконочная кнопка с подписью ─────────────────────────────────────────────

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AppTooltip(
      message: tooltip,
      child: Semantics(
        container: true,
        excludeSemantics: true,
        button: true,
        label: label,
        enabled: onPressed != null,
        onTap: onPressed,
        child: IconButton(onPressed: onPressed, icon: Icon(icon, size: 18)),
      ),
    );
  }
}

// ─── Поиск ───────────────────────────────────────────────────────────────────

class _SearchField extends ConsumerStatefulWidget {
  const _SearchField({this.autofocus = false});

  final bool autofocus;

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  bool _focused = false;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _currentQuery())
      ..addListener(_handleTextChanged);
    _focusNode = FocusNode(debugLabel: 'AppTopBar.search')
      ..addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleTextChanged)
      ..dispose();
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    super.dispose();
  }

  String _currentQuery() {
    return ref.read(organizationSearchSettingsProvider).filters.query;
  }

  void _handleTextChanged() {
    if (!mounted) return;
    // Пересобрать поле ради clear-кнопки; строка пишется в onChanged.
    setState(() {});
  }

  void _handleFocusChanged() {
    if (!mounted) return;
    setState(() => _focused = _focusNode.hasFocus);
  }

  void _applyQuery(String value) {
    final notifier = ref.read(organizationSearchSettingsProvider.notifier);
    notifier.setQuery(value);
    notifier.persist();
  }

  void _clear() {
    _controller.clear();
    _applyQuery('');
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    // Синхронизация с внешними изменениями: восстановление настроек,
    // сброс фильтров из workspace.
    ref.listen(
      organizationSearchSettingsProvider.select(
        (settings) => settings.filters.query,
      ),
      (previous, next) {
        if (next == _controller.text) return;
        _controller.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      },
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        height: AppSizes.controlHeight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          color: palette.field,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(
            color:
                _hovered && !_focused ? palette.controlBorder : palette.border,
            width: AppStroke.normal,
          ),
        ),
        foregroundDecoration:
            _focused
                ? BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  border: Border.all(
                    color: palette.selection,
                    width: AppStroke.focus,
                  ),
                )
                : null,
        child: Row(
          children: [
            Icon(Icons.search, size: 18, color: palette.textMuted),
            const SizedBox(width: AppSpacing.sm - 2),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: widget.autofocus,
                textAlignVertical: TextAlignVertical.center,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: palette.text,
                ),
                cursorColor: palette.selection,
                onChanged: _applyQuery,
                decoration: InputDecoration.collapsed(
                  hintText: 'Поиск по файлам и метаданным',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: palette.textMuted,
                  ),
                ),
              ),
            ),
            if (_controller.text.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.xs),
              AppTooltip(
                message: 'Очистить поиск',
                child: Semantics(
                  container: true,
                  excludeSemantics: true,
                  button: true,
                  label: 'Очистить поиск',
                  onTap: _clear,
                  child: IconButton(
                    onPressed: _clear,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: AppSizes.chipRemoveHitArea,
                      minHeight: AppSizes.chipRemoveHitArea,
                    ),
                    icon: const Icon(Icons.close, size: 16),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Диалог поиска для узкого окна, где поле свёрнуто в иконку.
class _SearchDialog extends StatelessWidget {
  const _SearchDialog();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Dialog(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(AppSpacing.xxl),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.panel),
        side: BorderSide(color: palette.border, width: AppStroke.normal),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Поиск',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: palette.text,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const _SearchField(autofocus: true),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Ищет по имени файла, заголовку, описанию и ключевым словам '
                'в текущей области.',
                style: TextStyle(fontSize: 12, color: palette.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Popover навигации ───────────────────────────────────────────────────────

/// Содержимое popover: рабочие области, подпапки текущей папки, проекты,
/// коллекции и «Отбор». Переиспользует существующие блоки без переписывания.
class _AppNavPopover extends ConsumerStatefulWidget {
  const _AppNavPopover({required this.onClose, required this.onSelected});

  /// Закрыть popover (без смены вкладки).
  final VoidCallback onClose;

  /// Область выбрана: закрыть popover и перейти на вкладку «Файлы».
  final VoidCallback onSelected;

  @override
  ConsumerState<_AppNavPopover> createState() => _AppNavPopoverState();
}

class _AppNavPopoverState extends ConsumerState<_AppNavPopover> {
  /// Первый вызов onSelection приходит автоматически при подключении корня
  /// дерева папок; он не должен закрывать popover.
  bool _firstFolderEmission = true;

  late final void Function(FolderSelection selection) _onFolderSelection =
      _handleFolderSelection;

  void _handleFolderSelection(FolderSelection selection) {
    final isAutomatic = _firstFolderEmission;
    _firstFolderEmission = false;

    final currentPath = ref.read(workspacesProvider).currentPath;
    if (currentPath == null || currentPath.trim().isEmpty) return;

    final searchSettings = ref.read(organizationSearchSettingsProvider);
    // Защита от перезаписи восстановленного проекта/коллекции/отбора или подпапки
    // (перенесено из прежней оболочки без изменений).
    if (selection.path == currentPath && !selection.includeSubfolders) {
      if (searchSettings.scope.type != SearchScopeType.folder) return;
      if (searchSettings.scope.folderPath.isNotEmpty &&
          searchSettings.scope.folderPath != currentPath &&
          isPathInsideRoot(searchSettings.scope.folderPath, currentPath)) {
        return;
      }
    }

    final notifier = ref.read(organizationSearchSettingsProvider.notifier);
    notifier.setScope(
      SearchScope.folder(
        folderPath: selection.path,
        includeSubfolders: selection.includeSubfolders,
      ),
    );
    notifier.persist();

    if (!isAutomatic) widget.onSelected();
  }

  void _selectProject(Project? project) {
    final notifier = ref.read(organizationSearchSettingsProvider.notifier);
    if (project != null) {
      notifier.setScope(
        SearchScope.project(projectId: project.id, includeSubfolders: false),
      );
    } else {
      final current = ref.read(workspacesProvider).currentPath ?? '';
      notifier.setScope(
        SearchScope.folder(folderPath: current, includeSubfolders: false),
      );
    }
    notifier.persist();
    widget.onSelected();
  }

  void _selectFolder(String folderPath) {
    ref.read(workspacesProvider.notifier).addWorkspace(folderPath);
    final notifier = ref.read(organizationSearchSettingsProvider.notifier);
    notifier.setScope(
      SearchScope.folder(folderPath: folderPath, includeSubfolders: false),
    );
    notifier.persist();
    widget.onSelected();
  }

  void _selectCollection(Collection? collection) {
    final notifier = ref.read(organizationSearchSettingsProvider.notifier);
    if (collection != null) {
      notifier.setScope(SearchScope.collection(collectionId: collection.id));
    } else {
      final current = ref.read(workspacesProvider).currentPath ?? '';
      notifier.setScope(
        SearchScope.folder(folderPath: current, includeSubfolders: false),
      );
    }
    notifier.persist();
    widget.onSelected();
  }

  void _openSelection() {
    final notifier = ref.read(organizationSearchSettingsProvider.notifier);
    notifier.setScope(const SearchScope.selection());
    notifier.persist();
    widget.onSelected();
  }

  @override
  Widget build(BuildContext context) {
    // Выбор другой рабочей области закрывает popover.
    ref.listen(workspacesProvider.select((state) => state.currentIndex), (
      previous,
      next,
    ) {
      if (previous != null && previous != next) widget.onClose();
    });

    final currentEntry = ref.watch(
      workspacesProvider.select((state) => state.currentEntry),
    );
    final currentPath = currentEntry?.path;
    final scope = ref.watch(
      organizationSearchSettingsProvider.select((settings) => settings.scope),
    );
    final selectedFileIds = ref.watch(activeGridSelectionProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const WorkspacesSidebarBlock(),
          if (currentPath != null && currentPath.trim().isNotEmpty)
            FolderNavigationView(
              key: ValueKey('folder_nav_$currentPath'),
              rootFolder: currentPath,
              access: SecurityScopedFolderAccessScope(
                rootPath: currentPath,
                bookmark: currentEntry?.bookmark,
              ),
              onSelection: _onFolderSelection,
            ),
          OrganizationSidebarView(
            selectedProjectId:
                scope.type == SearchScopeType.project ? scope.projectId : null,
            selectedCollectionId:
                scope.type == SearchScopeType.collection
                    ? scope.collectionId
                    : null,
            isSelectionSource: scope.type == SearchScopeType.selection,
            selectedFileIds: selectedFileIds,
            onProjectSelected: _selectProject,
            onFolderSelected: _selectFolder,
            onCollectionSelected: _selectCollection,
            onOpenSelection: _openSelection,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}
