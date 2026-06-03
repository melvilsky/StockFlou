import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'core/theme/app_theme.dart';
import 'core/state/navigation_provider.dart';
import 'core/state/workspaces_provider.dart';
import 'features/generation/presentation/generation_screen.dart';
import 'features/history/presentation/history_screen.dart';
import 'features/settings/settings_screen.dart';
import 'core/services/window_config_service.dart';
import 'core/state/history_filter_provider.dart';
import 'core/state/active_stocks_provider.dart';
import 'core/widgets/single_click_area.dart';
import 'core/constants/app_constants.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  final windowConfig = WindowConfigService();
  final windowOptions = await windowConfig.getStoredWindowOptions();

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowConfig.applyStoredPosition();
    await windowManager.show();
    await windowManager.focus();
    
    // Start listening for window changes
    await windowConfig.init();
  });

  runApp(const ProviderScope(child: StockFlowApp()));
}

class StockFlowApp extends StatelessWidget {
  const StockFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StockFlow',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      home: const MainShell(),
    );
  }
}

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  bool _navigationRestored = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentIndex = ref.watch(navigationProvider);
    ref.listen(initialNavigationIndexProvider, (prev, next) {
      next.whenData((tab) {
        if (!_navigationRestored) {
          _navigationRestored = true;
          ref.read(navigationProvider.notifier).setTab(tab);
        }
      });
    });

    return Scaffold(
      body: Row(
        children: [
          // Left Sidebar
          Container(
            width: 256,
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(right: BorderSide(color: colorScheme.outline)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Window drag area & Brand
                GestureDetector(
                  onPanStart: (details) {
                    windowManager.startDragging();
                  },
                  child: Container(
                    padding: const EdgeInsets.only(
                      top: 36,
                      left: 16,
                      right: 16,
                      bottom: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      border: Border(
                        bottom: BorderSide(color: colorScheme.outlineVariant),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.photo_library_outlined,
                          color: colorScheme.primary,
                          size: 28,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'StockFlow',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Рабочие области — только в разделе «Рабочее пространство»
                if (currentIndex == NavigationTab.workspace)
                  _buildWorkspacesBlock(context, colorScheme, ref),

                // Меню настроек — только в разделе «Настройки»
                if (currentIndex == NavigationTab.settings)
                  _buildSettingsSidebarBlock(context, colorScheme, ref),

                // Меню загрузок — только в разделе «Uploads»
                if (currentIndex == NavigationTab.uploads)
                  _buildUploadsSidebarBlock(context, colorScheme, ref),

                const Spacer(),

                // Разделы и настройки — компактная горизонтальная панель внизу
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: colorScheme.outline)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _SidebarIconItem(
                        icon: Icons.folder_outlined,
                        tooltip: 'Рабочее пространство',
                        isSelected: currentIndex == NavigationTab.workspace,
                        onTap: () => ref
                            .read(navigationProvider.notifier)
                            .setTab(NavigationTab.workspace),
                        compact: true,
                      ),
                      _SidebarIconItem(
                        icon: Icons.cloud_upload_outlined,
                        tooltip: 'Uploads',
                        isSelected: currentIndex == NavigationTab.uploads,
                        onTap: () => ref
                            .read(navigationProvider.notifier)
                            .setTab(NavigationTab.uploads),
                        compact: true,
                      ),
                      _SidebarIconItem(
                        icon: Icons.analytics_outlined,
                        tooltip: 'Analytics',
                        isSelected: currentIndex == NavigationTab.analytics,
                        onTap: () => ref
                            .read(navigationProvider.notifier)
                            .setTab(NavigationTab.analytics),
                        compact: true,
                      ),
                      _SidebarIconItem(
                        icon: Icons.settings_outlined,
                        tooltip: 'Настройки',
                        isSelected: currentIndex == NavigationTab.settings,
                        onTap: () => ref
                            .read(navigationProvider.notifier)
                            .setTab(NavigationTab.settings),
                        compact: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Main Content
          Expanded(
            child: IndexedStack(
              index: currentIndex.index,
              children: const [
                GenerationScreen(), // workspace
                HistoryScreen(), // uploads
                Center(child: Text('Analytics Dashboard')), // analytics
                SettingsScreen(), // settings
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSidebarBlock(
    BuildContext context,
    ColorScheme colorScheme,
    WidgetRef ref,
  ) {
    final currentTab = ref.watch(settingsTabProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final blockBg = isDark
        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
        : colorScheme.surfaceContainerLow;

    Widget buildItem(SettingsTab tab, String title, IconData icon) {
      final isSelected = currentTab == tab;
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: Colors.transparent,
          child: SingleClickArea(
            onTap: () {
              ref.read(settingsTabProvider.notifier).setTab(tab);
            },
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? colorScheme.primary.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: 16,
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: blockBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Настройки',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 10),
          buildItem(SettingsTab.general, 'Общие', Icons.settings_outlined),
          buildItem(
            SettingsTab.stocks,
            'Стоки (FTP)',
            Icons.cloud_upload_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspacesBlock(
    BuildContext context,
    ColorScheme colorScheme,
    WidgetRef ref,
  ) {
    final workspaces = ref.watch(workspacesProvider);
    final paths = workspaces.paths;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final blockBg = isDark
        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
        : colorScheme.surfaceContainerLow;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: blockBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Рабочие области',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 160),
            child: paths.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Нет папок',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: paths.length,
                    itemBuilder: (context, idx) {
                      final path = paths[idx];
                      final name = path.split(Platform.pathSeparator).last;
                      final isSelected = idx == workspaces.currentIndex;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Material(
                          color: Colors.transparent,
                          child: SingleClickArea(
                            onTap: () {
                              ref
                                  .read(workspacesProvider.notifier)
                                  .setCurrent(idx);
                              ref
                                  .read(navigationProvider.notifier)
                                  .setTab(NavigationTab.workspace);
                            },
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? colorScheme.primary.withValues(
                                          alpha: 0.15,
                                        )
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.folder_outlined,
                                      size: 18,
                                      color: isSelected
                                          ? colorScheme.primary
                                          : colorScheme.onSurface.withValues(
                                              alpha: 0.6,
                                            ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Tooltip(
                                        message: path,
                                        child: Text(
                                          name,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: isSelected
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                            color: isSelected
                                                ? colorScheme.primary
                                                : colorScheme.onSurface,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.close,
                                        size: 16,
                                        color: colorScheme.onSurface.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                      onPressed: () {
                                        ref
                                            .read(workspacesProvider.notifier)
                                            .removeWorkspace(idx);
                                      },
                                      tooltip: 'Удалить из рабочих областей',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 28,
                                        minHeight: 28,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: FilledButton.icon(
              onPressed: () async {
                final path = await getDirectoryPath();
                if (path != null && path.isNotEmpty) {
                  await ref
                      .read(workspacesProvider.notifier)
                      .addWorkspace(path);
                  if (context.mounted) {
                    ref
                        .read(navigationProvider.notifier)
                        .setTab(NavigationTab.workspace);
                  }
                }
              },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Добавить папку'),
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 34,
            child: OutlinedButton.icon(
              onPressed: workspaces.currentPath == null
                  ? null
                  : () {
                      ref.read(refreshWorkspaceProvider.notifier).trigger();
                      ref
                          .read(navigationProvider.notifier)
                          .setTab(NavigationTab.workspace);
                    },
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Обновить'),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colorScheme.outline),
              ),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildUploadsSidebarBlock(
    BuildContext context,
    ColorScheme colorScheme,
    WidgetRef ref,
  ) {
    final currentFilter = ref.watch(historyFilterProvider);
    final activeStocks = ref.watch(activeStocksProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final blockBg = isDark
        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
        : colorScheme.surfaceContainerLow;

    Widget buildFilterItem(UploadFilter filter, IconData icon) {
      final isSelected = currentFilter == filter;
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: Colors.transparent,
          child: SingleClickArea(
            onTap: () {
              ref.read(historyFilterProvider.notifier).setFilter(filter);
            },
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? colorScheme.primary.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: 16,
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        filter.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget buildStockToggle(String stockKey, String label) {
      final isSelected = activeStocks.contains(stockKey);
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              ref.read(activeStocksProvider.notifier).toggle(stockKey);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: isSelected,
                      onChanged: (_) {
                        ref.read(activeStocksProvider.notifier).toggle(stockKey);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: blockBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Фильтры',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 10),
          buildFilterItem(UploadFilter.all, Icons.list),
          buildFilterItem(UploadFilter.uploading, Icons.upload),
          buildFilterItem(UploadFilter.pending, Icons.hourglass_empty),
          buildFilterItem(UploadFilter.success, Icons.check_circle_outline),
          buildFilterItem(UploadFilter.error, Icons.error_outline),
          const SizedBox(height: 12),
          Divider(color: colorScheme.outline.withValues(alpha: 0.2)),
          const SizedBox(height: 12),
          Text(
            'Активные стоки',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 10),
          buildStockToggle('adobe', 'Adobe Stock'),
          buildStockToggle('shutterstock', 'Shutterstock'),
        ],
      ),
    );
  }
}

class _SidebarIconItem extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isSelected;
  final VoidCallback onTap;
  final bool compact;

  const _SidebarIconItem({
    required this.icon,
    required this.tooltip,
    required this.isSelected,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary;
    final selectedBg = primary.withValues(alpha: 0.12);
    final padding = compact ? 6.0 : 12.0;
    final iconSize = compact ? 20.0 : 24.0;
    return Tooltip(
      message: tooltip,
      child: SingleClickArea(
        onTap: onTap,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(compact ? 6 : 8),
            child: Container(
              padding: EdgeInsets.all(padding),
              decoration: BoxDecoration(
                color: isSelected ? selectedBg : Colors.transparent,
                borderRadius: BorderRadius.circular(compact ? 6 : 8),
              ),
              child: Icon(
                icon,
                size: iconSize,
                color: isSelected
                    ? primary
                    : colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
