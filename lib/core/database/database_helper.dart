import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../models/app_file.dart';

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
      options: OpenDatabaseOptions(version: 1, onCreate: _createDB),
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
  created_at INTEGER NOT NULL
)
''');
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
}
