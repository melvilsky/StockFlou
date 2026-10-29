import 'dart:async';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../domain/organization_models.dart';

/// Local persistence for projects, collections and the persisted selection
/// ("Отбор"). Stores only references (AppFile ids, workspace folder paths);
/// it never touches originals, files, metadata or upload jobs. Ids that are
/// unknown to the caller can be recorded — registration of local files stays
/// with the existing catalog (see docs result notes for the contract).
class OrganizationRepository {
  final Future<Database> Function() _db;
  final Uuid? _uuid;

  OrganizationRepository(this._db, {Uuid? uuid}) : _uuid = uuid;

  Future<Database> _database() => _db();

  // ─── Projects ─────────────────────────────────────────────────────────────

  Future<Project> createProject(String name) async {
    final trimmed = _validateName(name, 'Project');
    final db = await _database();
    final now = DateTime.now().millisecondsSinceEpoch;
    final project = Project(
      id: (_uuid ?? const Uuid()).v4(),
      name: trimmed,
      pinned: false,
      archived: false,
      sortOrder: 0,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('projects', {
      'id': project.id,
      'name': project.name,
      'pinned': 0,
      'archived': 0,
      'sort_order': 0,
      'created_at': project.createdAt,
      'updated_at': project.updatedAt,
    });
    return project;
  }

  Future<List<Project>> getProjects() async {
    final db = await _database();
    final rows = await db.query(
      'projects',
      orderBy: 'pinned DESC, sort_order ASC, created_at ASC, id ASC',
    );
    return rows.map(_projectFromRow).toList();
  }

  Future<Project> renameProject(String id, String name) async {
    final trimmed = _validateName(name, 'Project');
    await _updateProject(id, {'name': trimmed});
    return _getProjectOrThrow(id);
  }

  Future<void> setProjectPinned(String id, {required bool pinned}) =>
      _updateProject(id, {'pinned': pinned ? 1 : 0});

  Future<void> setProjectArchived(String id, {required bool archived}) =>
      _updateProject(id, {'archived': archived ? 1 : 0});

  /// Persists the given project order: [orderedIds] must contain every project
  /// id exactly once. The first id becomes sort_order 0.
  Future<void> reorderProjects(List<String> orderedIds) async {
    final db = await _database();
    await db.transaction((txn) async {
      for (var index = 0; index < orderedIds.length; index++) {
        final updated = await txn.update(
          'projects',
          {'sort_order': index, 'updated_at': _now()},
          where: 'id = ?',
          whereArgs: [orderedIds[index]],
        );
        if (updated == 0) {
          throw OrganizationNotFoundException('Project', orderedIds[index]);
        }
      }
    });
  }

  /// Removes the project and its folder memberships only. Never touches
  /// files, metadata, upload jobs or the workspaces list.
  Future<void> deleteProject(String id) async {
    final db = await _database();
    await db.transaction((txn) async {
      await txn.delete('project_folders', where: 'project_id = ?', whereArgs: [id]);
      await txn.delete('projects', where: 'id = ?', whereArgs: [id]);
    });
  }

  // ─── Project folders ──────────────────────────────────────────────────────

  /// Adds a folder reference; idempotent, and a folder can belong to several
  /// projects.
  Future<void> addProjectFolder(String projectId, String folderPath) async {
    await _ensureProjectExists(projectId);
    final db = await _database();
    await db.insert(
      'project_folders',
      {'project_id': projectId, 'folder_path': folderPath, 'added_at': _now()},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> removeProjectFolder(String projectId, String folderPath) async {
    final db = await _database();
    await db.delete(
      'project_folders',
      where: 'project_id = ? AND folder_path = ?',
      whereArgs: [projectId, folderPath],
    );
  }

  Future<List<String>> getProjectFolders(String projectId) async {
    final db = await _database();
    final rows = await db.query(
      'project_folders',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'added_at ASC, folder_path ASC',
      columns: ['folder_path'],
    );
    return rows.map((row) => row['folder_path'] as String).toList();
  }

  // ─── Collections ───────────────────────────────────────────────────────────

  Future<Collection> createCollection(String name) async {
    final trimmed = _validateName(name, 'Collection');
    final db = await _database();
    final now = DateTime.now().millisecondsSinceEpoch;
    final collection = Collection(
      id: (_uuid ?? const Uuid()).v4(),
      name: trimmed,
      sortOrder: 0,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('collections', {
      'id': collection.id,
      'name': collection.name,
      'sort_order': 0,
      'created_at': collection.createdAt,
      'updated_at': collection.updatedAt,
    });
    return collection;
  }

  Future<List<Collection>> getCollections() async {
    final db = await _database();
    final rows = await db.query(
      'collections',
      orderBy: 'sort_order ASC, created_at ASC, id ASC',
    );
    return rows.map(_collectionFromRow).toList();
  }

  Future<Collection> renameCollection(String id, String name) async {
    final trimmed = _validateName(name, 'Collection');
    final db = await _database();
    final updated = await db.update(
      'collections',
      {'name': trimmed, 'updated_at': _now()},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (updated == 0) throw OrganizationNotFoundException('Collection', id);
    return _getCollectionOrThrow(id);
  }

  /// Removes the collection and its memberships only. Never deletes
  /// originals, files, metadata or upload jobs.
  Future<void> deleteCollection(String id) async {
    final db = await _database();
    await db.transaction((txn) async {
      await txn.delete('collection_items', where: 'collection_id = ?', whereArgs: [id]);
      await txn.delete('collections', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Adds a reference to an existing AppFile id. Duplicate memberships are
  /// ignored; the position of a new item is deterministic (max + 1).
  Future<void> addFileToCollection(String collectionId, String appFileId) async {
    final db = await _database();
    await db.insert(
      'collection_items',
      {
        'collection_id': collectionId,
        'app_file_id': appFileId,
        'position': await _nextPosition('collection_items', 'collection_id', collectionId),
        'added_at': _now(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> removeFileFromCollection(
    String collectionId,
    String appFileId,
  ) async {
    final db = await _database();
    await db.delete(
      'collection_items',
      where: 'collection_id = ? AND app_file_id = ?',
      whereArgs: [collectionId, appFileId],
    );
  }

  Future<void> clearCollection(String collectionId) async {
    final db = await _database();
    await db.delete('collection_items', where: 'collection_id = ?', whereArgs: [collectionId]);
  }

  /// AppFile ids in deterministic order.
  Future<List<String>> getFileIdsInCollection(String collectionId) async {
    final db = await _database();
    final rows = await db.query(
      'collection_items',
      where: 'collection_id = ?',
      whereArgs: [collectionId],
      orderBy: 'position ASC, app_file_id ASC',
      columns: ['app_file_id'],
    );
    return rows.map((row) => row['app_file_id'] as String).toList();
  }

  // ─── Selection ("Отбор") ───────────────────────────────────────────────────

  Future<List<String>> getSelectionFileIds() async {
    final db = await _database();
    final rows = await db.query(
      'selection_items',
      orderBy: 'position ASC, app_file_id ASC',
      columns: ['app_file_id'],
    );
    return rows.map((row) => row['app_file_id'] as String).toList();
  }

  /// Persists the selection until [clearSelection] is called. Idempotent.
  Future<void> addToSelection(String appFileId) async {
    final db = await _database();
    await db.insert(
      'selection_items',
      {'app_file_id': appFileId, 'position': await _nextPosition('selection_items', null, null)},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> removeFromSelection(String appFileId) async {
    final db = await _database();
    await db.delete('selection_items', where: 'app_file_id = ?', whereArgs: [appFileId]);
  }

  Future<void> clearSelection() async {
    final db = await _database();
    await db.delete('selection_items');
  }

  // ─── Internals ─────────────────────────────────────────────────────────────

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  String _validateName(String name, String kind) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, '$kind name', 'must not be empty');
    }
    return trimmed;
  }

  Future<int> _nextPosition(String table, String? idColumn, String? id) async {
    final db = await _database();
    final rows = await db.rawQuery(
      'SELECT COALESCE(MAX(position), -1) + 1 AS next FROM $table'
      '${idColumn != null ? ' WHERE $idColumn = ?' : ''}',
      idColumn != null ? [id] : null,
    );
    return (rows.first['next'] as int?) ?? 0;
  }

  Future<void> _ensureProjectExists(String id) async {
    final db = await _database();
    final rows = await db.query('projects', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) throw OrganizationNotFoundException('Project', id);
  }

  Future<void> _updateProject(String id, Map<String, Object?> updates) async {
    final db = await _database();
    final updated = await db.update(
      'projects',
      {...updates, 'updated_at': _now()},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (updated == 0) throw OrganizationNotFoundException('Project', id);
  }

  Future<Project> _getProjectOrThrow(String id) async {
    final db = await _database();
    final rows = await db.query('projects', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) throw OrganizationNotFoundException('Project', id);
    return _projectFromRow(rows.first);
  }

  Future<Collection> _getCollectionOrThrow(String id) async {
    final db = await _database();
    final rows = await db.query('collections', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) throw OrganizationNotFoundException('Collection', id);
    return _collectionFromRow(rows.first);
  }

  static Project _projectFromRow(Map<String, Object?> row) => Project(
        id: row['id'] as String,
        name: row['name'] as String,
        pinned: (row['pinned'] as int) == 1,
        archived: (row['archived'] as int) == 1,
        sortOrder: row['sort_order'] as int,
        createdAt: row['created_at'] as int,
        updatedAt: row['updated_at'] as int,
      );

  static Collection _collectionFromRow(Map<String, Object?> row) => Collection(
        id: row['id'] as String,
        name: row['name'] as String,
        sortOrder: row['sort_order'] as int,
        createdAt: row['created_at'] as int,
        updatedAt: row['updated_at'] as int,
      );
}
