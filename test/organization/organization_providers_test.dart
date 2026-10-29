import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_flow/core/database/database_helper.dart';
import 'package:stock_flow/features/organization/application/organization_providers.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late DatabaseHelper helper;
  late OrganizationRepository repo;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sf_org_prov_test_');
    helper = DatabaseHelper.forTest(tempDir.path);
    repo = OrganizationRepository(() => helper.database);

    container = ProviderContainer(
      overrides: [
        organizationRepositoryProvider.overrideWithValue(repo),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    final db = await helper.database;
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('projectsProvider and projectFoldersProvider perform mutations and invalidate',
      () async {
    // Initial state is empty
    expect(await container.read(projectsProvider.future), isEmpty);

    // Create project
    final p = await container
        .read(projectsProvider.notifier)
        .createProject('Brand Campaign');
    expect(p.name, equals('Brand Campaign'));

    var projects = await container.read(projectsProvider.future);
    expect(projects.length, equals(1));
    expect(projects.first.id, equals(p.id));

    // Add folders
    await container
        .read(projectFoldersProvider(p.id).notifier)
        .addFolder('/path/to/folder1');
    await container
        .read(projectFoldersProvider(p.id).notifier)
        .addFolder('/path/to/folder2');

    var folders = await container.read(projectFoldersProvider(p.id).future);
    expect(folders, equals(['/path/to/folder1', '/path/to/folder2']));

    // Remove folder
    await container
        .read(projectFoldersProvider(p.id).notifier)
        .removeFolder('/path/to/folder1');
    folders = await container.read(projectFoldersProvider(p.id).future);
    expect(folders, equals(['/path/to/folder2']));

    // Rename project
    await container
        .read(projectsProvider.notifier)
        .renameProject(p.id, 'Summer Campaign');
    projects = await container.read(projectsProvider.future);
    expect(projects.first.name, equals('Summer Campaign'));

    // Pin project
    await container
        .read(projectsProvider.notifier)
        .setProjectPinned(p.id, pinned: true);
    projects = await container.read(projectsProvider.future);
    expect(projects.first.pinned, isTrue);

    // Delete project
    await container.read(projectsProvider.notifier).deleteProject(p.id);
    projects = await container.read(projectsProvider.future);
    expect(projects, isEmpty);
  });

  test('collectionsProvider and collectionFileIdsProvider manage memberships',
      () async {
    expect(await container.read(collectionsProvider.future), isEmpty);

    // Create collection
    final col = await container
        .read(collectionsProvider.notifier)
        .createCollection('Favorites');
    expect(col.name, equals('Favorites'));

    var cols = await container.read(collectionsProvider.future);
    expect(cols.length, equals(1));

    // Add file items
    await container
        .read(collectionFileIdsProvider(col.id).notifier)
        .addFile('f-101');
    await container
        .read(collectionFileIdsProvider(col.id).notifier)
        .addFile('f-102');

    var fileIds =
        await container.read(collectionFileIdsProvider(col.id).future);
    expect(fileIds, equals(['f-101', 'f-102']));

    // Remove one item
    await container
        .read(collectionFileIdsProvider(col.id).notifier)
        .removeFile('f-101');
    fileIds = await container.read(collectionFileIdsProvider(col.id).future);
    expect(fileIds, equals(['f-102']));

    // Clear collection
    await container.read(collectionFileIdsProvider(col.id).notifier).clear();
    fileIds = await container.read(collectionFileIdsProvider(col.id).future);
    expect(fileIds, isEmpty);

    // Rename collection
    await container
        .read(collectionsProvider.notifier)
        .renameCollection(col.id, 'Top Picks');
    cols = await container.read(collectionsProvider.future);
    expect(cols.first.name, equals('Top Picks'));

    // Delete collection
    await container
        .read(collectionsProvider.notifier)
        .deleteCollection(col.id);
    cols = await container.read(collectionsProvider.future);
    expect(cols, isEmpty);
  });

  test('selectionFileIdsProvider maintains persistent selection across operations',
      () async {
    expect(await container.read(selectionFileIdsProvider.future), isEmpty);

    // Add items
    await container.read(selectionFileIdsProvider.notifier).addFile('f-1');
    await container.read(selectionFileIdsProvider.notifier).addFile('f-2');

    var selection = await container.read(selectionFileIdsProvider.future);
    expect(selection, equals(['f-1', 'f-2']));

    // Remove one item
    await container.read(selectionFileIdsProvider.notifier).removeFile('f-1');
    selection = await container.read(selectionFileIdsProvider.future);
    expect(selection, equals(['f-2']));

    // Clear selection
    await container.read(selectionFileIdsProvider.notifier).clear();
    selection = await container.read(selectionFileIdsProvider.future);
    expect(selection, isEmpty);
  });
}
