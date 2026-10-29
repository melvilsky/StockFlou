/// A project is a logical group of connected folders. It never owns, copies
/// or moves files; the old workspaces list (SharedPreferences + bookmarks)
/// stays untouched and folder paths may overlap between projects.
class Project {
  final String id;
  final String name;
  final bool pinned;
  final bool archived;
  final int sortOrder;
  final int createdAt;
  final int updatedAt;

  const Project({
    required this.id,
    required this.name,
    required this.pinned,
    required this.archived,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  static const String idField = 'id';
  static const String nameField = 'name';
  static const String pinnedField = 'pinned';
  static const String archivedField = 'archived';
  static const String sortOrderField = 'sort_order';
  static const String createdAtField = 'created_at';
  static const String updatedAtField = 'updated_at';

  @override
  String toString() =>
      'Project(id: $id, name: $name, pinned: $pinned, archived: $archived, '
      'sortOrder: $sortOrder)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Project && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A collection holds ordered references to existing AppFile ids. It stores
/// no copies of file metadata, and removing a collection (or a membership)
/// never deletes originals, metadata or upload history.
class Collection {
  final String id;
  final String name;
  final int sortOrder;
  final int createdAt;
  final int updatedAt;

  const Collection({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  String toString() => 'Collection(id: $id, name: $name)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Collection && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Thrown when an update targets a project or collection that does not exist.
class OrganizationNotFoundException implements Exception {
  final String entityKind;
  final String id;

  const OrganizationNotFoundException(this.entityKind, this.id);

  @override
  String toString() => '$entityKind not found: $id';
}
