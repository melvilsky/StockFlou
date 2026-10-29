# Отчёт о выполнении: Волна 2 — Задача 04 (UI-виджеты управления проектами, коллекциями и «Отбором»)

## 1. Что сделано

В соответствии с требованиями задачи 04 (Волна 2), контрактами задачи 03 (`docs/agent-prompts/folders-projects/03-result.md`), правилами AGENTS.md и дизайн-требованиями Impeccable (SKILL.md) реализован полный комплект презентационных компонентов для сайдбара и навигации:

1. **Диалоги ввода и подтверждения (`lib/features/organization/presentation/dialogs/`)**:
   - `OrganizationNameDialog`:
     - Диалог создания и переименования проектов и коллекций.
     - Валидация: непустое имя (с тримированием пробелов `trim()`), запрет строк только из пробелов, ограничение длины (до 100 символов) с понятным текстом ошибок.
     - Автофокус на поле ввода, выделение начального значения, поддержка клавиш `Enter` (подтверждение) и `Esc` (отмена).
   - `OrganizationConfirmDeleteDialog`:
     - Специализированный диалог безопасного подтверждения организационного удаления.
     - Чётко и явно объясняет пользователю последствия: *«Будет удалена только организационная запись. Все оригиналы файлов на диске, их метаданные и история загрузок останутся в полной сохранности»*.
     - Безопасная кнопка «Отмена» по умолчанию находится в фокусе; деструктивное действие выделено цветом ошибки (`colorScheme.error`).
   - `ProjectFoldersDialog`:
     - Диалог управления подключёнными папками выбранного проекта.
     - Отображает список привязанных директорий из `projectFoldersProvider(projectId)`.
     - Добавление папки из диска через нативный диалог (`directoryPicker`).
     - Быстрое добавление открытых рабочих областей (`workspacesProvider.entries`) в один клик.
     - Исключение папки из проекта с подтверждением (оригиналы на диске не удаляются).

2. **Компоненты сайдбара и секций (`lib/features/organization/presentation/widgets/`)**:
   - `CollapsibleSectionCard`:
     - Раскрываемый контейнер-карточка, визуально идентичный `WorkspacesSidebarBlock` (скругление 12px, рамка `outline.withValues(alpha: 0.2)`, цвета `surfaceContainerHighest` в тёмной теме и `surfaceContainerLow` в светлой).
     - Доступность: клавиатурный фокус на заголовке, переключение раскладки по клику/Enter/Space, `Semantics(button: true, expanded: isExpanded)`.
     - Индикатор количества элементов (бейдж) и слот для кнопки создания («+»).
   - `ProjectsSectionView`:
     - Управление проектами: список, создание, переименование, удаление.
     - Закрепление (`pinned` — закреплённые проекты отображаются сверху с иконкой `Icons.push_pin`).
     - Архивирование (`archived` — скрыты по умолчанию, раскрываются по кнопке «Показать архив (N)»).
     - Выбор активного проекта (`onProjectSelected`).
     - Просмотр привязанных папок проекта и переход к ним (`onFolderSelected`).
     - Защита от повторного нажатия во время активной асинхронной операции (`_isOperating`).
     - Обработка ошибок с показом понятного `SnackBar`.
   - `CollectionsSectionView`:
     - Управление коллекциями: список, создание, переименование, удаление.
     - Отображение счётчика материалов в каждой коллекции.
     - Выбор активной коллекции (`onCollectionSelected`).
     - **Добавление выбранных материалов (`selectedFileIds`) в коллекцию**.
     - **Удаление выбранных материалов из коллекции (только ссылок, не оригиналов!)**.
     - Очистка всей коллекции (`clear`) с предупреждением о сохранности файлов.
     - Фиксация snapshot выбранных ID (`List<String>.from(widget.selectedFileIds)`) до первого `await`.
     - Защита от гонок и повторных кликов (`_isOperating`).
   - `SelectionSectionView`:
     - Управление постоянным «Отбором»: отображение счётчика отобранных файлов.
     - Переход к просмотру материалов «Отбора» (`onOpenSelection`).
     - **Добавление текущих выбранных в сетке материалов (`selectedFileIds`) в «Отбор»**.
     - **Удаление выбранных материалов из «Отбора» (только ссылок, не оригиналов!)**.
     - Очистка всего «Отбора» (`clear`) с диалогом подтверждения.
     - Защита от повторных кликов и обработка ошибок.

