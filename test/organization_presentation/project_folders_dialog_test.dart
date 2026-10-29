import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_flow/core/state/workspaces_provider.dart';
import 'package:stock_flow/features/organization/presentation/organization_presentation.dart';

import 'test_helpers.dart';

class FakeWorkspacesNotifier extends WorkspacesNotifier {
  final WorkspacesState initialState;
  FakeWorkspacesNotifier(this.initialState);

  @override
  WorkspacesState build() => initialState;
}

void main() {
  testWidgets('ProjectFoldersDialog: добавление и безопасное удаление папки проекта',
      (tester) async {
    final repo = FakeOrganizationRepository();
    final project = await repo.createProject('Природа Карелии');
    await repo.addProjectFolder(project.id, '/Volumes/Media/Karelia_RAW');

    String? pickedDirectory = '/Volumes/Media/Karelia_DNG';

    await tester.pumpWidget(
      buildTestAppWithRepo(
        repo: repo,
        extraOverrides: [
          workspacesProvider.overrideWith(
            () => FakeWorkspacesNotifier(
              WorkspacesState(
                entries: [
                  const WorkspaceEntry(path: '/Volumes/Media/Karelia_RAW'),
                  const WorkspaceEntry(path: '/Volumes/Media/Karelia_JPEG'),
                ],
                currentIndex: 0,
              ),
            ),
          ),
        ],
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              ProjectFoldersDialog.show(
                context: context,
                project: project,
                directoryPicker: () async => pickedDirectory,
              );
            },
            child: const Text('Открыть папки'),
          ),
        ),
      ),
    );

    // 1. Открываем диалог
    await tester.tap(find.text('Открыть папки'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Папки проекта: Природа Карелии'), findsOneWidget);
    expect(find.text('Karelia_RAW'), findsOneWidget);

    // 2. Быстрое добавление из открытых рабочих областей (Karelia_JPEG)
    expect(find.text('Karelia_JPEG'), findsOneWidget);
    await tester.tap(
      find.byKey(Key('project_quick_add_folder_${project.id}_/Volumes/Media/Karelia_JPEG')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repo.recordedCalls, contains('addProjectFolder(${project.id}, /Volumes/Media/Karelia_JPEG)'));
    var folders = await repo.getProjectFolders(project.id);
    expect(folders, contains('/Volumes/Media/Karelia_JPEG'));

    // 3. Добавление через пикер
    await tester.tap(find.byKey(const Key('project_folders_pick_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repo.recordedCalls, contains('addProjectFolder(${project.id}, /Volumes/Media/Karelia_DNG)'));
    folders = await repo.getProjectFolders(project.id);
    expect(folders, contains('/Volumes/Media/Karelia_DNG'));

    // 4. Исключение папки Karelia_RAW из проекта
    expect(find.byKey(Key('project_remove_folder_${project.id}_0')), findsOneWidget);
    await tester.tap(find.byKey(Key('project_remove_folder_${project.id}_0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Проверяем диалог подтверждения
    expect(find.text('Исключить папку из проекта?'), findsOneWidget);
    expect(
      find.text(
        'Папка будет исключена из проекта. Все файлы и метаданные '
        'на диске останутся в сохранности.',
      ),
      findsOneWidget,
    );

    // Подтверждаем исключение
    await tester.tap(find.byKey(const Key('organization_delete_confirm_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repo.recordedCalls, contains('removeProjectFolder(${project.id}, /Volumes/Media/Karelia_RAW)'));
    folders = await repo.getProjectFolders(project.id);
    expect(folders.contains('/Volumes/Media/Karelia_RAW'), isFalse);

    // Закрываем диалог
    await tester.tap(find.byKey(const Key('project_folders_close_button')));
    await tester.pumpAndSettle();

    expect(find.byType(ProjectFoldersDialog), findsNothing);
  });
}
