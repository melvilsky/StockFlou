/// Пункт дерева папок: подпапка внутри подключённого корня.
class FolderNavigationItem {
  const FolderNavigationItem({
    required this.path,
    required this.name,
    required this.isSymlink,
  });

  /// Абсолютный путь папки (без завершающего слеша, кроме корня «/»).
  final String path;

  /// Отображаемое имя папки.
  final String name;

  /// true — папка-символьная ссылка. Такие узлы не раскрываются
  /// автоматически, чтобы рекурсивное чтение не попало в цикл или
  /// за пределы разрешённого корня.
  final bool isSymlink;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FolderNavigationItem &&
          runtimeType == other.runtimeType &&
          path == other.path &&
          name == other.name &&
          isSymlink == other.isSymlink;

  @override
  int get hashCode => Object.hash(path, name, isSymlink);
}

/// Состояние листинга одной папки: различает «загружается», «пусто» и «ошибка».
enum FolderNodeStatus { loading, ready, error }

class FolderNodeState {
  const FolderNodeState.loading()
    : status = FolderNodeStatus.loading,
      children = const <FolderNavigationItem>[],
      errorMessage = null;

  const FolderNodeState.ready(this.children)
    : status = FolderNodeStatus.ready,
      errorMessage = null;

  const FolderNodeState.error(String this.errorMessage)
    : status = FolderNodeStatus.error,
      children = const <FolderNavigationItem>[];

  final FolderNodeStatus status;
  final List<FolderNavigationItem> children;
  final String? errorMessage;

  bool get isLoading => status == FolderNodeStatus.loading;
  bool get hasError => status == FolderNodeStatus.error;
  bool get isEmpty => status == FolderNodeStatus.ready && children.isEmpty;
}

/// Выдача наружу: выбранный путь папки и режим «С подпапками».
class FolderSelection {
  const FolderSelection({
    required this.path,
    required this.includeSubfolders,
  });

  final String path;
  final bool includeSubfolders;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FolderSelection &&
          runtimeType == other.runtimeType &&
          path == other.path &&
          includeSubfolders == other.includeSubfolders;

  @override
  int get hashCode => Object.hash(path, includeSubfolders);

  @override
  String toString() =>
      'FolderSelection(path: $path, includeSubfolders: $includeSubfolders)';
}

/// Состояние навигации по дереву папок подключённого корня.
class FolderNavigationState {
  const FolderNavigationState({
    this.rootPath,
    this.currentPath,
    this.expandedPaths = const <String>{},
    this.nodes = const <String, FolderNodeState>{},
    this.backHistory = const <String>[],
    this.forwardHistory = const <String>[],
    this.includeSubfolders = false,
  });

  /// Нормализованный путь подключённого корня; null — корень не подключён.
  final String? rootPath;

  /// Текущий выбранный путь (всегда равен rootPath или находится внутри него).
  final String? currentPath;

  /// Пути раскрытых узлов (ленивое раскрытие: читаются только дети раскрытых узлов).
  final Set<String> expandedPaths;

  /// Состояние листинга по путям узлов.
  final Map<String, FolderNodeState> nodes;

  /// История переходов назад/вперёд (пути, последний элемент — предыдущий).
  final List<String> backHistory;
  final List<String> forwardHistory;

  /// Режим «С подпапками»: в выдаче [FolderSelection], сам модуль ничего
  /// рекурсивно не читает.
  final bool includeSubfolders;

  bool get canGoBack => backHistory.isNotEmpty;
  bool get canGoForward => forwardHistory.isNotEmpty;

  FolderNavigationState copyWith({
    String? rootPath,
    String? currentPath,
    Set<String>? expandedPaths,
    Map<String, FolderNodeState>? nodes,
    List<String>? backHistory,
    List<String>? forwardHistory,
    bool? includeSubfolders,
  }) {
    return FolderNavigationState(
      rootPath: rootPath ?? this.rootPath,
      currentPath: currentPath ?? this.currentPath,
      expandedPaths: expandedPaths ?? this.expandedPaths,
      nodes: nodes ?? this.nodes,
      backHistory: backHistory ?? this.backHistory,
      forwardHistory: forwardHistory ?? this.forwardHistory,
      includeSubfolders: includeSubfolders ?? this.includeSubfolders,
    );
  }
}
