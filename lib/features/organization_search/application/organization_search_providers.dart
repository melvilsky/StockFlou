import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/state/files_provider.dart';
import '../../organization/application/organization_providers.dart';
import '../data/search_settings_storage.dart';
import '../domain/search_engine.dart';
import '../domain/search_filter_criteria.dart';
import '../domain/search_result_item.dart';
import '../domain/search_scope.dart';
import '../domain/search_settings.dart';
import '../../../models/app_file.dart';

export '../data/search_settings_storage.dart';
export '../domain/search_engine.dart';
export '../domain/search_filter_criteria.dart';
export '../domain/search_result_item.dart';
export '../domain/search_scope.dart';
export '../domain/search_settings.dart';

/// Провайдер хранилища настроек поиска.
final searchSettingsStorageProvider = Provider<SearchSettingsStorage>((ref) {
  return SharedPreferencesSearchSettingsStorage();
});

/// Провайдер движка фильтрации и разрешения файлов.
final searchEngineProvider = Provider<SearchEngine>((ref) {
  return const SearchEngine();
});

/// Загрузчик полного каталога файлов из БД (включая файлы на временно отключенных дисках).
///
/// Семантика [filesProvider] отфильтровывает отсутствующие файлы в рантайме,
/// однако поиск и членство в коллекциях должны сохранять все зарегистрированные файлы
/// каталога с явным признаком [SearchResultItem.isAccessible].
final catalogFilesLoaderProvider =
    Provider<Future<List<AppFile>> Function()>((ref) {
  return () => DatabaseHelper.instance.getAllFiles();
});

/// Провайдер полного набора файлов каталога для модуля поиска.
///
/// Реагирует на любые изменения в [filesProvider] (добавление, обновление, удаление),
/// но загружает полный набор из базы данных через [catalogFilesLoaderProvider].
final allCatalogFilesProvider = FutureProvider<List<AppFile>>((ref) async {
  // Подписываемся на реактивные изменения состояния файлов и дожидаемся готовности
  await ref.watch(filesProvider.future);
  final loader = ref.watch(catalogFilesLoaderProvider);
  return loader();
});

/// Провайдер функции проверки доступности файла на диске.
/// По умолчанию использует неблокирующий [File.exists].
final fileAccessibilityProbeProvider =
    Provider<FileAccessibilityProbe>((ref) {
  return (path) => File(path).exists();
});

/// Нотификатор настроек поиска, фильтрации и положения скролла.
///
/// Управляет текущей областью поиска, фильтрами и смещением прокрутки.
/// Сохраняет только легковесные настройки без дублирования каталога файлов.
/// Не затрагивает и не сбрасывает состояние редактора.
class OrganizationSearchSettingsNotifier
    extends Notifier<OrganizationSearchSettings> {
  @override
  OrganizationSearchSettings build() {
    return const OrganizationSearchSettings();
  }

  /// Устанавливает область поиска. При смене источника сбрасывает scrollOffset в 0.
  void setScope(SearchScope scope) {
    if (state.scope == scope) return;
    state = state.copyWith(
      scope: scope,
      scrollOffset: 0.0,
    );
  }

  /// Устанавливает строку поиска по названию, имени, описанию или ключам.
  void setQuery(String query) {
    if (state.filters.query == query) return;
    state = state.copyWith(
      filters: state.filters.copyWith(query: query),
    );
  }

  /// Заменяет критерии фильтрации.
  void setFilters(SearchFilterCriteria filters) {
    if (state.filters == filters) return;
    state = state.copyWith(filters: filters);
  }

  /// Атомарно обновляет фильтры через функцию-модификатор.
  void updateFilters(
    SearchFilterCriteria Function(SearchFilterCriteria current) updater,
  ) {
    final updated = updater(state.filters);
    if (state.filters == updated) return;
    state = state.copyWith(filters: updated);
  }

  /// Сохраняет позицию прокрутки списка выдачи.
  void setScrollOffset(double offset) {
    final sanitized = offset < 0 ? 0.0 : offset;
    if (state.scrollOffset == sanitized) return;
    state = state.copyWith(scrollOffset: sanitized);
  }

  /// Сбрасывает фильтры и строку поиска к значениям по умолчанию,
  /// сохраняя выбранную область поиска.
  void resetFilters() {
    state = state.copyWith(
      filters: const SearchFilterCriteria(),
      scrollOffset: 0.0,
    );
  }

  /// Сбрасывает все настройки, включая область поиска.
  void resetAll() {
    state = const OrganizationSearchSettings();
  }

  /// Сохраняет текущие настройки в персистентное хранилище.
  Future<void> persist() async {
    final storage = ref.read(searchSettingsStorageProvider);
    await storage.saveSettings(state);
  }

  /// Загружает сохраненные настройки из персистентного хранилища.
  Future<void> restore() async {
    final storage = ref.read(searchSettingsStorageProvider);
    final saved = await storage.loadSettings();
    if (saved != null) {
      state = saved;
    }
  }
}

