import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_flow/features/organization/presentation/dialogs/organization_name_dialog.dart';

void main() {
  Widget buildTestApp(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: child,
      ),
    );
  }

  testWidgets('OrganizationNameDialog: валидация пустого имени и пробелов',
      (tester) async {
    String? result;

    await tester.pumpWidget(
      buildTestApp(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await OrganizationNameDialog.show(
                context: context,
                title: 'Новый проект',
              );
            },
            child: const Text('Открыть'),
          ),
        ),
      ),
    );

    // Открываем диалог
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();

    expect(find.text('Новый проект'), findsOneWidget);
    expect(find.byKey(const Key('organization_name_input')), findsOneWidget);

    // 1. Попытка подтверждения с пустым полем
    await tester.tap(find.byKey(const Key('organization_name_submit_button')));
    await tester.pumpAndSettle();

    expect(find.text('Название не может быть пустым'), findsOneWidget);
    expect(result, isNull);

    // 2. Попытка подтверждения со строкой только из пробелов
    await tester.enterText(
      find.byKey(const Key('organization_name_input')),
      '     ',
    );
    await tester.tap(find.byKey(const Key('organization_name_submit_button')));
    await tester.pumpAndSettle();

    expect(find.text('Название не может быть пустым'), findsOneWidget);
    expect(result, isNull);

    // 3. Попытка подтверждения со строкой > 100 символов
    final longName = 'A' * 105;
    await tester.enterText(
      find.byKey(const Key('organization_name_input')),
      longName,
    );
    await tester.tap(find.byKey(const Key('organization_name_submit_button')));
    await tester.pumpAndSettle();

    expect(find.text('Название не должно превышать 100 символов'), findsOneWidget);
    expect(result, isNull);

    // 4. Валидное имя с пробелами по краям (должно быть trimmed)
    await tester.enterText(
      find.byKey(const Key('organization_name_input')),
      '   Летняя серия 2026   ',
    );
    await tester.tap(find.byKey(const Key('organization_name_submit_button')));
    await tester.pumpAndSettle();

    // Диалог закрылся и вернул trim-строку
    expect(find.byType(OrganizationNameDialog), findsNothing);
    expect(result, equals('Летняя серия 2026'));
  });

  testWidgets('OrganizationNameDialog: кнопка Отмена возвращает null',
      (tester) async {
    String? result = 'initial';

    await tester.pumpWidget(
      buildTestApp(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await OrganizationNameDialog.show(
                context: context,
                title: 'Переименовать',
                initialValue: 'Старое имя',
              );
            },
            child: const Text('Открыть'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();

    expect(find.text('Старое имя'), findsOneWidget);

    await tester.tap(find.byKey(const Key('organization_name_cancel_button')));
    await tester.pumpAndSettle();

    expect(find.byType(OrganizationNameDialog), findsNothing);
    expect(result, isNull);
  });
}
