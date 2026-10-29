# Отчёт о выполнении: Волна 1 (Локальное хранение проектов, коллекций и «Отбора»)

## 1. Что сделано
- **Схема SQLite (v7) и DatabaseHelper**:
  - Реализован инкремент версии БД с 6 до 7 в `lib/core/database/database_helper.dart`.
  - Добавлены таблицы `projects`, `project_folders`, `collections`, `collection_items`, `selection_items` с индексами.
  - Реализована безопасная процедура резервного копирования до миграции через команду SQLite `VACUUM INTO '<dbPath>.bak-v<version>'` с последующей верификацией бэкапа (`PRAGMA integrity_check` == `'ok'` и проверка `PRAGMA user_version`). Это гарантирует корректную фиксацию незакоммиченного/активного WAL-журнала без наивного файлового копирования.
  - Устранена гонка и параллельное создание соединений/бэкапов через SingleFlight Future в геттере `DatabaseHelper.database`.
  - Метод `DatabaseHelper.deleteFile` переведен на транзакцию с аргументом `txn` (исключен риск deadlock и типовых несоответствий `sqflite`), обеспечивая каскадное удаление ссылок на файл из `collection_items` и `selection_items` без удаления коллекций, других файлов и истории `upload_jobs`.
  - Добавлен конструктор `DatabaseHelper.forTest(directoryPath)` для изолированного тестирования без обращения к пользовательской БД.
- **Доменный слой (`lib/features/organization/domain/`)**:
  - `Project`: модель проекта со стабильным UUID, непустым именем, флагами `pinned`, `archived`, порядком `sortOrder`, таймстемпами `createdAt`, `updatedAt`.
  - `Collection`: модель именованной коллекции ссылок на `AppFile.id` со стабильным UUID, порядком `sortOrder` и таймстемпами.
  - `OrganizationNotFoundException`: ошибка при обращении к несуществующему проекту или коллекции.
- **Слой данных (`lib/features/organization/data/`)**:
  - `OrganizationRepository`: реализация репозитория поверх `DatabaseHelper` с валидацией входных данных (непустые имена), детерминированной сортировкой, транзакциями с `txn` и поддержкой связи many-to-many между проектами и папками.
  - Обеспечено, что удаление проекта/коллекции/членства никогда не затрагивает физические файлы, записи таблицы `files`, метаданные и историю `upload_jobs`.
- **Слой приложения (`lib/features/organization/application/`)**:
  - Экспортированы Riverpod-провайдеры для использования в задачах 04, 05, 06:
    - `organizationRepositoryProvider`
    - `projectsProvider` (список проектов + методы мутации)
    - `projectFoldersProvider(projectId)` (список путей папок проекта + добавление/удаление)
    - `collectionsProvider` (список коллекций + методы мутации)
    - `collectionFileIdsProvider(collectionId)` (список `AppFile.id` коллекции в детерминированном порядке + добавление/удаление/очистка)
    - `selectionFileIdsProvider` (список `AppFile.id` «Отбора», сохраняемый между сессиями до явной очистки + добавление/удаление/очистка).
- **Тесты (`test/organization/`)**:
  - `database_migration_test.dart` (4 теста): миграция чистой БД, миграция v6 в v7 с активным WAL, проверка бэкапа и целостности, защита от параллельного открытия, каскадное удаление ссылок при `deleteFile`.
  - `organization_repository_test.dart` (9 тестов): валидация имен, создание/переименование/закрепление/архивация/сортировка проектов, many-to-many папок проектов, коллекции и их ссылки, дедупликация, детерминированный порядок, устойчивый «Отбор».
  - `organization_providers_test.dart` (3 теста): проверка интеграции всех Riverpod-провайдеров через `ProviderContainer`.

---

## 2. Точные пути созданных и изменённых файлов
- `lib/core/database/database_helper.dart` (изменён)
- `lib/features/organization/domain/organization_models.dart` (создан)
- `lib/features/organization/data/db_organization_repository.dart` (создан)
- `lib/features/organization/application/organization_providers.dart` (создан)
- `test/organization/database_migration_test.dart` (создан)
- `test/organization/organization_repository_test.dart` (создан)
- `test/organization/organization_providers_test.dart` (создан)
- `docs/agent-prompts/folders-projects/03-result.md` (создан)

---

## 3. Схема базы данных (SQLite v7)
```sql
CREATE TABLE IF NOT EXISTS projects (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  pinned INTEGER NOT NULL DEFAULT 0,
  archived INTEGER NOT NULL DEFAULT 0,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS project_folders (
  project_id TEXT NOT NULL,
  folder_path TEXT NOT NULL,
  added_at INTEGER NOT NULL,
  PRIMARY KEY (project_id, folder_path)
);

CREATE TABLE IF NOT EXISTS collections (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS collection_items (
  collection_id TEXT NOT NULL,
  app_file_id TEXT NOT NULL,
  position INTEGER NOT NULL,
  added_at INTEGER NOT NULL,
  PRIMARY KEY (collection_id, app_file_id)
);
CREATE INDEX IF NOT EXISTS idx_collection_items_position 
  ON collection_items(collection_id, position);

CREATE TABLE IF NOT EXISTS selection_items (
  app_file_id TEXT PRIMARY KEY,
  position INTEGER NOT NULL
);
```

---

