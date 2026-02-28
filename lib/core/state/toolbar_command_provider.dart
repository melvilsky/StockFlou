import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Команда от кнопок панели инструментов (внизу слева в разделе «Рабочее пространство»).
enum ToolbarCommand {
  selectAll,
  generateAI,
  clearSelection,
}

class ToolbarCommandNotifier extends Notifier<ToolbarCommand?> {
  @override
  ToolbarCommand? build() => null;

  void emit(ToolbarCommand cmd) {
    state = cmd;
  }

  void clear() {
    state = null;
  }
}

final toolbarCommandProvider =
    NotifierProvider<ToolbarCommandNotifier, ToolbarCommand?>(() => ToolbarCommandNotifier());
