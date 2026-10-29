import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_flow/core/state/files_provider.dart';
import 'package:stock_flow/core/state/history_filter_provider.dart';
import 'package:stock_flow/core/state/workspace_command_provider.dart';
import 'package:stock_flow/core/state/workspaces_provider.dart';
import 'package:stock_flow/features/generation/presentation/generation_screen.dart';
import 'package:stock_flow/features/history/presentation/history_screen.dart';
import 'package:stock_flow/features/organization/application/organization_providers.dart';
import 'package:stock_flow/features/organization_search/application/organization_search_providers.dart';
import 'package:stock_flow/main.dart';
import 'package:stock_flow/models/app_file.dart';

import '../folders_projects_integration/integration_scenario_test.dart'
    show TestFilesNotifier, TestWorkspacesNotifier;
import '../organization_presentation/test_helpers.dart';

/// Проверяет швы новой оболочки: верхнюю панель, вкладки, единый поиск
/// и меню «Импорт» — то, что раньше жило в постоянном сайдбаре.
void main() {
  late Directory temp;
  late String folder;
  late List<AppFile> catalog;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final raw = Directory.systemTemp.createTempSync('sf_shell_');
    temp = Directory(raw.resolveSymbolicLinksSync());
    folder = (Directory('${temp.path}/photos')..createSync()).path;
    final png = img.encodePng(img.Image(width: 1, height: 1));
    catalog = [
      AppFile(
        id: 'a',
        path: '$folder/a.png',
        filename: 'a.png',
        createdAt: 1,
      ),
    ];
    for (final file in catalog) {
      File(file.path).writeAsBytesSync(png);
    }
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  Future<ProviderContainer> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
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
        child: const StockFlowApp(),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('оболочка: вкладки открывают файлы, загрузки и историю', (
    tester,
  ) async {
    final container = await pumpShell(tester);

    expect(find.text('StockFlow'), findsOneWidget);
    expect(find.text('Файлы'), findsOneWidget);
    expect(find.text('Загрузки'), findsOneWidget);
    expect(find.text('История'), findsOneWidget);
    expect(find.byType(GenerationScreen), findsOneWidget);

    // «Загрузки» и «История» — один экран с разными фильтрами, без своего AppBar.
    await tester.tap(find.text('История'));
    await tester.pumpAndSettle();
    expect(container.read(historyFilterProvider), UploadFilter.success);
    expect(find.byType(HistoryScreen), findsOneWidget);
    expect(find.text('Upload Queue'), findsNothing);

    await tester.tap(find.text('Загрузки'));
    await tester.pumpAndSettle();
    expect(container.read(historyFilterProvider), UploadFilter.all);

    await tester.tap(find.text('Файлы'));
    await tester.pumpAndSettle();
    expect(find.byType(GenerationScreen), findsOneWidget);
  });

  testWidgets('единый поиск пишет в существующие настройки области', (
    tester,
  ) async {
    final container = await pumpShell(tester);
    final searchField = find.byType(TextField).first;
    await tester.enterText(searchField, 'golden');
    await tester.pumpAndSettle();
    expect(
      container.read(organizationSearchSettingsProvider).filters.query,
      'golden',
    );
  });

  testWidgets('«Импорт» не эмитит команды вне вкладки «Файлы»', (
    tester,
  ) async {
    final container = await pumpShell(tester);
    await tester.tap(find.text('История'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Импорт'));
    await tester.pumpAndSettle();
    expect(container.read(workspaceCommandProvider), isNull);

    await tester.tap(find.text('Файлы'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Импорт'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Открыть папку'));
    await tester.pump();
    expect(container.read(workspaceCommandProvider)?.command,
        WorkspaceCommand.openFolder);
  });
}
