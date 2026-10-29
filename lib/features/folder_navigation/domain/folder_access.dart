import 'dart:io';

import 'package:macos_secure_bookmarks/macos_secure_bookmarks.dart';

import 'folder_navigation_models.dart';

/// Контракт доступа к папкам в пределах подключённого корня.
///
/// Это единственная точка чтения файловой системы модуля навигации.
/// Реализация обязана:
/// 1. держать macOS security scope активным на время операций
///    [exists]/[listSubfolders] (на macOS — start/stopAccessingSecurityScopedResource
///    корневой рабочей области, как в workspacesProvider/generation_screen);
/// 2. не выполнять чтение путей вне [rootPath] (guard).
abstract class FolderAccessScope {
  const FolderAccessScope();

  /// Нормализованный путь подключённого корня.
  String get rootPath;

  /// Проверяет, что папка [path] существует (и доступна для чтения).
  Future<bool> exists(String path);

  /// Возвращает подпапки [path], отсортированные по имени.
  /// Пустой список — папка существует, но подпапок нет;
  /// ошибки доступа/чтения бросаются как исключение.
  ///
  /// Папки-символьные ссылки включаются с isSymlink = true.
  /// Сами ссылки по символическим путям не открываются.
  Future<List<FolderNavigationItem>> listSubfolders(String path);
}

/// Нормализация пути для path guard: без завершающих слешей (кроме корня «/»),
/// без изменения регистра и без разыменования симлинков — совпадает с
/// normalizeWorkspacePath из lib/core/state/workspaces_provider.dart.
String normalizeFolderPath(String path) {
  if (path.isEmpty) return '';
  if (RegExp(r'^/+$').hasMatch(path)) return '/';
  return path.replaceAll(RegExp(r'/+$'), '');
}

/// Возвращает родительский posix-путь или null, если [path] — корень «/».
String? parentFolderPath(String path) {
  if (path.isEmpty || path == '/') return null;
  final withoutTrailing = normalizeFolderPath(path);
  if (withoutTrailing == '/') return null;
  final index = withoutTrailing.lastIndexOf('/');
  if (index < 0) return null;
  if (index == 0) return '/';
  return withoutTrailing.substring(0, index);
}

String _normalizeMacPrivate(String path) {
  if (Platform.isMacOS) {
    if (path.startsWith('/private/var/')) {
      return path.substring('/private'.length);
    }
    if (path == '/private/var') return '/var';
    if (path.startsWith('/private/tmp/')) {
      return path.substring('/private'.length);
    }
    if (path == '/private/tmp') return '/tmp';
  }
  return path;
}

/// true, если [candidate] — это [rootPath] или путь внутри него.
bool isPathInsideRoot(String candidate, String rootPath) {
  final c = _normalizeMacPrivate(normalizeFolderPath(candidate));
  final r = _normalizeMacPrivate(normalizeFolderPath(rootPath));
  if (c == r) return true;
  if (r == '/') return c.length > 1 && c.startsWith('/');
  return c.startsWith('$r/');
}

/// Проверяет принадлежность файла или подпапки [filePath] к папке [folderPath].
/// При [includeSubfolders: false] возвращает true только для непосредственных потомков.
bool isPathInFolder(
  String filePath,
  String folderPath, {
  required bool includeSubfolders,
}) {
  final f = _normalizeMacPrivate(normalizeFolderPath(filePath));
  final root = _normalizeMacPrivate(normalizeFolderPath(folderPath));
  if (root.isEmpty) return false;
  if (f == root) return true;
  final prefix = root == '/' ? '/' : '$root/';
  if (!f.startsWith(prefix)) return false;
  if (includeSubfolders) return true;
  final rel = f.substring(prefix.length);
  return !rel.contains('/');
}

class DefaultFolderAccessScope implements FolderAccessScope {
  const DefaultFolderAccessScope(this.rootPath);

  @override
  final String rootPath;

  void _guard(String path) {
    if (!isPathInsideRoot(normalizeFolderPath(path), rootPath)) {
      throw ArgumentError('Путь вне подключённого корня: $path');
    }
  }

  @override
  Future<bool> exists(String path) {
    _guard(path);
    return Directory(path).exists();
  }

  @override
  Future<List<FolderNavigationItem>> listSubfolders(String path) async {
    _guard(path);
    final entities = await Directory(path).list(followLinks: false).toList();
    final folders = <FolderNavigationItem>[];
    for (final entity in entities) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      String name = entity.path;
      final lastSlash = name.lastIndexOf('/');
      if (lastSlash >= 0) {
        name = name.substring(lastSlash + 1);
      }
      if (type == FileSystemEntityType.directory) {
        folders.add(
          FolderNavigationItem(path: entity.path, name: name, isSymlink: false),
        );
      } else if (type == FileSystemEntityType.link) {
        // Тип цели ссылки определяем с followLinks: true, но не сканируем её содержимое
        final resolvedType = await FileSystemEntity.type(entity.path, followLinks: true);
        if (resolvedType == FileSystemEntityType.directory) {
          folders.add(
            FolderNavigationItem(
              path: entity.path,
              name: name,
              isSymlink: true,
            ),
          );
        }
      }
    }
    folders.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return folders;
  }
}

/// Реализация [FolderAccessScope] с удержанием macOS security-scoped bookmark.
///
/// Разрешает переданный [bookmark] корневой папки, активирует доступ
/// через [SecureBookmarks.startAccessingSecurityScopedResource] на время
/// операций чтения и освобождает его после завершения.
class SecurityScopedFolderAccessScope implements FolderAccessScope {
  SecurityScopedFolderAccessScope({
    required this.rootPath,
    this.bookmark,
    SecureBookmarks? secureBookmarks,
    FolderAccessScope? delegate,
  })  : _secureBookmarks = secureBookmarks ?? SecureBookmarks(),
        _delegate = delegate ?? DefaultFolderAccessScope(rootPath);

  @override
  final String rootPath;
  final String? bookmark;
  final SecureBookmarks _secureBookmarks;
  final FolderAccessScope _delegate;

  Future<T> _withSecurityScope<T>(Future<T> Function() action) async {
    if (!Platform.isMacOS || bookmark == null || bookmark!.isEmpty) {
      return action();
    }
    Directory? scopedDir;
    bool scopeStarted = false;
    try {
      final entity = await _secureBookmarks.resolveBookmark(
        bookmark!,
        isDirectory: true,
      );
      if (entity is Directory) {
        scopedDir = entity;
        scopeStarted = await _secureBookmarks
            .startAccessingSecurityScopedResource(entity);
      }
    } catch (_) {}

    try {
      return await action();
    } finally {
      if (scopedDir != null && scopeStarted) {
        try {
          await _secureBookmarks.stopAccessingSecurityScopedResource(scopedDir);
        } catch (_) {}
      }
    }
  }

  @override
  Future<bool> exists(String path) {
    return _withSecurityScope(() => _delegate.exists(path));
  }

  @override
  Future<List<FolderNavigationItem>> listSubfolders(String path) {
    return _withSecurityScope(() => _delegate.listSubfolders(path));
  }
}
