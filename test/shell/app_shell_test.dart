import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_flow/core/state/files_provider.dart';
import 'package:stock_flow/core/state/history_filter_provider.dart';
import 'package:stock_flow/core/state/workspace_command_provider.dart';
import 'package:stock_flow/core/state/workspaces_provider.dart';
import 'package:stock_flow/core/widgets/workspaces_sidebar_block.dart';
import 'package:stock_flow/features/generation/presentation/generation_screen.dart';
import 'package:stock_flow/features/history/presentation/history_screen.dart';
import 'package:stock_flow/features/organization/application/organization_providers.dart';
import 'package:stock_flow/features/organization_search/application/organization_search_providers.dart';
import 'package:stock_flow/main.dart';
import 'package:stock_flow/models/app_file.dart';

import '../folders_projects_integration/integration_scenario_test.dart'
    show TestFilesNotifier;
import '../folders_projects_acceptance/grid_search_link_acceptance_test.dart'
    show pumpWithRealIo;
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
      AppFile(id: 'a', path: '$folder/a.png', filename: 'a.png', createdAt: 1),
    ];
    for (final file in catalog) {
      File(file.path).writeAsBytesSync(png);
    }
    SharedPreferences.setMockInitialValues({
      keyWorkspaceEntries: jsonEncode([
        {'path': folder},
      ]),
    });
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
          () => WorkspacesNotifier(isMacOS: false),
        ),
        organizationRepositoryProvider.overrideWithValue(
          FakeOrganizationRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      container.read(workspacesProvider);
      await container.read(workspacesProvider.notifier).initialization;
      await container.read(workspacesProvider.notifier).availabilityCheckFuture;
    });
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

  testWidgets('список папок ограничен по размеру и закрывается по Escape', (
    tester,
  ) async {
    final container = await pumpShell(tester);
    container
        .read(organizationSearchSettingsProvider.notifier)
        .setScope(
          SearchScope.folder(folderPath: folder, includeSubfolders: true),
        );
    await tester.pumpAndSettle();
    for (final size in [const Size(1280, 800), const Size(900, 600)]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Область: photos'));
      await pumpWithRealIo(tester);
      final block = find.byType(WorkspacesSidebarBlock);
      expect(tester.getSize(block).width, lessThanOrEqualTo(384));
      final scroll =
          find
              .ancestor(of: block, matching: find.byType(SingleChildScrollView))
              .first;
      final bounds = tester.getRect(scroll);
      expect(bounds.bottom, lessThanOrEqualTo(size.height));
      expect(bounds.right, lessThanOrEqualTo(size.width));
      expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(block, findsNothing);
      expect(
        container
            .read(organizationSearchSettingsProvider)
            .scope
            .includeSubfolders,
        isTrue,
      );
    }
  });

  testWidgets('плюс импортирует вложенные папки и не проходит по ссылкам', (
    tester,
  ) async {
    final imported = Directory('$folder/imported')..createSync();
    final nested = Directory('${imported.path}/one/two')
      ..createSync(recursive: true);
    final outside = Directory('${temp.path}/outside')..createSync();
    final png = img.encodePng(img.Image(width: 1, height: 1));
    File('${imported.path}/root.png').writeAsBytesSync(png);
    File('${nested.path}/nested.PNG').writeAsBytesSync(png);
    File('${nested.path}/ignored.txt').writeAsStringSync('not media');
    File('${outside.path}/outside.png').writeAsBytesSync(png);
    Link('${imported.path}/cycle').createSync(imported.path);
    Link('${imported.path}/outside').createSync(outside.path);

    const picker = MethodChannel('plugins.flutter.io/file_selector');
    var pickerCalls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(picker, (
      call,
    ) async {
      expect(call.method, 'getDirectoryPath');
      pickerCalls++;
      return imported.path;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        picker,
        null,
      );
    });

    final container = await pumpShell(tester);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Область:')));
    await pumpWithRealIo(tester);
    await tester.tap(find.byTooltip('Импортировать папку с подпапками'));
    await pumpWithRealIo(tester);
    expect(pickerCalls, 1);
    expect(find.byType(WorkspacesSidebarBlock), findsNothing);
    expect(container.read(workspacesProvider).currentPath, imported.path);
    expect(
      container.read(organizationSearchSettingsProvider).scope,
      SearchScope.folder(folderPath: imported.path, includeSubfolders: true),
    );
    expect(find.text('root.png'), findsOneWidget);
    expect(find.text('nested.PNG'), findsOneWidget);
    expect(find.text('ignored.txt'), findsNothing);
    expect(find.text('outside.png'), findsNothing);
    await tester.tap(find.text('Импорт'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Открыть папку'));
    await pumpWithRealIo(tester);
    expect(pickerCalls, 2);
    expect(container.read(workspacesProvider).entries.length, 2);
    expect(find.text('root.png'), findsOneWidget);
    expect(find.text('nested.PNG'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('меню остаётся открытым при переводе мыши с кнопки в список', (
    tester,
  ) async {
    final strategy = FocusManager.instance.highlightStrategy;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = strategy);
    final container = await pumpShell(tester);
    final scope = SearchScope.folder(folderPath: folder);
    container.read(organizationSearchSettingsProvider.notifier).setScope(scope);
    await pumpWithRealIo(tester);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(10, 400));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
      tester.getCenter(find.bySemanticsLabel('Область: photos')),
    );
    await tester.pump();
    await mouse.down(
      tester.getCenter(find.bySemanticsLabel('Область: photos')),
    );
    await mouse.up();
    await pumpWithRealIo(tester);
    expect(find.byType(WorkspacesSidebarBlock), findsOneWidget);

    await mouse.moveTo(tester.getCenter(find.text('Рабочие области')));
    await pumpWithRealIo(tester);
    expect(find.byType(WorkspacesSidebarBlock), findsOneWidget);
    await mouse.down(tester.getCenter(find.text('Рабочие области')));
    await mouse.up();
    await pumpWithRealIo(tester);
    expect(find.byType(WorkspacesSidebarBlock), findsOneWidget);
    expect(container.read(organizationSearchSettingsProvider).scope, scope);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await pumpWithRealIo(tester);
    expect(find.byType(WorkspacesSidebarBlock), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('«С подпапками» не закрывает меню и не перекрывает подпись', (
    tester,
  ) async {
    final subfolder = Directory('$folder/sub')..createSync();
    final container = await pumpShell(tester);
    container
        .read(organizationSearchSettingsProvider.notifier)
        .setScope(SearchScope.folder(folderPath: folder));
    await pumpWithRealIo(tester);
    await tester.tap(find.bySemanticsLabel('Область: photos'));
    await pumpWithRealIo(tester);

    await tester.tap(find.byType(Switch));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(WorkspacesSidebarBlock), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(tester.hasRunningAnimations, isTrue);
    await pumpWithRealIo(tester);
    expect(
      container.read(organizationSearchSettingsProvider).scope,
      SearchScope.folder(folderPath: folder, includeSubfolders: true),
    );
    expect(
      tester.getRect(find.text('С подпапками')).right,
      lessThan(tester.getRect(find.byType(Switch)).left),
    );

    await tester.tap(find.text('С подпапками'));
    await pumpWithRealIo(tester);
    expect(find.byType(WorkspacesSidebarBlock), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(
      container.read(organizationSearchSettingsProvider).scope,
      SearchScope.folder(folderPath: folder),
    );
    tester.view.physicalSize = const Size(900, 600);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpWithRealIo(tester);
    expect(
      tester.getRect(find.text('С подпапками')).right,
      lessThan(tester.getRect(find.byType(Switch)).left),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    container
        .read(organizationSearchSettingsProvider.notifier)
        .setScope(SearchScope.folder(folderPath: subfolder.path));
    await pumpWithRealIo(tester);
    await tester.tap(find.bySemanticsLabel('Область: sub'));
    await pumpWithRealIo(tester);
    await tester.tap(find.byType(Switch));
    await pumpWithRealIo(tester);
    expect(find.byType(WorkspacesSidebarBlock), findsOneWidget);
    expect(
      container.read(organizationSearchSettingsProvider).scope,
      SearchScope.folder(folderPath: subfolder.path, includeSubfolders: true),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('«Импорт» не эмитит команды вне вкладки «Файлы»', (tester) async {
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
    expect(
      container.read(workspaceCommandProvider)?.command,
      WorkspaceCommand.openFolder,
    );
  });
}
