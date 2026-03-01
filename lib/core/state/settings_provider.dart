import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState {
  final String? apiKey;
  final List<String> savedLocations;

  SettingsState({this.apiKey, this.savedLocations = const []});

  SettingsState copyWith({String? apiKey, List<String>? savedLocations}) {
    return SettingsState(
      apiKey: apiKey ?? this.apiKey,
      savedLocations: savedLocations ?? this.savedLocations,
    );
  }
}

class SettingsNotifier extends AsyncNotifier<SettingsState> {
  static const _keyLocations = 'editorial_locations';

  @override
  Future<SettingsState> build() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('api_key');
    final savedLocations = prefs.getStringList(_keyLocations) ?? [];
    return SettingsState(apiKey: apiKey, savedLocations: savedLocations);
  }

  Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_key', key);
    state = AsyncValue.data(state.value!.copyWith(apiKey: key));
  }

  Future<void> addLocation(String city, String country) async {
    final loc = '${city.trim()}|${country.trim()}';
    if (loc == '|') return; // Empty

    final current = List<String>.from(state.value?.savedLocations ?? []);
    if (!current.contains(loc)) {
      current.add(loc);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_keyLocations, current);
      state = AsyncValue.data(state.value!.copyWith(savedLocations: current));
    }
  }

  Future<void> removeLocation(String loc) async {
    final current = List<String>.from(state.value?.savedLocations ?? []);
    if (current.remove(loc)) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_keyLocations, current);
      state = AsyncValue.data(state.value!.copyWith(savedLocations: current));
    }
  }
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, SettingsState>(
  () {
    return SettingsNotifier();
  },
);
