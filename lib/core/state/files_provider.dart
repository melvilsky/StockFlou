import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/app_file.dart';
import '../database/database_helper.dart';

class FilesNotifier extends AsyncNotifier<List<AppFile>> {
  @override
  Future<List<AppFile>> build() async {
    final files = await DatabaseHelper.instance.getAllFiles();
    return _filterExistingFiles(files);
  }

  Future<List<AppFile>> _filterExistingFiles(List<AppFile> files) async {
    final existingFiles = <AppFile>[];
    for (final file in files) {
      if (await File(file.path).exists()) {
        existingFiles.add(file);
      }
      // We don't delete from database anymore so that tags and metadata are preserved
      // if the file is ever restored or re-added.
    }
    return existingFiles;
  }

  Future<void> syncWithDisk() async {
    final currentFiles = state.value ?? [];
    final existing = await _filterExistingFiles(currentFiles);
    if (existing.length != currentFiles.length) {
      state = AsyncData(existing);
    }
  }

  Future<void> addFile(AppFile file) async {
    final previous = state.value ?? [];
    // Optimistic update
    state = AsyncData([file, ...previous]);
    try {
      await DatabaseHelper.instance.insertFile(file);
      final refreshed = await DatabaseHelper.instance.getAllFiles();
      state = AsyncData(refreshed);
    } catch (e) {
      // Rollback to previous data instead of showing error state in UI
      state = AsyncData(previous);
      rethrow;
    }
  }

  Future<void> removeFile(String id) async {
    final previous = state.value ?? [];
    state = AsyncData(previous.where((f) => f.id != id).toList());
    try {
      await DatabaseHelper.instance.deleteFile(id);
    } catch (e) {
      state = AsyncData(previous);
      rethrow;
    }
  }

  Future<void> updateFile(AppFile file) async {
    final previous = state.value ?? [];
    state = AsyncData([
      for (final f in previous)
        if (f.id == file.id) file else f,
    ]);
    try {
      await DatabaseHelper.instance.updateFile(file);
    } catch (e) {
      state = AsyncData(previous);
      rethrow;
    }
  }
}

final filesProvider = AsyncNotifierProvider<FilesNotifier, List<AppFile>>(() {
  return FilesNotifier();
});