3. **Составной виджет сайдбара и фасад экспорта**:
   - `OrganizationSidebarView` (`lib/features/organization/presentation/organization_sidebar_view.dart`):
     - Объединяет `ProjectsSectionView`, `CollectionsSectionView` и `SelectionSectionView` в единый вертикальный блок сайдбара.
     - Оборачивает секции в `FocusTraversalGroup` для предсказуемой навигации клавишей Tab.
   - `organization_presentation.dart` (`lib/features/organization/presentation/organization_presentation.dart`):
     - Экспортирует все виджеты и диалоги, предоставляя готовый единый API для задачи 06.

4. **Тестовое покрытие (`test/organization_presentation/`)**:
   - `organization_name_dialog_test.dart` (2 теста): валидация пустого имени, пробелов, длины > 100 символов, обрезка пробелов `trim()`, отмена.
   - `organization_confirm_delete_dialog_test.dart` (1 тест): отображение текста предупреждения о сохранности файлов, отмена (`false`), подтверждение (`true`).
   - `project_folders_dialog_test.dart` (1 тест): отображение папок, быстрое добавление из рабочих областей, выбор через пикер, безопасное исключение папки с подтверждением.
   - `projects_section_view_test.dart` (1 тест): создание проекта, выбор проекта, клик по подключенной папке, закрепление, переименование, архивирование, раскрытие архива, безопасное удаление проекта.
   - `collections_section_view_test.dart` (1 тест): создание коллекции с автодобавлением выбранных ID, выбор коллекции, добавление выбранных ID в существующую коллекцию, удаление выбранных ID (только ссылок), очистка коллекции, удаление коллекции.
   - `selection_section_view_test.dart` (1 тест): счётчик элементов, переход к просмотру, добавление выбранных ID, удаление выбранных ID из отбора, очистка отбора.
   - `organization_sidebar_view_test.dart` (1 тест): интеграция всех трёх секций, корректное отображение в светлой (`AppTheme.lightTheme`) и тёмной (`AppTheme.darkTheme`) темах.

---

## 2. Точные пути созданных и изменённых файлов

### Созданные файлы presentation:
- `lib/features/organization/presentation/dialogs/organization_name_dialog.dart`
- `lib/features/organization/presentation/dialogs/organization_confirm_delete_dialog.dart`
- `lib/features/organization/presentation/dialogs/project_folders_dialog.dart`
- `lib/features/organization/presentation/widgets/collapsible_section_card.dart`
- `lib/features/organization/presentation/widgets/projects_section_view.dart`
- `lib/features/organization/presentation/widgets/collections_section_view.dart`
- `lib/features/organization/presentation/widgets/selection_section_view.dart`
- `lib/features/organization/presentation/organization_sidebar_view.dart`
- `lib/features/organization/presentation/organization_presentation.dart`

### Созданные файлы тестов:
- `test/organization_presentation/test_helpers.dart`
- `test/organization_presentation/organization_name_dialog_test.dart`
- `test/organization_presentation/organization_confirm_delete_dialog_test.dart`
- `test/organization_presentation/project_folders_dialog_test.dart`
- `test/organization_presentation/projects_section_view_test.dart`
- `test/organization_presentation/collections_section_view_test.dart`
- `test/organization_presentation/selection_section_view_test.dart`
- `test/organization_presentation/organization_sidebar_view_test.dart`

### Отчёт:
- `docs/agent-prompts/folders-projects/04-result.md`

*Примечание: файлы `main.dart`, `generation_screen.dart`, `workspaces_sidebar_block.dart`, схема БД и domain/data/application задачи 03 не изменялись.*

---

## 3. Публичные контракты для задачи 06

Все компоненты доступны через единый импорт:
```dart
import 'package:stock_flow/features/organization/presentation/organization_presentation.dart';
```

### 3.1. Единый составной сайдбар `OrganizationSidebarView`
```dart
class OrganizationSidebarView extends StatelessWidget {
  final String? selectedProjectId;
  final ValueChanged<Project?>? onProjectSelected;
  final ValueChanged<String>? onFolderSelected;

  final String? selectedCollectionId;
  final ValueChanged<Collection?>? onCollectionSelected;

  final bool isSelectionSource;
  final VoidCallback? onOpenSelection;

  final List<String> selectedFileIds;
  final Future<String?> Function()? directoryPicker;

  const OrganizationSidebarView({
    super.key,
    this.selectedProjectId,
    this.onProjectSelected,
    this.onFolderSelected,
    this.selectedCollectionId,
    this.onCollectionSelected,
    this.isSelectionSource = false,
    this.onOpenSelection,
    this.selectedFileIds = const [],
    this.directoryPicker,
  });
}
```

