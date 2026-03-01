import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyNavIndex = 'navigation_index';

class NavigationNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setIndex(int index) {
    if (state == index) return;
    state = index;
    _save(index);
  }

  static Future<void> _save(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyNavIndex, index);
  }

  /// Восстанавливает сохранённый индекс при старте приложения.
  static Future<int> loadSavedIndex() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyNavIndex) ?? 0;
  }
}

final navigationProvider = NotifierProvider<NavigationNotifier, int>(() {
  return NavigationNotifier();
});

/// При старте загружает сохранённый раздел (для восстановления состояния).
final initialNavigationIndexProvider = FutureProvider<int>((ref) {
  return NavigationNotifier.loadSavedIndex();
});
