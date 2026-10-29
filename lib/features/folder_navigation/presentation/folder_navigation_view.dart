import '../../../core/widgets/app_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/single_click_area.dart';
import '../domain/folder_access.dart';
import '../domain/folder_navigation_controller.dart';
import '../domain/folder_navigation_models.dart';

/// Навигация по подпапкам подключённой корневой папки (рабочей области).
///
/// Пример подключения:
/// ```dart
/// final navigation = FolderNavigationView(
///   rootFolder: currentWorkspace.path,
///   access: DefaultFolderAccessScope(currentWorkspace.path),
///   onSelection: (selection) {
///     // selection.path — выбранная папка,
//     // selection.includeSubfolders — режим «С подпапками»
///   },
/// );
/// ```
///
/// Стиль соответствует workspaces_sidebar_block: блок 12/12, элементы
/// SingleClickArea + InkWell, Semantics с selected/button.
class FolderNavigationView extends ConsumerStatefulWidget {
  const FolderNavigationView({
    super.key,
    required this.rootFolder,
    required this.access,
    this.onSelection,
  });

  /// Путь подключённой корневой папки (рабочей области).
  final String rootFolder;

  /// Контракт доступа: держит security scope, ограничивает чтение корнем.
  final FolderAccessScope access;

  /// Выдача выбора: путь папки и режим «С подпапками».
  final void Function(FolderSelection selection)? onSelection;

  @override
  ConsumerState<FolderNavigationView> createState() =>
      _FolderNavigationViewState();
}

