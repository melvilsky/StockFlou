import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_flow/features/organization/presentation/organization_presentation.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('ProjectsSectionView: создание, выбор, pin, archive и безопасное удаление проекта',
      (tester) async {
    final repo = FakeOrganizationRepository();
    final p1 = await repo.createProject('Летняя коллекция');
    await repo.addProjectFolder(p1.id, '/Volumes/Media/Summer_2026');

    Project? selectedProject;
    String? selectedFolder;

    await tester.pumpWidget(
      buildTestAppWithRepo(
        repo: repo,
        child: StatefulBuilder(
          builder: (context, setState) {
            return ProjectsSectionView(
              selectedProjectId: selectedProject?.id,
              onProjectSelected: (p) {
                setState(() => selectedProject = p);
              },
              onFolderSelected: (f) {
                setState(() => selectedFolder = f);
              },
            );
          },
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 1. Проверяем отображение существующего проекта
    expect(find.text('Летняя коллекция'), findsOneWidget);
    expect(find.text('1'), findsNWidgets(2)); // бейдж секции (1 проект) и бейдж папок (1 папка)

    // 2. Выбор проекта через клик
    await tester.tap(find.byKey(Key('project_row_${p1.id}')));
    await tester.pumpAndSettle();

    expect(selectedProject?.id, equals(p1.id));

    // Проверяем отображение папки и клик по ней
    expect(find.text('Summer_2026'), findsOneWidget);
    await tester.tap(find.byKey(Key('project_folder_${p1.id}_/Volumes/Media/Summer_2026')));
    await tester.pumpAndSettle();
    expect(selectedFolder, equals('/Volumes/Media/Summer_2026'));

    // 3. Создание нового проекта через заголовок
    await tester.tap(find.byKey(const Key('create_project_header_button')));
    await tester.pumpAndSettle();

    expect(find.text('Новый проект'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('organization_name_input')),
      'Осенний пейзаж',
    );
    await tester.tap(find.byKey(const Key('organization_name_submit_button')));
    await tester.pumpAndSettle();

    expect(repo.recordedCalls, contains('createProject(Осенний пейзаж)'));
    expect(selectedProject?.name, equals('Осенний пейзаж'));

    // 4. Меню проекта: Закрепить (Pin)
    await tester.tap(find.byKey(Key('project_menu_button_${p1.id}')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Закрепить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repo.recordedCalls, contains('setProjectPinned(${p1.id}, pinned: true)'));

    // 5. Меню проекта: Переименовать
    await tester.tap(find.byKey(Key('project_menu_button_${p1.id}')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Переименовать...'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('organization_name_input')),
      'Лето 2026 обновлённое',
    );
    await tester.tap(find.byKey(const Key('organization_name_submit_button')));
    await tester.pumpAndSettle();

    expect(repo.recordedCalls, contains('renameProject(${p1.id}, Лето 2026 обновлённое)'));

    // 6. Меню проекта: Архивировать
    await tester.tap(find.byKey(Key('project_menu_button_${p1.id}')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('В архив'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repo.recordedCalls, contains('setProjectArchived(${p1.id}, archived: true)'));

    // Проверяем переключатель "Показать архив"
    expect(find.text('Показать архив (1)'), findsOneWidget);
    await tester.tap(find.text('Показать архив (1)'));
    await tester.pump();
    expect(find.text('Скрыть архив (1)'), findsOneWidget);

    // 7. Безопасное удаление проекта
    await tester.tap(find.byKey(Key('project_menu_button_${p1.id}')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Удалить проект...'));
    await tester.pumpAndSettle();

    // Проверяем диалог предупреждения
    expect(find.text('Удалить проект?'), findsOneWidget);
    expect(
      find.text(
        'Будет удалена только организационная запись проекта. '
        'Все подключённые папки, оригиналы файлов на диске, их метаданные '
        'и история загрузок останутся в полной сохранности.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('organization_delete_confirm_button')));
    await tester.pumpAndSettle();

    expect(repo.recordedCalls, contains('deleteProject(${p1.id})'));
    final remaining = await repo.getProjects();
    expect(remaining.any((p) => p.id == p1.id), isFalse);
  });
}