final organizationSearchSettingsProvider = NotifierProvider<
    OrganizationSearchSettingsNotifier, OrganizationSearchSettings>(() {
  return OrganizationSearchSettingsNotifier();
});

/// Провайдер результатов поиска и фильтрации.
///
/// Реактивно пересчитывает выдачу при изменении:
/// - настроек поиска ([organizationSearchSettingsProvider])
/// - каталога файлов ([filesProvider] -> [allCatalogFilesProvider])
/// - структуры папок проекта ([projectFoldersProvider])
/// - состава коллекции ([collectionFileIdsProvider])
/// - состава «Отбора» ([selectionFileIdsProvider])
///
/// Важно:
/// 1. Не блокирует UI поток Flutter: проверка доступности выполняется асинхронно
///    через пул параллелизма.
/// 2. Возвращает полный набор файлов из базы данных (даже если физический носитель
///    сейчас отключен), выставляя [SearchResultItem.isAccessible] = false.
/// 3. Никак не модифицирует состояние редактора и не вмешивается в выбор
///    файлов пользователя в других экранах.
final organizationSearchResultsProvider =
    FutureProvider<List<SearchResultItem>>((ref) async {
  final settings = ref.watch(organizationSearchSettingsProvider);
  final engine = ref.watch(searchEngineProvider);
  final probe = ref.watch(fileAccessibilityProbeProvider);

  // Получаем полный список всех зарегистрированных файлов в каталоге
  final allFiles = await ref.watch(allCatalogFilesProvider.future);

  // Регистрируем зависимости для конкретного источника на верхнем уровне провайдера
  List<String> projectFolders = const [];
  List<String> collectionFileIds = const [];
  List<String> selectionFileIds = const [];

  switch (settings.scope.type) {
    case SearchScopeType.project:
      if (settings.scope.projectId.isNotEmpty) {
        projectFolders = await ref.watch(
          projectFoldersProvider(settings.scope.projectId).future,
        );
      }
      break;
    case SearchScopeType.collection:
      if (settings.scope.collectionId.isNotEmpty) {
        collectionFileIds = await ref.watch(
          collectionFileIdsProvider(settings.scope.collectionId).future,
        );
      }
      break;
    case SearchScopeType.selection:
      selectionFileIds = await ref.watch(selectionFileIdsProvider.future);
      break;
    case SearchScopeType.folder:
    case SearchScopeType.all:
      break;
  }

  // Разрешаем файлы для выбранного источника
  final scopeFiles = await engine.resolveFilesForScope(
    scope: settings.scope,
    allFiles: allFiles,
    getProjectFolders: (_) async => projectFolders,
    getCollectionFileIds: (_) async => collectionFileIds,
    getSelectionFileIds: () async => selectionFileIds,
  );

  // Неблокирующая асинхронная фильтрация с ограниченным параллелизмом
  return engine.filterFilesAsync(
    files: scopeFiles,
    criteria: settings.filters,
    fileExistsProbe: probe,
    concurrency: 16,
  );
});
