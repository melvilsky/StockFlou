import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../models/app_file.dart';
import '../../models/upload_job.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('stockflou_state.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    sqfliteFfiInit();
    var databaseFactory = databaseFactoryFfi;

    final appDocDir = await getApplicationSupportDirectory();
    final dbPath = join(appDocDir.path, filePath);

    return await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 5,
        onCreate: _createDB,
        onUpgrade: _upgradeDB,
      ),
    );
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
  created_at INTEGER NOT NULL
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
  }

  Future<void> insertFile(AppFile file) async {
    final db = await instance.database;
    await db.insert(
      'files',
      file.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<AppFile>> getAllFiles() async {
    final db = await instance.database;
    final result = await db.query('files', orderBy: 'created_at DESC');
    return result.map((map) => AppFile.fromMap(map)).toList();
  }

  Future<void> updateFile(AppFile file) async {
    final db = await instance.database;
    await db.update(
      'files',
      file.toMap(),
      where: 'id = ?',
      whereArgs: [file.id],
    );
  }

  Future<void> deleteFile(String id) async {
    final db = await instance.database;
    await db.delete('files', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> insertUploadJob(UploadJob job) async {
    final db = await instance.database;
    await db.insert(
      'upload_jobs',
      job.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateUploadJob(UploadJob job) async {
    final db = await instance.database;
    await db.update(
      'upload_jobs',
      job.toMap(),
      where: 'id = ?',
      whereArgs: [job.id],
    );
  }

  Future<List<UploadJob>> getUploadJobs() async {
    final db = await instance.database;
    final result = await db.query('upload_jobs', orderBy: 'created_at DESC');
    return result.map((row) => UploadJob.fromMap(row)).toList();
  }
}
