import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_flow/features/organization/presentation/organization_presentation.dart';

import 'test_helpers.dart';

void main() {
  testWidgets(
      'CollectionsSectionView: создание, добавление/удаление выбранных ID, очистка и удаление коллекции',
      (tester) async {
    final repo = FakeOrganizationRepository();
    final col1 = await repo.createCollection('Избранное');
    await repo.addFileToCollection(col1.id, 'file_1');
    await repo.addFileToCollection(col1.id, 'file_2');

    Collection? selectedCollection;
    List<String> currentGridSelection = ['file_2', 'file_3'];

    await tester.pumpWidget(
      buildTestAppWithRepo(
        repo: repo,
        child: StatefulBuilder(
          builder: (context, setState) {
            return CollectionsSectionView(
              selectedCollectionId: selectedCollection?.id,
              selectedFileIds: currentGridSelection,
              onCollectionSelected: (c) {
                setState(() => selectedCollection = c);
              },
            );
          },
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 1. Проверяем отображение существующей коллекции и счётчика
    expect(find.text('Избранное'), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // счётчик файлов

    // 2. Выбор коллекции
    await tester.tap(find.byKey(Key('collection_row_${col1.id}')));
    await tester.pump();
    expect(selectedCollection?.id, equals(col1.id));

    // 3. Добавление выбранных ID (file_2, file_3) в существующую коллекцию
    await tester.tap(find.byKey(Key('collection_menu_button_${col1.id}')));
    await tester.pumpAndSettle();

    expect(find.text('Добавить выбранные (2)'), findsOneWidget);
    await tester.tap(find.text('Добавить выбранные (2)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repo.recordedCalls, contains('addFileToCollection(${col1.id}, file_2)'));
    expect(repo.recordedCalls, contains('addFileToCollection(${col1.id}, file_3)'));

    var filesInCol = await repo.getFileIdsInCollection(col1.id);
    expect(filesInCol, containsAll(['file_1', 'file_2', 'file_3']));

    // 4. Удаление выбранных ID из коллекции (только ссылок)
    await tester.tap(find.byKey(Key('collection_menu_button_${col1.id}')));
    await tester.pumpAndSettle();

    expect(find.text('Удалить выбранные (2)'), findsOneWidget);
    await tester.tap(find.text('Удалить выбранные (2)'));
    await tester.pumpAndSettle();

    // Проверяем диалог предупреждения о сохранности оригиналов
    expect(find.text('Удалить выбранные из коллекции?'), findsOneWidget);
    expect(
      find.text(
        'Из коллекции будут удалены только ссылки на выбранные материалы. '
        'Физические файлы на диске и их метаданные не будут изменены.',
      ),
      findsOneWidget,
    );

    // Подтверждаем удаление ссылок
    await tester.tap(find.byKey(const Key('organization_delete_confirm_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repo.recordedCalls, contains('removeFileFromCollection(${col1.id}, file_2)'));
    expect(repo.recordedCalls, contains('removeFileFromCollection(${col1.id}, file_3)'));

    filesInCol = await repo.getFileIdsInCollection(col1.id);
    expect(filesInCol.contains('file_2'), isFalse);
    expect(filesInCol.contains('file_3'), isFalse);
    expect(filesInCol.contains('file_1'), isTrue); // file_1 остался

    // 5. Создание новой коллекции с автоматическим добавлением выбранных ID
    await tester.tap(find.byKey(const Key('create_collection_header_button')));
    await tester.pumpAndSettle();

    expect(find.text('Новая коллекция'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('organization_name_input')),
      'Макро 2026',
    );
    await tester.tap(find.byKey(const Key('organization_name_submit_button')));
    await tester.pumpAndSettle();

    expect(repo.recordedCalls, contains('createCollection(Макро 2026)'));
    expect(selectedCollection?.name, equals('Макро 2026'));

    final createdCol = (await repo.getCollections()).firstWhere((c) => c.name == 'Макро 2026');
    final createdFiles = await repo.getFileIdsInCollection(createdCol.id);
    expect(createdFiles, containsAll(['file_2', 'file_3']));

    // 6. Очистка коллекции
    await tester.tap(find.byKey(Key('collection_menu_button_${col1.id}')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Очистить коллекцию...'));
    await tester.pumpAndSettle();

    expect(find.text('Очистить коллекцию?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('organization_delete_confirm_button')));
    await tester.pumpAndSettle();

    expect(repo.recordedCalls, contains('clearCollection(${col1.id})'));
    expect(await repo.getFileIdsInCollection(col1.id), isEmpty);

    // 7. Безопасное удаление коллекции
    await tester.tap(find.byKey(Key('collection_menu_button_${col1.id}')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Удалить коллекцию...'));
    await tester.pumpAndSettle();

    expect(find.text('Удалить коллекцию?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('organization_delete_confirm_button')));
    await tester.pumpAndSettle();

    expect(repo.recordedCalls, contains('deleteCollection(${col1.id})'));
    final collections = await repo.getCollections();
    expect(collections.any((c) => c.id == col1.id), isFalse);
  });
}
