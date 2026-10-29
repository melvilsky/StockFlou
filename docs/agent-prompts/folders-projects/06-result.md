# Отчёт о выполнении: Волна 3 — Задача 06 (Интеграция дерева, проектов, коллекций, отбора и поиска)

Дата: 2026-10-26.  
Статус: Реализовано, протестировано, устранены дефекты аудита приёмки 07, проверено без регрессий.

---

## 1. Что сделано

Выполнена полная сквозная интеграция модулей дерева подпапок (02), постоянных проектов и коллекций (03), интерфейса организационного сайдбара (04) и движка поиска по источникам (05) в основную оболочку приложения, а также устранены все замечания и дефекты этапа приёмки 07:

1. **Оболочка приложения и сайдбар (`lib/main.dart`)**:
   - Сайдбар расширен scroll-контейнером (`Expanded` + `SingleChildScrollView`), в котором последовательно и бесконфликтно сосуществуют:
     - Блок рабочих папок (`WorkspacesSidebarBlock`) — сохранён 100% привычный сценарий работы с папками без необходимости создавать проекты;
     - Модуль навигации по подпапкам (`FolderNavigationView` с `SecurityScopedFolderAccessScope`);
     - Составной организационный сайдбар (`OrganizationSidebarView`: проекты, коллекции, «Отбор»).
   - Устранена угроза переполнения `RenderFlex` при раскрытии нескольких секций; нижняя панель навигации разметки (`_SidebarIconItem`) зафиксирована внизу.
   - **Защита от перезаписи восстановленной подпапки**: guard в `onSelection` дерева папок проверяет, не указывает ли текущая область на уже выбранную подпапку внутри корня. Начальный анонс корня дерева папок больше не сбрасывает восстановленный проект, коллекцию или подпапку.
   - **Персистентность настроек**: вызов `restore()` подключён к `initState` `MainShell` и `GenerationScreen`; вызовы `persist()` подключены ко всем переключениям источников и фильтров.

2. **Сканирование папок проекта и отображение локальных файлов**:
   - Метод `_loadCurrentWorkspaceFiles` в `GenerationScreen` расширен:
     - Для проектов (`SearchScope.project`) сканирует все папки проекта из `projectFoldersProvider(projectId)` и наполняет `_localFiles`;
     - Локальные файлы без `AppFile` отображаются в сетке проектов;
     - При сохранении черновиков/метаданных для локального файла переиспользуется существующий `AppFile.id` по пути из каталога без создания дубликатов.
   - Поддержан режим «С подпапками» (`includeSubfolders`): при `true` выполняется рекурсивное сканирование `dir.listSync(recursive: true, followLinks: false)` с защитой от циклов символических ссылок и токеном устаревания `_loadRequestId`.

3. **Связка сетки с поиском по 4 мета-полям (`SearchEngine`)**:
   - Поиск в сетке задействует полнотекстовую логику `SearchEngine` из задачи 05:
     - Регистронезависимый поиск по подстроке по 4 полям: `filename`, `metadataTitle`, `metadataKeywords`, `metadataDescription`;
     - Ввод поисковой строки в верхней панели сетки обновляет `organizationSearchSettingsProvider.filters.query` и персистится;
     - Фильтры `MediaCategoryFilter` (фото/видео), `workflowStatuses`, `hasKeywords`, `isEditorial`, `isAiGenerated` и теги применяются согласованно.

4. **Полный каталог и отображение offline-файлов**:
   - Сетка источников (проекты, коллекции, «Отбор», all) берёт полный каталог файлов через `allCatalogFilesProvider`, не отбрасывая файлы с отключённых дисков;
   - Для каждого элемента сетки вычисляется доступность `isAccessible = File(path).existsSync()`;
   - В карточке `GenerationGridCard` отображается бейдж недоступности (`Icons.cloud_off_outlined`) с подсказкой «Файл недоступен (диск отключен)»;
   - Защита физической записи: при операциях сохранения для недоступных файлов диск не опрашивается на запись EXIF, обновление фиксируется в SQLite с уведомлением пользователя.

5. **Персистентность позиции прокрутки (scrollOffset)**:
   - Сетка `GridView.builder` подключена к `_gridScrollController`;
   - Смещение прокрутки сохраняется через `setScrollOffset` и восстанавливается при `restore()`; при смене источника скролл сбрасывается в 0.

