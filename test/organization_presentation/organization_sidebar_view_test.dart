import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_flow/core/theme/app_theme.dart';
import 'package:stock_flow/features/organization/presentation/organization_presentation.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('OrganizationSidebarView: объединяет все секции, поддерживает темную/светлую тему',
      (tester) async {
    final repo = FakeOrganizationRepository();
    await repo.createProject('Проект Альфа');
    await repo.createCollection('Коллекция Бета');
    await repo.addToSelection('file_X');

    String? selectedProjId;
    String? selectedColId;
    bool openedSelection = false;

    // 1. Проверка в светлой теме
    await tester.pumpWidget(
      buildTestAppWithRepo(
        repo: repo,
        child: Theme(
          data: AppTheme.lightTheme,
          child: SingleChildScrollView(
            child: OrganizationSidebarView(
              selectedProjectId: selectedProjId,
              onProjectSelected: (p) => selectedProjId = p?.id,
              selectedCollectionId: selectedColId,
              onCollectionSelected: (c) => selectedColId = c?.id,
              isSelectionSource: openedSelection,
              onOpenSelection: () => openedSelection = true,
              selectedFileIds: const ['file_X', 'file_Y'],
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(ProjectsSectionView), findsOneWidget);
    expect(find.byType(CollectionsSectionView), findsOneWidget);
    expect(find.byType(SelectionSectionView), findsOneWidget);

    expect(find.text('ПРОЕКТЫ'), findsOneWidget);
    expect(find.text('КОЛЛЕКЦИИ'), findsOneWidget);
    expect(find.text('ОТБОР'), findsOneWidget);

    expect(find.text('Проект Альфа'), findsOneWidget);
    expect(find.text('Коллекция Бета'), findsOneWidget);

    // 2. Проверка в тёмной теме
    await tester.pumpWidget(
      buildTestAppWithRepo(
        repo: repo,
        child: Theme(
          data: AppTheme.darkTheme,
          child: SingleChildScrollView(
            child: OrganizationSidebarView(
              selectedProjectId: selectedProjId,
              onProjectSelected: (p) => selectedProjId = p?.id,
              selectedCollectionId: selectedColId,
              onCollectionSelected: (c) => selectedColId = c?.id,
              isSelectionSource: openedSelection,
              onOpenSelection: () => openedSelection = true,
              selectedFileIds: const ['file_X', 'file_Y'],
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Проект Альфа'), findsOneWidget);
    expect(find.text('Коллекция Бета'), findsOneWidget);
  });
}
