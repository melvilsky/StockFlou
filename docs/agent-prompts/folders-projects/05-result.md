# Отчёт о выполнении: Волна 2 (Поиск и фильтрация по источнику)

## 1. Что сделано
- **Модуль `lib/features/organization_search`**:
  - Реализован доменный слой выбора источника (`SearchScope`), критериев фильтрации (`SearchFilterCriteria`), настроек поиска (`OrganizationSearchSettings`) и элементов выдачи (`SearchResultItem`).
  - Поддержаны все явно выбираемые источники:
    - `SearchScope.folder(folderPath, includeSubfolders)`: папка с опциональным включением подпапок.
    - `SearchScope.project(projectId, includeSubfolders)`: проект, объединяющий все связанные с ним папки из API 03 (`projectFoldersProvider`).
    - `SearchScope.collection(collectionId)`: коллекция файлов по упорядоченным идентификаторам из API 03 (`collectionFileIdsProvider`).
    - `SearchScope.selection()`: список файлов «Отбора» из API 03 (`selectionFileIdsProvider`).
    - `SearchScope.all()`: весь каталог файлов.
  - **Поисковый движок (`SearchEngine`)**:
    - Поиск по подстроке без учета регистра по 4 полям: имя файла (`filename`), название (`metadataTitle`), описание (`metadataDescription`), ключевые слова (`metadataKeywords`).
    - Пустой поисковый запрос (или только пробелы) не отсекает файлы и возвращает весь объем выбранного источника.
    - Фильтрация по подтверждаемым свойствам текущей модели `AppFile`:
      - `workflowStatuses`: этапы подготовки (`newFile`, `metadataReady`, `qcFailed`, `readyToUpload`, `uploaded`, `submitted`);
      - `hasKeywords`: флаг наличия ключевых слов (`false` для быстрого фильтра «Без ключей»);
      - `hasTitle`, `hasDescription`: наличие названия/описания;
      - `isEditorial`: флаг или тег `editorial`;
      - `isAiGenerated`: тег `ai_generated`;
      - `mediaCategory`: фото/видео/вектор на основе расширения файла;
      - `isAccessible`: физическая доступность файла на диске по probe-функции.
    - **Особое ограничение по ТЗ**: намеренно не синтезируется статус «Не записано» из `workflowStatus`, так как в `AppFile` отсутствует отдельный достоверный признак синхронизации записи метаданных на диск.
    - **Корректность источников**:
      - При пересечении корней проекта (например, `/root` и `/root/sub`) один и тот же `AppFile.id` дедуплицируется и включается ровно один раз.
      - Разные файлы с одинаковыми именами (например, `/a/img.jpg` и `/b/img.jpg`) считаются независимыми и оба сохраняются в выдаче.
      - Недоступность носителя/диска не очищает коллекцию и не удаляет членство: файлы возвращаются с флагом `isAccessible: false`.
    - **Неблокирующая проверка доступности (`filterFilesAsync`)**:
      - Проверка физической доступности файлов на диске выполняется асинхронно с ограниченным параллелизмом (пул `Pool(16)`), что предотвращает блокировку основного UI-потока Flutter и исчерпание дескрипторов файлов ОС.
      - Проверка диска вызывается только для файлов, прошедших фильтры метаданных.
      - Сохранен синхронный метод `filterFiles` для простых изолированных тестов.
  - **Разрешение полного каталога файлов (`allCatalogFilesProvider`)**:
    - Существующий `filesProvider` отфильтровывает отсутствующие на диске файлы в `build()`, поэтому для модуля поиска введен тестируемый `allCatalogFilesProvider` на основе `catalogFilesLoaderProvider` (по умолчанию читает полный каталог из базы данных `DatabaseHelper.getAllFiles()`).
    - Сохранена полная реактивность: провайдер подписан на `filesProvider.future` и автоматически перезагружается при любых мутациях каталога.
    - Если диск отключен, коллекция и поиск по-прежнему показывают все файлы со статусом `isAccessible: false`.
  - **Персистентность настроек (`SearchSettingsStorage`)**:
    - Сохраняются только легковесные настройки: выбранный `SearchScope`, `SearchFilterCriteria` и смещение скролла `scrollOffset`.
    - Библиотека файлов не дублируется. Установлен лимит размера сериализации (16 КБ).
    - При смене области поиска (`SearchScope`) позиция скролла автоматически сбрасывается в 0.
    - Состояние редактора никак не затрагивается и не перезаписывается.
  - **Riverpod-провайдеры (`organization_search_providers.dart`)**:
    - `catalogFilesLoaderProvider`: загрузчик полного набора файлов каталога из БД.
    - `allCatalogFilesProvider`: реактивный провайдер полного каталога.
    - `fileAccessibilityProbeProvider`: тестируемая функция проверки доступности файла.
    - `searchSettingsStorageProvider`: хранилище настроек (SharedPreferences / InMemory).
    - `searchEngineProvider`: экземпляр движка поиска.
    - `organizationSearchSettingsProvider`: Notifier для мутаций источника, поисковой строки, фильтров и скролла с поддержкой `persist()` / `restore()`.
    - `organizationSearchResultsProvider`: реактивный провайдер списка `SearchResultItem`, автоматически пересчитывающий выдачу при смене настроек, каталога файлов или состава папок/коллекций.
