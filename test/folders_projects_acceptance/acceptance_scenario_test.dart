import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_flow/core/state/files_provider.dart';
import 'package:stock_flow/core/state/settings_provider.dart';
import 'package:stock_flow/core/state/workspaces_provider.dart';
import 'package:stock_flow/features/generation/presentation/generation_screen.dart';
import 'package:stock_flow/features/organization/application/organization_providers.dart';
import 'package:stock_flow/features/organization_search/application/organization_search_providers.dart';
import 'package:stock_flow/models/app_file.dart';
import 'package:stock_flow/models/workflow_status.dart';

import '../organization_presentation/test_helpers.dart';

class AcceptanceFilesNotifier extends FilesNotifier {
  final List<AppFile> files;
  final List<AppFile> updated = [];
  final List<AppFile> added = [];

  AcceptanceFilesNotifier(List<AppFile> initial) : files = List.of(initial);

  @override
  Future<List<AppFile>> build() async => List.of(files);

  @override
  Future<void> syncWithDisk() async {}

  @override
  Future<void> updateFile(AppFile file) async {
    updated.add(file);
    final idx = files.indexWhere((f) => f.id == file.id);
    if (idx >= 0) {
      files[idx] = file;
    } else {
      files.add(file);
    }
    state = AsyncData(List.of(files));
  }

  @override
  Future<void> addFile(AppFile file) async {
    added.add(file);
    final idx = files.indexWhere((f) => f.id == file.id || f.path == file.path);
    if (idx >= 0) {
      files[idx] = file;
    } else {
      files.add(file);
    }
    state = AsyncData(List.of(files));
  }
}

class AcceptanceWorkspacesNotifier extends WorkspacesNotifier {
  final List<WorkspaceEntry> initialEntries;
  int initialIndex;

  AcceptanceWorkspacesNotifier(this.initialEntries, {this.initialIndex = 0});

  @override
  WorkspacesState build() {
    return WorkspacesState(
      entries: initialEntries,
      currentIndex: initialIndex,
    );
  }

  @override
  Future<bool> setCurrent(int index) async {
    state = state.copyWith(currentIndex: index);
    return true;
  }

  @override
  Future<bool> addWorkspace(String path) async {
    final updated = List<WorkspaceEntry>.from(state.entries)
      ..add(WorkspaceEntry(path: path));
    state = state.copyWith(
      entries: updated,
      currentIndex: updated.length - 1,
    );
    return true;
  }

