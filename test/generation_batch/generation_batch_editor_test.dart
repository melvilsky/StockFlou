import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_flow/core/state/active_grid_selection_provider.dart';
import 'package:stock_flow/core/state/files_provider.dart';
import 'package:stock_flow/core/state/workspaces_provider.dart';
import 'package:stock_flow/features/generation/presentation/generation_screen.dart';
import 'package:stock_flow/features/generation/presentation/widgets/generation_editor_panel.dart';
import 'package:stock_flow/features/generation/presentation/widgets/generation_widgets.dart';
import 'package:stock_flow/features/organization/application/organization_providers.dart';
import 'package:stock_flow/features/organization_search/application/organization_search_providers.dart';
import 'package:stock_flow/models/app_file.dart';

import '../folders_projects_acceptance/grid_search_link_acceptance_test.dart'
    show pumpWithRealIo;
import '../folders_projects_integration/integration_scenario_test.dart'
    show TestFilesNotifier, TestWorkspacesNotifier;
import '../organization_presentation/test_helpers.dart';

/// Поведенческие тесты batch-контракта нижнего редактора:
/// mixed-значения, явная очистка, ключи add/replace, tri-state Editorial,
/// неизменность целей при смене выделения и одиночный клик.
void main() {
  late Directory temp;
  late String folder;
  late List<AppFile> catalog;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final raw = Directory.systemTemp.createTempSync('sf_batch_');
    temp = Directory(raw.resolveSymbolicLinksSync());
    folder = (Directory('${temp.path}/photos')..createSync()).path;
    final png = img.encodePng(img.Image(width: 1, height: 1));
    catalog = [
      AppFile(
        id: 'a',
        path: '$folder/a.png',
        filename: 'a.png',
        metadataTitle: 'Title A',
        metadataDescription: 'Desc A',
        metadataKeywords: 'alpha, beta',
        createdAt: 1,
      ),
      AppFile(
        id: 'b',
        path: '$folder/b.png',
        filename: 'b.png',
        metadataTitle: 'Title B',
        metadataDescription: 'Desc B',
        metadataKeywords: 'gamma',
        createdAt: 2,
      ),
      AppFile(
        id: 'c',
        path: '$folder/c.png',
        filename: 'c.png',
        metadataTitle: 'Title C',
        metadataDescription: 'Desc C',
        metadataKeywords: 'delta',
        createdAt: 3,
      ),
    ];
    for (final file in catalog) {
      File(file.path).writeAsBytesSync(png);
    }
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  Future<ProviderContainer> pumpScreen(
    WidgetTester tester, {
    Future<bool> Function({
      required String filePath,
      required String title,
      required String keywords,
      String? description,
      String? city,
      String? country,
      DateTime? shootDate,
    })?
    writeMetadata,
    List<String>? initialLocalFiles,
  }) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = FakeOrganizationRepository();
    final container = ProviderContainer(
      overrides: [
        filesProvider.overrideWith(() => TestFilesNotifier(List.of(catalog))),
        catalogFilesLoaderProvider.overrideWithValue(() async => catalog),
        workspacesProvider.overrideWith(
          () => TestWorkspacesNotifier([WorkspaceEntry(path: folder)]),
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
            body: GenerationScreen(
              writeMetadata: writeMetadata,
              initialLocalFiles:
                  initialLocalFiles?.map(File.new).toList() ?? const [],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    container
        .read(organizationSearchSettingsProvider.notifier)
        .setScope(SearchScope.folder(folderPath: folder));
    await pumpWithRealIo(tester);
    return container;
  }

  Future<void> selectAll(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(OutlinedButton, 'Выделить всё'));
    await tester.pumpAndSettle();
  }

  Finder titleField() => find
      .descendant(
        of: find.byType(GenerationEditorPanel),
        matching: find.byType(TextField),
      )
      .at(0);

  Finder keywordsField() => find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        (widget.decoration?.hintText ?? '').contains('ключ'),
  );

  Finder applyButton(String label) => find.widgetWithText(FilledButton, label);

  Future<void> applyAndSettle(WidgetTester tester, String label) async {
    await tester.tap(applyButton(label));
    await tester.pump();
    // Запись идёт последовательно по файлам; ждём, пока редактор перестанет
    // показывать «Применение…», вместо фиксированного числа кадров.
    for (var attempt = 0; attempt < 40; attempt++) {
      await pumpWithRealIo(tester);
      if (find.text('Применение…').evaluate().isEmpty && attempt >= 1) break;
    }
  }

  testWidgets('незатронутые поля нескольких файлов не перезаписываются', (
    tester,
  ) async {
    final container = await pumpScreen(tester);
    await selectAll(tester);

    // Разные значения показываются как placeholder, а не как данные.
    expect(find.text('Разные значения'), findsWidgets);
    expect(
      tester.widget<FilledButton>(applyButton('Применить к 3 файлам')).onPressed,
      isNull,
    );

    await tester.enterText(titleField(), 'Общий заголовок');
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(applyButton('Применить к 3 файлам')).onPressed,
      isNotNull,
    );
    await applyAndSettle(tester, 'Применить к 3 файлам');

    final files = container.read(filesProvider).value!;
    for (final id in ['a', 'b', 'c']) {
      final updated = files.singleWhere((file) => file.id == id);
      expect(updated.metadataTitle, 'Общий заголовок');
    }
    expect(
      files.singleWhere((file) => file.id == 'a').metadataDescription,
      'Desc A',
    );
    expect(
      files.singleWhere((file) => file.id == 'b').metadataDescription,
      'Desc B',
    );
    expect(
      files.singleWhere((file) => file.id == 'c').metadataDescription,
      'Desc C',
    );
  });

  testWidgets('явная очистка заголовка очищает его у выбранных файлов', (
    tester,
  ) async {
    final container = await pumpScreen(tester);
    await selectAll(tester);

    // Сначала вводим значение, чтобы получить явную кнопку очистки.
    await tester.enterText(titleField(), 'Временный заголовок');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Очистить у выбранных файлов').first);
    await tester.pumpAndSettle();
    expect(find.text('Значение будет очищено у выбранных файлов'), findsOneWidget);

    await applyAndSettle(tester, 'Применить к 3 файлам');
    final files = container.read(filesProvider).value!;
    for (final id in ['a', 'b', 'c']) {
      expect(files.singleWhere((file) => file.id == id).metadataTitle, isNull);
    }
  });

  testWidgets('ключи по умолчанию добавляются, индивидуальные сохраняются', (
    tester,
  ) async {
    final container = await pumpScreen(tester);
    await selectAll(tester);

    await tester.enterText(keywordsField(), 'shared,');
    await tester.pumpAndSettle();
    await applyAndSettle(tester, 'Применить к 3 файлам');

    final files = container.read(filesProvider).value!;
    expect(
      files.singleWhere((file) => file.id == 'a').metadataKeywords,
      'alpha, beta, shared',
    );
    expect(
      files.singleWhere((file) => file.id == 'b').metadataKeywords,
      'gamma, shared',
    );
  });

  testWidgets('режим «Заменить» заменяет ключи у всех выбранных', (
    tester,
  ) async {
    final container = await pumpScreen(tester);
    await selectAll(tester);

    await tester.tap(find.text('Заменить'));
    await tester.pumpAndSettle();
    await tester.enterText(keywordsField(), 'one, two,');
    await tester.pumpAndSettle();
    await applyAndSettle(tester, 'Применить к 3 файлам');

    final files = container.read(filesProvider).value!;
    for (final id in ['a', 'b', 'c']) {
      expect(
        files.singleWhere((file) => file.id == id).metadataKeywords,
        'one, two',
      );
    }
  });

  testWidgets('Editorial tri-state применяется только по «Применить»', (
    tester,
  ) async {
    final container = await pumpScreen(tester);
    await selectAll(tester);
    expect(
      container.read(filesProvider).value!.any((file) => file.isEditorial),
      isFalse,
    );

    await tester.tap(find.text('Вкл').first);
    await tester.pumpAndSettle();
    // До применения база не меняется.
    expect(
      container.read(filesProvider).value!.any((file) => file.isEditorial),
      isFalse,
    );

    await applyAndSettle(tester, 'Применить к 3 файлам');
    final files = container.read(filesProvider).value!;
    for (final id in ['a', 'b', 'c']) {
      final updated = files.singleWhere((file) => file.id == id);
      expect(updated.isEditorial, isTrue);
      expect(updated.tags, contains(AppTags.editorial));
    }
  });

  testWidgets('смена выделения во время записи не меняет цели', (
    tester,
  ) async {
    final release = Completer<void>();
    final started = <String>[];
    final container = await pumpScreen(
      tester,
      writeMetadata: ({
        required String filePath,
        required String title,
        required String keywords,
        String? description,
        String? city,
        String? country,
        DateTime? shootDate,
      }) async {
        started.add(filePath);
        await release.future;
        return true;
      },
    );
    await selectAll(tester);
    await tester.enterText(titleField(), 'Только для трёх');
    await tester.pumpAndSettle();

    await tester.tap(applyButton('Применить к 3 файлам'));
    await tester.pump();
    expect(started, isNotEmpty);

    // Клик по другой карточке во время записи не должен менять цели.
    await tester.tap(find.text('a.png'));
    await tester.pump();
    expect(
      tester
          .widgetList<GenerationGridCard>(find.byType(GenerationGridCard))
          .where((card) => card.isSelected)
          .length,
      3,
    );

    release.complete();
    for (var attempt = 0; attempt < 3; attempt++) {
      await pumpWithRealIo(tester);
    }

    final files = container.read(filesProvider).value!;
    for (final id in ['a', 'b', 'c']) {
      expect(
        files.singleWhere((file) => file.id == id).metadataTitle,
        'Только для трёх',
      );
    }
  });

  testWidgets('одиночный клик выбирает один файл и не срабатывает дважды', (
    tester,
  ) async {
    final container = await pumpScreen(tester);
    expect(find.text('Выберите файлы для редактирования'), findsOneWidget);

    await tester.tap(find.text('a.png'));
    await tester.pumpAndSettle();
    expect(find.text('1 файл выбран'), findsOneWidget);
    expect(container.read(activeGridSelectionProvider), ['a']);

    await tester.tap(find.text('Снять выделение'));
    await tester.pumpAndSettle();
    expect(find.text('Выберите файлы для редактирования'), findsOneWidget);
  });
}
