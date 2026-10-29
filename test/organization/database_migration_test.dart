import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_flow/core/database/database_helper.dart';
import 'package:stock_flow/models/app_file.dart';
import 'package:stock_flow/models/upload_job.dart';

void main() {
  sqfliteFfiInit();
  final databaseFactory = databaseFactoryFfi;

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sf_db_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('Fresh database initializes at version 7 with all tables', () async {
    final helper = DatabaseHelper.forTest(tempDir.path);
    final db = await helper.database;

    final versionRows = await db.rawQuery('PRAGMA user_version');
    final version = versionRows.first.values.first as int;
    expect(version, equals(DatabaseHelper.databaseVersion));

    // Verify all expected tables exist
    final tablesRows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    );
    final tableNames = tablesRows.map((r) => r['name'] as String).toSet();

    expect(
      tableNames,
      containsAll([
        'files',
        'upload_jobs',
        'projects',
        'project_folders',
        'collections',
        'collection_items',
        'selection_items',
      ]),
    );

    // Verify no backup was created for a fresh database
    final backupFiles = tempDir
        .listSync()
        .where((e) => e.path.contains('.bak-'))
        .toList();
    expect(backupFiles, isEmpty);

    await db.close();
  });

  test('Upgrade from v6 preserves rows, creates verified backup including WAL',
      () async {
    final dbPath = p.join(tempDir.path, 'stock_flow_state.db');

    // 1. Manually create a v6 database using raw sqflite_common_ffi
    final v6Db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: (db, version) async {
          await db.execute('''
CREATE TABLE files (
  id TEXT PRIMARY KEY,
  path TEXT NOT NULL,
  filename TEXT NOT NULL,
  metadata_title TEXT,
  metadata_description TEXT,
  metadata_keywords TEXT,
  is_editorial INTEGER NOT NULL DEFAULT 0,
  editorial_city TEXT,
  editorial_country TEXT,
  editorial_date INTEGER,
  workflow_status TEXT NOT NULL DEFAULT 'new',
  created_at INTEGER NOT NULL,
  tags TEXT NOT NULL DEFAULT ''
)
''');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_files_path ON files(path)',
          );
          await db.execute('''
CREATE TABLE upload_jobs (
  id TEXT PRIMARY KEY,
  file_id TEXT NOT NULL,
  file_path TEXT NOT NULL,
  filename TEXT NOT NULL,
  stock_key TEXT NOT NULL,
  protocol TEXT NOT NULL,
  status TEXT NOT NULL,
  progress REAL NOT NULL DEFAULT 0,
  error_message TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''');
        },
      ),
    );

    // Switch to WAL mode to verify WAL folding during backup
    await v6Db.execute('PRAGMA journal_mode=WAL');

    // Insert sample files and upload jobs into v6
    await v6Db.insert('files', {
      'id': 'file-1',
      'path': '/media/pic1.jpg',
      'filename': 'pic1.jpg',
      'metadata_title': 'Mountain Sunrise',
      'metadata_description': 'Beautiful dawn',
      'metadata_keywords': 'mountain,sunrise',
      'is_editorial': 0,
      'editorial_city': null,
      'editorial_country': null,
      'editorial_date': null,
      'workflow_status': 'new',
      'created_at': 1700000000,
      'tags': 'ai_generated',
    });

    await v6Db.insert('upload_jobs', {
      'id': 'job-1',
      'file_id': 'file-1',
      'file_path': '/media/pic1.jpg',
      'filename': 'pic1.jpg',
      'stock_key': 'adobe',
      'protocol': 'sftp',
      'status': 'pending',
      'progress': 0.0,
      'error_message': null,
      'created_at': 1700000001,
      'updated_at': 1700000001,
    });

    // Close without checkpointing to leave state in WAL if any
    await v6Db.close();

    // 2. Open via DatabaseHelper to trigger backup and migration
    final helper = DatabaseHelper.forTest(tempDir.path);
    final migratedDb = await helper.database;

    final versionRows = await migratedDb.rawQuery('PRAGMA user_version');
    final version = versionRows.first.values.first as int;
    expect(version, equals(7));

    // Verify backup file exists
    final backupPath = '$dbPath.bak-v6';
    final backupFile = File(backupPath);
    expect(await backupFile.exists(), isTrue);
    expect(await backupFile.length(), greaterThan(0));

    // Verify backup integrity and version
    final backupDb = await databaseFactory.openDatabase(backupPath);
    try {
      final integrity = await backupDb.rawQuery('PRAGMA integrity_check');
      expect(integrity.first.values.first, equals('ok'));

      final backupVersion =
          (await backupDb.rawQuery('PRAGMA user_version')).first.values.first;
      expect(backupVersion, equals(6));

      // Backup contains old rows
      final backupFiles = await backupDb.query('files');
      expect(backupFiles.length, equals(1));
      expect(backupFiles.first['id'], equals('file-1'));
    } finally {
      await backupDb.close();
    }

    // Verify migrated DB contains old rows intact
    final files = await helper.getAllFiles();
    expect(files.length, equals(1));
    expect(files.first.id, equals('file-1'));
    expect(files.first.metadataTitle, equals('Mountain Sunrise'));
    expect(files.first.tags, equals(['ai_generated']));

    final jobs = await helper.getUploadJobs();
    expect(jobs.length, equals(1));
    expect(jobs.first.id, equals('job-1'));
    expect(jobs.first.stockKey, equals('adobe'));

    // Verify new organization tables exist and are functional
    final orgTables = await migratedDb.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('projects', 'collections', 'selection_items')",
    );
    expect(orgTables.length, equals(3));

    await migratedDb.close();
  });

  test('Concurrent calls to database getter do not re-run backup or open multiple connections',
      () async {
    final dbPath = p.join(tempDir.path, 'stock_flow_state.db');

    // Create v6 db
    final v6Db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE files (id TEXT PRIMARY KEY, path TEXT NOT NULL, filename TEXT NOT NULL, is_editorial INTEGER NOT NULL DEFAULT 0, workflow_status TEXT NOT NULL DEFAULT "new", created_at INTEGER NOT NULL, tags TEXT NOT NULL DEFAULT "")');
          await db.execute('CREATE TABLE upload_jobs (id TEXT PRIMARY KEY, file_id TEXT NOT NULL, file_path TEXT NOT NULL, filename TEXT NOT NULL, stock_key TEXT NOT NULL, protocol TEXT NOT NULL, status TEXT NOT NULL, progress REAL NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)');
        },
      ),
    );
    await v6Db.close();

    final helper = DatabaseHelper.forTest(tempDir.path);

    // Call getter concurrently 5 times
    final results = await Future.wait([
      helper.database,
      helper.database,
      helper.database,
      helper.database,
      helper.database,
    ]);

    // All should resolve to the exact same instance
    for (var i = 1; i < results.length; i++) {
      expect(identical(results[0], results[i]), isTrue);
    }

    // Exactly one backup file exists
    final backups = tempDir
        .listSync()
        .where((e) => e.path.contains('.bak-'))
        .toList();
    expect(backups.length, equals(1));

    await results[0].close();
  });

  test('deleteFile cascades to collection_items and selection_items without touching collections or jobs',
      () async {
    final helper = DatabaseHelper.forTest(tempDir.path);
    final db = await helper.database;

    // Insert 2 files
    final file1 = AppFile(
      id: 'f-1',
      path: '/media/f1.jpg',
      filename: 'f1.jpg',
      createdAt: 100,
    );
    final file2 = AppFile(
      id: 'f-2',
      path: '/media/f2.jpg',
      filename: 'f2.jpg',
      createdAt: 200,
    );
    await helper.insertFile(file1);
    await helper.insertFile(file2);

    // Insert an upload job for f-1 and f-2
    final job1 = UploadJob(
      id: 'j-1',
      fileId: 'f-1',
      filePath: '/media/f1.jpg',
      filename: 'f1.jpg',
      stockKey: 'adobe',
      protocol: UploadProtocol.sftp,
      status: UploadJobStatus.pending,
      createdAt: 100,
      updatedAt: 100,
    );
    await helper.insertUploadJob(job1);

    // Insert a collection with items
    await db.insert('collections', {
      'id': 'col-1',
      'name': 'My Collection',
      'sort_order': 0,
      'created_at': 100,
      'updated_at': 100,
    });
    await db.insert('collection_items', {
      'collection_id': 'col-1',
      'app_file_id': 'f-1',
      'position': 0,
      'added_at': 100,
    });
    await db.insert('collection_items', {
      'collection_id': 'col-1',
      'app_file_id': 'f-2',
      'position': 1,
      'added_at': 101,
    });

    // Insert selection items
    await db.insert('selection_items', {'app_file_id': 'f-1', 'position': 0});
    await db.insert('selection_items', {'app_file_id': 'f-2', 'position': 1});

    // Delete f-1
    await helper.deleteFile('f-1');

    // f-1 is gone, f-2 remains in files
    final files = await helper.getAllFiles();
    expect(files.map((f) => f.id), equals(['f-2']));

    // Collection col-1 still exists
    final cols = await db.query('collections');
    expect(cols.length, equals(1));
    expect(cols.first['id'], equals('col-1'));

    // collection_items has f-2 only (f-1 removed)
    final colItems = await db.query('collection_items');
    expect(colItems.length, equals(1));
    expect(colItems.first['app_file_id'], equals('f-2'));

    // selection_items has f-2 only
    final selItems = await db.query('selection_items');
    expect(selItems.length, equals(1));
    expect(selItems.first['app_file_id'], equals('f-2'));

    // upload_jobs are NOT deleted when file is deleted (history preserved)
    final jobs = await helper.getUploadJobs();
    expect(jobs.length, equals(1));
    expect(jobs.first.id, equals('j-1'));

    await db.close();
  });
}
