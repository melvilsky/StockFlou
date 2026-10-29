import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'folder_access.dart';
import 'folder_navigation_models.dart';

/// Контроллер навигации по подпапкам подключённого корня.
///
/// Гарантии:
/// — дерево раскрывается лениво: читаются только дети раскрытых узлов;
/// — пути вне подключённого корня игнорируются (path guard);
/// — папки-символьные ссылки не раскрываются автоматически;
/// — устаревшие результаты чтения отбрасываются при быстрой навигации.
class FolderNavigationController extends Notifier<FolderNavigationState> {
  FolderAccessScope? _access;
  void Function(FolderSelection selection)? _onSelection;
  bool _isDisposed = false;

  /// Идентификатор последнего запроса листинга узла. Результаты с другим
  /// идентификатором (или после очистки карты — например, при смене корня)
  /// считаются устаревшими и отбрасываются.
  final Map<String, int> _requestIds = {};
  int _nextRequestId = 0;

  int get _nextId => ++_nextRequestId;

  @override
  FolderNavigationState build() {
    ref.onDispose(() => _isDisposed = true);
    return const FolderNavigationState();
  }

  /// Подключает корневую папку. Повторный вызов с тем же корнем — no-op,
  /// с другим корнем — сбрасывает дерево, историю и выдаёт новый выбор.
  void open({
    required String rootPath,
    required FolderAccessScope access,
    void Function(FolderSelection selection)? onSelection,
  }) {
    final normalizedRoot = normalizeFolderPath(rootPath);
    if (state.rootPath == normalizedRoot &&
        _access == access &&
        _onSelection == onSelection) {
      return;
    }
    _access = access;
    _onSelection = onSelection;
    _requestIds.clear();
    state = FolderNavigationState(
      rootPath: normalizedRoot,
      currentPath: normalizedRoot,
      expandedPaths: {normalizedRoot},
      includeSubfolders: state.includeSubfolders,
    );
    _emitSelection(normalizedRoot);
    _loadChildren(normalizedRoot);
  }

  /// Текущий выбор (путь + режим «С подпапками»); null — корень не подключён.
  FolderSelection? get currentSelection {
    final path = state.currentPath;
    if (path == null) return null;
    return FolderSelection(
      path: path,
      includeSubfolders: state.includeSubfolders,
    );
  }

  void selectFolder(String path) {
    if (_isDisposed || !isPathInsideRoot(path, state.rootPath ?? '')) return;
    if (state.currentPath == path) return;
    final previous = state.currentPath;
    final back = List<String>.of(state.backHistory);
    if (previous != null) back.add(previous);
    state = state.copyWith(
      currentPath: path,
      backHistory: back,
      forwardHistory: <String>[],
    );
    _emitSelection(path);
  }

  /// Переход к родителю текущей папки в рамках подключённого корня.
  void navigateUp() {
    final current = state.currentPath;
    final root = state.rootPath;
    if (current == null || root == null) return;
    final parent = parentFolderPath(current);
    if (parent == null || !isPathInsideRoot(parent, root)) return;
    if (parent == current) return;
    selectFolder(parent);
  }

  void goBack() {
    if (_isDisposed || state.backHistory.isEmpty) return;
    final back = List<String>.of(state.backHistory);
    final path = back.removeLast();
    final forward = List<String>.of(state.forwardHistory);
    final current = state.currentPath;
    if (current != null) forward.add(current);
    state = state.copyWith(
      currentPath: path,
      backHistory: back,
      forwardHistory: forward,
    );
    _emitSelection(path);
  }

  void goForward() {
    if (_isDisposed || state.forwardHistory.isEmpty) return;
    final forward = List<String>.of(state.forwardHistory);
    final path = forward.removeLast();
    final back = List<String>.of(state.backHistory);
    final current = state.currentPath;
    if (current != null) back.add(current);
    state = state.copyWith(
      currentPath: path,
      backHistory: back,
      forwardHistory: forward,
    );
    _emitSelection(path);
  }

  /// Переключатель «С подпапками»: попадает в контракт выдачи выбора.
  void setIncludeSubfolders(bool value) {
    if (_isDisposed || state.includeSubfolders == value) return;
    state = state.copyWith(includeSubfolders: value);
    final current = state.currentPath;
    if (current != null) _emitSelection(current);
  }

  /// Раскрывает/сворачивает узел. Папки-символьные ссылки не раскрываются.
  void toggleExpand(String path) {
    if (_isDisposed || !isPathInsideRoot(path, state.rootPath ?? '')) return;
    final expanded = Set<String>.of(state.expandedPaths);
    final node = state.nodes[path];
    if (expanded.contains(path)) {
      expanded.remove(path);
    } else if (_isExpandableChild(path)) {
      expanded.add(path);
      if (node == null) {
        _loadChildren(path);
      }
    }
    if (!_samePaths(expanded, state.expandedPaths)) {
      state = state.copyWith(expandedPaths: expanded);
    }
  }

  bool _isExpandableChild(String path) {
    final parent = parentFolderPath(path);
    if (parent == null) return true; // сам корень
    final parentNode = state.nodes[parent];
    // Узел отображается только если его родитель загружен; не найден —
    // позволяем раскрыть (guard уже проверен выше).
    if (parentNode == null) return true;
    for (final child in parentNode.children) {
      if (child.path == path) return !child.isSymlink;
    }
    return true;
  }

  bool _samePaths(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final path in a) {
      if (!b.contains(path)) return false;
    }
    return true;
  }

  /// Повторяет чтение папки после ошибки.
  void reloadFolder(String path) {
    if (_isDisposed || !isPathInsideRoot(path, state.rootPath ?? '')) return;
    if (!state.expandedPaths.contains(path)) return;
    _loadChildren(path);
  }

  void _emitSelection(String path) {
    _onSelection?.call(
      FolderSelection(
        path: path,
        includeSubfolders: state.includeSubfolders,
      ),
    );
  }

  Future<void> _loadChildren(String path) async {
    final access = _access;
    if (access == null || _isDisposed) return;
    final requestId = _nextId;
    _requestIds[path] = requestId;
    state = state.copyWith(
      nodes: {...state.nodes, path: const FolderNodeState.loading()},
    );
    try {
      final children = await access.listSubfolders(path);
      if (_isDisposed ||
          _requestIds[path] != requestId ||
          state.rootPath == null) {
        return;
      }
      state = state.copyWith(
        nodes: {...state.nodes, path: FolderNodeState.ready(children)},
      );
    } catch (e) {
      if (_isDisposed ||
          _requestIds[path] != requestId ||
          state.rootPath == null) {
        return;
      }
      state = state.copyWith(
        nodes: {...state.nodes, path: FolderNodeState.error(e.toString())},
      );
    }
  }
}

/// Единственный глобальный экземпляр навигации: один подключённый корень
/// (текущая рабочая область) одновременно.
final folderNavigationProvider =
    NotifierProvider<FolderNavigationController, FolderNavigationState>(
      FolderNavigationController.new,
    );