- **Тесты (`test/organization_search/`)**:
  - `search_engine_test.dart` (18 тестов): проверка всех областей поиска, пересекающихся корней, одинаковых имен, пустого запроса, поиска по полям, недоступного диска, фильтра «Без ключей», AI и Editorial, а также неблокирующего `filterFilesAsync` с пулом.
  - `search_settings_test.dart` (5 тестов): сериализация, десериализация, лимит размера payload, сохранение в SharedPreferences и InMemory.
  - `organization_search_providers_test.dart` (4 теста): Riverpod-провайдеры, интеграция с коллекциями и отбором, а также проверка сохранения полного набора файлов со статусом недоступности при отфильтрованном рантайм-поднаборе в `filesProvider`.

---

## 2. Точные пути созданных файлов
- `lib/features/organization_search/domain/search_scope.dart`
- `lib/features/organization_search/domain/search_filter_criteria.dart`
- `lib/features/organization_search/domain/search_result_item.dart`
- `lib/features/organization_search/domain/search_settings.dart`
- `lib/features/organization_search/domain/search_engine.dart`
- `lib/features/organization_search/data/search_settings_storage.dart`
- `lib/features/organization_search/application/organization_search_providers.dart`
- `test/organization_search/search_engine_test.dart`
- `test/organization_search/search_settings_test.dart`
- `test/organization_search/organization_search_providers_test.dart`
- `docs/agent-prompts/folders-projects/05-result.md`

---

## 3. Публичные контракты для следующей задачи (06 — UI/Интеграция)

Экспортируются из `package:stock_flow/features/organization_search/application/organization_search_providers.dart`:

### 3.1. Модели и типы
```dart
enum SearchScopeType { folder, project, collection, selection, all }

class SearchScope {
  const SearchScope.folder({required String folderPath, bool includeSubfolders = false});
  const SearchScope.project({required String projectId, bool includeSubfolders = false});
  const SearchScope.collection({required String collectionId});
  const SearchScope.selection();
  const SearchScope.all();

  final SearchScopeType type;
  final String targetId;
  final bool includeSubfolders;
}

enum MediaCategoryFilter { image, video, vector }

class SearchFilterCriteria {
  const SearchFilterCriteria({
    this.query = '',
    this.workflowStatuses,
    this.hasKeywords,
    this.hasTitle,
    this.hasDescription,
    this.isEditorial,
    this.isAiGenerated,
    this.mediaCategory,
    this.isAccessible,
  });

  final String query;
  final Set<WorkflowStatus>? workflowStatuses;
  final bool? hasKeywords;
  final bool? hasTitle;
  final bool? hasDescription;
  final bool? isEditorial;
  final bool? isAiGenerated;
  final MediaCategoryFilter? mediaCategory;
  final bool? isAccessible;
}

class SearchResultItem {
  final AppFile file;
  final bool isAccessible;
  final String? sourcePath;

  String get id => file.id;
  String get filename => file.filename;
  String get path => file.path;
}

class OrganizationSearchSettings {
  final SearchScope scope;
  final SearchFilterCriteria filters;
  final double scrollOffset;
}
```

