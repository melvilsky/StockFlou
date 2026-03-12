import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks which stocks are currently selected/active in the Uploads sidebar.
/// This determines where the files will be queued when "Queue ready" is clicked.
class ActiveStocksNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    return {'adobe'};
  }

  void toggle(String stockKey) {
    if (state.contains(stockKey)) {
      state = {...state}..remove(stockKey);
    } else {
      state = {...state}..add(stockKey);
    }
  }
}

final activeStocksProvider = NotifierProvider<ActiveStocksNotifier, Set<String>>(
  ActiveStocksNotifier.new,
);
