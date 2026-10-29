import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_flow/features/organization/presentation/dialogs/organization_confirm_delete_dialog.dart';

void main() {
  Widget buildTestApp(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: child,
      ),
    );
  }

  testWidgets('OrganizationConfirmDeleteDialog: отображает пояснение и кнопки',
      (tester) async {
    bool? confirmed;

    await tester.pumpWidget(
      buildTestApp(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              confirmed = await OrganizationConfirmDeleteDialog.show(
                context: context,
                title: 'Удалить коллекцию?',
                entityName: 'Архитектура',
                explanation:
                    'Будет удалена только коллекция. Оригинальные файлы '
                    'на диске останутся в сохранности.',
                confirmButtonText: 'Удалить коллекцию',
              );
            },
            child: const Text('Открыть'),
          ),
        ),
      ),
    );

    // 1. Проверяем отмену
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();

    expect(find.text('Удалить коллекцию?'), findsOneWidget);
    expect(find.text('Архитектура'), findsOneWidget);
    expect(
      find.text(
        'Будет удалена только коллекция. Оригинальные файлы '
        'на диске останутся в сохранности.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('organization_delete_cancel_button')));
    await tester.pumpAndSettle();

    expect(find.byType(OrganizationConfirmDeleteDialog), findsNothing);
    expect(confirmed, isFalse);

    // 2. Проверяем подтверждение
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('organization_delete_confirm_button')));
    await tester.pumpAndSettle();

    expect(find.byType(OrganizationConfirmDeleteDialog), findsNothing);
    expect(confirmed, isTrue);
  });
}