### 3.2. Riverpod-провайдеры для UI задачи 06
1. **`organizationSearchSettingsProvider`**:
   `NotifierProvider<OrganizationSearchSettingsNotifier, OrganizationSearchSettings>`
   - `void setScope(SearchScope scope)`: переключение источника (автоматически сбрасывает `scrollOffset` в 0).
   - `void setQuery(String query)`: ввод поисковой строки.
   - `void setFilters(SearchFilterCriteria filters)`: установка фильтров.
   - `void updateFilters(SearchFilterCriteria Function(SearchFilterCriteria current) updater)`: точечное обновление.
   - `void setScrollOffset(double offset)`: запоминание позиции прокрутки.
   - `void resetFilters()`: сброс фильтров и строки поиска без смены источника.
   - `void resetAll()`: полный сброс.
   - `Future<void> persist()`: сохранение в SharedPreferences.
   - `Future<void> restore()`: восстановление сохраненного состояния.

2. **`organizationSearchResultsProvider`**:
   `FutureProvider<List<SearchResultItem>>`
   - Возвращает актуальный отфильтрованный список файлов для отображения в сетке/таблице.
   - Не блокирует UI поток (асинхронный probe с `Pool(16)`).
   - Сохраняет все файлы из базы данных (даже если диск сейчас оффлайн) с флагом `isAccessible: false`.
   - Автоматически обновляется при любых мутациях каталога файлов или структуры проектов/коллекций/отбора.
   - Не трогает и не сбрасывает выделение материалов в редакторе (`selectedFilesProvider` и т.д.).

---

## 4. Команды и реальные результаты проверок

### 4.1. Статический анализ Dart
Команда: `dart analyze lib/features/organization_search/ test/organization_search/`
Результат:
```
Analyzing organization_search, organization_search...
No issues found!
```

### 4.2. Модульные и интеграционные тесты поиска
Команда: `flutter test test/organization_search/`
Результат:
```
00:00 +27: All tests passed!
```
Все 27 тестов модуля поиска пройдены успешно:
- 18 тестов `SearchEngine`: источники, подпапки, пересечение папок, одинаковые имена, пустой запрос, полнотекстовый поиск, доступность носителей, фильтры свойств, пул асинхронного `filterFilesAsync`.
- 5 тестов `search_settings`: сериализация, десериализация, лимит размера, SharedPreferences и InMemory хранилища.
- 4 теста `organization_search_providers`: Riverpod-провайдеры, реактивность, связка с коллекциями и отбором, выдача оффлайн-файлов при фильтрации в `filesProvider`.

### 4.3. Регрессионная проверка связки с задачей 03
Команда: `flutter test test/organization/ test/organization_search/`
Результат:
```
00:00 +43: All tests passed!
```
Все 43 теста связки модуля организации и поиска пройдены успешно.

---

## 5. Ограничения (shortcut)
- `shortcut: no reliable embedded/written-to-disk flag exists in AppFile or WorkflowStatus`: в модели `AppFile` отсутствует поле подтверждения физической синхронизации метаданных с диском; фильтр «Не записано» не выдумывался и не выводился из `WorkflowStatus`.
- `shortcut: search query uses substring match on metadata fields`: текстовый поиск использует регистронезависимое вхождение подстроки без полнотекстового индекса SQLite FTS или морфологии.
- `shortcut: maxSerializedBytes = 16KB`: размер сериализованных настроек поиска ограничен 16 КБ для защиты от раздувания SharedPreferences.
