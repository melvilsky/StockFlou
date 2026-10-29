import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_flow/core/state/files_provider.dart';
import 'package:stock_flow/core/state/workspaces_provider.dart';
import 'package:stock_flow/core/theme/app_theme.dart';
import 'package:stock_flow/features/generation/presentation/generation_screen.dart';
import 'package:stock_flow/features/generation/presentation/widgets/generation_scope_bar.dart';
import 'package:stock_flow/features/organization/application/organization_providers.dart';
import 'package:stock_flow/features/organization_search/application/organization_search_providers.dart';
import 'package:stock_flow/models/app_file.dart';

import '../folders_projects_integration/integration_scenario_test.dart'
    show TestFilesNotifier, TestWorkspacesNotifier;
import '../organization_presentation/test_helpers.dart';

/// Регрессия по §6/§7 спеки: при 125/150% text scaling, в обеих темах и на
/// поддерживаемых размерах окна нет overflow, а действия редактора доступны
/// (на узком/увеличенном тексте — вкладками «Текст / Ключи / Действия»).
void main() {
  late Directory temp;
  late String folder;
  late List<AppFile> catalog;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final raw = Directory.systemTemp.createTempSync('sf_scaling_');
    temp = Directory(raw.resolveSymbolicLinksSync());
    folder = (Directory('${temp.path}/photos')..createSync()).path;
    final png = img.encodePng(img.Image(width: 4, height: 3));
    catalog = [
      for (var i = 0; i < 6; i++)
        AppFile(
          id: '$i',
          path: '$folder/f$i.png',
          filename: 'f$i.png',
          metadataTitle: 'Title $i',
          metadataDescription: 'Description $i',
          metadataKeywords: 'keyword$i, second$i, third$i',
          createdAt: i,
        ),
    ];
    for (final file in catalog) {
      File(file.path).writeAsBytesSync(png);
    }
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  Future<void> pumpAt(
    WidgetTester tester, {
    required Size size,
    required double textScale,
    required bool light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        filesProvider.overrideWith(() => TestFilesNotifier(catalog)),
        catalogFilesLoaderProvider.overrideWithValue(() async => catalog),
        workspacesProvider.overrideWith(
          () => TestWorkspacesNotifier([WorkspaceEntry(path: folder)]),
        ),
        organizationRepositoryProvider.overrideWithValue(
          FakeOrganizationRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
          home: const Scaffold(body: GenerationScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    container
        .read(organizationSearchSettingsProvider.notifier)
        .setScope(SearchScope.folder(folderPath: folder));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Выделить всё'));
    await tester.pumpAndSettle();
  }

  for (final textScale in [1.25, 1.5]) {
    for (final light in [false, true]) {
      testWidgets(
        'нет overflow при text scale $textScale, '
        '${light ? 'светлая' : 'тёмная'} тема',
        (tester) async {
          for (final size in [
            const Size(1600, 1000),
            const Size(1280, 800),
            const Size(900, 600),
          ]) {
            await pumpAt(
              tester,
              size: size,
              textScale: textScale,
              light: light,
            );
            expect(
              tester.takeException(),
              isNull,
              reason: 'overflow при $size и масштабе $textScale',
            );
            expect(find.byType(GenerationScopeBar), findsOneWidget);
            // Редактор остаётся доступным: на узком окне и при увеличенном
            // тексте он переходит на вкладки, иначе показывает три колонки.
            final expectTabs = size.width < 1100 * textScale;
            if (expectTabs) {
              expect(find.text('Текст'), findsOneWidget);
              expect(find.text('Ключи'), findsOneWidget);
              expect(find.text('Действия'), findsOneWidget);
            } else {
              expect(find.textContaining('Действия для'), findsOneWidget);
              expect(find.textContaining('Применить к'), findsOneWidget);
            }
          }
        },
      );
    }
  }
}
