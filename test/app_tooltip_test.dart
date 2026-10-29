import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_flow/core/widgets/app_tooltip.dart';

void main() {
  testWidgets(
    'sibling tooltips keep distinct accessible anchors in a list row',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              tooltipTheme: const TooltipThemeData(waitDuration: Duration.zero),
            ),
            home: Scaffold(
              body: ListView(
                children: const [
                  Row(
                    children: [
                      AppTooltip(message: 'Первая подсказка', child: Text('A')),
                      SizedBox(width: 40),
                      AppTooltip(message: 'Вторая подсказка', child: Text('B')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
        final first = tester.getSemantics(find.byType(AppTooltip).at(0));
        final second = tester.getSemantics(find.byType(AppTooltip).at(1));
        expect(first.id, isNot(second.id));
        expect(first.getSemanticsData().tooltip, 'Первая подсказка');
        expect(second.getSemanticsData().tooltip, 'Вторая подсказка');

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer();
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(find.text('A')));
        await tester.pumpAndSettle();
        expect(find.text('Первая подсказка'), findsOneWidget);
        await mouse.moveTo(tester.getCenter(find.text('B')));
        await tester.pumpAndSettle();
        expect(find.text('Вторая подсказка'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
}
