import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Провайдер идентификаторов файлов (`AppFile.id`), выделенных в сетке в текущий момент.
///
/// Связывает единое выделение сетки [GenerationScreen] с организационным
/// сайдбаром ([OrganizationSidebarView]), позволяя операциям коллекций
/// и «Отбора» получать актуальный снимок выбранных элементов.
class ActiveGridSelectionNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => const [];

  void setSelection(List<String> fileIds) {
    if (_listEquals(state, fileIds)) return;
    state = List<String>.unmodifiable(fileIds);
  }

  void clear() {
    if (state.isEmpty) return;
    state = const [];
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

final activeGridSelectionProvider =
    NotifierProvider<ActiveGridSelectionNotifier, List<String>>(() {
  return ActiveGridSelectionNotifier();
});