class _FolderNavigationViewState extends ConsumerState<FolderNavigationView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _open();
    });
  }

  @override
  void didUpdateWidget(FolderNavigationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rootFolder != widget.rootFolder ||
        oldWidget.access != widget.access ||
        oldWidget.onSelection != widget.onSelection) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _open();
      });
    }
  }

  void _open() {
    ref
        .read(folderNavigationProvider.notifier)
        .open(
          rootPath: widget.rootFolder,
          access: widget.access,
          onSelection: widget.onSelection,
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(folderNavigationProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final blockBg =
        isDark
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
            : colorScheme.surfaceContainerLow;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: blockBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildToolbar(state, colorScheme),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: _buildTree(state, colorScheme),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(FolderNavigationState state, ColorScheme colorScheme) {
    return Row(
      children: [
        AppTooltip(
          message: 'Назад',
          child: SingleClickArea(
            onTap:
                state.canGoBack
                    ? () => ref.read(folderNavigationProvider.notifier).goBack()
                    : null,
            child: IconButton(
              onPressed:
                  state.canGoBack
                      ? () =>
                          ref.read(folderNavigationProvider.notifier).goBack()
                      : null,
              icon: Icon(
                Icons.arrow_back,
                size: 18,
                color:
                    state.canGoBack
                        ? colorScheme.primary
                        : colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
        AppTooltip(
          message: 'Вперёд',
          child: SingleClickArea(
            onTap:
                state.canGoForward
                    ? () =>
                        ref.read(folderNavigationProvider.notifier).goForward()
                    : null,
            child: IconButton(
              onPressed:
                  state.canGoForward
                      ? () =>
                          ref
                              .read(folderNavigationProvider.notifier)
                              .goForward()
                      : null,
              icon: Icon(
                Icons.arrow_forward,
                size: 18,
                color:
                    state.canGoForward
                        ? colorScheme.primary
                        : colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
        AppTooltip(
          message: 'На уровень вверх',
          child: SingleClickArea(
            onTap:
                state.rootPath != null && state.currentPath != state.rootPath
                    ? () =>
                        ref.read(folderNavigationProvider.notifier).navigateUp()
                    : null,
            child: IconButton(
              onPressed:
                  state.rootPath != null && state.currentPath != state.rootPath
                      ? () =>
                          ref
                              .read(folderNavigationProvider.notifier)
                              .navigateUp()
                      : null,
              icon: Icon(
                Icons.arrow_upward,
                size: 18,
                color:
                    state.rootPath != null &&
                            state.currentPath != state.rootPath
                        ? colorScheme.primary
                        : colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Текущий путь выбранной папки.
        Expanded(
          child: AppTooltip(
            message: state.currentPath ?? '',
            child: Text(
              state.currentPath ?? '',
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'С подпапками',
          style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 32,
          height: 32,
          child: Switch(
            value: state.includeSubfolders,
            onChanged:
                (value) => ref
                    .read(folderNavigationProvider.notifier)
                    .setIncludeSubfolders(value),
          ),
        ),
      ],
    );
  }

  Widget _buildTree(FolderNavigationState state, ColorScheme colorScheme) {
    final nodes = _visibleNodes(state);
    if (nodes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Нет папок',
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: nodes.length,
      itemBuilder:
          (context, index) => _buildRow(nodes[index], state, colorScheme),
    );
  }

  Widget _buildRow(
    _VisibleNode node,
    FolderNavigationState state,
    ColorScheme colorScheme,
  ) {
    final isSelected = node.item.path == state.currentPath;
    final nodeState = state.nodes[node.item.path];
    final item = node.item;

    final row = Material(
      color: Colors.transparent,
      child: SingleClickArea(
        onTap:
            () => ref
                .read(folderNavigationProvider.notifier)
                .selectFolder(item.path),
        child: Semantics(
          label:
              '${item.name}${item.isSymlink ? ', символическая ссылка' : ''}',
          selected: isSelected,
          button: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap:
                () => ref
                    .read(folderNavigationProvider.notifier)
                    .selectFolder(item.path),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color:
                    isSelected
                        ? colorScheme.primary.withValues(alpha: 0.15)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  SizedBox(width: 16.0 * node.depth),
                  _buildExpandToggle(node, item, state, colorScheme),
                  Icon(
                    item.isSymlink ? Icons.link : Icons.folder_outlined,
                    size: 18,
                    color:
                        isSelected
                            ? colorScheme.primary
                            : colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w600 : null,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (nodeState?.isLoading ?? false)
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          colorScheme.primary.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final children = <Widget>[row];
    if (nodeState?.hasError ?? false) {
      children.add(
        Padding(
          padding: EdgeInsets.only(left: 16.0 * (node.depth + 2)),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Не удалось прочитать папку',
                  style: TextStyle(fontSize: 11, color: colorScheme.error),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AppTooltip(
                message: 'Повторить чтение папки',
                child: SingleClickArea(
                  onTap:
                      () => ref
                          .read(folderNavigationProvider.notifier)
                          .reloadFolder(item.path),
                  child: IconButton(
                    onPressed:
                        () => ref
                            .read(folderNavigationProvider.notifier)
                            .reloadFolder(item.path),
                    icon: Icon(
                      Icons.refresh,
                      size: 16,
                      color: colorScheme.error,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else if (nodeState != null &&
        nodeState.isEmpty &&
        node.item.path != state.rootPath) {
      children.add(
        Padding(
          padding: EdgeInsets.only(left: 16.0 * (node.depth + 2)),
          child: Text(
            'Пусто',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
      );
    }
    if (children.length == 1) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _buildExpandToggle(
    _VisibleNode node,
    FolderNavigationItem item,
    FolderNavigationState state,
    ColorScheme colorScheme,
  ) {
    final isRoot = item.path == state.rootPath;
    if (isRoot) {
      return const SizedBox(width: 24);
    }
    if (item.isSymlink) {
      return const AppTooltip(
        message: 'Символьная ссылка не раскрывается',
        child: SizedBox(width: 24),
      );
    }
    final isExpanded = state.expandedPaths.contains(item.path);
    return AppTooltip(
      message: isExpanded ? 'Свернуть' : 'Развернуть',
      child: SingleClickArea(
        onTap:
            () => ref
                .read(folderNavigationProvider.notifier)
                .toggleExpand(item.path),
        child: SizedBox(
          width: 24,
          height: 24,
          child: Icon(
            isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
            size: 18,
            color: colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

class _VisibleNode {
  const _VisibleNode({required this.item, required this.depth});

  final FolderNavigationItem item;
  final int depth;
}

/// Плоский список видимых узлов дерева: раскрывает только узлы из
/// [state.expandedPaths] (лениво, без чтения файловой системы).
List<_VisibleNode> _visibleNodes(FolderNavigationState state) {
  final root = state.rootPath;
  if (root == null) return const [];
  final result = <_VisibleNode>[];
  final rootItem = FolderNavigationItem(
    path: root,
    name: _folderName(root),
    isSymlink: false,
  );
  result.add(_VisibleNode(item: rootItem, depth: 0));

  void visitChildren(String path, int depth) {
    final node = state.nodes[path];
    if (node == null || !node.isLoading && !node.hasError && node.isEmpty) {
      return;
    }
    for (final child in node.children) {
      if (!state.expandedPaths.contains(path)) continue;
      result.add(_VisibleNode(item: child, depth: depth));
      if (state.expandedPaths.contains(child.path) && !child.isSymlink) {
        visitChildren(child.path, depth + 1);
      }
    }
  }

  visitChildren(root, 1);
  return result;
}

String _folderName(String path) {
  final name = path.split('/').last;
  return name.isEmpty ? path : name;
}
