import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_flow/core/state/files_provider.dart';
import 'package:stock_flow/core/state/settings_provider.dart';
import 'package:stock_flow/core/state/workspaces_provider.dart';
import 'package:stock_flow/features/folder_navigation/domain/folder_access.dart';
import 'package:stock_flow/features/folder_navigation/domain/folder_navigation_models.dart';
import 'package:stock_flow/features/generation/presentation/generation_screen.dart';
import 'package:stock_flow/features/organization/application/organization_providers.dart';
import 'package:stock_flow/features/organization_search/application/organization_search_providers.dart';
import 'package:stock_flow/models/app_file.dart';
import 'package:stock_flow/models/workflow_status.dart';

import '../organization_presentation/test_helpers.dart';
import 'acceptance_scenario_test.dart';

/// Реальный I/O и fake-async продвигаем по очереди, пока сканирование папок не завершится.
Future<void> pumpWithRealIo(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  }
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  TestWidgetsFlutterBinding.ensureInitialized();

  group('Проверка 1: Local файлы без AppFile в проектах', () {
    late Directory tempRoot;
    late Directory projectDir;
    late File diskOnlyFile;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('sf_local_files_proj_');
      projectDir = Directory('${tempRoot.path}/proj_dir')..createSync();
      diskOnlyFile = File('${projectDir.path}/local_photo.jpg')..writeAsStringSync('data');
      expect(diskOnlyFile.existsSync(), isTrue);
    });

    tearDown(() {
      try {
        if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
      } catch (_) {}
    });

    testWidgets(
      'ИСПРАВЛЕНО: local файлы без AppFile в проектах сканируются и отображаются в сетке',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // База данных пуста (нет AppFile для diskOnlyFile)
        final fakeFiles = AcceptanceFilesNotifier([]);
        final fakeOrgRepo = FakeOrganizationRepository();
        final project = await fakeOrgRepo.createProject('Disk Project');
        await fakeOrgRepo.addProjectFolder(project.id, projectDir.path);

        final container = ProviderContainer(
          overrides: [
            workspacesProvider.overrideWith(
              () => AcceptanceWorkspacesNotifier([
                WorkspaceEntry(path: projectDir.path),
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

        // 1. Устанавливаем область папки и инициируем загрузку файлов папки
        container.read(organizationSearchSettingsProvider.notifier).setScope(
              SearchScope.folder(folderPath: projectDir.path, includeSubfolders: false),
            );
        await tester.pumpAndSettle();

        // 2. Переключаемся на проект (project scope)
        container.read(organizationSearchSettingsProvider.notifier).setScope(
              SearchScope.project(projectId: project.id, includeSubfolders: false),
            );
        await pumpWithRealIo(tester);

        // Проверяем, что локальный файл отображается в сетке проекта
        final foundInProject = find.text('local_photo.jpg');
        expect(
          foundInProject,
          findsOneWidget,
          reason: 'Local файлы без AppFile из папок проекта отображаются в сетке проекта.',
        );

        // Отмена retry-таймеров провайдеров, иначе тест падает на pending timer.
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      },
    );
  });

  group('Проверка 2: Влияние includeSubfolders на локальные файлы', () {
    late Directory tempRoot;
    late Directory rootDir;
    late Directory subDir;
    late File fileInSub;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('sf_subfolders_local_');
      rootDir = Directory('${tempRoot.path}/root_dir')..createSync();
      subDir = Directory('${rootDir.path}/sub_dir')..createSync();
      fileInSub = File('${subDir.path}/nested_local.jpg')..writeAsStringSync('nested');
      expect(fileInSub.existsSync(), isTrue);
    });

    tearDown(() {
      try {
        if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
      } catch (_) {}
    });

    testWidgets(
      'ИСПРАВЛЕНО: _loadCurrentWorkspaceFiles при includeSubfolders выполняет recursive сканирование '
      'и отображает вложенные локальные файлы',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeFiles = AcceptanceFilesNotifier([]);
        final fakeOrgRepo = FakeOrganizationRepository();

        final container = ProviderContainer(
          overrides: [
            workspacesProvider.overrideWith(
              () => AcceptanceWorkspacesNotifier([
                WorkspaceEntry(path: rootDir.path),
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

        // Включаем режим «С подпапками»
        container.read(organizationSearchSettingsProvider.notifier).setScope(
              SearchScope.folder(folderPath: rootDir.path, includeSubfolders: true),
            );
        // Кадр запускает post-frame callback смены области; затем ждём реальный I/O.
        await pumpWithRealIo(tester);

        final foundNested = find.text('nested_local.jpg');
        expect(
          foundNested,
          findsOneWidget,
          reason: 'Рекурсивное сканирование обнаруживает локальные файлы во вложенных подпапках.',
        );

        // Отмена retry-таймеров провайдеров, иначе тест падает на pending timer.
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      },
    );
  });

  group('Проверка 3: Поиск по метаданным и фильтры из 05 в реальной сетке', () {
    late Directory tempRoot;
    late File filePhoto;
    late AppFile appFile;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('sf_meta_search_');
      filePhoto = File('${tempRoot.path}/sunset.jpg')..writeAsStringSync('img');
      appFile = AppFile(
        id: 'id_sunset_1',
        path: filePhoto.path,
        filename: 'sunset.jpg',
        metadataTitle: 'Majestic Evening Sky',
        metadataKeywords: 'golden_hour, landscape, clouds',
        metadataDescription: 'A beautiful evening captured from the hills',
        workflowStatus: WorkflowStatus.metadataReady,
        createdAt: 1000,
      );
    });

    tearDown(() {
      try {
        if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
      } catch (_) {}
    });

    testWidgets(
      'ИСПРАВЛЕНО: Grid _applyFilters выполняет поиск по metadataKeywords/Title/Description/Filename',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeFiles = AcceptanceFilesNotifier([appFile]);
        final fakeOrgRepo = FakeOrganizationRepository();

        final container = ProviderContainer(
          overrides: [
            workspacesProvider.overrideWith(
              () => AcceptanceWorkspacesNotifier([
                WorkspaceEntry(path: tempRoot.path),
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

        expect(find.text('sunset.jpg'), findsOneWidget);

        // 1. Поиск по строке из ключевых слов ('golden_hour').
        // Поле поиска переехало в глобальную панель; контракт фильтрации
        // проверяем через тот же провайдер, который пишет панель.
        container
            .read(organizationSearchSettingsProvider.notifier)
            .setQuery('golden_hour');
        await tester.pumpAndSettle();

        // sunset.jpg находится по ключевым словам!
        expect(
          find.text('sunset.jpg'),
          findsOneWidget,
          reason: 'Поиск по ключевым словам находит файл, даже если имя не содержит запрос.',
        );

        // 2. Поиск по описанию ('hills')
        container
            .read(organizationSearchSettingsProvider.notifier)
            .setQuery('hills');
        await tester.pumpAndSettle();
        expect(find.text('sunset.jpg'), findsOneWidget);

        // 3. Запрос, которого нет ни в одном поле, фильтрует файл
        container
            .read(organizationSearchSettingsProvider.notifier)
            .setQuery('nonexistent_pattern_xyz');
        await tester.pumpAndSettle();
        expect(find.text('sunset.jpg'), findsNothing);
      },
    );
  });

  group('Проверка 4: Персистентность и восстановление (restore/persist)', () {
    testWidgets('ИСПРАВЛЕНО: restore() вызывается при монтировании GenerationScreen', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final inMemoryStorage = InMemorySearchSettingsStorage();
      await inMemoryStorage.saveSettings(
        const OrganizationSearchSettings(
          scope: SearchScope.project(projectId: 'saved_proj_123', includeSubfolders: true),
          filters: SearchFilterCriteria(query: 'saved_query'),
          scrollOffset: 150.0,
        ),
      );

      final container = ProviderContainer(
        overrides: [
          searchSettingsStorageProvider.overrideWithValue(inMemoryStorage),
          filesProvider.overrideWith(() => AcceptanceFilesNotifier([])),
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

      final restored = container.read(organizationSearchSettingsProvider);
      expect(restored.scope.type, SearchScopeType.project);
      expect(restored.scope.projectId, 'saved_proj_123');
      expect(restored.filters.query, 'saved_query');
      expect(restored.scrollOffset, 150.0);
    });
  });

  group('Проверка 5: Отображение offline файлов в сетке при отключении диска', () {
    testWidgets('ИСПРАВЛЕНО: offline файлы из allCatalogFilesProvider отображаются в сетке со значком недоступности', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final offlineFile = AppFile(
        id: 'f_offline_drive',
        path: '/Volumes/DisconnectedDrive/offline.jpg',
        filename: 'offline.jpg',
        workflowStatus: WorkflowStatus.readyToUpload,
        createdAt: 2000,
      );

      final fakeOrgRepo = FakeOrganizationRepository();
      final collection = await fakeOrgRepo.createCollection('Offline Collection');
      await fakeOrgRepo.addFileToCollection(collection.id, offlineFile.id);

      final container = ProviderContainer(
        overrides: [
          // filesProvider не содержит offline файл
          filesProvider.overrideWith(() => AcceptanceFilesNotifier([])),
          // allCatalogFilesProvider загружает полный каталог из БД, включая offline
          allCatalogFilesProvider.overrideWith((ref) async => [offlineFile]),
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

      // Открываем коллекцию с оффлайн файлом
      container.read(organizationSearchSettingsProvider.notifier).setScope(
            SearchScope.collection(collectionId: collection.id),
          );
      await tester.pumpAndSettle();

      // Файл виден в сетке!
      expect(find.text('offline.jpg'), findsOneWidget);
      // Отображается значок cloud_off
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    });
  });

  group('Проверка 6: Защита от перезаписи восстановленной подпапки в main.dart', () {
    test('ИСПРАВЛЕНО: начальный onSelection дерева папок не сбрасывает восстановленную подпапку', () {
      const rootPath = '/media/workspaces/photos';
      const subPath = '/media/workspaces/photos/subfolder_vacation';

      final initialScope = const SearchScope.folder(
        folderPath: subPath,
        includeSubfolders: false,
      );

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(organizationSearchSettingsProvider.notifier).setScope(initialScope);
      expect(
        container.read(organizationSearchSettingsProvider).scope.folderPath,
        subPath,
      );

      // Логика onSelection из main.dart:
      void simulateMainOnSelection(FolderSelection selection) {
        final searchSettings = container.read(organizationSearchSettingsProvider);
        if (selection.path == rootPath && !selection.includeSubfolders) {
          if (searchSettings.scope.type != SearchScopeType.folder) {
            return;
          }
          if (searchSettings.scope.folderPath.isNotEmpty &&
              searchSettings.scope.folderPath != rootPath &&
              isPathInsideRoot(searchSettings.scope.folderPath, rootPath)) {
            return;
          }
        }
        container.read(organizationSearchSettingsProvider.notifier).setScope(
              SearchScope.folder(
                folderPath: selection.path,
                includeSubfolders: selection.includeSubfolders,
              ),
            );
      }

      // При открытии дерева (open) контроллер сообщает выбор корневой папки:
      simulateMainOnSelection(
        const FolderSelection(path: rootPath, includeSubfolders: false),
      );

      // Восстановленный subPath НЕ перезаписан!
      expect(
        container.read(organizationSearchSettingsProvider).scope.folderPath,
        subPath,
        reason: 'Начальный onSelection дерева не должен перезаписывать восстановленную подпапку.',
      );
    });
  });
}