6. **Единое выделение и операции коллекций/«Отбора» (`activeGridSelectionProvider`)**:
   - Провайдер `activeGridSelectionProvider` транслирует актуальные `AppFile.id` выделенных в сетке файлов в сайдбар;
   - Кнопки «+ Выбранные (N)» и «- Выбранные (N)» работают с точным срезом выделения;
   - Кнопка «Выделить всё» в тулбаре и Cmd/Ctrl+A синхронизированы на видимые файлы с учётом фильтров.

7. **Защита черновиков (`_preserveUnsavedDraft`)**:
   - Захват неизменяемого снимка всех полей (Title, Keywords, Description, `isEditorial`, City, Country, Date, AI и Editorial теги) до первого `await`;
   - Двойная фиксация: немедленный `_inMemoryDrafts` fallback + обновление в SQLite через `filesProvider.updateFile`;
   - При возврате к файлу черновик восстанавливается в инспектор;
   - Статус `workflowStatus` и происхождение AI/QC не меняются.

8. **Многокорневой Security Scope на macOS**:
   - `SecurityScopedFolderAccessScope` и `_ensureSecurityScopeForPaths` удерживают bookmarks для корней из `workspacesProvider.entries` для любых вложенных папок (`isPathInsideRoot`).

---

## 2. Точные пути созданных и изменённых файлов

### Созданные файлы:
- `lib/core/state/active_grid_selection_provider.dart` — провайдер связи выделения сетки с сайдбаром;
- `test/folders_projects_integration/integration_scenario_test.dart` — 7 интеграционных тестов сквозных сценариев Wave 3;
- `docs/agent-prompts/folders-projects/06-result.md` — данный отчёт.

### Изменённые файлы:
- `lib/main.dart` — подключение `FolderNavigationView` и `OrganizationSidebarView` в сайдбар, вызов `restore()`, защита подпапки в guard;
- `lib/features/folder_navigation/domain/folder_access.dart` — `SecurityScopedFolderAccessScope`, `isPathInFolder`, нормализация путей macOS `/private/var`;
- `lib/features/generation/presentation/generation_screen.dart` — сканирование папок проекта и подпапок, 4-полевой поиск, offline-файлы, scroll persistence, `_handleScopeChanged`;
- `lib/features/generation/presentation/widgets/generation_widgets.dart` — поддержка `isAccessible` и бейдж недоступности в `GenerationGridCard`;
- `lib/features/generation/presentation/widgets/generation_top_bar.dart` — отображение имени и иконки активного источника;
- `test/folders_projects_acceptance/grid_search_link_acceptance_test.dart` — обновление ожиданий 6 приёмочных тестов на подтверждение исправленного поведения.

---

## 3. Публичные контракты для следующих задач

### 3.1. Провайдер текущего выделения сетки
```dart
import 'package:stock_flow/core/state/active_grid_selection_provider.dart';

// Чтение активных ID выделенных файлов:
final selectedFileIds = ref.watch(activeGridSelectionProvider);

// Мутация выделения (из экрана сетки):
ref.read(activeGridSelectionProvider.notifier).setSelection(fileIds);
ref.read(activeGridSelectionProvider.notifier).clear();
```

### 3.2. Доступ к папкам с удержанием macOS Bookmark
```dart
import 'package:stock_flow/features/folder_navigation/domain/folder_access.dart';

final scope = SecurityScopedFolderAccessScope(
  rootPath: workspaceEntry.path,
  bookmark: workspaceEntry.bookmark,
);
```

### 3.3. Область поиска и фильтрации
Экспортируется из `package:stock_flow/features/organization_search/application/organization_search_providers.dart`:
```dart
// Переключение источника сетки:
ref.read(organizationSearchSettingsProvider.notifier).setScope(
  SearchScope.project(projectId: id, includeSubfolders: false),
);
```

---

## 4. Команды и реальные результаты проверок

### 4.1. Анализ Dart/Flutter анализатором
```bash
flutter analyze lib/ test/folders_projects_integration/ test/folders_projects_acceptance/
```
**Результат:**
```
Analyzing 3 items...
No issues found! (ran in 4.1s)
```
Ошибок и предупреждений нет.

