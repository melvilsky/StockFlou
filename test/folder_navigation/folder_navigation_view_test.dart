import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_flow/features/folder_navigation/domain/folder_access.dart';
import 'package:stock_flow/features/folder_navigation/domain/folder_navigation_models.dart';
import 'package:stock_flow/features/folder_navigation/presentation/folder_navigation_view.dart';

class MockFolderAccessScope implements FolderAccessScope {
  MockFolderAccessScope(this.rootPath);

  @override
  final String rootPath;

  final Map<String, List<FolderNavigationItem>> tree = {};
  String? errorPath;

  @override
  Future<bool> exists(String path) async => true;

  @override
  Future<List<FolderNavigationItem>> listSubfolders(String path) async {
    if (path == errorPath) {
      throw Exception('Access denied to $path');
    }
    return tree[path] ?? const [];
  }
}

void main() {
  testWidgets('FolderNavigationView: отображает панель, дерево, реагирует на клики', (tester) async {
    final access = MockFolderAccessScope('/workspace');
    access.tree['/workspace'] = [
      const FolderNavigationItem(path: '/workspace/sub1', name: 'sub1', isSymlink: false),
      const FolderNavigationItem(path: '/workspace/sub2', name: 'sub2', isSymlink: false),
    ];
    access.tree['/workspace/sub1'] = [
      const FolderNavigationItem(path: '/workspace/sub1/nested', name: 'nested', isSymlink: false),
    ];

    FolderSelection? currentSelection;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: FolderNavigationView(
              rootFolder: '/workspace',
              access: access,
              onSelection: (sel) => currentSelection = sel,
            ),
          ),
        ),
      ),
    );

    // Первоначальный кадр
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Проверяем элементы тулбара: переключатель «С подпапками», кнопки навигации
    expect(find.text('С подпапками'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);

    // В дереве виден корень ('workspace') и дочерние sub1, sub2
    expect(find.text('workspace'), findsOneWidget);
    expect(find.text('sub1'), findsOneWidget);
    expect(find.text('sub2'), findsOneWidget);

    // Выбираем sub1
    await tester.tap(find.text('sub1'));
    await tester.pump();
    expect(currentSelection?.path, '/workspace/sub1');

    // Раскрываем sub1
    await tester.tap(find.byTooltip('Развернуть').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('nested'), findsOneWidget);

    // Переключаем «С подпапками»
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(currentSelection?.includeSubfolders, true);

    // Нажимаем «Назад»
    await tester.tap(find.byTooltip('Назад'));
    await tester.pump();
    expect(currentSelection?.path, '/workspace');
  });

  testWidgets('FolderNavigationView: отображает ошибку и кнопку повтора', (tester) async {
    final access = MockFolderAccessScope('/workspace');
    access.tree['/workspace'] = [
      const FolderNavigationItem(path: '/workspace/err_dir', name: 'err_dir', isSymlink: false),
    ];
    access.errorPath = '/workspace/err_dir';

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: FolderNavigationView(
              rootFolder: '/workspace',
              access: access,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Раскрываем err_dir
    await tester.tap(find.byTooltip('Развернуть').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Не удалось прочитать папку'), findsOneWidget);
    expect(find.byTooltip('Повторить чтение папки'), findsOneWidget);
  });
}
