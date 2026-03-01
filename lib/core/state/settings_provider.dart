import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/stock_credentials.dart';

class SettingsState {
  final String? apiKey;
  final List<String> savedLocations;
  final StockCredentials adobeCredentials;
  final StockCredentials shutterstockCredentials;

  SettingsState({
    this.apiKey,
    this.savedLocations = const [],
    this.adobeCredentials = const StockCredentials(),
    this.shutterstockCredentials = const StockCredentials(),
  });

  SettingsState copyWith({
    String? apiKey,
    List<String>? savedLocations,
    StockCredentials? adobeCredentials,
    StockCredentials? shutterstockCredentials,
  }) {
    return SettingsState(
      apiKey: apiKey ?? this.apiKey,
      savedLocations: savedLocations ?? this.savedLocations,
      adobeCredentials: adobeCredentials ?? this.adobeCredentials,
      shutterstockCredentials:
          shutterstockCredentials ?? this.shutterstockCredentials,
    );
  }
}

class SettingsNotifier extends AsyncNotifier<SettingsState> {
  static const _keyLocations = 'editorial_locations';
  static const _keyAdobe = 'adobe_ftp';
  static const _keyShutter = 'shutter_ftp';

  @override
  Future<SettingsState> build() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('api_key');
    final savedLocations = prefs.getStringList(_keyLocations) ?? [];

    final adobeStr = prefs.getString(_keyAdobe) ?? '';
    final shutterStr = prefs.getString(_keyShutter) ?? '';

    return SettingsState(
      apiKey: apiKey,
      savedLocations: savedLocations,
      adobeCredentials: StockCredentials.fromStorageString(adobeStr),
      shutterstockCredentials: StockCredentials.fromStorageString(shutterStr),
    );
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

  Future<void> saveAdobeCredentials(StockCredentials creds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAdobe, creds.toStorageString());
    state = AsyncValue.data(state.value!.copyWith(adobeCredentials: creds));
  }

  Future<void> saveShutterstockCredentials(StockCredentials creds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyShutter, creds.toStorageString());
    state = AsyncValue.data(
      state.value!.copyWith(shutterstockCredentials: creds),
    );
  }
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, SettingsState>(
  () {
    return SettingsNotifier();
  },
);