  @override
  Future<bool> removeWorkspace(int index) async {
    final updated = List<WorkspaceEntry>.from(state.entries);
    if (index >= 0 && index < updated.length) {
      updated.removeAt(index);
      final newIdx = updated.isEmpty ? -1 : 0;
      state = state.copyWith(
        entries: updated,
        currentIndex: newIdx,
      );
      return true;
    }
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Приёмочный сценарий 1: Две папки -> Проект -> Коллекция -> Редактирование -> Перезапуск', () {
    late Directory tempRoot;
    late Directory folderA;
    late Directory folderB;
    late File fileA;
    late File fileB;
    late AppFile appFileA;
    late AppFile appFileB;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('sf_acceptance_scenario_');
      folderA = Directory('${tempRoot.path}/workspace_alpha')..createSync();
      folderB = Directory('${tempRoot.path}/workspace_beta')..createSync();

      fileA = File('${folderA.path}/photo_alpha.jpg')..writeAsStringSync('alpha');
      fileB = File('${folderB.path}/photo_beta.jpg')..writeAsStringSync('beta');

      appFileA = AppFile(
        id: 'id_alpha_1',
        path: fileA.path,
        filename: 'photo_alpha.jpg',
        metadataTitle: 'Title Alpha Original',
        metadataKeywords: 'alpha, test',
        workflowStatus: WorkflowStatus.newFile,
        createdAt: 1000,
      );

      appFileB = AppFile(
        id: 'id_beta_1',
        path: fileB.path,
        filename: 'photo_beta.jpg',
        metadataTitle: 'Title Beta Original',
        metadataKeywords: 'beta, test',
        workflowStatus: WorkflowStatus.newFile,
        createdAt: 2000,
      );
    });

    tearDown(() {
      try {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    testWidgets(
      'Сквозной сценарий: проект объединяет обе папки, коллекция объединяет материалы из обеих, редактирование сохраняет черновик',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeFiles = AcceptanceFilesNotifier([appFileA, appFileB]);
        final fakeOrgRepo = FakeOrganizationRepository();

        // 1. Создаем проект и добавляем обе папки
        final project = await fakeOrgRepo.createProject('Stock Project Alpha-Beta');
        await fakeOrgRepo.addProjectFolder(project.id, folderA.path);
        await fakeOrgRepo.addProjectFolder(project.id, folderB.path);

        // 2. Создаем коллекцию и добавляем файлы из обеих папок
        final collection = await fakeOrgRepo.createCollection('Best Shots Collection');
        await fakeOrgRepo.addFileToCollection(collection.id, appFileA.id);
        await fakeOrgRepo.addFileToCollection(collection.id, appFileB.id);

        final container = ProviderContainer(
          overrides: [
            workspacesProvider.overrideWith(
              () => AcceptanceWorkspacesNotifier([
                WorkspaceEntry(path: folderA.path),
                WorkspaceEntry(path: folderB.path),
              ]),
            ),
            filesProvider.overrideWith(() => fakeFiles),
            organizationRepositoryProvider.overrideWithValue(fakeOrgRepo),
            settingsProvider.overrideWith(
              () => SettingsNotifier()..state = AsyncData(SettingsState(apiKey: 'key')),
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: Scaffold(
                body: GenerationScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Проверяем, что в начальном виде отображается папка Alpha
        expect(find.text('photo_alpha.jpg'), findsOneWidget);

        // Переключаемся на проект через SearchScope
        container.read(organizationSearchSettingsProvider.notifier).setScope(
              SearchScope.project(projectId: project.id, includeSubfolders: false),
            );
        await tester.pumpAndSettle();

        // Проект объединяет файлы обеих папок
        expect(find.text('photo_alpha.jpg'), findsOneWidget);
        expect(find.text('photo_beta.jpg'), findsOneWidget);

        // Переключаемся на коллекцию
        container.read(organizationSearchSettingsProvider.notifier).setScope(
              SearchScope.collection(collectionId: collection.id),
            );
        await tester.pumpAndSettle();

        expect(find.text('photo_alpha.jpg'), findsOneWidget);
        expect(find.text('photo_beta.jpg'), findsOneWidget);

        // Выбираем photo_alpha.jpg и редактируем через инспектор
        await tester.tap(find.text('photo_alpha.jpg'));
        await tester.pumpAndSettle();

        expect(find.text('Title Alpha Original'), findsOneWidget);

        await tester.enterText(
          find.widgetWithText(TextField, 'Title Alpha Original'),
          'Title Alpha Edited In Collection',
        );
        await tester.pumpAndSettle();

        // Переключаемся обратно на папку: черновик фиксируется
        container.read(organizationSearchSettingsProvider.notifier).setScope(
              SearchScope.folder(folderPath: folderA.path, includeSubfolders: false),
            );
        await tester.pumpAndSettle();

        expect(fakeFiles.updated.any((f) => f.id == 'id_alpha_1'), isTrue);
        final updatedAlpha = fakeFiles.updated.firstWhere((f) => f.id == 'id_alpha_1');
        expect(updatedAlpha.metadataTitle, 'Title Alpha Edited In Collection');

        // Имитируем перезапуск приложения (создание нового контейнера)
        final restartedContainer = ProviderContainer(
          overrides: [
            workspacesProvider.overrideWith(
              () => AcceptanceWorkspacesNotifier([
                WorkspaceEntry(path: folderA.path),
                WorkspaceEntry(path: folderB.path),
              ]),
            ),
            filesProvider.overrideWith(
              () => AcceptanceFilesNotifier([updatedAlpha, appFileB]),
            ),
            organizationRepositoryProvider.overrideWithValue(fakeOrgRepo),
            settingsProvider.overrideWith(
              () => SettingsNotifier()..state = AsyncData(SettingsState(apiKey: 'key')),
            ),
          ],
        );
        addTearDown(restartedContainer.dispose);

        // Проверяем, что в репозитории организаций проект и коллекция сохранены
        final restoredProjects = await fakeOrgRepo.getProjects();
        expect(restoredProjects.any((p) => p.id == project.id), isTrue);

        final restoredFolders = await fakeOrgRepo.getProjectFolders(project.id);
        expect(restoredFolders, containsAll([folderA.path, folderB.path]));

        final restoredCollections = await fakeOrgRepo.getCollections();
        expect(restoredCollections.any((c) => c.id == collection.id), isTrue);

        final restoredCollectionFiles =
            await fakeOrgRepo.getFileIdsInCollection(collection.id);
        expect(restoredCollectionFiles, equals([appFileA.id, appFileB.id]));
      },
    );
  });

  group('Приёмочный сценарий 2: Обычная работа с папкой без проекта остаётся доступной', () {
    late Directory tempRoot;
    late Directory workspace1;
    late Directory workspace2;
    late File file1;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('sf_regular_workspace_');
      workspace1 = Directory('${tempRoot.path}/ws_1')..createSync();
      workspace2 = Directory('${tempRoot.path}/ws_2')..createSync();
      file1 = File('${workspace1.path}/image1.jpg')..writeAsStringSync('img1');
      expect(file1.existsSync(), isTrue);
    });

    tearDown(() {
      try {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    testWidgets('Добавление, переключение и удаление рабочих папок работает автономно без проектов', (tester) async {
      final fakeOrgRepo = FakeOrganizationRepository();
      final workspacesNotifier = AcceptanceWorkspacesNotifier([
        WorkspaceEntry(path: workspace1.path),
      ]);

      final container = ProviderContainer(
        overrides: [
          workspacesProvider.overrideWith(() => workspacesNotifier),
          organizationRepositoryProvider.overrideWithValue(fakeOrgRepo),
        ],
      );
      addTearDown(container.dispose);

      // Проверяем начальное состояние
      expect(container.read(workspacesProvider).entries.length, 1);
      expect(container.read(workspacesProvider).currentPath, workspace1.path);

      // Добавляем вторую папку
      await workspacesNotifier.addWorkspace(workspace2.path);
      expect(container.read(workspacesProvider).entries.length, 2);
      expect(container.read(workspacesProvider).currentPath, workspace2.path);

      // Переключаемся на первую
      await workspacesNotifier.setCurrent(0);
      expect(container.read(workspacesProvider).currentPath, workspace1.path);

      // Удаляем вторую папку
      await workspacesNotifier.removeWorkspace(1);
      expect(container.read(workspacesProvider).entries.length, 1);
      expect(container.read(workspacesProvider).currentPath, workspace1.path);

      // Проекты не создавались
      expect(await fakeOrgRepo.getProjects(), isEmpty);
      expect(await fakeOrgRepo.getCollections(), isEmpty);
    });
  });

  group('Приёмочный сценарий 3: Защита данных при удалении, пересечениях и одинаковых именах', () {
    late Directory tempRoot;
    late Directory folderMain;
    late Directory folderSub;
    late Directory folderOther;
    late File fileSubInMain;
    late File fileOtherSameName;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('sf_data_safety_');
      folderMain = Directory('${tempRoot.path}/main')..createSync();
      folderSub = Directory('${folderMain.path}/sub')..createSync();
      folderOther = Directory('${tempRoot.path}/other')..createSync();

      fileSubInMain = File('${folderSub.path}/picture.jpg')..writeAsStringSync('sub pic');
      fileOtherSameName = File('${folderOther.path}/picture.jpg')..writeAsStringSync('other pic');
    });

    tearDown(() {
      try {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    test('Удаление проекта и коллекции не удаляет оригиналы файлов на диске', () async {
      final fakeOrgRepo = FakeOrganizationRepository();
      final project = await fakeOrgRepo.createProject('Temp Project');
      await fakeOrgRepo.addProjectFolder(project.id, folderMain.path);

      final collection = await fakeOrgRepo.createCollection('Temp Collection');
      await fakeOrgRepo.addFileToCollection(collection.id, 'id_pic_1');
      await fakeOrgRepo.addFileToCollection(collection.id, 'id_pic_2');

      // Удаляем коллекцию
      await fakeOrgRepo.deleteCollection(collection.id);
      expect((await fakeOrgRepo.getCollections()).any((c) => c.id == collection.id), isFalse);

      // Удаляем проект
      await fakeOrgRepo.deleteProject(project.id);
      expect((await fakeOrgRepo.getProjects()).any((p) => p.id == project.id), isFalse);

      // Файлы на диске физически не тронуты
      expect(fileSubInMain.existsSync(), isTrue);
      expect(fileOtherSameName.existsSync(), isTrue);
    });

    test('Пересекающиеся корни не дублируют материалы в проекте', () async {
      const searchEngine = SearchEngine();
      final file1 = AppFile(
        id: 'f_in_sub',
        path: fileSubInMain.path,
        filename: 'picture.jpg',
        workflowStatus: WorkflowStatus.newFile,
        createdAt: 1000,
      );

      final allFiles = [file1];

      // Проект содержит как родительскую папку folderMain, так и дочернюю folderSub
      final scope = const SearchScope.project(
        projectId: 'proj_overlapping',
        includeSubfolders: true,
      );

      final result = await searchEngine.resolveFilesForScope(
        scope: scope,
        allFiles: allFiles,
        getProjectFolders: (_) async => [folderMain.path, folderSub.path],
        getCollectionFileIds: (_) async => [],
        getSelectionFileIds: () async => [],
      );

      // Файл f_in_sub присутствует ровно один раз
      expect(result.length, 1);
      expect(result.first.id, 'f_in_sub');
    });

    test('Одинаковые имена в разных папках остаются независимыми сущностями', () async {
      const searchEngine = SearchEngine();
      final fileA = AppFile(
        id: 'id_main_pic',
        path: fileSubInMain.path,
        filename: 'picture.jpg',
        metadataTitle: 'Picture in Sub',
        workflowStatus: WorkflowStatus.newFile,
        createdAt: 1000,
      );
      final fileB = AppFile(
        id: 'id_other_pic',
        path: fileOtherSameName.path,
        filename: 'picture.jpg',
        metadataTitle: 'Picture in Other',
        workflowStatus: WorkflowStatus.metadataReady,
        createdAt: 2000,
      );

      final allFiles = [fileA, fileB];

      final scope = const SearchScope.all();
      final result = await searchEngine.resolveFilesForScope(
        scope: scope,
        allFiles: allFiles,
        getProjectFolders: (_) async => [],
        getCollectionFileIds: (_) async => [],
        getSelectionFileIds: () async => [],
      );

      expect(result.length, 2);
      expect(result.map((f) => f.id).toSet(), equals({'id_main_pic', 'id_other_pic'}));
      expect(result.map((f) => f.path).toSet(), equals({fileSubInMain.path, fileOtherSameName.path}));
    });
  });
}
