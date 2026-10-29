import 'package:path/path.dart' as p;

/// Тип области поиска.
enum SearchScopeType {
  folder,
  project,
  collection,
  selection,
  all,
}

/// Явно выбранная область поиска/фильтрации.
///
/// Поддерживает:
/// - конкретную папку [SearchScope.folder] с опциональным рекурсивным включением подпапок;
/// - проект [SearchScope.project] с объединением всех его папок;
/// - именованную коллекцию [SearchScope.collection] по списку AppFile.id;
/// - «Отбор» [SearchScope.selection] по списку AppFile.id;
/// - весь каталог [SearchScope.all].
class SearchScope {
  const SearchScope.folder({
    required String folderPath,
    this.includeSubfolders = false,
  })  : type = SearchScopeType.folder,
        targetId = folderPath;

  const SearchScope.project({
    required String projectId,
    this.includeSubfolders = false,
  })  : type = SearchScopeType.project,
        targetId = projectId;

  const SearchScope.collection({
    required String collectionId,
  })  : type = SearchScopeType.collection,
        targetId = collectionId,
        includeSubfolders = false;

  const SearchScope.selection()
      : type = SearchScopeType.selection,
        targetId = '',
        includeSubfolders = false;

  const SearchScope.all()
      : type = SearchScopeType.all,
        targetId = '',
        includeSubfolders = false;

  const SearchScope._raw({
    required this.type,
    required this.targetId,
    required this.includeSubfolders,
  });

  final SearchScopeType type;

  /// Идентификатор цели:
  /// - для folder: нормализованный путь папки;
  /// - для project: projectId;
  /// - для collection: collectionId;
  /// - для selection и all: пустая строка.
  final String targetId;

  /// Режим включения подпапок (для folder и project).
  final bool includeSubfolders;

  String get folderPath => type == SearchScopeType.folder ? targetId : '';
  String get projectId => type == SearchScopeType.project ? targetId : '';
  String get collectionId => type == SearchScopeType.collection ? targetId : '';

  SearchScope copyWith({
    SearchScopeType? type,
    String? targetId,
    bool? includeSubfolders,
  }) {
    return SearchScope._raw(
      type: type ?? this.type,
      targetId: targetId ?? this.targetId,
      includeSubfolders: includeSubfolders ?? this.includeSubfolders,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'target_id': targetId,
      'include_subfolders': includeSubfolders,
    };
  }

  factory SearchScope.fromMap(Map<String, dynamic> map) {
    final typeName = map['type'] as String? ?? 'all';
    final targetId = map['target_id'] as String? ?? '';
    final includeSubfolders = map['include_subfolders'] as bool? ?? false;

    final type = SearchScopeType.values.firstWhere(
      (e) => e.name == typeName,
      orElse: () => SearchScopeType.all,
    );

    switch (type) {
      case SearchScopeType.folder:
        return SearchScope.folder(
          folderPath: targetId.isNotEmpty ? p.canonicalize(targetId) : '',
          includeSubfolders: includeSubfolders,
        );
      case SearchScopeType.project:
        return SearchScope.project(
          projectId: targetId,
          includeSubfolders: includeSubfolders,
        );
      case SearchScopeType.collection:
        return SearchScope.collection(collectionId: targetId);
      case SearchScopeType.selection:
        return const SearchScope.selection();
      case SearchScopeType.all:
        return const SearchScope.all();
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchScope &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          targetId == other.targetId &&
          includeSubfolders == other.includeSubfolders;

  @override
  int get hashCode => Object.hash(type, targetId, includeSubfolders);

  @override
  String toString() =>
      'SearchScope(type: ${type.name}, targetId: $targetId, includeSubfolders: $includeSubfolders)';
}