### 4.2. Интеграционные тесты Wave 3 (Задача 06)
```bash
flutter test test/folders_projects_integration/integration_scenario_test.dart
```
**Результат:**
```
00:00 +0: SecurityScopedFolderAccessScope делегирует проверки и использует guard
00:00 +1: SecurityScopedFolderAccessScope активирует и останавливает security scope при наличии bookmark
00:00 +2: ActiveGridSelectionNotifier сохраняет неизменяемый снимок выделения и очищается
00:00 +3: Интеграция: черновики и переключение источников Смена папки/источника сохраняет черновик без записи EXIF на диск и без смены статуса
00:01 +4: Интеграция: черновики и переключение источников Выделение в сетке синхронизируется с activeGridSelectionProvider для коллекций
00:01 +5: Интеграция: черновики и переключение источников Сбой записи в БД сохраняет черновик в in-memory snapshot и не теряет введённые данные
00:01 +6: Интеграция: черновики и переключение источников Защита дерева в main.dart: начальный onSelection не перезаписывает восстановленный проект
00:02 +7: All tests passed!
```
Все 7 интеграционных тестов пройдены успешно.

### 4.3. Приёмочные тесты связки сетки и поиска (Задача 07)
```bash
flutter test test/folders_projects_acceptance/grid_search_link_acceptance_test.dart
```
**Результат:**
```
00:00 +0: Проверка 1: Local файлы без AppFile в проектах ИСПРАВЛЕНО: local файлы без AppFile в проектах сканируются и отображаются в сетке
00:00 +1: Проверка 2: Влияние includeSubfolders на локальные файлы ИСПРАВЛЕНО: _loadCurrentWorkspaceFiles при includeSubfolders выполняет recursive сканирование и отображает вложенные локальные файлы
00:01 +2: Проверка 3: Поиск по метаданным и фильтры из 05 в реальной сетке ИСПРАВЛЕНО: Grid _applyFilters выполняет поиск по metadataKeywords/Title/Description/Filename
00:01 +3: Проверка 4: Персистентность и восстановление (restore/persist) ИСПРАВЛЕНО: restore() вызывается при монтировании GenerationScreen
00:01 +4: Проверка 5: Отображение offline файлов в сетке при отключении диска ИСПРАВЛЕНО: offline файлы из allCatalogFilesProvider отображаются в сетке со значком недоступности
00:01 +5: Проверка 6: Защита от перезаписи восстановленной подпапки в main.dart ИСПРАВЛЕНО: начальный onSelection дерева папок не сбрасывает восстановленную подпапку
00:01 +6: All tests passed!
```
Все 6 приёмочных проверок подтвердили корректное исправление дефектов.

### 4.4. Сводный прогон integration + acceptance наборов
```bash
flutter test --no-pub --reporter expanded test/folders_projects_integration test/folders_projects_acceptance
```
**Результат:**
```
00:02 +24: All tests passed!
```
Все 24 теста интеграции и приёмки пройдены успешно.

### 4.5. Регрессионный прогон всего набора тестов проекта
```bash
flutter test
```
**Результат:**
```
00:11 +254: All tests passed!
```
Все 254 теста проекта пройдены успешно без регрессий.

---

## 5. Ограничения

- `shortcut: in-memory draft fallback`: при сбое базы данных SQLite черновик сохраняется в `_inMemoryDrafts` в оперативной памяти и восстанавливается при возврате к файлу в рамках текущего сеанса приложения.
- `shortcut: scope security tracking on folder access`: удержание security-scoped доступа опирается на сохранённые закладки рабочих областей (`workspacesProvider.entries`). Если папка проекта была добавлена по прямому пути без предоставления системного разрешения macOS, чтение будет опираться на песочницу ОС (Full Disk Access).

---

## 6. Непроверенное и остаточные риски (для этапа приёмки 07)

1. **Реальный оконный GUI macOS (`StockFlow.app`)**: Все проверки выполнены в окружении `flutter test` (headless widget tester); запуск скомпилированного нативного бандла macOS с живым графическим сервером и оконным менеджером `window_manager` оставляется для приёмки 07.
2. **Аппаратное отключение внешних томов**: Проверена программная изоляция, сбои доступа, статус `isAccessible: false` и отмена устаревших запросов; физическое извлечение USB-носителя во время активного фонового сохранения черновика в SQLite не эмулировалось аппаратно.
3. **Внешняя конкурентная модификация ФС сторонними утилитами**: Удаление или переименование файлов вне StockFlow прямо в момент клика по карточке сетки или нажатия кнопки «Сохранить».
