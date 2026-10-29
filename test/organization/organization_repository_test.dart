import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_flow/core/database/database_helper.dart';
import 'package:stock_flow/features/organization/data/db_organization_repository.dart';
import 'package:stock_flow/features/organization/domain/organization_models.dart';
import 'package:stock_flow/models/app_file.dart';
import 'package:stock_flow/models/upload_job.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late DatabaseHelper helper;
  late OrganizationRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sf_org_repo_test_');
    helper = DatabaseHelper.forTest(tempDir.path);
    repo = OrganizationRepository(() => helper.database);
  });

  tearDown(() async {
    final db = await helper.database;
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Projects', () {
    test('createProject validates name and sets defaults', () async {
      expect(() => repo.createProject(''), throwsArgumentError);
      expect(() => repo.createProject('   '), throwsArgumentError);

      final project = await repo.createProject('  Nature Photos  ');
      expect(project.name, equals('Nature Photos'));
      expect(project.id, isNotEmpty);
      expect(project.pinned, isFalse);
      expect(project.archived, isFalse);
      expect(project.sortOrder, equals(0));

      final list = await repo.getProjects();
      expect(list.length, equals(1));
      expect(list.first.id, equals(project.id));
    });

    test('renameProject updates name and throws if not found', () async {
      expect(
        () => repo.renameProject('non-existent', 'New Name'),
        throwsA(isA<OrganizationNotFoundException>()),
      );

      final project = await repo.createProject('Initial Name');
      final renamed = await repo.renameProject(project.id, 'Renamed Project');
      expect(renamed.name, equals('Renamed Project'));

      final list = await repo.getProjects();
      expect(list.first.name, equals('Renamed Project'));
    });

    test('setProjectPinned and setProjectArchived update flags and ordering',
        () async {
      await repo.createProject('A-Project');
      final p2 = await repo.createProject('B-Project');

      // Default order: created_at ASC (p1, p2)
      var list = await repo.getProjects();
      expect(list.map((p) => p.name).toList(), equals(['A-Project', 'B-Project']));

      // Pin p2 -> p2 comes first
      await repo.setProjectPinned(p2.id, pinned: true);
      list = await repo.getProjects();
      expect(list.map((p) => p.name).toList(), equals(['B-Project', 'A-Project']));
      expect(list.first.pinned, isTrue);

      // Archive p2
      await repo.setProjectArchived(p2.id, archived: true);
      list = await repo.getProjects();
      expect(list.first.archived, isTrue);
    });

    test('reorderProjects updates sort order and preserves it', () async {
      final p1 = await repo.createProject('Project 1');
      final p2 = await repo.createProject('Project 2');
      final p3 = await repo.createProject('Project 3');

      await repo.reorderProjects([p3.id, p1.id, p2.id]);

      final list = await repo.getProjects();
      expect(
        list.map((p) => p.id).toList(),
        equals([p3.id, p1.id, p2.id]),
      );
    });

    test('project folders support many-to-many, idempotency and isolated deletion',
        () async {
      final p1 = await repo.createProject('Project 1');
      final p2 = await repo.createProject('Project 2');

      const sharedFolder = '/Volumes/Media/Shared';
      const p1Folder = '/Volumes/Media/P1';

      // Add folders
      await repo.addProjectFolder(p1.id, sharedFolder);
      await repo.addProjectFolder(p1.id, p1Folder);
      await repo.addProjectFolder(p2.id, sharedFolder);

      // Idempotency: adding again does not duplicate
      await repo.addProjectFolder(p1.id, sharedFolder);

      final p1Folders = await repo.getProjectFolders(p1.id);
      expect(p1Folders, equals([sharedFolder, p1Folder]));

      final p2Folders = await repo.getProjectFolders(p2.id);
      expect(p2Folders, equals([sharedFolder]));

      // Remove folder from p1
      await repo.removeProjectFolder(p1.id, p1Folder);
      expect(await repo.getProjectFolders(p1.id), equals([sharedFolder]));

      // Delete p1 removes its folder links, but does NOT affect p2 or p2's folders
      await repo.deleteProject(p1.id);
      expect(await repo.getProjects(), hasLength(1));
      expect(await repo.getProjectFolders(p2.id), equals([sharedFolder]));
    });
  });

  group('Collections and Selection', () {
    test('createCollection validates name and returns model', () async {
      expect(() => repo.createCollection(''), throwsArgumentError);
      final col = await repo.createCollection('Summer 2026');
      expect(col.name, equals('Summer 2026'));
      expect(col.id, isNotEmpty);

      final cols = await repo.getCollections();
      expect(cols.length, equals(1));
    });

    test('renameCollection updates name and validates not found', () async {
      expect(
        () => repo.renameCollection('no-id', 'Test'),
        throwsA(isA<OrganizationNotFoundException>()),
      );

      final col = await repo.createCollection('Old Name');
      final updated = await repo.renameCollection(col.id, 'New Name');
      expect(updated.name, equals('New Name'));
    });

    test('collection items: deterministic ordering, deduplication, isolated delete',
        () async {
      // Seed files and upload job into database
      final f1 = AppFile(
        id: 'file-1',
        path: '/a/1.jpg',
        filename: '1.jpg',
        createdAt: 10,
      );
      final f2 = AppFile(
        id: 'file-2',
        path: '/a/2.jpg',
        filename: '2.jpg',
        createdAt: 20,
      );
      await helper.insertFile(f1);
      await helper.insertFile(f2);

      final job = UploadJob(
        id: 'job-1',
        fileId: 'file-1',
        filePath: '/a/1.jpg',
        filename: '1.jpg',
        stockKey: 'shutterstock',
        protocol: UploadProtocol.ftps,
        status: UploadJobStatus.success,
        createdAt: 10,
        updatedAt: 10,
      );
      await helper.insertUploadJob(job);

      final col = await repo.createCollection('Best Shots');

      // Add file-1, file-2
      await repo.addFileToCollection(col.id, 'file-1');
      await repo.addFileToCollection(col.id, 'file-2');

      // Add duplicate file-1 -> ignored
      await repo.addFileToCollection(col.id, 'file-1');

      var items = await repo.getFileIdsInCollection(col.id);
      expect(items, equals(['file-1', 'file-2']));

      // Remove single file
      await repo.removeFileFromCollection(col.id, 'file-1');
      items = await repo.getFileIdsInCollection(col.id);
      expect(items, equals(['file-2']));

      // Delete collection col: does NOT delete files or upload jobs
      await repo.deleteCollection(col.id);
      expect(await repo.getCollections(), isEmpty);

      // Verify files and jobs still exist
      final allFiles = await helper.getAllFiles();
      expect(allFiles.map((f) => f.id).toList(), equals(['file-2', 'file-1']));
      final allJobs = await helper.getUploadJobs();
      expect(allJobs.length, equals(1));
      expect(allJobs.first.id, equals('job-1'));
    });

    test('selection ("Отбор") persists until explicit clear, deduplicates and keeps order',
        () async {
      expect(await repo.getSelectionFileIds(), isEmpty);

      await repo.addToSelection('file-a');
      await repo.addToSelection('file-b');
      await repo.addToSelection('file-c');

      // Deduplication: adding file-b again does not duplicate or change order
      await repo.addToSelection('file-b');

      expect(
        await repo.getSelectionFileIds(),
        equals(['file-a', 'file-b', 'file-c']),
      );

      // Remove one file
      await repo.removeFromSelection('file-b');
      expect(
        await repo.getSelectionFileIds(),
        equals(['file-a', 'file-c']),
      );

      // Explicit clear
      await repo.clearSelection();
      expect(await repo.getSelectionFileIds(), isEmpty);
    });
  });
}