### 3.2. Секция проектов `ProjectsSectionView`
```dart
class ProjectsSectionView extends ConsumerStatefulWidget {
  final String? selectedProjectId;
  final ValueChanged<Project?>? onProjectSelected;
  final ValueChanged<String>? onFolderSelected;
  final Future<String?> Function()? directoryPicker;
  final bool initialExpanded;
}
```

### 3.3. Секция коллекций `CollectionsSectionView`
```dart
class CollectionsSectionView extends ConsumerStatefulWidget {
  final String? selectedCollectionId;
  final ValueChanged<Collection?>? onCollectionSelected;
  final List<String> selectedFileIds;
  final bool initialExpanded;
}
```

### 3.4. Секция «Отбора» `SelectionSectionView`
```dart
class SelectionSectionView extends ConsumerStatefulWidget {
  final List<String> selectedFileIds;
  final bool isSelectedSource;
  final VoidCallback? onOpenSelection;
  final bool initialExpanded;
}
```

### 3.5. Диалоги
```dart
// Диалог ввода/редактирования имени с валидацией
Future<String?> OrganizationNameDialog.show({
  required BuildContext context,
  required String title,
  String initialValue = '',
  String label = 'Название',
  String confirmButtonText = 'Сохранить',
});

// Диалог подтверждения организационного удаления с пояснением
Future<bool> OrganizationConfirmDeleteDialog.show({
  required BuildContext context,
  required String title,
  String? entityName,
  String explanation = '...',
  String confirmButtonText = 'Удалить',
});

// Диалог управления подключёнными папками проекта
Future<void> ProjectFoldersDialog.show({
  required BuildContext context,
  required Project project,
  Future<String?> Function()? directoryPicker,
});
```

---

## 4. Команды и реальные результаты проверок

### 4.1. Статический анализ Dart:
Команда: `dart analyze lib/features/organization/ test/organization_presentation/`  
Результат:
```
Analyzing organization, organization_presentation...
No issues found!
```

### 4.2. Тесты презентационного слоя (задача 04):
Команда: `flutter test test/organization_presentation/`  
Результат:
```
00:03 +8: All tests passed!
```
Все 8 тестов успешно пройдены:
- `organization_confirm_delete_dialog_test.dart`: отображение предупреждения о сохранности файлов, отмена/подтверждение.
- `organization_name_dialog_test.dart`: валидация пустого имени, пробелов, длины, trim.
- `project_folders_dialog_test.dart`: добавление из рабочих областей/диска, безопасное исключение папки.
- `projects_section_view_test.dart`: создание, выбор, pin, archive, переименование, удаление проекта.
- `collections_section_view_test.dart`: создание, добавление выбранных ID, удаление выбранных ID, очистка, удаление коллекции.
- `selection_section_view_test.dart`: счётчик, просмотр, добавление выбранных ID, удаление выбранных ID, очистка «Отбора».
- `organization_sidebar_view_test.dart`: связывание всех секций, светлая и тёмная темы.

### 4.3. Регрессионные тесты модуля организации (задача 03):
Команда: `flutter test test/organization/`  
Результат:
```
00:00 +16: All tests passed!
```

### 4.4. Полный прогон тестов проекта:
Команда: `flutter test`  
Результат:
```
00:11 +230: All tests passed!
```
Все 230 тестов проекта успешно пройдены без регрессий.

---

## 5. Ограничения (shortcut)
- `shortcut: drag-and-drop between grid and collections is not implemented in presentation layer widgets`: перетаскивание мыши из медиа-сетки на виджет коллекции будет подключено на уровне экрана рабочей области в задаче 06 через общий `DragTarget`.
- `shortcut: project sort order reordering via drag-and-drop handles`: ручной reorder перетаскиванием списка проектов оставлен для этапа расширения (задача 06), в UI реализована приоритизация закреплённых проектов (`pinned` первыми) и фильтрация архива.