## 4. Публичные контракты для следующих задач (04, 05, 06)

Экспортируются из `package:stock_flow/features/organization/application/organization_providers.dart`:

### 4.1. Сущности и исключения
```dart
class Project {
  final String id;
  final String name;
  final bool pinned;
  final bool archived;
  final int sortOrder;
  final int createdAt;
  final int updatedAt;
}

class Collection {
  final String id;
  final String name;
  final int sortOrder;
  final int createdAt;
  final int updatedAt;
}

class OrganizationNotFoundException implements Exception {
  final String entityKind;
  final String id;
}
```

### 4.2. Riverpod провайдеры
1. `organizationRepositoryProvider`: доступ к экземпляру `OrganizationRepository`.
2. `projectsProvider`: `AsyncNotifierProvider<ProjectsNotifier, List<Project>>`
   - `Future<Project> createProject(String name)`
   - `Future<Project> renameProject(String id, String name)`
   - `Future<void> setProjectPinned(String id, {required bool pinned})`
   - `Future<void> setProjectArchived(String id, {required bool archived})`
   - `Future<void> reorderProjects(List<String> orderedIds)`
   - `Future<void> deleteProject(String id)`
3. `projectFoldersProvider(String projectId)`: `AsyncNotifierProvider.family<ProjectFoldersNotifier, List<String>, String>`
   - `Future<void> addFolder(String folderPath)`
   - `Future<void> removeFolder(String folderPath)`
4. `collectionsProvider`: `AsyncNotifierProvider<CollectionsNotifier, List<Collection>>`
   - `Future<Collection> createCollection(String name)`
   - `Future<Collection> renameCollection(String id, String name)`
   - `Future<void> deleteCollection(String id)`
5. `collectionFileIdsProvider(String collectionId)`: `AsyncNotifierProvider.family<CollectionFileIdsNotifier, List<String>, String>`
   - `Future<void> addFile(String appFileId)`
   - `Future<void> removeFile(String appFileId)`
   - `Future<void> clear()`
6. `selectionFileIdsProvider`: `AsyncNotifierProvider<SelectionFileIdsNotifier, List<String>>`
   - `Future<void> addFile(String appFileId)`
   - `Future<void> removeFile(String appFileId)`
   - `Future<void> clear()`

### 4.3. Модель ошибок
- Пустое или состоящее только из пробелов имя проекта или коллекции выбрасывает `ArgumentError`.
- Попытка обновления/удаления несуществующей сущности по `id` выбрасывает `OrganizationNotFoundException`.
- Добавление дубликатов папок или файлов безопасно игнорируется (`ConflictAlgorithm.ignore`), не вызывая исключений.

---

## 5. Контракт регистрации локальных файлов в каталоге (для задачи интеграции)
В соответствии с требованиями и AGENTS.md второй каталог не создается. Для регистрации файлов без записи:
1. Коллекции и «Отбор» оперируют только постоянным строковым идентификатором `AppFile.id`.
2. Если локальный файл еще не зарегистрирован в таблице `files`, задача интеграции (волна 04/05) должна вызвать регистрацию через существующий `filesProvider.notifier.addFile(file)` или пакетный метод каталога:
   ```dart
   // Контракт регистрации файла перед добавлением в коллекцию:
   final file = AppFile(
     id: const Uuid().v4(),
     path: absoluteFilePath,
     filename: p.basename(absoluteFilePath),
     createdAt: DateTime.now().millisecondsSinceEpoch,
   );
   await ref.read(filesProvider.notifier).addFile(file);
   // После этого AppFile.id готов для добавления в коллекцию или «Отбор»:
   await ref.read(collectionFileIdsProvider(collectionId).notifier).addFile(file.id);
   ```
3. Таблица `files` выступает единственным источником правды для файлов и их метаданных. При удалении файла из каталога (`DatabaseHelper.deleteFile`), ссылки на него в коллекциях и отборе удаляются автоматически без повреждения коллекций.

---

## 6. Команды и реальные результаты проверок

### 6.1. Статический анализ Dart:
Команда: `dart analyze lib/core/database/ lib/features/organization/ test/organization/`
Результат:
```
Analyzing database, organization, organization...
No issues found!
```

### 6.2. Тесты модуля организации:
Команда: `flutter test test/organization/`
Результат:
```
00:00 +16: All tests passed!
```
Все 16 тестов успешно пройдены:
- 4 теста миграции БД, WAL, integrity check и каскадного удаления ссылок.
- 9 тестов репозитория проектов, папок, коллекций и отбора.
- 3 теста Riverpod провайдеров.

### 6.3. Полный регрессионный прогон тестов проекта:
Команда: `flutter test`
Результат:
```
00:08 +195: All tests passed!
```
Все 195 тестов проекта прошли успешно без регрессий.

---

## 7. Ограничения (shortcut)
- `shortcut: projects and collections do not emit streaming changes via DB triggers, state invalidation is managed explicitly via Riverpod Notifiers`: подходит для текущей десктопной однопользовательской архитектуры; при переходе на фоновые независимые процессы может потребоваться SQLite table listener.
- `shortcut: project_folders stores raw folder paths without security bookmarks`: сами bookmarks и права доступа продолжают централизованно управляться сервисом рабочих областей (`WorkspacesState`), проект является чисто логической группировкой.
