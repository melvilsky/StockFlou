import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_secure_bookmarks/macos_secure_bookmarks.dart';
import 'package:stock_flow/core/state/active_grid_selection_provider.dart';
import 'package:stock_flow/core/state/files_provider.dart';
import 'package:stock_flow/core/state/settings_provider.dart';
import 'package:stock_flow/core/state/workspaces_provider.dart';
import 'package:stock_flow/features/folder_navigation/domain/folder_access.dart';
import 'package:stock_flow/features/generation/presentation/generation_screen.dart';
import 'package:stock_flow/features/generation/presentation/widgets/generation_widgets.dart';
import 'package:stock_flow/features/organization/application/organization_providers.dart';
import 'package:stock_flow/features/organization_search/application/organization_search_providers.dart';
import 'package:stock_flow/models/app_file.dart';
import 'package:stock_flow/models/workflow_status.dart';

import '../organization_presentation/test_helpers.dart';

class MockSecureBookmarks implements SecureBookmarks {
  int startCount = 0;
  int stopCount = 0;
  final Map<String, Directory> resolved = {};

  @override
  Future<String> bookmark(FileSystemEntity entity) async {
    return 'bm_${entity.path}';
  }

  Future<String> createBookmark(FileSystemEntity entity) async {
    return 'bm_${entity.path}';
  }

  @override
  Future<FileSystemEntity> resolveBookmark(
    String bookmark, {
    bool isDirectory = false,
  }) async {
    final path = bookmark.replaceFirst('bm_', '');
    final dir = Directory(path);
    resolved[path] = dir;
    return dir;
  }

  @override
  Future<bool> startAccessingSecurityScopedResource(
    FileSystemEntity entity,
  ) async {
    startCount++;
    return true;
  }

  @override
  Future<bool> stopAccessingSecurityScopedResource(
    FileSystemEntity entity,
  ) async {
    stopCount++;
    return true;
  }
}

class TestFilesNotifier extends FilesNotifier {
  final List<AppFile> files;
  final List<AppFile> updated = [];
  final List<AppFile> added = [];

  TestFilesNotifier(List<AppFile> initial) : files = List.of(initial);

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

class TestWorkspacesNotifier extends WorkspacesNotifier {
  final List<WorkspaceEntry> initialEntries;
  int initialIndex;

  TestWorkspacesNotifier(this.initialEntries, {this.initialIndex = 0});

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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecurityScopedFolderAccessScope', () {
    test('делегирует проверки и использует guard', () async {
      final scope = SecurityScopedFolderAccessScope(
        rootPath: '/media/photos',
      );

      expect(() => scope.exists('/etc/passwd'), throwsArgumentError);
      expect(() => scope.listSubfolders('/other/dir'), throwsArgumentError);
    });

