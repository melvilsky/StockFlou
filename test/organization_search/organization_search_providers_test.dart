import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_flow/core/database/database_helper.dart';
import 'package:stock_flow/core/state/files_provider.dart';
import 'package:stock_flow/features/organization/application/organization_providers.dart';
import 'package:stock_flow/features/organization_search/application/organization_search_providers.dart';
import 'package:stock_flow/models/app_file.dart';
import 'package:stock_flow/models/workflow_status.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late DatabaseHelper helper;
  late OrganizationRepository repo;
  late InMemorySearchSettingsStorage storage;
  late ProviderContainer container;

  final sampleFileA = AppFile(
    id: 'f-alpha',
    path: '/media/workspaces/proj/forest.jpg',
    filename: 'forest.jpg',
    metadataTitle: 'Green Forest',
    metadataKeywords: 'trees, leaves, nature',
    workflowStatus: WorkflowStatus.metadataReady,
    createdAt: 1000,
  );

  final sampleFileOffline = AppFile(
    id: 'f-offline',
    path: '/Volumes/DetachedDrive/city.jpg',
    filename: 'city.jpg',
    metadataTitle: 'Urban Sunset',
    metadataKeywords: 'buildings, lights',
    workflowStatus: WorkflowStatus.newFile,
    createdAt: 2000,
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sf_org_search_test_');
    helper = DatabaseHelper.forTest(tempDir.path);
    repo = OrganizationRepository(() => helper.database);
    storage = InMemorySearchSettingsStorage();

    // Заполняем тестовую БД файлами (в БД сохраняются оба файла)
    await helper.insertFile(sampleFileA);
    await helper.insertFile(sampleFileOffline);

    container = ProviderContainer(
      overrides: [
        organizationRepositoryProvider.overrideWithValue(repo),
        searchSettingsStorageProvider.overrideWithValue(storage),
        // Моделируем поведение реального filesProvider: он отфильтровал offline-файл,
        // поэтому в его значении виден только существующий sampleFileA.
        filesProvider.overrideWith(() => _TestFilesNotifier([sampleFileA])),
        // catalogFilesLoaderProvider загружает полный набор из базы данных
        catalogFilesLoaderProvider.overrideWithValue(
          () async => [sampleFileA, sampleFileOffline],
        ),
        // fileAccessibilityProbeProvider: доступен только файл на локальном диске
        fileAccessibilityProbeProvider.overrideWithValue(
          (path) => path.startsWith('/media/workspaces/'),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    final db = await helper.database;
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('organizationSearchSettingsProvider управляет настройками и сохранением', () async {
    final notifier = container.read(organizationSearchSettingsProvider.notifier);

    // Начальное состояние
    var settings = container.read(organizationSearchSettingsProvider);
    expect(settings.scope.type, equals(SearchScopeType.all));
    expect(settings.filters.isEmpty, isTrue);
    expect(settings.scrollOffset, equals(0.0));

    // Установка скролла
    notifier.setScrollOffset(150.0);
    expect(container.read(organizationSearchSettingsProvider).scrollOffset, equals(150.0));

    // Смена scope сбрасывает scrollOffset в 0
    const newScope = SearchScope.folder(folderPath: '/media/workspaces/proj');
    notifier.setScope(newScope);
    settings = container.read(organizationSearchSettingsProvider);
    expect(settings.scope, equals(newScope));
    expect(settings.scrollOffset, equals(0.0));

    // Установка query
    notifier.setQuery('forest');
    expect(container.read(organizationSearchSettingsProvider).filters.query, equals('forest'));

    // Сохранение и восстановление через storage
    await notifier.persist();
    expect(storage.loadSettings(), completes);

    notifier.resetAll();
    expect(container.read(organizationSearchSettingsProvider).scope.type, equals(SearchScopeType.all));

    await notifier.restore();
    expect(container.read(organizationSearchSettingsProvider).scope, equals(newScope));
    expect(container.read(organizationSearchSettingsProvider).filters.query, equals('forest'));
  });

  test('поиск возвращает полный набор файлов со статусом недоступности, даже когда filesProvider отфильтровал отсутствующие', () async {
    // Проверяем исходное состояние filesProvider: в нем виден только 1 файл
    final visibleInFilesProvider = await container.read(filesProvider.future);
    expect(visibleInFilesProvider.length, equals(1));
    expect(visibleInFilesProvider.first.id, equals('f-alpha'));

    // При этом organizationSearchResultsProvider видит ОБА файла из каталога
    final results = await container.read(organizationSearchResultsProvider.future);
    expect(results.length, equals(2));

    final itemA = results.firstWhere((r) => r.id == 'f-alpha');
    expect(itemA.isAccessible, isTrue);

    final itemOffline = results.firstWhere((r) => r.id == 'f-offline');
    expect(itemOffline.isAccessible, isFalse);
  });

  test('organizationSearchResultsProvider фильтрует файлы по источнику и строке поиска', () async {
    // 1. Поиск по query 'forest'
    container.read(organizationSearchSettingsProvider.notifier).setQuery('forest');
    var results = await container.read(organizationSearchResultsProvider.future);
    expect(results.length, equals(1));
    expect(results.first.id, equals('f-alpha'));

    // 2. Фильтр по статусу workflow
    container.read(organizationSearchSettingsProvider.notifier).resetFilters();
    container.read(organizationSearchSettingsProvider.notifier).setFilters(
          const SearchFilterCriteria(
            workflowStatuses: {WorkflowStatus.newFile},
          ),
        );
    results = await container.read(organizationSearchResultsProvider.future);
    expect(results.length, equals(1));
    expect(results.first.id, equals('f-offline'));
    expect(results.first.isAccessible, isFalse);
  });

  test('organizationSearchResultsProvider интегрируется с коллекцией и отбором, сохраняя недоступные файлы', () async {
    // Создаем коллекцию через репозиторий 03 с оффлайн-файлом
    final col = await repo.createCollection('Favorites');
    await repo.addFileToCollection(col.id, sampleFileOffline.id);

    // Переключаем scope на коллекцию
    container.read(organizationSearchSettingsProvider.notifier).setScope(
          SearchScope.collection(collectionId: col.id),
        );

    var results = await container.read(organizationSearchResultsProvider.future);
    // Коллекция не пуста, оффлайн-файл не потерян
    expect(results.length, equals(1));
    expect(results.first.id, equals('f-offline'));
    expect(results.first.isAccessible, isFalse);

    // Проверяем «Отбор»
    await repo.addToSelection(sampleFileA.id);
    container.read(organizationSearchSettingsProvider.notifier).setScope(
          const SearchScope.selection(),
        );

    results = await container.read(organizationSearchResultsProvider.future);
    expect(results.length, equals(1));
    expect(results.first.id, equals('f-alpha'));
    expect(results.first.isAccessible, isTrue);
  });
}

class _TestFilesNotifier extends FilesNotifier {
  _TestFilesNotifier(this.initial);
  final List<AppFile> initial;

  @override
  Future<List<AppFile>> build() async => initial;
}
