# Волна 1 — Задача 01: Baseline рабочих папок и выбора материалов

Дата: 2026-10-25 (по часам окружения; зафиксировано от `2026-10-25T23:32+01:00`).
Ветка: `codex/analyze-features-and-create-todo-list`.

## 0. Сфера и границы

- Задача — **только анализ и проверки**, код приложения не изменять.
- Единственный разрешённый для записи файл — данный отчёт.
- **Исходный baseline (работа пользователя и предыдущих задач до текущей волны):**
  Существовавший до волны незакоммиченный рабочий git diff включает:
  - Управление рабочими папками: `lib/core/state/workspaces_provider.dart`, `lib/core/widgets/workspaces_sidebar_block.dart`, `lib/models/workspace_availability.dart`.
  - Метаданные и CSV: `lib/core/services/metadata_service.dart`, `lib/core/services/csv_metadata_service.dart`, `lib/features/generation/presentation/widgets/csv_import_preview_dialog.dart`, `lib/models/csv_import_plan.dart`, `lib/models/file_metadata_result.dart`.
  - Генерация и предпросмотр: `lib/features/generation/presentation/generation_screen.dart`, `lib/features/generation/presentation/video_player_widget.dart`, `lib/features/generation/domain/`.
  - Оболочка, навигация, история: `lib/main.dart`, `lib/core/services/window_config_service.dart`, `lib/features/history/presentation/history_screen.dart`.
  - Существующие тесты в `test/workspaces_persistence/`, `test/metadata_service/`, `test/generation_context/`, `test/generation_ai_origin/`, `test/csv_metadata/`, `test/video_preview/`, `test/widget_test.dart`.
- **Что НЕ входит в исходный baseline (параллельная реализация задач 02 и 03):**
  - `lib/features/folder_navigation/**` (создаётся задачей 02);
  - `lib/features/organization/**` (создаётся задачей 03);
  - изменения `lib/core/database/database_helper.dart` (автор изменений — задача 03: добавление версионирования v7, резервного копирования перед миграцией и `forTest`).
  Этот код появился в рабочей копии прямо во время анализа, находится в незавершённом состоянии и **не оценивается как исходные ошибки**. Проверки baseline отделены от наблюдений за параллельной разработкой.
- Перед анализом использован CodeGraph (`codegraph status`, `query`, `explore`), исходники изучены напрямую.

Инструменты среды: Flutter 3.41.4 (`/opt/homebrew/share/flutter`), exiftool 13.55 (`/opt/homebrew/bin/exiftool`), `codegraph` CLI — доступны и работоспособны.

## 1. Ключевые выводы-гарантии (для задач 02–08)

Зафиксировано по коду исходного baseline и подтверждено существующими тестами:

1. **Старые рабочие папки доступны и без проекта.**
   - Управление рабочими папками в baseline полностью автономно и самодостаточно: их список, порядок и текущий выбор сохраняются в `SharedPreferences` под ключами `workspace_entries`, `workspace_current_path`, `workspace_current_index` (с поддержкой legacy-ключа `workspace_paths`). Механизм не знает и не требует концепции «проектов».
   - Каталог метаданных файлов хранится в единой глобальной базе данных SQLite (`stock_flow_state.db`) через `filesProvider` (`lib/core/state/files_provider.dart`) и `DatabaseHelper`. Метаданные связаны с файлами через пути и устойчивые `AppFile.id`.
   - Отсутствие файла на диске или отсутствие проекта не приводит к удалению записей из БД: метод `_filterExistingFiles` в `files_provider.dart:13-22` лишь фильтрует выдачу для UI («We don't delete from database anymore so that tags and metadata are preserved if the file is ever restored or re-added»).
   - При удалении рабочей папки из списка в `WorkspacesNotifier.removeWorkspace` база данных SQLite вообще не затрагивается. При повторном подключении папки все сохранённые ранее метаданные восстанавливаются в интерфейсе.
2. **Подключение не копирует файлы.**
   - Вызов `WorkspacesNotifier.addWorkspace(path)` (`workspaces_provider.dart:537-589`) выполняет исключительно: нормализацию строки пути, создание macOS security-scoped bookmark, добавление записи в список и сохранение настроек в `SharedPreferences`, после чего запускает асинхронную проверку доступности.
   - Сканирование директории при подключении в UI (`_loadCurrentWorkspaceFiles` / `_pickFile` в `generation_screen.dart:471-507`) делает только `dir.list(recursive: false)` для обнаружения поддерживаемых расширений. Никакого физического копирования или перемещения файлов на диске не происходит.
3. **Удаление из списка не удаляет оригиналы.**
   - Метод `WorkspacesNotifier.removeWorkspace(index)` (`workspaces_provider.dart:591-629`) модифицирует только внутренний список `entries` и карту доступности `availability` в памяти и сохраняет обновлённый список в `SharedPreferences`.
   - Файловые операции удаления (`delete`, `deleteSync` и т.д.) не вызываются. Поведение зафиксировано тестом `testWidgets('Удаление из списка не вызывает операций над файлами')` в `test/workspaces_persistence/workspaces_sidebar_block_test.dart:378`.

## 2. Матрица текущих сценариев baseline

| # | Сценарий | Текущее поведение baseline | Точки входа в коде |
|---|---|---|---|
| 1 | Подключение рабочей папки | Системный диалог выбора папки (`file_selector.getDirectoryPath`) → `addWorkspace(path)`. Нормализация пути через `normalizeWorkspacePath`: пробелы в начале/конце не удаляются (`trim` запрещён), одиночный или кратный `/` нормализуется в `/`, замыкающие слеши удаляются, регистр и симлинки не меняются. На macOS создаётся bookmark (ошибка создания логгируется, но не блокирует добавление). При совпадении пути обновляется bookmark, дубликат не создаётся. Папка сразу становится выбранной (`currentIndex`). Параллельно запускается неблокирующий опрос доступности `_probeAndUpdateAvailability`. | `lib/core/state/workspaces_provider.dart:537-589`, `lib/core/widgets/workspaces_sidebar_block.dart:300-334` |
| 2 | Переключение папки | Клик по элементу списка → `setCurrent(idx)` с немедленным сохранением в prefs. `GenerationScreen` через `ref.listen(workspacesProvider)` отслеживает изменение `currentPath`: вызывает `_loadCurrentWorkspaceFiles()` и **полностью сбрасывает текущее выделение** (`_selectedPaths.clear()`, `_selectedExistingFile = null`, `_selectedLocalInspectorFile = null`). Несохранённые правки в текстовых контроллерах инспектора теряются (выбор обнуляется, контроллеры не коммитятся в БД). | `lib/features/generation/presentation/generation_screen.dart:1898-1909`, `lib/core/state/workspaces_provider.dart:631-638` |
| 3 | Удаление из списка | `removeWorkspace(index)`: удаляет запись из `entries` и отменяет токен проверки доступности. Если удаляется неактивная папка, текущий выбор сохраняется по пути; если активная — индекс смещается (`clamp`). Оригиналы файлов на диске и записи в SQLite не затрагиваются. | `lib/core/state/workspaces_provider.dart:591-629` |
| 4 | Восстановление и устойчивость (перезапуск) | Порядок сохранения: сначала пишется путь (`workspace_current_path`), затем список (`workspace_entries`), затем индекс (`workspace_current_index`), и только в конце удаляется legacy-ключ `workspace_paths`. При загрузке восстанавливается папка по пути, а не по голому числу. Повреждённый JSON не перезаписывается: создаётся бэкап `workspace_entries_corrupt_backup`, выставляется `lastError`, доступна кнопка «Повторить» (`retry()`). Ошибки индекса или частичной записи не приводят к потере списка. | `lib/core/state/workspaces_provider.dart:260-359, 361-415` |
| 5 | macOS bookmarks | Создаются через `macos_secure_bookmarks`. При проверке доступности: `resolveBookmark` → строгая проверка совпадения нормализованного пути (при несовпадении статус `unavailable` с просьбой выбрать папку снова, запись не удаляется) → `startAccessingSecurityScopedResource` → пробное чтение первого элемента (`take(1).drain()`) → `stopAccessingSecurityScopedResource`. В `GenerationScreen` security-scoped доступ для текущей папки удерживается открытым на всё время её активности (`_currentScopedResource`), чтобы работали превью (`Image.file`) и чтение метаданных. | `lib/core/state/workspaces_provider.dart:443-487`, `lib/features/generation/presentation/generation_screen.dart:409-468` |
| 6 | Недоступные диски | Недоступная папка остаётся в списке с индикацией ошибки (красная обводка, иконка `folder_off_outlined`, иконка предупреждения, tooltip с текстом ошибки и подсказкой для VoiceOver/Semantics). Кнопка «Обновить» запускает `recheckAvailability(path: current)`. При успехе вызывается `refreshWorkspaceProvider.trigger()`, при сохранении недоступности — `SnackBar`. Опрос безопасен к race condition: токен проверки (`_probeTokens`) отсекает запоздалые результаты фоновых проверок. | `lib/core/state/workspaces_provider.dart:489-512`, `lib/core/widgets/workspaces_sidebar_block.dart:127-136, 339-377` |
| 7 | Выбор материалов (Selection) | Выделение хранится как `Set<String> _selectedPaths` (по путям файлов), активный элемент — в `_selectedExistingFile` или `_selectedLocalInspectorFile`. Одиночный клик сбрасывает предыдущее и выбирает один элемент; Shift+Click добавляет непрерывный диапазон. Клавиатурное сочетание Cmd/Ctrl+A (`_handleSelectAll`) выбирает все файлы с учётом активных фильтров. Кнопка «Выделить всё» в тулбаре (`GenerationToolsBar.onSelectAll`) выбирает все файлы рабочей области без учёта фильтров (расхождение в baseline). Повторный вызов `_selectAll` снимает выделение, если выделены все. Drag&drop добавляет файлы к выделению. Смена фильтрации или поискового запроса **не сбрасывает** текущее выделение `_selectedPaths`. | `lib/features/generation/presentation/generation_screen.dart:709-809, 1940-1984` |
| 8 | Сохранение метаданных при переходах | Метаданные сохраняются в SQLite через `filesProvider` (`addFile`/`updateFile`). Переключение между разделами приложения (Рабочее пространство, Uploads, Настройки) сохраняет состояние экранов (через `IndexedStack` в `main.dart:199-208`). Одиночное сохранение (`_saveChanges`) записывает данные в БД и в файл (через `MetadataService.writeMetadata` для неподвижных изображений). Пакетное сохранение применяет непустые `batchTitle`/`batchKeywords` ко всем выбранным элементам. Кнопка Save активируется при флаге `_metadataDirty && hasSelection && !isFocusedVideo`. | `lib/features/generation/presentation/generation_screen.dart:1300-1512`, `lib/features/generation/presentation/widgets/generation_tools_bar.dart:63-68` |
| 9 | Параллельность и жизненный цикл | Все операции мутации и чтения настроек сериализованы очередью `_runSynchronized`. Вызовы guarded флагами `_isDisposed` и `_isLive`. Поздний ответ диалога выбора папки после размонтирования сайдбара безопасно отбрасывается. | `lib/core/state/workspaces_provider.dart:246-258`, `test/workspaces_persistence/workspaces_sidebar_block_test.dart:185` |

## 3. Известные исходные дефекты baseline (НЕ будущие регрессии)

Проверено по текущему коду baseline. Данные дефекты уже присутствуют в коде пользователя и не должны приписываться последующим задачам 02–08:

1. **Игнорирование результата записи метаданных вызывающими операциями:**
   В `MetadataService` существует метод `writeMetadataDetailed` (`lib/core/services/metadata_service.dart:39`), возвращающий типизированный `FileMetadataWriteResult`. Однако вызывающий код в `GenerationScreen` (`_generateAI` на строке 985, `_saveChanges` на строках 1398, 1445, 1492) использует булев метод `writeMetadata` и не проверяет возвращаемое значение `bool`, сразу сообщая об успешном сохранении («Изменения сохранены в БД и в файл»).
2. **Преждевременная установка готовности к загрузке:**
   При любом сохранении метаданных или генерации в `GenerationScreen` объекту безусловно присваивается статус `workflowStatus: WorkflowStatus.readyToUpload` (строки 938, 953, 1207, 1224, 1366, 1391, 1439, 1485), минуя этап валидации требований стоков.
3. **Распространение описания активного файла при пакетном сохранении:**
   В `_saveChanges` при множественном выборе (`generation_screen.dart:1350-1353`) поле `metadataDescription` берётся из одиночного контроллера `description` активного файла: если оно не пустое, то неявно записывается во все выбранные файлы серии.
4. **Раздельные структуры данных для локальных и каталогизированных файлов:**
   В `GenerationScreen` файлы, ещё не записанные в БД, хранятся в `_localFiles` (список `File`), а сохранённые — в `filesProvider` (список `AppFile`). Это приводит к дублированию логики фильтрации, отображения и выделения.
5. **Рассинхронизация логики «Выделить всё»:**
   Шорткат Cmd+A (`_handleSelectAll`, строка 709) выделяет только видимые с учётом поисковых и типовых фильтров элементы. Кнопка тулбара (`onSelectAll`, строка 1968) передаёт полный неотфильтрованный список файлов рабочей области.
6. **Потеря несохранённых правок инспектора при смене папки:**
   При смене `currentPath` выделение сбрасывается, но пользователь не предупреждается о наличии несохранённых правок (`_metadataDirty == true`), текст в контроллерах перезаписывается при следующем выборе файла.

**Исправленные пункты из плана (не являются ошибками в текущем baseline):**
- Генерация описаний **не** меняет флаг происхождения «создано ИИ»: `tagsAfterMetadataGeneration` (`lib/features/generation/domain/generation_tags.dart`) сохраняет метку `aiGenerated` нетронутой и регулирует только тег `editorial`.
- Чтение существующих в файле метаданных реализовано (`MetadataService.readMetadata`).

## 4. Перечень и результаты проверок

Все проверки выполнены на временных изолированных данных без изменения оригинальных файлов проекта и пользовательских баз данных.

### 4.1 Автоматические тесты baseline

1. **Набор тестов персистентности и сайдбара рабочих папок:**
   - Команда: `flutter test test/workspaces_persistence/`
   - Реальный вывод:
     ```
     00:01 +42: All tests passed!
     ```
   - Проверено 42 теста (31 модульный тест персистентности и 11 виджет-тестов сайдбара): миграция со старого ключа `workspace_paths`, устойчивость к повреждённому JSON, сохранение порядка записи, предотвращение дубликатов, изоляция файловых операций при удалении, семантика корня `/`, overflow-устойчивость интерфейса.
2. **Набор тестов сервисов метаданных, генерации, CSV и видео:**
   - Команда: `flutter test test/metadata_service/ test/generation_context/ test/generation_ai_origin/ test/csv_metadata/ test/video_preview/`
   - Реальный вывод:
     ```
     00:09 +123: All tests passed!
     ```
   - Проверено 123 теста: парсинг и запись метаданных ExifTool, изоляция AI-тегов, заморозка контекста генерации при асинхронных сдвигах выделения, импорт/экспорт CSV с граничными случаями, логика аудиоплеера в превью видео.
3. **Smoke-тест приложения:**
   - Команда: `flutter test test/widget_test.dart`
   - Реальный вывод:
     ```
     00:00 +1: All tests passed!
     ```
   - Проверен 1 тест запуска корневого виджета.

**Итого автоматических проверок baseline: 166 тестов выполнены, 166 успешно, 0 сбоев.**

### 4.2 Статический анализ кода
- Изучены точки вызова `addWorkspace`, `removeWorkspace`, `setCurrent`, `resolveBookmark`, `startAccessingSecurityScopedResource`, `probeRead`.
- Подтверждено отсутствие вызовов записи/копирования оригинальных файлов при операциях с рабочими областями.

## 5. Обязательные условия совместимости для задач 02–08

Для сохранения работоспособности приложения последующие задачи должны соблюдать следующие инварианты:

### 5.1 Контракты хранения настроек и данных
- **SharedPreferences:** Ключи `workspace_entries` (формат JSON-массива объектов `{path: String, bookmark: String?}`), `workspace_current_path` (String), `workspace_current_index` (int), `workspace_paths` (legacy JSON-массив строк) и `workspace_entries_corrupt_backup` обязаны поддерживаться. Новые форматы должны предусматривать сохранение этих ключей.
- **Нормализация путей:** Алгоритм `normalizeWorkspacePath` не должен подвергаться `trim()` (для сохранения пробелов в именах папок) и не должен разыменовывать симлинки.
- **Порядок записи:** При сохранении настроек путь `workspace_current_path` обязан записываться до списка и индекса, чтобы отфильтрованные некорректные записи не меняли выбранную папку.
- **База данных SQLite:** Сущность `AppFile` и её поле `id` (UUIDv4) являются постоянным первичным ключом каталога. Метаданные не должны привязываться исключительно к проектам; доступность метаданных для папок вне проектов обязана сохраняться.

### 5.2 Инварианты поведения файловых операций
- **Защита оригиналов:** Никакие операции навигации по папкам, выбора проектов, создания коллекций или удаления папок из списков не должны изменять, перемещать или удалять оригинальные файлы на диске.
- **macOS Bookmarks:** При смене папки или завершении работы security-scoped ресурсы должны корректно закрываться (`stopAccessingSecurityScopedResource`), а при активной работе с папкой — удерживаться открытыми для работы генерации превью.
- **Сброс и сохранение выделения:** Смена рабочей папки сбрасывает локальное выделение `_selectedPaths`. Любые фоновые пакетные операции должны фиксировать (freeze) список обрабатываемых `AppFile.id` и путей до первого `await`, как это реализовано в `MetadataGenerationContext`.

### 5.3 Наблюдения за параллельной разработкой (задачи 02 и 03)
- В рабочей копии параллельно создаются:
  - `lib/features/folder_navigation/**` (автор: задача 02) — контроллер навигации по подпапкам и дереву каталогов;
  - `lib/features/organization/**` (автор: задача 03) — репозиторий проектов и коллекций `OrganizationRepository`;
  - `lib/core/database/database_helper.dart` (автор: задача 03) — миграция на версию базы данных 7 с таблицами `projects`, `project_folders`, `collections`, `collection_items`, `selection_items` и созданием бэкапа базы через `VACUUM INTO`.
- Контракт задачи 03 явно формулирует правило: проект является лишь логической группой путей и ссылок на `AppFile.id`, проект не владеет файлами и не дублирует их, а существующий список рабочих папок остаётся автономным.

## 6. Ограничения анализа

- Не выполнялся запуск графического интерфейса приложения macOS (`StockFlow.app`): для целей аналитической фиксации baseline, проверки персистентности, bookmarks и контрактов достаточно статического анализа кода и полного прогона модульных и виджет-тестов без поднятия графического сервера.
- Физическое отключение внешнего накопителя проверялось через программные эмуляции и тесты `DirectoryProbe`/`SecureBookmarksAdapter`, реальное аппаратное отключение внешнего тома во время дискового ввода-вывода не исследовалось.
- Сервис памяти Hindsight для данного репозитория возвращает ошибку авторизации 401 (отсутствует API-токен в среде), анализ выполнен на основе кода и локальных документов.