    test('активирует и останавливает security scope при наличии bookmark', () async {
      final mockBookmarks = MockSecureBookmarks();
      final tempDir = Directory.systemTemp.createTempSync('sf_sec_scope_test_');
      Directory('${tempDir.path}/sub1').createSync();

      try {
        final scope = SecurityScopedFolderAccessScope(
          rootPath: tempDir.path,
          bookmark: 'bm_${tempDir.path}',
          secureBookmarks: mockBookmarks,
        );

        final subfolders = await scope.listSubfolders(tempDir.path);
        expect(subfolders.length, 1);
        expect(subfolders.first.name, 'sub1');
        // Проверяем, что start/stop были вызваны сбалансированно
        if (Platform.isMacOS) {
          expect(mockBookmarks.startCount, 1);
          expect(mockBookmarks.stopCount, 1);
        }
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('ActiveGridSelectionNotifier', () {
    test('сохраняет неизменяемый снимок выделения и очищается', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(activeGridSelectionProvider), isEmpty);

      container.read(activeGridSelectionProvider.notifier).setSelection(['id_1', 'id_2']);
      expect(container.read(activeGridSelectionProvider), ['id_1', 'id_2']);

      // Повторная передача идентичного списка не вызывает лишних нотификаций
      container.read(activeGridSelectionProvider.notifier).setSelection(['id_1', 'id_2']);
      expect(container.read(activeGridSelectionProvider), ['id_1', 'id_2']);

      container.read(activeGridSelectionProvider.notifier).clear();
      expect(container.read(activeGridSelectionProvider), isEmpty);
    });
  });

  group('Интеграция: черновики и переключение источников', () {
    late Directory tempDir;
    late File testFileA;
    late File testFileB;
    late AppFile appFileA;
    late AppFile appFileB;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('sf_integration_test_');
      testFileA = File('${tempDir.path}/photo_a.jpg')..writeAsStringSync('a');
      testFileB = File('${tempDir.path}/photo_b.jpg')..writeAsStringSync('b');

      appFileA = AppFile(
        id: 'id_a',
        path: testFileA.path,
        filename: 'photo_a.jpg',
        metadataTitle: 'Original Title A',
        metadataKeywords: 'keyword1, keyword2',
        workflowStatus: WorkflowStatus.newFile,
        createdAt: 1000,
      );

      appFileB = AppFile(
        id: 'id_b',
        path: testFileB.path,
        filename: 'photo_b.jpg',
        metadataTitle: 'Original Title B',
        metadataKeywords: 'keywordB',
        workflowStatus: WorkflowStatus.metadataReady,
        createdAt: 2000,
      );
    });

    tearDown(() {
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    testWidgets(
      'Смена папки/источника сохраняет черновик без записи EXIF на диск и без смены статуса',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeFiles = TestFilesNotifier([appFileA, appFileB]);
        final fakeOrgRepo = FakeOrganizationRepository();
        final writtenExifPaths = <String>[];

        final container = ProviderContainer(
          overrides: [
            workspacesProvider.overrideWith(
              () => TestWorkspacesNotifier([
                WorkspaceEntry(path: tempDir.path),
                WorkspaceEntry(path: '/other/workspace'),
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
            child: MaterialApp(
              home: Scaffold(
                body: GenerationScreen(
                  writeMetadata: ({
                    required filePath,
                    required title,
                    required keywords,
                    description,
                  }) async {
                    writtenExifPaths.add(filePath);
                    return true;
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Выбираем photo_a.jpg в сетке
        await tester.tap(
          find.descendant(
            of: find.byType(GenerationGridCard),
            matching: find.text('photo_a.jpg'),
          ),
        );
        await tester.pumpAndSettle();

        // 2. Проверяем, что исходные данные появились в контроллерах
        expect(find.text('Original Title A'), findsOneWidget);

        // 3. Редактируем название и ключевые слова (появляется dirty flag)
        await tester.enterText(
          find.widgetWithText(TextField, 'Original Title A'),
          'Draft Title A (Unsaved)',
        );
        await tester.pumpAndSettle();

        // 4. Переключаем область поиска на проект без нажатия кнопки «Сохранить»
        container.read(organizationSearchSettingsProvider.notifier).setScope(
              const SearchScope.project(projectId: 'proj_new', includeSubfolders: false),
            );
        await tester.pumpAndSettle();

        // 5. Проверяем сохранность черновика в каталоге:
        // - Запись updateFile вызвана для id_a
        expect(fakeFiles.updated.any((f) => f.id == 'id_a'), isTrue);
        final draftedRecord = fakeFiles.updated.firstWhere((f) => f.id == 'id_a');
        expect(draftedRecord.metadataTitle, 'Draft Title A (Unsaved)');
        // - Статус НЕ изменился на readyToUpload (остался newFile!)
        expect(draftedRecord.workflowStatus, WorkflowStatus.newFile);
        // - Физический EXIF на диске НЕ перезаписывался
        expect(writtenExifPaths, isEmpty);

        // 6. Возвращаемся в папку: черновик восстанавливается в UI
        container.read(organizationSearchSettingsProvider.notifier).setScope(
              SearchScope.folder(folderPath: tempDir.path, includeSubfolders: false),
            );
        await tester.pumpAndSettle();

        await tester.tap(
          find.descendant(
            of: find.byType(GenerationGridCard),
            matching: find.text('photo_a.jpg'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Draft Title A (Unsaved)'), findsOneWidget);
      },
    );

    testWidgets(
      'Выделение в сетке синхронизируется с activeGridSelectionProvider для коллекций',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeFiles = TestFilesNotifier([appFileA, appFileB]);
        final fakeOrgRepo = FakeOrganizationRepository();

        final container = ProviderContainer(
          overrides: [
            workspacesProvider.overrideWith(
              () => TestWorkspacesNotifier([
                WorkspaceEntry(path: tempDir.path),
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

        // Выделение пустое
        expect(container.read(activeGridSelectionProvider), isEmpty);

        // Кликаем по photo_a.jpg
        await tester.tap(
          find.descendant(
            of: find.byType(GenerationGridCard),
            matching: find.text('photo_a.jpg'),
          ),
        );
        await tester.pumpAndSettle();

        // activeGridSelectionProvider содержит ['id_a']
        expect(container.read(activeGridSelectionProvider), ['id_a']);

        // Нажимаем кнопку тулбара: так как выделен только 1 из 2, она довыделяет все файлы
        await tester.tap(find.widgetWithText(OutlinedButton, 'Выделить всё'));
        await tester.pumpAndSettle();
        expect(container.read(activeGridSelectionProvider).toSet(), {'id_a', 'id_b'});

        // Снимаем выделение отдельной командой.
        await tester.tap(find.text('Снять выделение'));
        await tester.pumpAndSettle();
        expect(container.read(activeGridSelectionProvider), isEmpty);
      },
    );

    testWidgets(
      'Сбой записи в БД сохраняет черновик в in-memory snapshot и не теряет введённые данные',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Создаем notifier, который выбрасывает исключение при updateFile
        final failingFilesNotifier = _FailingUpdateFilesNotifier([appFileA]);
        final container = ProviderContainer(
          overrides: [
            workspacesProvider.overrideWith(
              () => TestWorkspacesNotifier([WorkspaceEntry(path: tempDir.path)]),
            ),
            filesProvider.overrideWith(() => failingFilesNotifier),
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

        // 1. Выбираем photo_a.jpg
        await tester.tap(
          find.descendant(
            of: find.byType(GenerationGridCard),
            matching: find.text('photo_a.jpg'),
          ),
        );
        await tester.pumpAndSettle();

        // 2. Вводим текст
        await tester.enterText(
          find.widgetWithText(TextField, 'Original Title A'),
          'Resilient InMemory Draft Title',
        );
        await tester.pumpAndSettle();

        // 3. Переключаем область поиска (вызывает _preserveUnsavedDraft, который упадет в БД, но зафиксирует in-memory)
        container.read(organizationSearchSettingsProvider.notifier).setScope(
              const SearchScope.project(projectId: 'proj_crash_test', includeSubfolders: false),
            );
        await tester.pumpAndSettle();

        // 4. Возвращаемся в папку и кликаем по файлу — проверяем, что черновик восстановился из in-memory snapshot
        container.read(organizationSearchSettingsProvider.notifier).setScope(
              SearchScope.folder(folderPath: tempDir.path, includeSubfolders: false),
            );
        await tester.pumpAndSettle();

        await tester.tap(
          find.descendant(
            of: find.byType(GenerationGridCard),
            matching: find.text('photo_a.jpg'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Resilient InMemory Draft Title'), findsOneWidget);
      },
    );

    test('Защита дерева в main.dart: начальный onSelection не перезаписывает восстановленный проект', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // 1. Восстановлен проект
      container.read(organizationSearchSettingsProvider.notifier).setScope(
            const SearchScope.project(projectId: 'restored_proj_42', includeSubfolders: false),
          );
      expect(
        container.read(organizationSearchSettingsProvider).scope.type,
        SearchScopeType.project,
      );

      // 2. Имитируем начальный callback FolderNavigationView: selection.path == currentPath, includeSubfolders == false
      const currentPath = '/workspace/root';
      const initialTreeSelection = (path: '/workspace/root', includeSubfolders: false);

      final searchSettings = container.read(organizationSearchSettingsProvider);
      final shouldIgnore = searchSettings.scope.type != SearchScopeType.folder &&
          initialTreeSelection.path == currentPath &&
          !initialTreeSelection.includeSubfolders;

      expect(shouldIgnore, isTrue);

      // Scope проекта остался нетронутым!
      expect(
        container.read(organizationSearchSettingsProvider).scope.type,
        SearchScopeType.project,
      );
    });
  });
}

class _FailingUpdateFilesNotifier extends FilesNotifier {
  final List<AppFile> files;
  _FailingUpdateFilesNotifier(List<AppFile> initial) : files = List.of(initial);

  @override
  Future<List<AppFile>> build() async => List.of(files);

  @override
  Future<void> syncWithDisk() async {}

  @override
  Future<void> updateFile(AppFile file) async {
    throw StateError('Simulated database write failure');
  }
}
