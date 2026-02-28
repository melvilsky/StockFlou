import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState {
  final String? apiKey;
  final String? workspacePath;
  SettingsState({this.apiKey, this.workspacePath});

  SettingsState copyWith({String? apiKey, String? workspacePath}) {
    return SettingsState(
      apiKey: apiKey ?? this.apiKey,
      workspacePath: workspacePath ?? this.workspacePath,
    );
  }
}

class SettingsNotifier extends AsyncNotifier<SettingsState> {
  @override
  Future<SettingsState> build() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('api_key');
    final workspacePath = prefs.getString('workspace_path');
    return SettingsState(apiKey: apiKey, workspacePath: workspacePath);
  }

  Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_key', key);
    state = AsyncValue.data(state.value!.copyWith(apiKey: key));
  }

  Future<void> setWorkspacePath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('workspace_path', path);
    state = AsyncValue.data(state.value!.copyWith(workspacePath: path));
  }
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, SettingsState>(
  () {
    return SettingsNotifier();
  },
);
