import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/stock_credentials.dart';

class SettingsState {
  final String? apiKey;
  final List<String> savedLocations;
  final StockCredentials adobeCredentials;
  final StockCredentials shutterstockCredentials;

  /// Per-stock allowed tag sets. Empty set = accept all files (no filter).
  /// e.g. {'adobe': {'ai_generated'}, 'shutterstock': {'editorial', 'ai_generated'}}
  final Map<String, Set<String>> stockTagFilters;

  /// Default number of keywords requested from the AI generation API.
  final int defaultKeywordsCount;

  SettingsState({
    this.apiKey,
    this.savedLocations = const [],
    this.adobeCredentials = const StockCredentials(
      hostname: StockCredentials.defaultAdobeHost,
    ),
    this.shutterstockCredentials = const StockCredentials(),
    this.stockTagFilters = const {},
    this.defaultKeywordsCount = 15,
  });

  SettingsState copyWith({
    String? apiKey,
    List<String>? savedLocations,
    StockCredentials? adobeCredentials,
    StockCredentials? shutterstockCredentials,
    Map<String, Set<String>>? stockTagFilters,
    int? defaultKeywordsCount,
  }) {
    return SettingsState(
      apiKey: apiKey ?? this.apiKey,
      savedLocations: savedLocations ?? this.savedLocations,
      adobeCredentials: adobeCredentials ?? this.adobeCredentials,
      shutterstockCredentials:
          shutterstockCredentials ?? this.shutterstockCredentials,
      stockTagFilters: stockTagFilters ?? this.stockTagFilters,
      defaultKeywordsCount: defaultKeywordsCount ?? this.defaultKeywordsCount,
    );
  }

  /// Returns true if [file tags] pass this stock's tag filter.
  /// If the stock has no configured filters → always accept.
  bool stockAcceptsTags(String stockKey, List<String> fileTags) {
    final allowed = stockTagFilters[stockKey];
    if (allowed == null || allowed.isEmpty) return true;
    return fileTags.any((t) => allowed.contains(t));
  }
}

class SettingsNotifier extends AsyncNotifier<SettingsState> {
  static const _keyLocations = 'editorial_locations';
  static const _keyAdobe = 'adobe_ftp';
  static const _keyShutter = 'shutter_ftp';
  static const _keyTagFilters = 'stock_tag_filters';
  static const _keyDefaultKeywords = 'default_keywords_count';

  @override
  Future<SettingsState> build() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('api_key');
    final savedLocations = prefs.getStringList(_keyLocations) ?? [];

    final adobeStr = prefs.getString(_keyAdobe) ?? '';
    final shutterStr = prefs.getString(_keyShutter) ?? '';

    final tagFiltersJson = prefs.getString(_keyTagFilters) ?? '{}';
    final Map<String, Set<String>> tagFilters = {};
    try {
      final decoded = jsonDecode(tagFiltersJson) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        tagFilters[entry.key] = Set<String>.from(entry.value as List);
      }
    } catch (_) {}

    final defaultKeywords = prefs.getInt(_keyDefaultKeywords) ?? 15;

    return SettingsState(
      apiKey: apiKey,
      savedLocations: savedLocations,
      adobeCredentials: StockCredentials.fromStorageString(
        adobeStr,
        defaultHost: StockCredentials.defaultAdobeHost,
      ),
      shutterstockCredentials: StockCredentials.fromStorageString(shutterStr),
      stockTagFilters: tagFilters,
      defaultKeywordsCount: defaultKeywords,
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
    final normalized = creds.copyWith(
      hostname: StockCredentials.sanitizeHost(
        creds.hostname,
        defaultHost: StockCredentials.defaultAdobeHost,
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAdobe, normalized.toStorageString());
    state = AsyncValue.data(
      state.value!.copyWith(adobeCredentials: normalized),
    );
  }

  Future<void> saveShutterstockCredentials(StockCredentials creds) async {
    final normalized = creds.copyWith(
      hostname: StockCredentials.sanitizeHost(creds.hostname),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyShutter, normalized.toStorageString());
    state = AsyncValue.data(
      state.value!.copyWith(shutterstockCredentials: normalized),
    );
  }

  Future<void> setDefaultKeywordsCount(int count) async {
    final clamped = count.clamp(5, 50);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDefaultKeywords, clamped);
    state = AsyncValue.data(
      state.value!.copyWith(defaultKeywordsCount: clamped),
    );
  }

  Future<void> setStockTagFilter(String stockKey, Set<String> tags) async {
    final updated = Map<String, Set<String>>.from(
      state.value?.stockTagFilters ?? {},
    );
    updated[stockKey] = tags;
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode({
      for (final e in updated.entries) e.key: e.value.toList(),
    });
    await prefs.setString(_keyTagFilters, encoded);
    state = AsyncValue.data(state.value!.copyWith(stockTagFilters: updated));
  }
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, SettingsState>(
  () {
    return SettingsNotifier();
  },
);
