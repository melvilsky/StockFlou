import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_secure_bookmarks/macos_secure_bookmarks.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyPaths = 'workspace_paths';
const _keyCurrentIndex = 'workspace_current_index';
const _keyEntries = 'workspace_entries';

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
}

class WorkspacesState {
  final List<WorkspaceEntry> entries;
  final int currentIndex;

  const WorkspacesState({this.entries = const [], this.currentIndex = 0});

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

  WorkspacesState copyWith({List<WorkspaceEntry>? entries, int? currentIndex}) {
    return WorkspacesState(
      entries: entries ?? this.entries,
      currentIndex: currentIndex ?? this.currentIndex,
    );
  }
}

class WorkspacesNotifier extends Notifier<WorkspacesState> {
  static final _secureBookmarks = SecureBookmarks();

  @override
  WorkspacesState build() {
    _loadFromPrefs();
    return const WorkspacesState();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    List<WorkspaceEntry> entries = [];
    final entriesJson = prefs.getString(_keyEntries);
    if (entriesJson != null) {
      try {
        final list = jsonDecode(entriesJson) as List<dynamic>?;
        if (list != null) {
          for (final e in list) {
            if (e is Map<String, dynamic>) {
              final entry = WorkspaceEntry.fromJson(e);
              if (entry.path.trim().isNotEmpty) entries.add(entry);
            }
          }
        }
      } catch (_) {}
    }

    if (entries.isEmpty) {
      final json = prefs.getString(_keyPaths);
      if (json != null) {
        try {
          final list = jsonDecode(json) as List<dynamic>?;
          if (list != null) {
            final paths = list
                .map((e) => e.toString().trim().replaceAll(RegExp(r'/+$'), ''))
                .where((p) => p.isNotEmpty)
                .toList();
            entries = paths.map((p) => WorkspaceEntry(path: p)).toList();
          }
        } catch (_) {}
        // Remove the legacy key after migrating to avoid keeping stale data
        await prefs.remove(_keyPaths);
      }
    }

    List<WorkspaceEntry> valid = [];
    for (final entry in entries) {
      bool exists = false;
      if (entry.bookmark != null && Platform.isMacOS) {
        try {
          final entity = await _secureBookmarks.resolveBookmark(
            entry.bookmark!,
            isDirectory: true,
          );
          final started = await _secureBookmarks
              .startAccessingSecurityScopedResource(entity);
          try {
            if (started && await entity.exists()) {
              exists = true;
            }
          } finally {
            if (started) {
              await _secureBookmarks.stopAccessingSecurityScopedResource(
                entity,
              );
            }
          }
        } catch (_) {
          // If bookmark fails, we'll try the raw path fallback below
        }
      }

      // Fallback to raw path check
      if (!exists) {
        try {
          if (await Directory(entry.path).exists()) {
            exists = true;
          }
        } catch (_) {}
      }

      // Only keep the entry if the directory actually exists.
      if (exists) {
        valid.add(entry);
      }
    }

    int idx = prefs.getInt(_keyCurrentIndex) ?? 0;
    if (idx >= valid.length) idx = 0;

    state = WorkspacesState(entries: valid, currentIndex: idx);
    // Only save if we actually found something to migrate or cleaned up empty paths
    // but don't save back 'valid' if it's just what we loaded.
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final list = state.entries.map((e) => e.toJson()).toList();
    await prefs.setString(_keyEntries, jsonEncode(list));
    await prefs.setInt(_keyCurrentIndex, state.currentIndex);
  }

  Future<void> addWorkspace(String path) async {
    // Strip only trailing slashes — do NOT trim() because folder names
    // may legitimately end with a space (e.g. "Знаки зодиака ").
    final normalized = path.replaceAll(RegExp(r'/+$'), '');

    String? bookmark;
    if (Platform.isMacOS) {
      try {
        // Use the normalized path (without trailing slashes) for bookmark.
        // Do NOT call trim() — macOS requires the exact directory path.
        bookmark = await _secureBookmarks.bookmark(Directory(normalized));
      } catch (e) {
        assert(() {
          debugPrint('WorkspacesProvider: не удалось создать bookmark: $e');
          return true;
        }());
      }
    }

    if (state.entries.any((e) => e.path == normalized)) {
      final idx = state.entries.indexWhere((e) => e.path == normalized);
      // Если папка уже есть, но пользователь выбрал её снова — обновляем bookmark
      final currentEntries = state.entries.toList();
      if (bookmark != null) {
        currentEntries[idx] = WorkspaceEntry(
          path: normalized,
          bookmark: bookmark,
        );
      }
      state = state.copyWith(entries: currentEntries, currentIndex: idx);
      await _save();
      return;
    }

    final newEntries = [
      ...state.entries,
      WorkspaceEntry(path: normalized, bookmark: bookmark),
    ];
    state = state.copyWith(
      entries: newEntries,
      currentIndex: newEntries.length - 1,
    );
    await _save();
  }

  Future<void> removeWorkspace(int index) async {
    if (index < 0 || index >= state.entries.length) return;
    final newEntries = state.entries.toList()..removeAt(index);
    int newIdx = state.currentIndex;
    if (index < state.currentIndex) {
      newIdx = state.currentIndex - 1;
    } else if (index == state.currentIndex) {
      newIdx = newEntries.isEmpty
          ? 0
          : (state.currentIndex.clamp(0, newEntries.length - 1));
    }
    state = state.copyWith(
      entries: newEntries,
      currentIndex: newIdx.clamp(0, newEntries.length),
    );
    await _save();
  }

  Future<void> setCurrent(int index) async {
    if (index < 0 || index >= state.entries.length) return;
    state = state.copyWith(currentIndex: index);
    await _save();
  }

  Future<void> setCurrentByPath(String path) async {
    final normalized = path.replaceAll(RegExp(r'/+$'), '');
    final idx = state.entries.indexWhere((e) => e.path == normalized);
    if (idx >= 0) {
      state = state.copyWith(currentIndex: idx);
      await _save();
    }
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
