import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_flow/features/folder_navigation/domain/folder_access.dart';
import 'package:stock_flow/features/folder_navigation/domain/folder_navigation_controller.dart';
import 'package:stock_flow/features/folder_navigation/domain/folder_navigation_models.dart';

/// Fake реализация FolderAccessScope для управляемых тестов
class FakeFolderAccessScope implements FolderAccessScope {
  FakeFolderAccessScope(this.rootPath);

  @override
  final String rootPath;

  final Map<String, List<FolderNavigationItem>> folders = {};
  final Set<String> failingPaths = {};
  final Map<String, Completer<List<FolderNavigationItem>>> pendingCompleters = {};
  int listCalls = 0;

  @override
  Future<bool> exists(String path) async => true;

  @override
  Future<List<FolderNavigationItem>> listSubfolders(String path) async {
    listCalls++;
    if (failingPaths.contains(path)) {
      throw const FileSystemException('Access denied', '', OSError('Permission denied', 13));
    }
    if (pendingCompleters.containsKey(path)) {
      return pendingCompleters[path]!.future;
    }
    return folders[path] ?? const [];
  }
}

void main() {
  group('Helper functions', () {
    test('parentFolderPath и isPathInsideRoot: границы', () {
      expect(parentFolderPath('/a/b/c'), '/a/b');
      expect(parentFolderPath('/a'), '/');
      expect(parentFolderPath('/'), isNull);
      expect(parentFolderPath(''), isNull);

      expect(isPathInsideRoot('/root', '/root'), true);
      expect(isPathInsideRoot('/root/sub', '/root'), true);
      expect(isPathInsideRoot('/root/sub/deep', '/root'), true);
      expect(isPathInsideRoot('/root2/sub', '/root'), false);
      expect(isPathInsideRoot('/roo', '/root'), false);
      expect(isPathInsideRoot('/', '/'), true);
      expect(isPathInsideRoot('/any', '/'), true);
      expect(isPathInsideRoot('', '/root'), false);
    });

    test('normalizeFolderPath корректно обрабатывает слэши', () {
      expect(normalizeFolderPath('/path/to/folder///'), '/path/to/folder');
      expect(normalizeFolderPath('/'), '/');
      expect(normalizeFolderPath('///'), '/');
      expect(normalizeFolderPath(''), '');
    });
  });

  group('DefaultFolderAccessScope (на реальной временной ФС)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('sf_test_access_scope_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('вложенность, сортировка, игнорирование обычных файлов и guard', () async {
      final root = tempDir.path;
      Directory('$root/beta').createSync();
      Directory('$root/alpha').createSync();
      Directory('$root/gamma/nested').createSync(recursive: true);
      File('$root/file.txt').writeAsStringSync('text');

      final access = DefaultFolderAccessScope(root);
      final folders = await access.listSubfolders(root);

      expect(folders.map((f) => f.name).toList(), ['alpha', 'beta', 'gamma']);
      expect(folders.every((f) => !f.isSymlink), true);

      // Проверка guard: выход за пределы корня
      expect(
        () => access.listSubfolders('/some/other/path'),
        throwsArgumentError,
      );
    });

    test('символическая ссылка помечается как isSymlink и не обходится рекурсивно', () async {
      final root = tempDir.path;
      final targetDir = Directory('$root/target')..createSync();
      Directory('${targetDir.path}/inner').createSync();

      // Создаем симлинк на целевую папку
      final link = Link('$root/symlink_folder');
      try {
        link.createSync(targetDir.path);
      } on FileSystemException {
        // Если ОС не поддерживает создание симлинков без админ прав (например Windows), пропускаем
        return;
      }

      // Создаем симлинк, указывающий на корень (цикл)
      final cyclicLink = Link('$root/cycle_to_root');
      try {
        cyclicLink.createSync(root);
      } on FileSystemException {
        return;
      }

      final access = DefaultFolderAccessScope(root);
      final folders = await access.listSubfolders(root);

      final symlinkItem = folders.firstWhere((f) => f.name == 'symlink_folder');
      expect(symlinkItem.isSymlink, true);

      final cycleItem = folders.firstWhere((f) => f.name == 'cycle_to_root');
      expect(cycleItem.isSymlink, true);

      // В списке корня не должно быть inner (рекурсивный обход не произошел)
      expect(folders.any((f) => f.name == 'inner'), false);
    });
  });

  group('FolderNavigationController', () {
    late ProviderContainer container;
    late FakeFolderAccessScope fakeScope;
    final List<FolderSelection> emittedSelections = [];

    setUp(() {
      container = ProviderContainer();
      fakeScope = FakeFolderAccessScope('/workspaces/root');
      fakeScope.folders['/workspaces/root'] = [
        const FolderNavigationItem(
          path: '/workspaces/root/photos',
          name: 'photos',
          isSymlink: false,
        ),
        const FolderNavigationItem(
          path: '/workspaces/root/videos',
          name: 'videos',
          isSymlink: false,
        ),
        const FolderNavigationItem(
          path: '/workspaces/root/link',
          name: 'link',
          isSymlink: true,
        ),
      ];
      fakeScope.folders['/workspaces/root/photos'] = [
        const FolderNavigationItem(
          path: '/workspaces/root/photos/2026',
          name: '2026',
          isSymlink: false,
        ),
      ];
      fakeScope.folders['/workspaces/root/photos/2026'] = [];
      emittedSelections.clear();
    });

    tearDown(() {
      container.dispose();
    });

    test('open() лениво загружает только корень и отсылает callback выбора', () async {
      final controller = container.read(folderNavigationProvider.notifier);

      controller.open(
        rootPath: '/workspaces/root',
        access: fakeScope,
        onSelection: (sel) => emittedSelections.add(sel),
      );

      // Сразу после open: состояние инициализировано
      var state = container.read(folderNavigationProvider);
      expect(state.rootPath, '/workspaces/root');
      expect(state.currentPath, '/workspaces/root');
      expect(state.expandedPaths, contains('/workspaces/root'));
      expect(emittedSelections, hasLength(1));
      expect(emittedSelections.first.path, '/workspaces/root');
      expect(emittedSelections.first.includeSubfolders, false);

      // Дожидаемся асинхронного завершения чтения детей корня
      await Future<void>.delayed(Duration.zero);

      state = container.read(folderNavigationProvider);
      final rootNode = state.nodes['/workspaces/root'];
      expect(rootNode, isNotNull);
      expect(rootNode!.status, FolderNodeStatus.ready);
      expect(rootNode.children, hasLength(3));
      expect(rootNode.children[0].name, 'photos');

      // Дети корня (photos) не должны быть загружены заранее (ленивость)
      expect(state.nodes['/workspaces/root/photos'], isNull);
      expect(fakeScope.listCalls, 1);
    });

    test('toggleExpand() загружает подпапку лениво только при раскрытии', () async {
      final controller = container.read(folderNavigationProvider.notifier);
      controller.open(
        rootPath: '/workspaces/root',
        access: fakeScope,
        onSelection: (sel) => emittedSelections.add(sel),
      );
      await Future<void>.delayed(Duration.zero);

      // Раскрываем /workspaces/root/photos
      controller.toggleExpand('/workspaces/root/photos');
      var state = container.read(folderNavigationProvider);
      expect(state.expandedPaths, contains('/workspaces/root/photos'));

      // Ждем завершения загрузки
      await Future<void>.delayed(Duration.zero);
      state = container.read(folderNavigationProvider);
      final photosNode = state.nodes['/workspaces/root/photos'];
      expect(photosNode, isNotNull);
      expect(photosNode!.status, FolderNodeStatus.ready);
      expect(photosNode.children, hasLength(1));
      expect(photosNode.children.first.name, '2026');
      expect(fakeScope.listCalls, 2);

      // Сворачиваем обратно
      controller.toggleExpand('/workspaces/root/photos');
      state = container.read(folderNavigationProvider);
      expect(state.expandedPaths.contains('/workspaces/root/photos'), false);
      // Повторного вызова listSubfolders быть не должно
      expect(fakeScope.listCalls, 2);
    });

    test('Символьные ссылки не раскрываются через toggleExpand', () async {
      final controller = container.read(folderNavigationProvider.notifier);
      controller.open(
        rootPath: '/workspaces/root',
        access: fakeScope,
        onSelection: (sel) => emittedSelections.add(sel),
      );
      await Future<void>.delayed(Duration.zero);

      // Пытаемся раскрыть symlink
      controller.toggleExpand('/workspaces/root/link');
      final state = container.read(folderNavigationProvider);
      expect(state.expandedPaths.contains('/workspaces/root/link'), false);
      expect(state.nodes['/workspaces/root/link'], isNull);
    });

    test('Навигация: переход к родителю, история назад/вперёд', () async {
      final controller = container.read(folderNavigationProvider.notifier);
      controller.open(
        rootPath: '/workspaces/root',
        access: fakeScope,
        onSelection: (sel) => emittedSelections.add(sel),
      );
      await Future<void>.delayed(Duration.zero);

      // Переход в photos
      controller.selectFolder('/workspaces/root/photos');
      var state = container.read(folderNavigationProvider);
      expect(state.currentPath, '/workspaces/root/photos');
      expect(state.canGoBack, true);
      expect(state.canGoForward, false);
      expect(state.backHistory, ['/workspaces/root']);

      // Переход в 2026
      controller.selectFolder('/workspaces/root/photos/2026');
      state = container.read(folderNavigationProvider);
      expect(state.currentPath, '/workspaces/root/photos/2026');
      expect(state.backHistory, ['/workspaces/root', '/workspaces/root/photos']);

      // Переход наверх (к родителю)
      controller.navigateUp();
      state = container.read(folderNavigationProvider);
      expect(state.currentPath, '/workspaces/root/photos');

      // Еще раз наверх (к корню)
      controller.navigateUp();
      state = container.read(folderNavigationProvider);
      expect(state.currentPath, '/workspaces/root');

      // Попытка подняться выше корня — не должна выйти за rootPath
      controller.navigateUp();
      state = container.read(folderNavigationProvider);
      expect(state.currentPath, '/workspaces/root');

      // Назад
      controller.goBack();
      state = container.read(folderNavigationProvider);
      expect(state.currentPath, '/workspaces/root/photos');
      expect(state.canGoForward, true);

      // Вперед
      controller.goForward();
      state = container.read(folderNavigationProvider);
      expect(state.currentPath, '/workspaces/root');
    });

    test('Переключатель «С подпапками» обновляет состояние и callback выбора', () async {
      final controller = container.read(folderNavigationProvider.notifier);
      controller.open(
        rootPath: '/workspaces/root',
        access: fakeScope,
        onSelection: (sel) => emittedSelections.add(sel),
      );
      await Future<void>.delayed(Duration.zero);

      controller.setIncludeSubfolders(true);
      var state = container.read(folderNavigationProvider);
      expect(state.includeSubfolders, true);
      expect(emittedSelections.last.includeSubfolders, true);

      controller.setIncludeSubfolders(false);
      state = container.read(folderNavigationProvider);
      expect(state.includeSubfolders, false);
      expect(emittedSelections.last.includeSubfolders, false);
    });

    test('Отмена/игнорирование устаревших результатов при быстрой навигации', () async {
      final controller = container.read(folderNavigationProvider.notifier);
      final completer1 = Completer<List<FolderNavigationItem>>();
      final completer2 = Completer<List<FolderNavigationItem>>();

      fakeScope.pendingCompleters['/workspaces/root/photos'] = completer1;

      controller.open(
        rootPath: '/workspaces/root',
        access: fakeScope,
      );
      await Future<void>.delayed(Duration.zero);

      // Запускаем загрузку 1
      controller.toggleExpand('/workspaces/root/photos');
      var state = container.read(folderNavigationProvider);
      expect(state.nodes['/workspaces/root/photos']!.status, FolderNodeStatus.loading);

      // Быстро перезагружаем папку (запрос 2)
      fakeScope.pendingCompleters['/workspaces/root/photos'] = completer2;
      controller.reloadFolder('/workspaces/root/photos');

      // Завершаем запрос 1 старыми данными
      completer1.complete([
        const FolderNavigationItem(path: '/workspaces/root/photos/old', name: 'old', isSymlink: false),
      ]);
      await Future<void>.delayed(Duration.zero);

      // Состояние все еще должно ожидать второй запрос
      state = container.read(folderNavigationProvider);
      expect(state.nodes['/workspaces/root/photos']!.status, FolderNodeStatus.loading);

      // Завершаем второй запрос актуальными данными
      completer2.complete([
        const FolderNavigationItem(path: '/workspaces/root/photos/new', name: 'new', isSymlink: false),
      ]);
      await Future<void>.delayed(Duration.zero);

      state = container.read(folderNavigationProvider);
      expect(state.nodes['/workspaces/root/photos']!.status, FolderNodeStatus.ready);
      expect(state.nodes['/workspaces/root/photos']!.children.first.name, 'new');
    });

    test('Различение пустоты (ready с пустым списком) и ошибки доступа (error)', () async {
      fakeScope.folders['/workspaces/root/empty_dir'] = [];
      fakeScope.failingPaths.add('/workspaces/root/error_dir');

      fakeScope.folders['/workspaces/root'] = [
        const FolderNavigationItem(
          path: '/workspaces/root/empty_dir',
          name: 'empty_dir',
          isSymlink: false,
        ),
        const FolderNavigationItem(
          path: '/workspaces/root/error_dir',
          name: 'error_dir',
          isSymlink: false,
        ),
      ];

      final controller = container.read(folderNavigationProvider.notifier);
      controller.open(
        rootPath: '/workspaces/root',
        access: fakeScope,
      );
      await Future<void>.delayed(Duration.zero);

      // Раскрываем пустую папку
      controller.toggleExpand('/workspaces/root/empty_dir');
      await Future<void>.delayed(Duration.zero);
      var state = container.read(folderNavigationProvider);
      final emptyNode = state.nodes['/workspaces/root/empty_dir']!;
      expect(emptyNode.status, FolderNodeStatus.ready);
      expect(emptyNode.isEmpty, true);
      expect(emptyNode.hasError, false);

      // Раскрываем папку с ошибкой доступа
      controller.toggleExpand('/workspaces/root/error_dir');
      await Future<void>.delayed(Duration.zero);
      state = container.read(folderNavigationProvider);
      final errorNode = state.nodes['/workspaces/root/error_dir']!;
      expect(errorNode.status, FolderNodeStatus.error);
      expect(errorNode.hasError, true);
      expect(errorNode.errorMessage, contains('Access denied'));
    });
  });
}
