import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../models/app_file.dart';
import '../../models/upload_job.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static const _databaseFileName = 'stock_flow_state.db';
  static const _legacyDatabaseFileName = 'stockflou_state.db';
  static const databaseVersion = 7;

  DatabaseHelper._init([this._directoryPath]);

  final String? _directoryPath;
  Database? _database;
  Future<Database>? _databaseInit;

  /// Instance for tests: same behavior, but rooted at [directoryPath] so the
  /// real user database is never opened.
  static DatabaseHelper forTest(String directoryPath) =>
      DatabaseHelper._init(directoryPath);

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;
    // Concurrent callers share one init Future: a second connection is never
    // opened and the pre-upgrade backup never runs twice.
    final init = _databaseInit ??= _initDB(_databaseFileName);
    try {
      final db = await init;
      _database = db;
      return db;
    } finally {
      if (identical(_databaseInit, init)) _databaseInit = null;
    }
  }

  Future<Database> _initDB(String filePath) async {
    sqfliteFfiInit();
    var databaseFactory = databaseFactoryFfi;

    final appDocDir = _directoryPath ??
        (await getApplicationSupportDirectory()).path;
    await _migrateLegacyDatabaseFile(appDocDir);
    final dbPath = join(appDocDir, filePath);
    await _backupBeforeUpgrade(dbPath, databaseVersion);

    return await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: databaseVersion,
        onCreate: _createDB,
        onUpgrade: _upgradeDB,
      ),
    );
  }

  Future<void> _migrateLegacyDatabaseFile(String directoryPath) async {
    final newDbPath = join(directoryPath, _databaseFileName);
    final legacyDbPath = join(directoryPath, _legacyDatabaseFileName);

    if (await File(newDbPath).exists() || !await File(legacyDbPath).exists()) {
      return;
    }

    for (final suffix in ['', '-wal', '-shm']) {
      final legacyFile = File('$legacyDbPath$suffix');
      if (await legacyFile.exists()) {
        await legacyFile.copy('$newDbPath$suffix');
      }
    }
  }

  /// Creates a verified backup before the schema upgrade runs. The copy is
  /// made by SQLite itself via `VACUUM INTO`, so an active WAL is folded in
  /// correctly. If the backup cannot be created or verified, opening (and thus
  /// migrating) aborts instead of risking user data.
  Future<void> _backupBeforeUpgrade(String dbPath, int targetVersion) async {
    if (!await File(dbPath).exists()) return;

    final probe = await databaseFactoryFfi.openDatabase(dbPath);
    try {
      final rows = await probe.rawQuery('PRAGMA user_version');
      final currentVersion = (rows.first.values.first as int?) ?? 0;
      if (currentVersion <= 0 || currentVersion >= targetVersion) return;

      final backupPath = '$dbPath.bak-v$currentVersion';
      final backupFile = File(backupPath);
      if (await backupFile.exists()) {
        await backupFile.delete();
      }
      final escapedPath = backupPath.replaceAll("'", "''");
      await probe.execute("VACUUM INTO '$escapedPath'");

      // Verify the backup: readable, non-empty, intact, at the expected
      // version.
      final backup = await databaseFactoryFfi.openDatabase(backupPath);
      try {
        final integrity = await backup.rawQuery('PRAGMA integrity_check');
        if (integrity.first.values.first != 'ok') {
          throw StateError('Backup integrity check failed: $backupPath');
        }
        final rows = await backup.rawQuery('PRAGMA user_version');
        if ((rows.first.values.first as int?) != currentVersion) {
          throw StateError('Unexpected backup version: $backupPath');
        }
      } finally {
        await backup.close();
      }
      if (await backupFile.length() == 0) {
        throw StateError('Backup is empty: $backupPath');
      }
    } finally {
      await probe.close();
    }
  }

  Future _createDB(Database db, int version) async {
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
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_upload_jobs_status ON upload_jobs(status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_upload_jobs_file ON upload_jobs(file_id)',
    );
    if (version >= 7) {
      await _createOrganizationTables(db);
    }
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE files ADD COLUMN is_editorial INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE files ADD COLUMN editorial_city TEXT');
      await db.execute('ALTER TABLE files ADD COLUMN editorial_country TEXT');
      await db.execute('ALTER TABLE files ADD COLUMN editorial_date INTEGER');
    }
    if (oldVersion < 4) {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_files_path ON files(path)',
      );
    }
    if (oldVersion < 5) {
      await db.execute(
        "ALTER TABLE files ADD COLUMN workflow_status TEXT NOT NULL DEFAULT 'new'",
      );
      await db.execute('''
    CREATE TABLE IF NOT EXISTS upload_jobs (
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
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_upload_jobs_status ON upload_jobs(status)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_upload_jobs_file ON upload_jobs(file_id)',
      );
    }
    if (oldVersion < 6) {
      await db.execute(
        "ALTER TABLE files ADD COLUMN tags TEXT NOT NULL DEFAULT ''",
      );
    }
    if (oldVersion < 7) {
      await _createOrganizationTables(db);
    }
  }

  Future _createOrganizationTables(Database db) async {
    await db.execute('''
    CREATE TABLE IF NOT EXISTS projects (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  pinned INTEGER NOT NULL DEFAULT 0,
  archived INTEGER NOT NULL DEFAULT 0,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''');
    await db.execute('''
    CREATE TABLE IF NOT EXISTS project_folders (
  project_id TEXT NOT NULL,
  folder_path TEXT NOT NULL,
  added_at INTEGER NOT NULL,
  PRIMARY KEY (project_id, folder_path)
)
''');
    await db.execute('''
    CREATE TABLE IF NOT EXISTS collections (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''');
    await db.execute('''
    CREATE TABLE IF NOT EXISTS collection_items (
  collection_id TEXT NOT NULL,
  app_file_id TEXT NOT NULL,
  position INTEGER NOT NULL,
  added_at INTEGER NOT NULL,
  PRIMARY KEY (collection_id, app_file_id)
)
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_collection_items_position ON collection_items(collection_id, position)',
    );
    await db.execute('''
    CREATE TABLE IF NOT EXISTS selection_items (
  app_file_id TEXT PRIMARY KEY,
  position INTEGER NOT NULL
)
''');
  }

  Future<void> insertFile(AppFile file) async {
    final db = await database;
    await db.insert(
      'files',
      file.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<AppFile>> getAllFiles() async {
    final db = await database;
    final result = await db.query('files', orderBy: 'created_at DESC');
    return result.map((map) => AppFile.fromMap(map)).toList();
  }

  Future<void> updateFile(AppFile file) async {
    final db = await database;
    await db.update(
      'files',
      file.toMap(),
      where: 'id = ?',
      whereArgs: [file.id],
    );
  }

  Future<void> deleteFile(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('files', where: 'id = ?', whereArgs: [id]);
      // Membership rows are only references; removing a file from the
      // catalog drops its references, never the other way around.
      await txn.delete(
        'collection_items',
        where: 'app_file_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'selection_items',
        where: 'app_file_id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> insertUploadJob(UploadJob job) async {
    final db = await database;
    await db.insert(
      'upload_jobs',
      job.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateUploadJob(UploadJob job) async {
    final db = await database;
    await db.update(
      'upload_jobs',
      job.toMap(),
      where: 'id = ?',
      whereArgs: [job.id],
    );
  }

  Future<List<UploadJob>> getUploadJobs() async {
    final db = await database;
    final result = await db.query('upload_jobs', orderBy: 'created_at DESC');
    return result.map((row) => UploadJob.fromMap(row)).toList();
  }

  Future<void> clearInactiveJobs() async {
    final db = await database;
    await db.delete(
      'upload_jobs',
      where: 'status IN (?, ?, ?)',
      whereArgs: ['success', 'cancelled', 'error'],
    );
  }
}
