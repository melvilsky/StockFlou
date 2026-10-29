import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_flow/features/organization/presentation/organization_presentation.dart';

import 'test_helpers.dart';

void main() {
  testWidgets(
      'SelectionSectionView: просмотр, добавление, удаление выбранных ID и очистка отбора',
      (tester) async {
    final repo = FakeOrganizationRepository();
    await repo.addToSelection('file_A');
    await repo.addToSelection('file_B');

    bool openedSelection = false;
    List<String> currentGridSelection = ['file_B', 'file_C'];

    await tester.pumpWidget(
      buildTestAppWithRepo(
        repo: repo,
        child: StatefulBuilder(
          builder: (context, setState) {
            return SelectionSectionView(
              selectedFileIds: currentGridSelection,
              isSelectedSource: openedSelection,
              onOpenSelection: () {
                setState(() => openedSelection = true);
              },
            );
          },
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 1. Отображение счётчика
    expect(find.text('2'), findsNWidgets(2)); // в бейдже секции и в строке "Просмотреть «Отбор»"

    // 2. Клик на просмотр отбора
    await tester.tap(find.byKey(const Key('open_selection_row')));
    await tester.pump();
    expect(openedSelection, isTrue);

    // 3. Добавление выбранных ID в «Отбор»
    expect(find.byKey(const Key('add_selected_to_selection_button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('add_selected_to_selection_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repo.recordedCalls, contains('addToSelection(file_B)'));
    expect(repo.recordedCalls, contains('addToSelection(file_C)'));

    var selection = await repo.getSelectionFileIds();
    expect(selection, containsAll(['file_A', 'file_B', 'file_C']));

    // 4. Удаление выбранных ID из «Отбора» (только ссылки)
    expect(find.byKey(const Key('remove_selected_from_selection_button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('remove_selected_from_selection_button')));
    await tester.pumpAndSettle();

    // Проверяем диалог предупреждения
    expect(find.text('Удалить выбранные из «Отбора»?'), findsOneWidget);
    expect(
      find.text(
        'Будут удалены ссылки на выбранные материалы из временного отбора. '
        'Оригиналы файлов на диске и метаданные останутся без изменений.',
      ),
      findsOneWidget,
    );

    // Подтверждаем удаление
    await tester.tap(find.byKey(const Key('organization_delete_confirm_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repo.recordedCalls, contains('removeFromSelection(file_B)'));
    expect(repo.recordedCalls, contains('removeFromSelection(file_C)'));

    selection = await repo.getSelectionFileIds();
    expect(selection.contains('file_B'), isFalse);
    expect(selection.contains('file_C'), isFalse);
    expect(selection.contains('file_A'), isTrue); // file_A остался

    // 5. Очистка всего «Отбора»
    await tester.tap(find.byKey(const Key('clear_selection_header_button')));
    await tester.pumpAndSettle();

    expect(find.text('Очистить «Отбор»?'), findsOneWidget);
    expect(
      find.text(
        'Будут очищены только сохранённые ссылки временного отбора. '
        'Все оригинальные файлы на диске, их метаданные и история '
        'загрузок останутся в полной сохранности.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('organization_delete_confirm_button')));
    await tester.pumpAndSettle();

    expect(repo.recordedCalls, contains('clearSelection()'));
    expect(await repo.getSelectionFileIds(), isEmpty);
  });
}
