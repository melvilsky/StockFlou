import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'core/constants/app_constants.dart';
import 'core/services/window_config_service.dart';
import 'core/state/history_filter_provider.dart';
import 'core/state/navigation_provider.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/app_top_bar.dart';
import 'core/widgets/safe_semantics_binding.dart';
import 'features/generation/presentation/generation_screen.dart';
import 'features/history/presentation/history_screen.dart';
import 'features/organization_search/application/organization_search_providers.dart';
import 'features/settings/settings_screen.dart';

Future<void> main() async {
  StockFlowBinding();

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

/// Оболочка приложения: одна глобальная панель сверху и переключаемые экраны.
///
/// Постоянного левого сайдбара нет: рабочие области, папки, проекты,
/// коллекции и «Отбор» доступны из popover текущей области в верхней панели.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  bool _navigationRestored = false;

  /// Выбранная вкладка панели. «Загрузки» и «История» делят один экран,
  /// поэтому одной [NavigationTab] для активной вкладки недостаточно.
  ShellTab _tab = ShellTab.files;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(organizationSearchSettingsProvider.notifier).restore();
    });
  }

  void _setTabState(ShellTab tab) {
    if (!mounted || _tab == tab) return;
    setState(() => _tab = tab);
  }

  /// Восстановление сохранённой вкладки при старте.
  void _applyRestoredTab(NavigationTab tab) {
    ref.read(navigationProvider.notifier).setTab(tab);
    switch (tab) {
      case NavigationTab.workspace:
        _setTabState(ShellTab.files);
      case NavigationTab.uploads:
        _setTabState(ShellTab.uploads);
      case NavigationTab.analytics:
      case NavigationTab.settings:
        break;
    }
  }

  void _selectTab(ShellTab tab) {
    final NavigationTab navigationTab;
    switch (tab) {
      case ShellTab.files:
        navigationTab = NavigationTab.workspace;
      case ShellTab.uploads:
        navigationTab = NavigationTab.uploads;
        // Вкладка «Загрузки» — тот же экран истории с фильтром «Все».
        ref.read(historyFilterProvider.notifier).setFilter(UploadFilter.all);
      case ShellTab.history:
        navigationTab = NavigationTab.uploads;
        // Вкладка «История» — тот же экран истории с фильтром «Успешно».
        ref
            .read(historyFilterProvider.notifier)
            .setFilter(UploadFilter.success);
    }
    // Сначала меняем навигацию: слушатель ниже синхронизирует _tab для
    // общего экрана, затем фиксируем выбранную пользователем вкладку.
    ref.read(navigationProvider.notifier).setTab(navigationTab);
    _setTabState(tab);
  }

  void _openSettings(SettingsTab section) {
    ref.read(settingsTabProvider.notifier).setTab(section);
    ref.read(navigationProvider.notifier).setTab(NavigationTab.settings);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(initialNavigationIndexProvider, (previous, next) {
      next.whenData((tab) {
        if (_navigationRestored) return;
        _navigationRestored = true;
        _applyRestoredTab(tab);
      });
    });

    // Навигацию могут менять и другие места (например, выбор рабочей области
    // в popover); держим активную вкладку панели в согласии с ней.
    ref.listen(navigationProvider, (previous, next) {
      if (previous == next) return;
      switch (next) {
        case NavigationTab.workspace:
          _setTabState(ShellTab.files);
        case NavigationTab.uploads:
          _setTabState(ShellTab.uploads);
        case NavigationTab.analytics:
        case NavigationTab.settings:
          break;
      }
    });

    final navigationTab = ref.watch(navigationProvider);
    final isOverflowView =
        navigationTab == NavigationTab.analytics ||
        navigationTab == NavigationTab.settings;

    final int contentIndex;
    if (navigationTab == NavigationTab.analytics) {
      contentIndex = 2;
    } else if (navigationTab == NavigationTab.settings) {
      contentIndex = 3;
    } else {
      // «Загрузки» и «История» — один и тот же экран с разными фильтрами.
      contentIndex = _tab == ShellTab.files ? 0 : 1;
    }

    return Scaffold(
      body: Column(
        children: [
          AppTopBar(
            activeTab: isOverflowView ? null : _tab,
            onTabSelected: _selectTab,
            onOpenSettings: _openSettings,
            onOpenAnalytics: () {
              ref
                  .read(navigationProvider.notifier)
                  .setTab(NavigationTab.analytics);
            },
          ),
          Expanded(
            // IndexedStack сохраняет состояние экранов при переключении вкладок.
            child: IndexedStack(
              index: contentIndex,
              children: const [
                GenerationScreen(),
                HistoryScreen(embedded: true),
                Center(child: Text('Analytics Dashboard')),
                SettingsScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
