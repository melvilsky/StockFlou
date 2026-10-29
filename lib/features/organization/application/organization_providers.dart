import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../data/db_organization_repository.dart';
import '../domain/organization_models.dart';

export '../domain/organization_models.dart';
export '../data/db_organization_repository.dart';

/// Provider for the [OrganizationRepository] instance.
final organizationRepositoryProvider = Provider<OrganizationRepository>((ref) {
  return OrganizationRepository(() => DatabaseHelper.instance.database);
});

// ─── Projects ────────────────────────────────────────────────────────────────

class ProjectsNotifier extends AsyncNotifier<List<Project>> {
  @override
  Future<List<Project>> build() async {
    final repo = ref.watch(organizationRepositoryProvider);
    return repo.getProjects();
  }

  Future<Project> createProject(String name) async {
    final repo = ref.read(organizationRepositoryProvider);
    final project = await repo.createProject(name);
    ref.invalidateSelf();
    await future;
    return project;
  }

  Future<Project> renameProject(String id, String name) async {
    final repo = ref.read(organizationRepositoryProvider);
    final project = await repo.renameProject(id, name);
    ref.invalidateSelf();
    await future;
    return project;
  }

  Future<void> setProjectPinned(String id, {required bool pinned}) async {
    final repo = ref.read(organizationRepositoryProvider);
    await repo.setProjectPinned(id, pinned: pinned);
    ref.invalidateSelf();
    await future;
  }

  Future<void> setProjectArchived(String id, {required bool archived}) async {
    final repo = ref.read(organizationRepositoryProvider);
    await repo.setProjectArchived(id, archived: archived);
    ref.invalidateSelf();
    await future;
  }

  Future<void> reorderProjects(List<String> orderedIds) async {
    final repo = ref.read(organizationRepositoryProvider);
    await repo.reorderProjects(orderedIds);
    ref.invalidateSelf();
    await future;
  }

  Future<void> deleteProject(String id) async {
    final repo = ref.read(organizationRepositoryProvider);
    await repo.deleteProject(id);
    ref.invalidateSelf();
    ref.invalidate(projectFoldersProvider(id));
    await future;
  }
}

final projectsProvider =
    AsyncNotifierProvider<ProjectsNotifier, List<Project>>(() {
  return ProjectsNotifier();
});

class ProjectFoldersNotifier extends AsyncNotifier<List<String>> {
  ProjectFoldersNotifier(this.projectId);
  final String projectId;

  @override
  Future<List<String>> build() async {
    final repo = ref.watch(organizationRepositoryProvider);
    return repo.getProjectFolders(projectId);
  }

  Future<void> addFolder(String folderPath) async {
    final repo = ref.read(organizationRepositoryProvider);
    await repo.addProjectFolder(projectId, folderPath);
    ref.invalidateSelf();
    await future;
  }

  Future<void> removeFolder(String folderPath) async {
    final repo = ref.read(organizationRepositoryProvider);
    await repo.removeProjectFolder(projectId, folderPath);
    ref.invalidateSelf();
    await future;
  }
}

final projectFoldersProvider =
    AsyncNotifierProvider.family<ProjectFoldersNotifier, List<String>, String>(
  (projectId) => ProjectFoldersNotifier(projectId),
);

// ─── Collections ─────────────────────────────────────────────────────────────

class CollectionsNotifier extends AsyncNotifier<List<Collection>> {
  @override
  Future<List<Collection>> build() async {
    final repo = ref.watch(organizationRepositoryProvider);
    return repo.getCollections();
  }

  Future<Collection> createCollection(String name) async {
    final repo = ref.read(organizationRepositoryProvider);
    final collection = await repo.createCollection(name);
    ref.invalidateSelf();
    await future;
    return collection;
  }

  Future<Collection> renameCollection(String id, String name) async {
    final repo = ref.read(organizationRepositoryProvider);
    final collection = await repo.renameCollection(id, name);
    ref.invalidateSelf();
    await future;
    return collection;
  }

  Future<void> deleteCollection(String id) async {
    final repo = ref.read(organizationRepositoryProvider);
    await repo.deleteCollection(id);
    ref.invalidateSelf();
    ref.invalidate(collectionFileIdsProvider(id));
    await future;
  }
}

final collectionsProvider =
    AsyncNotifierProvider<CollectionsNotifier, List<Collection>>(() {
  return CollectionsNotifier();
});

class CollectionFileIdsNotifier extends AsyncNotifier<List<String>> {
  CollectionFileIdsNotifier(this.collectionId);
  final String collectionId;

  @override
  Future<List<String>> build() async {
    final repo = ref.watch(organizationRepositoryProvider);
    return repo.getFileIdsInCollection(collectionId);
  }

  Future<void> addFile(String appFileId) async {
    final repo = ref.read(organizationRepositoryProvider);
    await repo.addFileToCollection(collectionId, appFileId);
    ref.invalidateSelf();
    await future;
  }

  Future<void> removeFile(String appFileId) async {
    final repo = ref.read(organizationRepositoryProvider);
    await repo.removeFileFromCollection(collectionId, appFileId);
    ref.invalidateSelf();
    await future;
  }

  Future<void> clear() async {
    final repo = ref.read(organizationRepositoryProvider);
    await repo.clearCollection(collectionId);
    ref.invalidateSelf();
    await future;
  }
}

final collectionFileIdsProvider = AsyncNotifierProvider.family<
    CollectionFileIdsNotifier, List<String>, String>(
  (collectionId) => CollectionFileIdsNotifier(collectionId),
);

// ─── Selection ("Отбор") ─────────────────────────────────────────────────────

class SelectionFileIdsNotifier extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async {
    final repo = ref.watch(organizationRepositoryProvider);
    return repo.getSelectionFileIds();
  }

  Future<void> addFile(String appFileId) async {
    final repo = ref.read(organizationRepositoryProvider);
    await repo.addToSelection(appFileId);
    ref.invalidateSelf();
    await future;
  }

  Future<void> removeFile(String appFileId) async {
    final repo = ref.read(organizationRepositoryProvider);
    await repo.removeFromSelection(appFileId);
    ref.invalidateSelf();
    await future;
  }

  Future<void> clear() async {
    final repo = ref.read(organizationRepositoryProvider);
    await repo.clearSelection();
    ref.invalidateSelf();
    await future;
  }
}

final selectionFileIdsProvider =
    AsyncNotifierProvider<SelectionFileIdsNotifier, List<String>>(() {
  return SelectionFileIdsNotifier();
});
