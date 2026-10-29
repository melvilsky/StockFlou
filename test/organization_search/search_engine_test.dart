import 'package:flutter_test/flutter_test.dart';
import 'package:stock_flow/features/organization_search/application/organization_search_providers.dart';
import 'package:stock_flow/models/app_file.dart';
import 'package:stock_flow/models/workflow_status.dart';

void main() {
  const engine = SearchEngine();

  // Вспомогательная фабрика тестовых файлов
  AppFile makeFile({
    required String id,
    required String path,
    required String filename,
    String? title,
    String? description,
    String? keywords,
    bool isEditorial = false,
    WorkflowStatus workflowStatus = WorkflowStatus.newFile,
    List<String> tags = const [],
  }) {
    return AppFile(
      id: id,
      path: path,
      filename: filename,
      metadataTitle: title,
      metadataDescription: description,
      metadataKeywords: keywords,
      isEditorial: isEditorial,
      workflowStatus: workflowStatus,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      tags: tags,
    );
  }

  group('SearchEngine - Область поиска (SearchScope)', () {
    final fileRoot = makeFile(
      id: 'f-1',
      path: '/media/workspaces/photos/img1.jpg',
      filename: 'img1.jpg',
    );
    final fileSub = makeFile(
      id: 'f-2',
      path: '/media/workspaces/photos/sub/img2.jpg',
      filename: 'img2.jpg',
    );
    final fileOther = makeFile(
      id: 'f-3',
      path: '/media/workspaces/videos/clip.mp4',
      filename: 'clip.mp4',
    );

    final allFiles = [fileRoot, fileSub, fileOther];

    test('поиск в папке без подпапок возвращает только прямые файлы', () async {
      final scope = const SearchScope.folder(
        folderPath: '/media/workspaces/photos',
        includeSubfolders: false,
      );

      final files = await engine.resolveFilesForScope(
        scope: scope,
        allFiles: allFiles,
        getProjectFolders: (_) async => [],
        getCollectionFileIds: (_) async => [],
        getSelectionFileIds: () async => [],
      );

      expect(files.map((f) => f.id).toList(), equals(['f-1']));
    });

    test('поиск в папке с включенными подпапками возвращает дерево файлов', () async {
      final scope = const SearchScope.folder(
        folderPath: '/media/workspaces/photos',
        includeSubfolders: true,
      );

      final files = await engine.resolveFilesForScope(
        scope: scope,
        allFiles: allFiles,
        getProjectFolders: (_) async => [],
        getCollectionFileIds: (_) async => [],
        getSelectionFileIds: () async => [],
      );

      expect(files.map((f) => f.id).toList(), equals(['f-1', 'f-2']));
    });

    test('поиск в проекте разрешает файлы всех его папок', () async {
      final scope = const SearchScope.project(
        projectId: 'p-1',
        includeSubfolders: false,
      );

      final files = await engine.resolveFilesForScope(
        scope: scope,
        allFiles: allFiles,
        getProjectFolders: (pId) async => [
          '/media/workspaces/photos',
          '/media/workspaces/videos',
        ],
        getCollectionFileIds: (_) async => [],
        getSelectionFileIds: () async => [],
      );

      expect(files.map((f) => f.id).toList(), equals(['f-1', 'f-3']));
    });

    test('поиск в коллекции возвращает файлы по упорядоченным идентификаторам', () async {
      final scope = const SearchScope.collection(collectionId: 'col-1');

      final files = await engine.resolveFilesForScope(
        scope: scope,
        allFiles: allFiles,
        getProjectFolders: (_) async => [],
        getCollectionFileIds: (cId) async => ['f-3', 'f-1'],
        getSelectionFileIds: () async => [],
      );

      expect(files.map((f) => f.id).toList(), equals(['f-3', 'f-1']));
    });

    test('поиск в «Отборе» возвращает выбранные идентификаторы', () async {
      const scope = SearchScope.selection();

      final files = await engine.resolveFilesForScope(
        scope: scope,
        allFiles: allFiles,
        getProjectFolders: (_) async => [],
        getCollectionFileIds: (_) async => [],
        getSelectionFileIds: () async => ['f-2'],
      );

      expect(files.map((f) => f.id).toList(), equals(['f-2']));
    });
  });

  group('SearchEngine - Пересекающиеся папки и дедупликация AppFile.id', () {
    test('файлы из вложенных папок не дублируются при пересечении корней проекта',
        () async {
      final fileParent = makeFile(
        id: 'f-10',
        path: '/storage/campaign/main.jpg',
        filename: 'main.jpg',
      );
      final fileChild = makeFile(
        id: 'f-11',
        path: '/storage/campaign/nested/sub.jpg',
        filename: 'sub.jpg',
      );

      final allFiles = [fileParent, fileChild];

      // Проект с пересекающимися корнями: родительская папка и ее подпапка
      final scope = const SearchScope.project(
        projectId: 'proj-overlap',
        includeSubfolders: true,
      );

      final files = await engine.resolveFilesForScope(
        scope: scope,
        allFiles: allFiles,
        getProjectFolders: (pId) async => [
          '/storage/campaign',
          '/storage/campaign/nested',
        ],
        getCollectionFileIds: (_) async => [],
        getSelectionFileIds: () async => [],
      );

      // Каждый файл должен быть ровно один раз, без повторов f-11
      expect(files.map((f) => f.id).toList(), equals(['f-10', 'f-11']));
    });
  });

  group('SearchEngine - Независимость файлов с одинаковыми именами', () {
    test('разные файлы с одинаковыми именами не объединяются и не схлопываются',
        () async {
      final fileA = makeFile(
        id: 'id-alpha',
        path: '/storage/brand_a/logo.png',
        filename: 'logo.png',
        title: 'Logo Alpha',
      );
      final fileB = makeFile(
        id: 'id-beta',
        path: '/storage/brand_b/logo.png',
        filename: 'logo.png',
        title: 'Logo Beta',
      );

      final allFiles = [fileA, fileB];

      final results = engine.filterFiles(
        files: allFiles,
        criteria: const SearchFilterCriteria(query: 'logo'),
        fileExistsProbe: (_) => true,
      );

      expect(results.length, equals(2));
      expect(results[0].id, equals('id-alpha'));
      expect(results[0].file.metadataTitle, equals('Logo Alpha'));
      expect(results[1].id, equals('id-beta'));
      expect(results[1].file.metadataTitle, equals('Logo Beta'));
    });
  });

  group('SearchEngine - Пустой запрос и текстовый поиск', () {
    final file = makeFile(
      id: 'f-text',
      path: '/storage/test/sample.jpg',
      filename: 'sample.jpg',
      title: 'Majestic Mountain',
      description: 'Sunrise view over peaks',
      keywords: 'nature, landscape, travel, dawn',
    );

    test('пустой запрос или запрос из пробелов возвращает все файлы источника', () {
      final files = [file];

      var res = engine.filterFiles(
        files: files,
        criteria: const SearchFilterCriteria(query: ''),
        fileExistsProbe: (_) => true,
      );
      expect(res.length, equals(1));

      res = engine.filterFiles(
        files: files,
        criteria: const SearchFilterCriteria(query: '   '),
        fileExistsProbe: (_) => true,
      );
      expect(res.length, equals(1));
    });

    test('поиск по подстроке в имени файла без учета регистра', () {
      final res = engine.filterFiles(
        files: [file],
        criteria: const SearchFilterCriteria(query: 'SAMPLE'),
        fileExistsProbe: (_) => true,
      );
      expect(res.length, equals(1));
    });

    test('поиск по подстроке в названии (title)', () {
      final res = engine.filterFiles(
        files: [file],
        criteria: const SearchFilterCriteria(query: 'mountain'),
        fileExistsProbe: (_) => true,
      );
      expect(res.length, equals(1));
    });

    test('поиск по подстроке в описании (description)', () {
      final res = engine.filterFiles(
        files: [file],
        criteria: const SearchFilterCriteria(query: 'sunrise'),
        fileExistsProbe: (_) => true,
      );
      expect(res.length, equals(1));
    });

    test('поиск по подстроке в ключевых словах (keywords)', () {
      final res = engine.filterFiles(
        files: [file],
        criteria: const SearchFilterCriteria(query: 'landscape'),
        fileExistsProbe: (_) => true,
      );
      expect(res.length, equals(1));
    });

    test('несовпадающий запрос отсекает файл', () {
      final res = engine.filterFiles(
        files: [file],
        criteria: const SearchFilterCriteria(query: 'underwater ocean'),
        fileExistsProbe: (_) => true,
      );
      expect(res, isEmpty);
    });
  });

  group('SearchEngine - Недоступный источник и членство', () {
    test('недоступность источника на диске не удаляет членство и не очищает коллекцию',
        () async {
      final fileOnline = makeFile(
        id: 'f-online',
        path: '/storage/internal/doc.jpg',
        filename: 'doc.jpg',
      );
      final fileOffline = makeFile(
        id: 'f-offline',
        path: '/Volumes/DetachedDrive/photo.jpg',
        filename: 'photo.jpg',
      );

      final allFiles = [fileOnline, fileOffline];

      // Проверяем резолвинг коллекции
      final resolved = await engine.resolveFilesForScope(
        scope: const SearchScope.collection(collectionId: 'my-col'),
        allFiles: allFiles,
        getProjectFolders: (_) async => [],
        getCollectionFileIds: (_) async => ['f-online', 'f-offline'],
        getSelectionFileIds: () async => [],
      );

      // Коллекция НЕ пуста: оба файла возвращаются
      expect(resolved.map((f) => f.id).toList(), equals(['f-online', 'f-offline']));

      // При фильтрации проверяем флаг доступности через probe
      final filtered = engine.filterFiles(
        files: resolved,
        criteria: const SearchFilterCriteria(),
        fileExistsProbe: (path) => path.startsWith('/storage/internal'),
      );

      expect(filtered.length, equals(2));
      expect(filtered[0].id, equals('f-online'));
      expect(filtered[0].isAccessible, isTrue);

      expect(filtered[1].id, equals('f-offline'));
      expect(filtered[1].isAccessible, isFalse);
    });
  });

  group('SearchEngine - Фильтры свойств', () {
    final fileWithoutKeywords = makeFile(
      id: 'f-no-kw',
      path: '/p/raw.jpg',
      filename: 'raw.jpg',
      keywords: null,
      workflowStatus: WorkflowStatus.newFile,
    );
    final fileWithKeywords = makeFile(
      id: 'f-kw',
      path: '/p/ready.jpg',
      filename: 'ready.jpg',
      keywords: 'sun, sky',
      isEditorial: true,
      workflowStatus: WorkflowStatus.metadataReady,
      tags: [AppTags.aiGenerated, AppTags.editorial],
    );

    test('фильтр «Без ключей» (hasKeywords: false)', () {
      final res = engine.filterFiles(
        files: [fileWithoutKeywords, fileWithKeywords],
        criteria: const SearchFilterCriteria(hasKeywords: false),
        fileExistsProbe: (_) => true,
      );
      expect(res.map((r) => r.id).toList(), equals(['f-no-kw']));
    });

    test('фильтр по workflow status', () {
      final res = engine.filterFiles(
        files: [fileWithoutKeywords, fileWithKeywords],
        criteria: const SearchFilterCriteria(
          workflowStatuses: {WorkflowStatus.metadataReady},
        ),
        fileExistsProbe: (_) => true,
      );
      expect(res.map((r) => r.id).toList(), equals(['f-kw']));
    });

    test('фильтр по AI-generated и Editorial', () {
      var res = engine.filterFiles(
        files: [fileWithoutKeywords, fileWithKeywords],
        criteria: const SearchFilterCriteria(isAiGenerated: true),
        fileExistsProbe: (_) => true,
      );
      expect(res.map((r) => r.id).toList(), equals(['f-kw']));

      res = engine.filterFiles(
        files: [fileWithoutKeywords, fileWithKeywords],
        criteria: const SearchFilterCriteria(isEditorial: true),
        fileExistsProbe: (_) => true,
      );
      expect(res.map((r) => r.id).toList(), equals(['f-kw']));
    });

    test('filterFilesAsync не блокирует UI и использует асинхронную проверку с пулом', () async {
      int activeProbes = 0;
      int maxActiveProbes = 0;

      final files = List.generate(
        30,
        (i) => makeFile(
          id: 'async-f-$i',
          path: '/storage/drive/file_$i.jpg',
          filename: 'file_$i.jpg',
        ),
      );

      final results = await engine.filterFilesAsync(
        files: files,
        criteria: const SearchFilterCriteria(),
        concurrency: 4,
        fileExistsProbe: (path) async {
          activeProbes++;
          if (activeProbes > maxActiveProbes) {
            maxActiveProbes = activeProbes;
          }
          await Future.delayed(const Duration(milliseconds: 5));
          activeProbes--;
          return true;
        },
      );

      expect(results.length, equals(30));
      expect(maxActiveProbes, lessThanOrEqualTo(4));
    });
  });
}
