# Отчёт о реализации: Волна 1 — Задача 02 (Модуль навигации по подпапкам)

Дата: 2026-10-25.  
Статус: Реализовано, протестировано, готово к подключению.

---

## 1. Что сделано

Создан отдельный, полностью автономный модуль навигации по подпапкам внутри подключённой корневой папки (рабочей области):

1. **Доменные модели (`lib/features/folder_navigation/domain/folder_navigation_models.dart`):**
   - `FolderNavigationItem`: представление подпапки (путь, отображаемое имя, флаг `isSymlink`).
   - `FolderNodeState` и `FolderNodeStatus`: строгое различение состояний узла дерева (`loading`, `ready`, `error`). Папка без вложенных директорий имеет статус `ready` с пустым списком `children` (различение пустоты от ошибки).
   - `FolderSelection`: модель выдачи наружу (выбранный путь `path` + признак `includeSubfolders`).
   - `FolderNavigationState`: состояние дерева, текущий путь, множество раскрытых путей `expandedPaths`, карта узлов `nodes`, история назад/вперёд `backHistory`/`forwardHistory`, флаг `includeSubfolders`.

2. **Контракт доступа и безопасность (`lib/features/folder_navigation/domain/folder_access.dart`):**
   - Абстрактный интерфейс `FolderAccessScope`:
     - `rootPath`: нормализованный корень рабочей области.
     - `exists(path)`: проверка доступности.
     - `listSubfolders(path)`: перечисление только непосредственных дочерних папок (`followLinks: false`).
   - `DefaultFolderAccessScope`: стандартная реализация с проверкой path guard (`isPathInsideRoot`). При попытке запроса директории за пределами `rootPath` выбрасывается `ArgumentError`.
   - Защита от циклов и неконтролируемого чтения: символические ссылки определяются с помощью `FileSystemEntity.type(path, followLinks: false) == FileSystemEntityType.link`. Если ссылка указывает на директорию, она помечается `isSymlink = true`, но её содержимое не сканируется автоматически и не раскрывается по умолчанию.
   - Утилиты нормализации путей: `normalizeFolderPath`, `parentFolderPath`, `isPathInsideRoot`.

3. **Контроллер Riverpod (`lib/features/folder_navigation/domain/folder_navigation_controller.dart`):**
   - `FolderNavigationController` (`folderNavigationProvider`):
     - `open({required String rootPath, required FolderAccessScope access, onSelection})`: подключение корня, сброс предыдущего состояния, первоначальное чтение только корневого уровня (ленивая загрузка, всё дерево при открытии не сканируется).
     - Постепенное (ленивое) раскрытие: метод `toggleExpand(path)` инициирует чтение подпапок только при раскрытии узла. Папки-символьные ссылки защищены от раскрытия.
     - История переходов: методы `selectFolder(path)`, `navigateUp()` (переход к родителю в рамках подключённого корня без выхода за `rootPath`), `goBack()`, `goForward()`.
     - Отмена устаревших результатов: отслеживание монотонно возрастающих идентификаторов запросов на каждый путь (`_requestIds[path]`). Поздние или отменённые ответы асинхронного чтения отбрасываются.
     - Переключатель «С подпапками»: метод `setIncludeSubfolders(bool)` и немедленная нотификация в `onSelection`.
     - Повтор при ошибке: метод `reloadFolder(path)`.

4. **UI-компонент (`lib/features/folder_navigation/presentation/folder_navigation_view.dart`):**
   - Виджет `FolderNavigationView`:
     - Тулбар навигации: кнопки «Назад» (`Icons.arrow_back`), «Вперёд» (`Icons.arrow_forward`), «На уровень вверх» (`Icons.arrow_upward`), текстовое поле текущего пути, переключатель `Switch` («С подпапками»).
     - Дерево каталогов: плоский список видимых узлов с отступами по глубине (`depth * 16.0`), стрелками сворачивания/разворачивания, иконками папок/ссылок (`Icons.folder_outlined`, `Icons.link`), индикаторами загрузки, индикацией пустых папок («Пусто») и плашкой ошибки («Не удалось прочитать папку») с кнопкой повтора (`Icons.refresh`).
     - Соответствие стилю приложения и гайдлайнам проекта: единый стиль карточки `Container` с `surfaceContainerLow`/`surfaceContainerHighest` и скруглением 12px; оборачивание кликабельных областей в `SingleClickArea` (обход десктопной проблемы двойного клика Flutter); доступность через `Semantics` (`selected`, `button`) и поддержка клавиатурного фокуса через `IconButton`/`InkWell`.

5. **Тестовое покрытие (`test/folder_navigation/`):**
   - `test/folder_navigation/folder_navigation_controller_test.dart` (11 тестов):
     - Нормализация путей, границы корня, вычисление родителя;
     - Реальная ФС во временной директории: вложенность, сортировка, игнорирование обычных файлов, path guard;
     - Обработка символических ссылок и циклических ссылок;
     - Ленивая загрузка (чтение только при раскрытии);
     - Защита от раскрытия симлинков;
     - Навигация (вверх/назад/вперёд/история);
     - Переключатель «С подпапками»;
     - Отмена устаревших результатов при быстрых повторных запросах;
     - Различение пустоты (`ready` c пустым списком) и ошибки доступа (`error`).
   - `test/folder_navigation/folder_navigation_view_test.dart` (2 теста):
     - Отображение тулбара, дерева, переключение «С подпапками», клики по папкам, навигация «Назад»;
     - Отображение ошибки чтения папки и кнопки повтора.

