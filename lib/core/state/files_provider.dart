import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/app_file.dart';
import '../database/database_helper.dart';

class FilesNotifier extends AsyncNotifier<List<AppFile>> {
  @override
  Future<List<AppFile>> build() async {
    return await DatabaseHelper.instance.getAllFiles();
  }

  Future<void> addFile(AppFile file) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await DatabaseHelper.instance.insertFile(file);
      return await DatabaseHelper.instance.getAllFiles();
    });
  }

  Future<void> removeFile(String id) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await DatabaseHelper.instance.deleteFile(id);
      return await DatabaseHelper.instance.getAllFiles();
    });
  }

  Future<void> updateFile(AppFile file) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await DatabaseHelper.instance.updateFile(file);
      return await DatabaseHelper.instance.getAllFiles();
    });
  }
}

final filesProvider = AsyncNotifierProvider<FilesNotifier, List<AppFile>>(() {
  return FilesNotifier();
});
