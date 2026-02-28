import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'core/theme/app_theme.dart';
import 'features/generation/presentation/generation_screen.dart';
import 'features/history/presentation/history_screen.dart';
import 'features/settings/settings_screen.dart';
import 'core/state/navigation_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 800),
    minimumSize: Size(900, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const ProviderScope(child: StockFlouApp()));
}

class StockFlouApp extends StatelessWidget {
  const StockFlouApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StockFlou',
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
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentIndex = ref.watch(navigationProvider);

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
                          'StockFlou',
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

                // Navigation
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(8),
                    children: [
                      _SidebarItem(
                        icon: Icons.folder_outlined,
                        label: 'Workspaces',
                        isSelected: currentIndex == 0,
                        onTap: () =>
                            ref.read(navigationProvider.notifier).setIndex(0),
                      ),
                      _SidebarItem(
                        icon: Icons.schedule_outlined,
                        label: 'Recent',
                        isSelected: currentIndex == 1,
                        onTap: () =>
                            ref.read(navigationProvider.notifier).setIndex(1),
                      ),
                      _SidebarItem(
                        icon: Icons.cloud_upload_outlined,
                        label: 'Uploads',
                        isSelected: currentIndex == 2,
                        onTap: () =>
                            ref.read(navigationProvider.notifier).setIndex(2),
                      ),
                      _SidebarItem(
                        icon: Icons.analytics_outlined,
                        label: 'Analytics',
                        isSelected: currentIndex == 3,
                        onTap: () =>
                            ref.read(navigationProvider.notifier).setIndex(3),
                      ),
                    ],
                  ),
                ),

                // Settings
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: colorScheme.outline)),
                  ),
                  child: _SidebarItem(
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                    isSelected: currentIndex == 4,
                    onTap: () =>
                        ref.read(navigationProvider.notifier).setIndex(4),
                  ),
                ),
              ],
            ),
          ),

          // Main Content
          Expanded(
            child: IndexedStack(
              index: currentIndex,
              children: const [
                GenerationScreen(), // 0: Workspaces
                HistoryScreen(), // 1: Recent / History
                Center(child: Text('Uploads Context')), // 2: Uploads
                Center(child: Text('Analytics Dashboard')), // 3: Analytics
                SettingsScreen(), // 4: Settings
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final selectedBg = primary.withValues(alpha: 0.1);
    final selectedText = primary;

    final unselectedHover = isDark
        ? Colors.white10
        : Colors.black.withValues(alpha: 0.05);
    final unselectedText = isDark ? Colors.white70 : Colors.black54;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
          hoverColor: isSelected ? selectedBg : unselectedHover,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? selectedBg : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected ? selectedText : unselectedText,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: isSelected
                        ? FontWeight.w500
                        : FontWeight.normal,
                    color: isSelected ? selectedText : unselectedText,
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
}
