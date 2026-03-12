import 'package:flutter_riverpod/flutter_riverpod.dart';

enum UploadFilter {
  all('Все'),
  uploading('В процессе'),
  pending('Ожидающие'),
  success('Успешно'),
  error('Ошибки');

  final String label;
  const UploadFilter(this.label);
}

class HistoryFilterNotifier extends Notifier<UploadFilter> {
  @override
  UploadFilter build() => UploadFilter.all;

  void setFilter(UploadFilter filter) {
    state = filter;
  }
}

final historyFilterProvider = NotifierProvider<HistoryFilterNotifier, UploadFilter>(
  HistoryFilterNotifier.new,
);
