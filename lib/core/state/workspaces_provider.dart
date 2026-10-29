import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_secure_bookmarks/macos_secure_bookmarks.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/workspace_availability.dart';

export '../../models/workspace_availability.dart';

const keyWorkspacePaths = 'workspace_paths';
const keyWorkspaceCurrentIndex = 'workspace_current_index';
const keyWorkspaceEntries = 'workspace_entries';
const keyWorkspaceEntriesBackup = 'workspace_entries_corrupt_backup';
const keyWorkspaceCurrentPath = 'workspace_current_path';

/// Нормализация пути рабочей области:
/// 1. Не применяет trim() (пробелы в начале/конце имени сохраняются).
/// 2. Одиночный или кратный "/" остаётся "/".
/// 3. В остальных путях удаляются замыкающие слеши.
/// 4. Не меняет регистр и не разыменовывает симлинки.
String normalizeWorkspacePath(String rawPath) {
  if (rawPath.isEmpty) return '';
  if (RegExp(r'^/+$').hasMatch(rawPath)) {
    return '/';
  }
  return rawPath.replaceAll(RegExp(r'/+$'), '');
}

/// Запись о рабочей области: путь и опционально bookmark (macOS) для доступа без Full Disk Access.
class WorkspaceEntry {
  final String path;
  final String? bookmark;

  const WorkspaceEntry({required this.path, this.bookmark});

  Map<String, dynamic> toJson() => {'path': path, 'bookmark': bookmark};

