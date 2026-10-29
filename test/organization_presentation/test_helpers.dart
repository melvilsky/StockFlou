import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stock_flow/features/organization/application/organization_providers.dart';

/// Тестовая реализация [OrganizationRepository] в оперативной памяти с
/// протоколированием вызовов.
class FakeOrganizationRepository implements OrganizationRepository {
  final List<Project> projects = [];
  final Map<String, List<String>> projectFolders = {};
  final List<Collection> collections = [];
  final Map<String, List<String>> collectionFiles = {};
  final List<String> selectionFiles = [];

  final List<String> recordedCalls = [];

  int _nextId = 1;

  @override
  Future<Project> createProject(String name) async {
    recordedCalls.add('createProject($name)');
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Project name cannot be empty');
    final project = Project(
      id: 'proj_${_nextId++}',
      name: trimmed,
      pinned: false,
      archived: false,
      sortOrder: projects.length,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    projects.add(project);
    return project;
  }

  @override
  Future<List<Project>> getProjects() async {
    recordedCalls.add('getProjects()');
    return List.from(projects);
  }

  @override
  Future<Project> renameProject(String id, String name) async {
    recordedCalls.add('renameProject($id, $name)');
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Project name cannot be empty');
    final idx = projects.indexWhere((p) => p.id == id);
    if (idx < 0) throw OrganizationNotFoundException('Project', id);
    final old = projects[idx];
    final updated = Project(
      id: old.id,
      name: trimmed,
      pinned: old.pinned,
      archived: old.archived,
      sortOrder: old.sortOrder,
      createdAt: old.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    projects[idx] = updated;
    return updated;
  }

  @override
  Future<void> setProjectPinned(String id, {required bool pinned}) async {
    recordedCalls.add('setProjectPinned($id, pinned: $pinned)');
    final idx = projects.indexWhere((p) => p.id == id);
    if (idx < 0) throw OrganizationNotFoundException('Project', id);
    final old = projects[idx];
    projects[idx] = Project(
      id: old.id,
      name: old.name,
      pinned: pinned,
      archived: old.archived,
      sortOrder: old.sortOrder,
      createdAt: old.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Future<void> setProjectArchived(String id, {required bool archived}) async {
    recordedCalls.add('setProjectArchived($id, archived: $archived)');
    final idx = projects.indexWhere((p) => p.id == id);
    if (idx < 0) throw OrganizationNotFoundException('Project', id);
    final old = projects[idx];
    projects[idx] = Project(
      id: old.id,
      name: old.name,
      pinned: old.pinned,
      archived: archived,
      sortOrder: old.sortOrder,
      createdAt: old.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Future<void> reorderProjects(List<String> orderedIds) async {
    recordedCalls.add('reorderProjects($orderedIds)');
  }

  @override
  Future<void> deleteProject(String id) async {
    recordedCalls.add('deleteProject($id)');
    projects.removeWhere((p) => p.id == id);
    projectFolders.remove(id);
  }

  @override
  Future<List<String>> getProjectFolders(String projectId) async {
    recordedCalls.add('getProjectFolders($projectId)');
    return List.from(projectFolders[projectId] ?? const []);
  }

  @override
  Future<void> addProjectFolder(String projectId, String folderPath) async {
    recordedCalls.add('addProjectFolder($projectId, $folderPath)');
    final list = projectFolders.putIfAbsent(projectId, () => []);
    if (!list.contains(folderPath)) {
      list.add(folderPath);
    }
  }

  @override
  Future<void> removeProjectFolder(String projectId, String folderPath) async {
    recordedCalls.add('removeProjectFolder($projectId, $folderPath)');
    projectFolders[projectId]?.remove(folderPath);
  }

  @override
  Future<Collection> createCollection(String name) async {
    recordedCalls.add('createCollection($name)');
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Collection name cannot be empty');
    final collection = Collection(
      id: 'col_${_nextId++}',
      name: trimmed,
      sortOrder: collections.length,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    collections.add(collection);
    return collection;
  }

  @override
  Future<List<Collection>> getCollections() async {
    recordedCalls.add('getCollections()');
    return List.from(collections);
  }

  @override
  Future<Collection> renameCollection(String id, String name) async {
    recordedCalls.add('renameCollection($id, $name)');
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Collection name cannot be empty');
    final idx = collections.indexWhere((c) => c.id == id);
    if (idx < 0) throw OrganizationNotFoundException('Collection', id);
    final old = collections[idx];
    final updated = Collection(
      id: old.id,
      name: trimmed,
      sortOrder: old.sortOrder,
      createdAt: old.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    collections[idx] = updated;
    return updated;
  }

  @override
  Future<void> deleteCollection(String id) async {
    recordedCalls.add('deleteCollection($id)');
    collections.removeWhere((c) => c.id == id);
    collectionFiles.remove(id);
  }

  @override
  Future<List<String>> getFileIdsInCollection(String collectionId) async {
    recordedCalls.add('getFileIdsInCollection($collectionId)');
    return List.from(collectionFiles[collectionId] ?? const []);
  }

  @override
  Future<void> addFileToCollection(String collectionId, String appFileId) async {
    recordedCalls.add('addFileToCollection($collectionId, $appFileId)');
    final list = collectionFiles.putIfAbsent(collectionId, () => []);
    if (!list.contains(appFileId)) {
      list.add(appFileId);
    }
  }

  @override
  Future<void> removeFileFromCollection(
    String collectionId,
    String appFileId,
  ) async {
    recordedCalls.add('removeFileFromCollection($collectionId, $appFileId)');
    collectionFiles[collectionId]?.remove(appFileId);
  }

  @override
  Future<void> clearCollection(String collectionId) async {
    recordedCalls.add('clearCollection($collectionId)');
    collectionFiles[collectionId]?.clear();
  }

  @override
  Future<List<String>> getSelectionFileIds() async {
    recordedCalls.add('getSelectionFileIds()');
    return List.from(selectionFiles);
  }

  @override
  Future<void> addToSelection(String appFileId) async {
    recordedCalls.add('addToSelection($appFileId)');
    if (!selectionFiles.contains(appFileId)) {
      selectionFiles.add(appFileId);
    }
  }

  @override
  Future<void> removeFromSelection(String appFileId) async {
    recordedCalls.add('removeFromSelection($appFileId)');
    selectionFiles.remove(appFileId);
  }

  @override
  Future<void> clearSelection() async {
    recordedCalls.add('clearSelection()');
    selectionFiles.clear();
  }
}

Widget buildTestAppWithRepo({
  required Widget child,
  required OrganizationRepository repo,
  List<dynamic> extraOverrides = const [],
}) {
  return ProviderScope(
    overrides: [
      organizationRepositoryProvider.overrideWithValue(repo),
      ...extraOverrides.cast(),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: child,
      ),
    ),
  );
}
