import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_flow/core/state/active_grid_selection_provider.dart';
import 'package:stock_flow/core/state/files_provider.dart';
import 'package:stock_flow/core/state/workspaces_provider.dart';
import 'package:stock_flow/features/generation/presentation/generation_screen.dart';
import 'package:stock_flow/core/theme/app_theme.dart';
import 'package:stock_flow/features/generation/presentation/widgets/generation_editor_panel.dart';
import 'package:stock_flow/features/generation/presentation/widgets/generation_scope_bar.dart';
import 'package:stock_flow/features/generation/presentation/widgets/generation_widgets.dart';
import 'package:stock_flow/features/organization/application/organization_providers.dart';
import 'package:stock_flow/features/organization_search/application/organization_search_providers.dart';
import 'package:stock_flow/models/app_file.dart';

import '../folders_projects_acceptance/grid_search_link_acceptance_test.dart'
    show pumpWithRealIo;
import '../folders_projects_integration/integration_scenario_test.dart'
    show TestFilesNotifier, TestWorkspacesNotifier;
import '../organization_presentation/test_helpers.dart';

void testMacWidgets(String description, WidgetTesterCallback callback) {
  testWidgets(
    description,
    callback,
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}

void main() {
  late Directory temp;
  late String folderA;
  late String folderB;
  late List<AppFile> catalog;
  late String localPath;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final rawTemp = Directory.systemTemp.createTempSync('sf_selection_');
    temp = Directory(rawTemp.resolveSymbolicLinksSync());
    folderA = (Directory('${temp.path}/a')..createSync()).path;
    folderB = (Directory('${temp.path}/b')..createSync()).path;
    Directory('$folderA/nested').createSync();
    final png = img.encodePng(img.Image(width: 1, height: 1));
    catalog = [
      for (final (id, path) in [
        ('a1', '$folderA/one.png'),
        ('a2', '$folderA/two.png'),
        ('nested', '$folderA/nested/deep.png'),
        ('b', '$folderB/three.png'),
        ('offline', '${temp.path}/offline/missing.png'),
      ])
        AppFile(
          id: id,
          path: path,
          filename: path.split('/').last,
          createdAt: 1,
          metadataTitle: ['a1', 'a2', 'b'].contains(id) ? 'match $id' : null,
        ),
    ];
    for (final f in catalog.where((f) => f.id != 'offline')) {
      File(f.path).writeAsBytesSync(png);
    }
    localPath = '$folderB/local.png';
    File(localPath).writeAsBytesSync(png);
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  Future<ProviderContainer> pumpScreen(
    WidgetTester tester,
    SearchScope scope,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = FakeOrganizationRepository();
    repo.projectFolders['project'] = [folderA, folderB];
    repo.collectionFiles['collection'] = ['b', 'offline'];
    repo.selectionFiles.addAll(['a2', 'b']);
    final container = ProviderContainer(
      overrides: [
        filesProvider.overrideWith(
          () => TestFilesNotifier(
            catalog.where((f) => f.id != 'offline').toList(),
          ),
        ),
        catalogFilesLoaderProvider.overrideWithValue(() async => catalog),
        workspacesProvider.overrideWith(
          () => TestWorkspacesNotifier([WorkspaceEntry(path: folderA)]),
        ),
        organizationRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: GenerationScreen(initialLocalFiles: [File(localPath)]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    container.read(organizationSearchSettingsProvider.notifier).setScope(scope);
    await pumpWithRealIo(tester);
    return container;
  }

  Set<String> selectedPaths(WidgetTester tester) => {
    for (final card in tester.widgetList<GenerationGridCard>(
      find.byType(GenerationGridCard),
    ))
      if (card.isSelected) card.imagePath,
  };

  Future<void> selectAllShortcut(
    WidgetTester tester,
    LogicalKeyboardKey modifier,
  ) async {
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(modifier);
    await tester.pumpAndSettle();
  }

  for (final modifier in [
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.controlLeft,
  ]) {
    testMacWidgets(
      '${modifier.keyLabel}+A selects the displayed folder and repeats safely',
      (tester) async {
        await pumpScreen(tester, SearchScope.folder(folderPath: folderB));
        final expected = {catalog[3].path, localPath};
        await selectAllShortcut(tester, modifier);
        expect(selectedPaths(tester), expected);
        await selectAllShortcut(tester, modifier);
        expect(selectedPaths(tester), expected);
      },
    );
  }

  for (final scopeName in ['all', 'project', 'collection', 'selection']) {
    testMacWidgets(
      'button and shortcut select the same visible files in $scopeName',
      (tester) async {
        final scope = switch (scopeName) {
          'project' => const SearchScope.project(projectId: 'project'),
          'collection' => const SearchScope.collection(
            collectionId: 'collection',
          ),
          'selection' => const SearchScope.selection(),
          _ => const SearchScope.all(),
        };
        final container = await pumpScreen(tester, scope);
        final visible =
            tester
                .widgetList<GenerationGridCard>(find.byType(GenerationGridCard))
                .map((card) => card.imagePath)
                .toSet();
        expect(visible, isNotEmpty);
        if (scopeName == 'project') expect(visible, contains(localPath));
        if (scopeName == 'collection') {
          expect(visible, contains(catalog.last.path));
        }

        await tester.tap(find.widgetWithText(OutlinedButton, 'Выделить всё'));
        await tester.pumpAndSettle();
        expect(selectedPaths(tester), visible);
        expect(
          container.read(activeGridSelectionProvider).toSet(),
          catalog
              .where((f) => visible.contains(f.path))
              .map((f) => f.id)
              .toSet(),
        );
        await tester.tap(find.text('Снять выделение'));
        await tester.pumpAndSettle();
        expect(selectedPaths(tester), isEmpty);
        await selectAllShortcut(tester, LogicalKeyboardKey.metaLeft);
        expect(selectedPaths(tester), visible);
      },
    );
  }

  testMacWidgets(
    'select all then Editorial is staged and applied to the selected files',
    (tester) async {
      final container = await pumpScreen(
        tester,
        SearchScope.folder(folderPath: folderA),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Выделить всё'));
      await tester.pumpAndSettle();
      expect(selectedPaths(tester), {catalog[0].path, catalog[1].path});

      // Batch Editorial — tri-state, применяется только по «Применить».
      await tester.ensureVisible(find.text('Вкл').first);
      await tester.tap(find.text('Вкл').first);
      await tester.pumpAndSettle();
      expect(
        container
            .read(filesProvider)
            .value!
            .where((f) => ['a1', 'a2'].contains(f.id))
            .every((f) => f.isEditorial),
        isFalse,
      );

      await tester.ensureVisible(find.text('Применить к 2 файлам'));
      await tester.tap(find.text('Применить к 2 файлам'));
      for (var attempt = 0; attempt < 20; attempt++) {
        await pumpWithRealIo(tester);
        final updated = container.read(filesProvider).value!;
        if (updated
            .where((f) => ['a1', 'a2'].contains(f.id))
            .every((f) => f.isEditorial)) {
          break;
        }
      }

      final files = container.read(filesProvider).value!;
      for (final id in ['a1', 'a2']) {
        final updated = files.singleWhere((f) => f.id == id);
        expect(updated.isEditorial, isTrue);
        expect(updated.tags, contains(AppTags.editorial));
        expect(
          updated.metadataTitle,
          catalog.firstWhere((f) => f.id == id).metadataTitle,
        );
      }
      expect(files.singleWhere((f) => f.id == 'b').isEditorial, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testMacWidgets(
    'filters exclude hidden selections and repeated selection stays selected',
    (tester) async {
      final container = await pumpScreen(tester, const SearchScope.all());
      await selectAllShortcut(tester, LogicalKeyboardKey.controlLeft);
      container
          .read(organizationSearchSettingsProvider.notifier)
          .setQuery('match');
      await tester.pumpAndSettle();
      await selectAllShortcut(tester, LogicalKeyboardKey.controlLeft);
      expect(selectedPaths(tester), {
        catalog[0].path,
        catalog[1].path,
        catalog[3].path,
      });
      await tester.tap(find.widgetWithText(OutlinedButton, 'Выделить всё'));
      await tester.pumpAndSettle();
      expect(selectedPaths(tester), {
        catalog[0].path,
        catalog[1].path,
        catalog[3].path,
      });
    },
  );

  testMacWidgets('Cmd+A edits text until a grid click restores grid focus', (
    tester,
  ) async {
    await pumpScreen(tester, const SearchScope.all());
    await tester.tap(find.byType(GenerationGridCard).first);
    await tester.pumpAndSettle();
    expect(selectedPaths(tester), hasLength(1));

    final titleField = find.descendant(
      of: find.byType(GenerationEditorPanel),
      matching: find.byType(TextField),
    ).first;
    await tester.enterText(titleField, 'match');
    await tester.pumpAndSettle();
    await selectAllShortcut(tester, LogicalKeyboardKey.metaLeft);
    final controller = tester.widget<TextField>(titleField).controller!;
    expect(
      controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 5),
    );
    expect(selectedPaths(tester), hasLength(1));

    await tester.tap(find.byType(GenerationGridCard).first);
    await tester.pumpAndSettle();
    await selectAllShortcut(tester, LogicalKeyboardKey.metaLeft);
    expect(selectedPaths(tester), hasLength(6));
  });

  testMacWidgets('select all stays visible and disabled for an empty result', (
    tester,
  ) async {
    final container = await pumpScreen(tester, const SearchScope.all());
    container
        .read(organizationSearchSettingsProvider.notifier)
        .setQuery('no matches');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Выделить всё'),
          )
          .onPressed,
      isNull,
    );
    await selectAllShortcut(tester, LogicalKeyboardKey.metaLeft);
    expect(selectedPaths(tester), isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testMacWidgets('workspace at 900x600 keeps actions reachable ($brightness)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            filesProvider.overrideWith(() => TestFilesNotifier([])),
            workspacesProvider.overrideWith(() => TestWorkspacesNotifier([])),
          ],
          child: MaterialApp(
            theme:
                brightness == Brightness.dark
                    ? AppTheme.darkTheme
                    : AppTheme.lightTheme,
            home: const Scaffold(body: GenerationScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GenerationScopeBar), findsOneWidget);
      expect(find.text('Выберите файлы для редактирования'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
