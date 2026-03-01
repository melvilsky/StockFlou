import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';

const _keyNavIndex = 'navigation_index';

class NavigationNotifier extends Notifier<NavigationTab> {
  @override
  NavigationTab build() => NavigationTab.workspace;

  void setTab(NavigationTab tab) {
    if (state == tab) return;
    state = tab;
    _save(tab.index);
  }

  static Future<void> _save(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyNavIndex, index);
  }

  /// Восстанавливает сохранённый индекс при старте приложения.
  static Future<NavigationTab> loadSavedTab() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt(_keyNavIndex) ?? 0;
    if (idx >= 0 && idx < NavigationTab.values.length) {
      return NavigationTab.values[idx];
    }
    return NavigationTab.workspace;
  }
}

final navigationProvider = NotifierProvider<NavigationNotifier, NavigationTab>(
  () {
    return NavigationNotifier();
  },
);

/// При старте загружает сохранённый раздел (для восстановления состояния).
final initialNavigationIndexProvider = FutureProvider<NavigationTab>((ref) {
  return NavigationNotifier.loadSavedTab();
});
