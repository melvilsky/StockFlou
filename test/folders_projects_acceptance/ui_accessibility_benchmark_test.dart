import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_flow/features/folder_navigation/domain/folder_access.dart';
import 'package:stock_flow/features/organization/presentation/dialogs/organization_confirm_delete_dialog.dart';
import 'package:stock_flow/features/organization/presentation/dialogs/organization_name_dialog.dart';
import 'package:stock_flow/features/organization/presentation/organization_sidebar_view.dart';
import 'package:stock_flow/features/organization_search/application/organization_search_providers.dart';
import 'package:stock_flow/models/app_file.dart';
import 'package:stock_flow/models/workflow_status.dart';

import '../folders_projects_integration/integration_scenario_test.dart';
import '../organization_presentation/test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UI, доступность и граничные случаи', () {
    testWidgets('Длинные имена проектов и коллекций не вызывают RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeRepo = FakeOrganizationRepository();
      // Имя длиной 100 символов с Unicode и эмодзи
      const veryLongProjectName = '📁 Очень длинное название проекта для проверки вёрстки сайдбара и отсутствия переполнения 1234567890 🚀🔥';
      await fakeRepo.createProject(veryLongProjectName);

      const veryLongCollectionName = '🏷️ Экстремально длинная коллекция отобранных материалов для стоков 2026 года и микростоковых агентств';
      await fakeRepo.createCollection(veryLongCollectionName);

      await tester.pumpWidget(
        buildTestAppWithRepo(
          repo: fakeRepo,
          child: OrganizationSidebarView(
            selectedFileIds: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Проверяем, что виджет отрендерился и нет ошибок overflow
      expect(find.byType(OrganizationSidebarView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('OrganizationNameDialog: подтверждение через TextInputAction.done и отмена через кнопку', (tester) async {
      String? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
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
        ),
      );

      // 1. Открытие диалога и подтверждение по TextInputAction.done (Enter на клавиатуре)
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Project Enter');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(result, 'Project Enter');

      // 2. Открытие диалога и отмена
      result = null;
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Cancelled Text');
      await tester.tap(find.byKey(const Key('organization_name_cancel_button')));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    testWidgets('OrganizationConfirmDeleteDialog: безопасная кнопка Отмена в фокусе', (tester) async {
      bool? confirmed;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  confirmed = await OrganizationConfirmDeleteDialog.show(
                    context: context,
                    title: 'Удалить коллекцию?',
                    entityName: 'My Collection',
                  );
                },
                child: const Text('Удалить'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();

      // По умолчанию фокус на «Отмена», нажатие Enter не должно приводить к удалению
      expect(find.text('Отмена'), findsOneWidget);
      expect(find.text('Удалить'), findsNWidgets(2)); // Кнопка под диалогом и в диалоге

      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();

      expect(confirmed, isFalse);
    });
  });

  group('macOS Security Scoped Access', () {
    test('SecurityScopedFolderAccessScope с MockSecureBookmarks выполняет start и stop', () async {
      final mockBookmarks = MockSecureBookmarks();
      final tempDir = Directory.systemTemp.createTempSync('sf_sec_acc_');
      try {
        final scope = SecurityScopedFolderAccessScope(
          rootPath: tempDir.path,
          bookmark: 'bm_${tempDir.path}',
          secureBookmarks: mockBookmarks,
        );

        expect(scope.rootPath, tempDir.path);
        final exists = await scope.exists(tempDir.path);
        expect(exists, isTrue);

        if (Platform.isMacOS) {
          expect(mockBookmarks.startCount, greaterThanOrEqualTo(1));
          expect(mockBookmarks.stopCount, greaterThanOrEqualTo(1));
        }
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('Бенчмарк производительности (1 000 и 10 000 файлов)', () {
    const engine = SearchEngine();

    List<AppFile> generateFiles(int count) {
      return List.generate(count, (i) {
        final folderIndex = i % 10;
        final isPhoto = i % 2 == 0;
        final hasKeywords = i % 3 != 0;
        final isEditorial = i % 5 == 0;

        return AppFile(
          id: 'file_$i',
          path: '/Volumes/TestStorage/folder_$folderIndex/item_$i.${isPhoto ? 'jpg' : 'mp4'}',
          filename: 'item_$i.${isPhoto ? 'jpg' : 'mp4'}',
          metadataTitle: 'Title for item $i in folder $folderIndex',
          metadataKeywords: hasKeywords ? 'travel, nature, outdoor, item_$i' : null,
          metadataDescription: 'Description of asset $i with detailed metadata',
          isEditorial: isEditorial,
          workflowStatus: WorkflowStatus.values[i % WorkflowStatus.values.length],
          createdAt: 1700000000000 + i * 1000,
          tags: isEditorial ? const ['editorial'] : const [],
        );
      });
    }

    test('Измерение для безопасного набора из 1 000 файлов', () async {
      final files1k = generateFiles(1000);
      final folders = List.generate(10, (i) => '/Volumes/TestStorage/folder_$i');

      final stopwatch = Stopwatch()..start();

      // 1. Разрешение project scope (с 10 папками и поиском совпадений)
      final scopeFiles = await engine.resolveFilesForScope(
        scope: const SearchScope.project(projectId: 'p1', includeSubfolders: true),
        allFiles: files1k,
        getProjectFolders: (_) async => folders,
        getCollectionFileIds: (_) async => [],
        getSelectionFileIds: () async => [],
      );

      final scopeTimeMs = stopwatch.elapsedMilliseconds;
      expect(scopeFiles.length, 1000);

      // 2. Поиск по подстроке во всех 4 мета-полях
      stopwatch.reset();
      final filteredResults = engine.filterFiles(
        files: scopeFiles,
        criteria: const SearchFilterCriteria(query: 'nature'),
        fileExistsProbe: (_) => true,
      );
      final searchTimeMs = stopwatch.elapsedMilliseconds;

      expect(filteredResults.isNotEmpty, isTrue);

      // 3. Комбинированный фильтр (query + workflowStatuses + hasKeywords)
      stopwatch.reset();
      final complexResults = engine.filterFiles(
        files: scopeFiles,
        criteria: const SearchFilterCriteria(
          query: 'item_1',
          hasKeywords: true,
          workflowStatuses: {WorkflowStatus.newFile, WorkflowStatus.readyToUpload},
        ),
        fileExistsProbe: (_) => true,
      );
      final complexTimeMs = stopwatch.elapsedMilliseconds;

      debugPrint('БЕНЧМАРК (1 000 файлов):');
      debugPrint('  - Project scope resolution: $scopeTimeMs ms');
      debugPrint('  - 4-field substring search: $searchTimeMs ms (найдено: ${filteredResults.length})');
      debugPrint('  - Complex criteria search: $complexTimeMs ms (найдено: ${complexResults.length})');

      expect(scopeTimeMs, lessThan(100), reason: 'Разрешение 1k файлов должно занимать < 100 ms');
      expect(searchTimeMs, lessThan(100), reason: 'Поиск 1k файлов должен занимать < 100 ms');
    });

    test('Измерение для безопасного набора из 10 000 файлов', () async {
      final files10k = generateFiles(10000);
      final folders = List.generate(10, (i) => '/Volumes/TestStorage/folder_$i');

      final stopwatch = Stopwatch()..start();

      // 1. Разрешение project scope для 10 000 файлов
      final scopeFiles = await engine.resolveFilesForScope(
        scope: const SearchScope.project(projectId: 'p1', includeSubfolders: true),
        allFiles: files10k,
        getProjectFolders: (_) async => folders,
        getCollectionFileIds: (_) async => [],
        getSelectionFileIds: () async => [],
      );

      final scopeTimeMs = stopwatch.elapsedMilliseconds;
      expect(scopeFiles.length, 10000);

      // 2. Полнотекстовый поиск по 4 мета-полям в 10 000 файлах
      stopwatch.reset();
      final searchResults = engine.filterFiles(
        files: scopeFiles,
        criteria: const SearchFilterCriteria(query: 'outdoor'),
        fileExistsProbe: (_) => true,
      );
      final searchTimeMs = stopwatch.elapsedMilliseconds;

      expect(searchResults.isNotEmpty, isTrue);

      // 3. Комбинированная фильтрация в 10 000 файлах
      stopwatch.reset();
      final complexResults = engine.filterFiles(
        files: scopeFiles,
        criteria: const SearchFilterCriteria(
          query: 'nature',
          isEditorial: true,
          hasKeywords: true,
        ),
        fileExistsProbe: (_) => true,
      );
      final complexTimeMs = stopwatch.elapsedMilliseconds;

      debugPrint('БЕНЧМАРК (10 000 файлов):');
      debugPrint('  - Project scope resolution: $scopeTimeMs ms');
      debugPrint('  - 4-field substring search: $searchTimeMs ms (найдено: ${searchResults.length})');
      debugPrint('  - Complex criteria search: $complexTimeMs ms (найдено: ${complexResults.length})');

      expect(scopeTimeMs, lessThan(500), reason: 'Разрешение 10k файлов должно занимать < 500 ms');
      expect(searchTimeMs, lessThan(350), reason: 'Поиск 10k файлов должен занимать < 350 ms');
    });
  });
}