---

## 2. Точные пути созданных и изменённых файлов

Разрешённая зона соблюдена на 100%:
- `lib/features/folder_navigation/domain/folder_navigation_models.dart`
- `lib/features/folder_navigation/domain/folder_access.dart`
- `lib/features/folder_navigation/domain/folder_navigation_controller.dart`
- `lib/features/folder_navigation/presentation/folder_navigation_view.dart`
- `test/folder_navigation/folder_navigation_controller_test.dart`
- `test/folder_navigation/folder_navigation_view_test.dart`
- `docs/agent-prompts/folders-projects/02-result.md`

*Файлы `main.dart`, `generation_screen.dart`, `workspaces_provider.dart`, `workspaces_sidebar_block.dart`, `AppFile`, `DatabaseHelper` не изменялись.*

---

## 3. Публичные контракты для задачи 06 (Подключение)

### Контракт выдачи выбора (`FolderSelection`)

```dart
class FolderSelection {
  final String path;                // Абсолютный путь выбранной папки
  final bool includeSubfolders;     // true, если активен режим «С подпапками»
}
```

### Контракт доступа (`FolderAccessScope`)

```dart
abstract class FolderAccessScope {
  String get rootPath;
  Future<bool> exists(String path);
  Future<List<FolderNavigationItem>> listSubfolders(String path);
}
```

При подключении к реальной рабочей области в macOS создаётся адаптер, который оборачивает вызовы в security-scoped bookmark рабочей области (или используется готовый `DefaultFolderAccessScope(currentWorkspacePath)` при открытом доступе).

### Пример подключения виджета

```dart
import 'package:stock_flow/features/folder_navigation/domain/folder_access.dart';
import 'package:stock_flow/features/folder_navigation/domain/folder_navigation_models.dart';
import 'package:stock_flow/features/folder_navigation/presentation/folder_navigation_view.dart';

// Внутри боковой панели или диалога:
FolderNavigationView(
  rootFolder: currentWorkspace.path,
  access: DefaultFolderAccessScope(currentWorkspace.path),
  onSelection: (FolderSelection selection) {
    debugPrint('Выбрана папка: ${selection.path}');
    debugPrint('Режим с подпапками: ${selection.includeSubfolders}');
    // Задача 06 связывает selection с фильтрацией каталога / filesProvider
  },
)
```

Также состояние доступно напрямую через Riverpod:
```dart
final state = ref.watch(folderNavigationProvider);
final currentSelection = ref.read(folderNavigationProvider.notifier).currentSelection;
```

---

## 4. Команды и реальные результаты проверок

1. **Анализ статических анализаторов Dart/Flutter:**
   ```bash
   flutter analyze --no-pub lib/features/folder_navigation/ test/folder_navigation/
   ```
   *Результат:*
   ```
   Analyzing 2 items...
   No issues found! (ran in 2.1s)
   ```

2. **Юнит- и виджет-тесты модуля:**
   ```bash
   flutter test test/folder_navigation/
   ```
   *Результат:*
   ```
   00:00 +0: Helper functions parentFolderPath и isPathInsideRoot: границы
   00:00 +1: Helper functions normalizeFolderPath корректно обрабатывает слэши
   00:00 +2: DefaultFolderAccessScope (на реальной временной ФС) вложенность, сортировка, игнорирование обычных файлов и guard
   00:00 +3: DefaultFolderAccessScope (на реальной временной ФС) символическая ссылка помечается как isSymlink и не обходится рекурсивно
   00:00 +4: FolderNavigationController open() лениво загружает только корень и отсылает callback выбора
   00:00 +5: FolderNavigationController toggleExpand() загружает подпапку лениво только при раскрытии
   00:00 +6: FolderNavigationController Символьные ссылки не раскрываются через toggleExpand
   00:00 +7: FolderNavigationController Навигация: переход к родителю, история назад/вперёд
   00:00 +8: FolderNavigationController Переключатель «С подпапками» обновляет состояние и callback выбора
   00:00 +9: FolderNavigationController Отмена/игнорирование устаревших результатов при быстрой навигации
   00:00 +10: FolderNavigationController Различение пустоты (ready с пустым списком) и ошибки доступа (error)
   00:00 +11: FolderNavigationView: отображает панель, дерево, реагирует на клики
   00:01 +12: FolderNavigationView: отображает ошибку и кнопку повтора
   00:01 +13: All tests passed!
   ```

---

## 5. Ограничения

- `shortcut: scope_security_binding`: Сам виджет и дефолтный `DefaultFolderAccessScope` работают в рамках переданного пути и защищают от выхода за пределы корня через path guard; если на macOS корневая папка требует удержания Security-Scoped Bookmark ресурса при вызове `listSubfolders`, реализация задачи 06 передаёт соответствующую обёртку `FolderAccessScope`, удерживающую resource access.
- Модуль управляет только навигацией по папкам и возвратом выбранного пути/режима рекурсии; непосредственную фильтрацию списка файлов по полученному `FolderSelection` выполняет экран генерации / каталог в задаче 06.