  static WorkspaceEntry fromJson(Map<String, dynamic> json) {
    return WorkspaceEntry(
      path: (json['path'] as String?) ?? '',
      bookmark: json['bookmark'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkspaceEntry &&
          runtimeType == other.runtimeType &&
          path == other.path &&
          bookmark == other.bookmark;

  @override
  int get hashCode => Object.hash(path, bookmark);

  @override
  String toString() => 'WorkspaceEntry(path: $path, bookmark: $bookmark)';
}

class WorkspacesState {
  final List<WorkspaceEntry> entries;
  final int currentIndex;
  final Map<String, WorkspaceAvailability> availability;
  final bool isCheckingAvailability;
  final String? lastError;

  const WorkspacesState({
    this.entries = const [],
    this.currentIndex = 0,
    this.availability = const {},
    this.isCheckingAvailability = false,
    this.lastError,
  });

  List<String> get paths => entries.map((e) => e.path).toList();

  String? get currentPath {
    if (entries.isEmpty || currentIndex < 0 || currentIndex >= entries.length) {
      return null;
    }
    return entries[currentIndex].path;
  }

  WorkspaceEntry? get currentEntry {
    if (entries.isEmpty || currentIndex < 0 || currentIndex >= entries.length) {
      return null;
    }
    return entries[currentIndex];
  }

  WorkspaceAvailability availabilityFor(String path) {
    return availability[path] ?? const WorkspaceAvailability.checking();
  }

  WorkspacesState copyWith({
    List<WorkspaceEntry>? entries,
    int? currentIndex,
    Map<String, WorkspaceAvailability>? availability,
    bool? isCheckingAvailability,
    String? lastError,
    bool clearLastError = false,
  }) {
    return WorkspacesState(
      entries: entries ?? this.entries,
      currentIndex: currentIndex ?? this.currentIndex,
      availability: availability ?? this.availability,
      isCheckingAvailability:
          isCheckingAvailability ?? this.isCheckingAvailability,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkspacesState &&
          runtimeType == other.runtimeType &&
          listEquals(entries, other.entries) &&
          currentIndex == other.currentIndex &&
          mapEquals(availability, other.availability) &&
          isCheckingAvailability == other.isCheckingAvailability &&
          lastError == other.lastError;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(entries),
    currentIndex,
    Object.hashAll(availability.keys),
    Object.hashAll(availability.values),
    isCheckingAvailability,
    lastError,
  );
}

/// Адаптер SecureBookmarks для тестирования и изоляции от macOS API.
abstract class SecureBookmarksAdapter {
  Future<String?> createBookmark(Directory directory);
  Future<FileSystemEntity> resolveBookmark(String bookmark);
  Future<bool> startAccessingSecurityScopedResource(FileSystemEntity entity);
  Future<void> stopAccessingSecurityScopedResource(FileSystemEntity entity);
}

class DefaultSecureBookmarksAdapter implements SecureBookmarksAdapter {
  final SecureBookmarks _secureBookmarks;
  DefaultSecureBookmarksAdapter([SecureBookmarks? secureBookmarks])
    : _secureBookmarks = secureBookmarks ?? SecureBookmarks();

  @override
  Future<String?> createBookmark(Directory directory) {
    return _secureBookmarks.bookmark(directory);
  }

  @override
  Future<FileSystemEntity> resolveBookmark(String bookmark) {
    return _secureBookmarks.resolveBookmark(bookmark, isDirectory: true);
  }

  @override
  Future<bool> startAccessingSecurityScopedResource(FileSystemEntity entity) {
    return _secureBookmarks.startAccessingSecurityScopedResource(entity);
  }

  @override
  Future<void> stopAccessingSecurityScopedResource(FileSystemEntity entity) {
    return _secureBookmarks.stopAccessingSecurityScopedResource(entity);
  }
}

/// Проверка существования и возможности чтения каталога.
abstract class DirectoryProbe {
  Future<bool> exists(String path);
  Future<void> probeRead(String path);
}

class DefaultDirectoryProbe implements DirectoryProbe {
  const DefaultDirectoryProbe();

  @override
  Future<bool> exists(String path) {
    return Directory(path).exists();
  }

  @override
  Future<void> probeRead(String path) async {
    final dir = Directory(path);
    // Ограниченная попытка чтения без полного сканирования
    final stream = dir.list(followLinks: false);
    await stream.take(1).drain();
  }
}

class WorkspacesNotifier extends Notifier<WorkspacesState> {
  final SecureBookmarksAdapter? _injectedBookmarks;
  final DirectoryProbe? _injectedDirectoryProbe;
  final Future<SharedPreferences> Function()? _injectedPrefsLoader;
  final bool? _injectedIsMacOS;

  late final SecureBookmarksAdapter _secureBookmarks;
  late final DirectoryProbe _directoryProbe;
  late final Future<SharedPreferences> Function() _prefsLoader;
  late final bool _isMacOS;

  bool _isDisposed = false;
  bool _hasPendingSave = false;
  bool _hasLoaded = false;
  Future<void> _lock = Future.value();
  Future<void>? _availabilityCheckFuture;
  final Map<String, Object> _probeTokens = {};

  WorkspacesNotifier({
    SecureBookmarksAdapter? bookmarksAdapter,
    DirectoryProbe? directoryProbe,
    Future<SharedPreferences> Function()? prefsLoader,
    bool? isMacOS,
  }) : _injectedBookmarks = bookmarksAdapter,
       _injectedDirectoryProbe = directoryProbe,
       _injectedPrefsLoader = prefsLoader,
       _injectedIsMacOS = isMacOS {
    _secureBookmarks = _injectedBookmarks ?? DefaultSecureBookmarksAdapter();
    _directoryProbe = _injectedDirectoryProbe ?? const DefaultDirectoryProbe();
    _prefsLoader = _injectedPrefsLoader ?? SharedPreferences.getInstance;
    _isMacOS = _injectedIsMacOS ?? Platform.isMacOS;
  }

  /// Future, завершающийся после окончания текущей очереди инициализации/мутаций.
  Future<void> get initialization => _lock;

  /// Future, завершающийся после текущей проверки доступности.
  Future<void> get availabilityCheckFuture =>
      _availabilityCheckFuture ?? Future.value();

  @override
  WorkspacesState build() {
    ref.onDispose(() {
      _isDisposed = true;
    });

    _runSynchronized(() => _loadFromPrefs());
    return const WorkspacesState();
  }

  Future<T> _runSynchronized<T>(Future<T> Function() action) async {
    final previousLock = _lock;
    final completer = Completer<void>();
    _lock = completer.future;
    try {
      await previousLock;
    } catch (_) {}
    try {
      return await action();
    } finally {
      completer.complete();
    }
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await _prefsLoader();
      if (_isDisposed) return;
      List<dynamic>? rawEntries;
      bool legacy = false;
      String? loadError;
      final stored = prefs.get(keyWorkspaceEntries);
      if (stored != null) {
        try {
          final decoded = stored is String ? jsonDecode(stored) : null;
          if (decoded is! List) throw const FormatException();
          rawEntries = decoded;
        } catch (_) {
          loadError = 'Повреждены настройки рабочих областей.';
        }
      }
      if (rawEntries == null) {
        final storedLegacy = prefs.get(keyWorkspacePaths);
        if (storedLegacy != null) {
          try {
            final decoded =
                storedLegacy is String ? jsonDecode(storedLegacy) : null;
            if (decoded is! List) throw const FormatException();
            rawEntries = decoded;
            legacy = true;
          } catch (_) {
            loadError =
                'Не удалось прочитать старые настройки рабочих областей.';
          }
        }
      }

      final entries = <WorkspaceEntry>[];
      String? pathOf(dynamic item) {
        final path = legacy ? item : (item is Map ? item['path'] : null);
        return path is String ? normalizeWorkspacePath(path) : null;
      }

      for (final item in rawEntries ?? <dynamic>[]) {
        final path = pathOf(item);
        if (path == null || path.isEmpty) continue;
        final bookmark =
            !legacy && item is Map && item['bookmark'] is String
                ? item['bookmark'] as String
                : null;
        final index = entries.indexWhere((entry) => entry.path == path);
        if (index < 0) {
          entries.add(WorkspaceEntry(path: path, bookmark: bookmark));
        } else if (entries[index].bookmark == null && bookmark != null) {
          entries[index] = WorkspaceEntry(path: path, bookmark: bookmark);
        }
      }

      final storedIndex = prefs.get(keyWorkspaceCurrentIndex);
      final savedIndex = storedIndex is int ? storedIndex : 0;
      final storedPath = prefs.get(keyWorkspaceCurrentPath);
      final savedPath = storedPath is String ? storedPath : null;
      final originalPath =
          rawEntries != null &&
                  savedIndex >= 0 &&
                  savedIndex < rawEntries.length
              ? pathOf(rawEntries[savedIndex])
              : null;
      final intendedPath =
          savedPath == null ? originalPath : normalizeWorkspacePath(savedPath);
      final selectedIndex = entries.indexWhere(
        (entry) => entry.path == intendedPath,
      );
      final index = selectedIndex >= 0 ? selectedIndex : 0;
      if (legacy ||
          (stored != null &&
              loadError == null &&
              prefs.containsKey(keyWorkspacePaths))) {
        try {
          await _persistEntries(prefs, entries, index);
          loadError = null;
        } catch (e) {
          loadError = 'Ошибка переноса старых настроек: $e';
        }
      }
      if (_isDisposed) return;
      _hasLoaded = true;
      state = WorkspacesState(
        entries: entries,
        currentIndex: index,
        lastError: loadError,
      );
      if (entries.isNotEmpty) {
        _availabilityCheckFuture = _checkAvailability(entries);
        unawaited(_availabilityCheckFuture!);
      }
    } catch (e) {
      if (!_isDisposed) {
        state = state.copyWith(
          lastError: 'Ошибка загрузки рабочих областей: $e',
        );
      }
    }
  }

  Future<void> _persistEntries(
    SharedPreferences prefs,
    List<WorkspaceEntry> entries,
    int index,
  ) async {
    // Check the stored value on every write: a later edit must not erase the
    // only copy of settings that failed to load during startup.
    final stored = prefs.get(keyWorkspaceEntries);
    if (stored != null) {
      bool valid = false;
      try {
        valid = stored is String && jsonDecode(stored) is List;
      } catch (_) {}
      if (!valid) {
        final backup = stored is String ? stored : jsonEncode(stored);
        if (!await prefs.setString(keyWorkspaceEntriesBackup, backup)) {
          throw StateError('Не удалось сохранить резервную копию настроек.');
        }
      }
    }
    if (_isDisposed) return;
    // Persist the path before the numeric index so filtering legacy entries
    // cannot change the intended selection after a partial write failure.
    final pathSaved =
        entries.isEmpty
            ? await prefs.remove(keyWorkspaceCurrentPath)
            : await prefs.setString(
              keyWorkspaceCurrentPath,
              entries[index].path,
            );
    if (!pathSaved) throw StateError('Не удалось сохранить выбранную папку.');
    if (_isDisposed) return;
    if (!await prefs.setString(
      keyWorkspaceEntries,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    )) {
      throw StateError('Не удалось сохранить список рабочих областей.');
    }
    if (_isDisposed) return;
    if (!await prefs.setInt(keyWorkspaceCurrentIndex, index)) {
      throw StateError('Не удалось сохранить выбор рабочей области.');
    }
    if (_isDisposed) return;
    final legacy = prefs.get(keyWorkspacePaths);
    bool validLegacy = false;
    try {
      validLegacy = legacy is String && jsonDecode(legacy) is List;
    } catch (_) {}
    // A malformed legacy value may still be the only recoverable source.
    if (validLegacy && !await prefs.remove(keyWorkspacePaths)) {
      throw StateError(
        'Не удалось завершить перенос старых настроек. Повторите сохранение.',
      );
    }
  }

  Future<bool> _save() async {
    if (_isDisposed) return false;
    _hasPendingSave = true;
    try {
      final prefs = await _prefsLoader();
      if (_isDisposed) return false;
      await _persistEntries(prefs, state.entries, state.currentIndex);
      if (_isDisposed) return false;
      _hasPendingSave = false;
      state = state.copyWith(clearLastError: true);
      return true;
    } catch (e) {
      if (!_isDisposed) {
        state = state.copyWith(lastError: 'Ошибка сохранения настроек: $e');
      }
      return false;
    }
  }

  Future<bool> retry() => _runSynchronized(() async {
    if (_isDisposed) return false;
    if (_hasPendingSave) return _save();
    await _loadFromPrefs();
    return !_isDisposed && state.lastError == null;
  });

  Future<WorkspaceAvailability> _probeEntry(WorkspaceEntry entry) async {
    bool scopeStarted = false;
    FileSystemEntity? resolvedEntity;
    WorkspaceAvailability result;
    try {
      if (entry.bookmark != null && _isMacOS) {
        resolvedEntity = await _secureBookmarks.resolveBookmark(
          entry.bookmark!,
        );
        if (normalizeWorkspacePath(resolvedEntity.path) != entry.path) {
          throw const FileSystemException(
            'Bookmark points to a different folder',
          );
        }
        if (_isDisposed) return const WorkspaceAvailability.unavailable();
        scopeStarted = await _secureBookmarks
            .startAccessingSecurityScopedResource(resolvedEntity);
        if (!scopeStarted) throw const FileSystemException('Access denied');
      }
      if (_isDisposed) return const WorkspaceAvailability.unavailable();
      if (!await _directoryProbe.exists(entry.path)) {
        throw const FileSystemException('Folder unavailable');
      }
      if (_isDisposed) return const WorkspaceAvailability.unavailable();
      await _directoryProbe.probeRead(entry.path);
      result = const WorkspaceAvailability.available();
    } catch (_) {
      result = const WorkspaceAvailability.unavailable(
        'Папка недоступна. Подключите диск или выберите эту папку снова.',
      );
    } finally {
      if (scopeStarted && resolvedEntity != null) {
        try {
          await _secureBookmarks.stopAccessingSecurityScopedResource(
            resolvedEntity,
          );
        } catch (_) {
          result = const WorkspaceAvailability.unavailable(
            'Ошибка завершения проверки доступа. Подключите папку снова.',
          );
        }
      }
    }
    return result;
  }

  Future<void> _checkAvailability(List<WorkspaceEntry> entriesToCheck) async {
    await Future.wait(entriesToCheck.map(_probeAndUpdateAvailability));
  }

  Future<void> _probeAndUpdateAvailability(WorkspaceEntry entry) async {
    if (_isDisposed || !state.entries.contains(entry)) return;
    final token = Object();
    _probeTokens[entry.path] = token;
    state = state.copyWith(
      availability: {
        ...state.availability,
        entry.path: const WorkspaceAvailability.checking(),
      },
      isCheckingAvailability: true,
    );
    final availability = await _probeEntry(entry);
    if (_isDisposed || _probeTokens[entry.path] != token) return;
    _probeTokens.remove(entry.path);
    if (!state.entries.contains(entry)) return;
    state = state.copyWith(
      availability: {...state.availability, entry.path: availability},
      isCheckingAvailability: _probeTokens.isNotEmpty,
    );
  }

  Future<void> recheckAvailability({String? path}) async {
    await initialization;
    if (_isDisposed) return;
    if (path != null) {
      final normalized = normalizeWorkspacePath(path);
      final entry =
          state.entries.where((e) => e.path == normalized).firstOrNull;
      if (entry != null) {
        _availabilityCheckFuture = _probeAndUpdateAvailability(entry);
        await _availabilityCheckFuture;
      }
    } else {
      _availabilityCheckFuture = _checkAvailability(state.entries);
      await _availabilityCheckFuture;
    }
  }

  Future<bool> _ensureLoaded() async {
    if (_isDisposed) return false;
    if (!_hasLoaded) await _loadFromPrefs();
    return !_isDisposed && _hasLoaded;
  }

  Future<bool> addWorkspace(String rawPath) async {
    final normalized = normalizeWorkspacePath(rawPath);
    if (normalized.isEmpty) return false;

    return _runSynchronized(() async {
      if (!await _ensureLoaded()) return false;
      String? bookmark;
      if (_isMacOS) {
        try {
          bookmark = await _secureBookmarks.createBookmark(
            Directory(normalized),
          );
        } catch (e) {
          debugPrint('WorkspacesProvider: не удалось создать bookmark: $e');
        }
      }

      if (_isDisposed) return false;
      final existingIndex = state.entries.indexWhere(
        (e) => e.path == normalized,
      );
      if (existingIndex >= 0) {
        final existingEntry = state.entries[existingIndex];
        final updatedBookmark = bookmark ?? existingEntry.bookmark;
        final updatedEntry = WorkspaceEntry(
          path: normalized,
          bookmark: updatedBookmark,
        );

        final newEntries = List<WorkspaceEntry>.from(state.entries);
        newEntries[existingIndex] = updatedEntry;

        state = state.copyWith(
          entries: newEntries,
          currentIndex: existingIndex,
        );
        final saveOk = await _save();
        _availabilityCheckFuture = _probeAndUpdateAvailability(updatedEntry);
        unawaited(_availabilityCheckFuture!);
        return saveOk;
      }

      final newEntry = WorkspaceEntry(path: normalized, bookmark: bookmark);
      final newEntries = [...state.entries, newEntry];
      final newIndex = newEntries.length - 1;

      state = state.copyWith(entries: newEntries, currentIndex: newIndex);
      final saveOk = await _save();
      _availabilityCheckFuture = _probeAndUpdateAvailability(newEntry);
      unawaited(_availabilityCheckFuture!);
      return saveOk;
    });
  }

  Future<bool> removeWorkspace(int index) async {
    return _runSynchronized(() async {
      if (!await _ensureLoaded()) return false;
      if (index < 0 || index >= state.entries.length) return true;

      final removedEntry = state.entries[index];
      _probeTokens.remove(removedEntry.path);
      final selectedEntry = state.currentEntry;

      final newEntries = List<WorkspaceEntry>.from(state.entries)
        ..removeAt(index);

      int newIndex;
      if (newEntries.isEmpty) {
        newIndex = 0;
      } else if (selectedEntry != null &&
          selectedEntry.path != removedEntry.path) {
        final preservedIndex = newEntries.indexWhere(
          (e) => e.path == selectedEntry.path,
        );
        newIndex = preservedIndex >= 0 ? preservedIndex : 0;
      } else {
        newIndex = index.clamp(0, newEntries.length - 1);
      }

      final newAvailability = Map<String, WorkspaceAvailability>.from(
        state.availability,
      )..remove(removedEntry.path);

      state = state.copyWith(
        entries: newEntries,
        currentIndex: newIndex,
        availability: newAvailability,
        isCheckingAvailability: _probeTokens.isNotEmpty,
      );

      return await _save();
    });
  }

  Future<bool> setCurrent(int index) async {
    return _runSynchronized(() async {
      if (!await _ensureLoaded()) return false;
      if (index < 0 || index >= state.entries.length) return false;
      state = state.copyWith(currentIndex: index);
      return await _save();
    });
  }

  Future<bool> setCurrentByPath(String path) async {
    final normalized = normalizeWorkspacePath(path);
    return _runSynchronized(() async {
      if (!await _ensureLoaded()) return false;
      final idx = state.entries.indexWhere((e) => e.path == normalized);
      if (idx >= 0) {
        state = state.copyWith(currentIndex: idx);
        return await _save();
      }
      return false;
    });
  }
}

final workspacesProvider =
    NotifierProvider<WorkspacesNotifier, WorkspacesState>(
      () => WorkspacesNotifier(),
    );

/// Триггер обновления файлов текущей папки (кнопка «Обновить»).
class RefreshWorkspaceNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void trigger() {
    state = state + 1;
  }
}

final refreshWorkspaceProvider =
    NotifierProvider<RefreshWorkspaceNotifier, int>(
      () => RefreshWorkspaceNotifier(),
    );
