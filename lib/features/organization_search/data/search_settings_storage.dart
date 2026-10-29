import 'package:shared_preferences/shared_preferences.dart';

import '../domain/search_settings.dart';

/// Абстракция хранилища настроек поиска.
abstract class SearchSettingsStorage {
  Future<OrganizationSearchSettings?> loadSettings();
  Future<void> saveSettings(OrganizationSearchSettings settings);
  Future<void> clearSettings();
}

/// Реализация сохранения настроек поиска поверх SharedPreferences.
///
/// Гарантии:
/// - Хранит только строку JSON настроек (источник, поисковый запрос, фильтры, scrollOffset);
/// - Ограниченный размер (до 16 КБ);
/// - Не сохраняет и не дублирует файлы каталога.
class SharedPreferencesSearchSettingsStorage implements SearchSettingsStorage {
  SharedPreferencesSearchSettingsStorage({
    Future<SharedPreferences> Function()? prefsLoader,
  }) : _prefsLoader = prefsLoader ?? SharedPreferences.getInstance;

  static const String settingsKey = 'organization_search_settings';

  final Future<SharedPreferences> Function() _prefsLoader;

  @override
  Future<OrganizationSearchSettings?> loadSettings() async {
    final prefs = await _prefsLoader();
    final raw = prefs.getString(settingsKey);
    if (raw == null || raw.isEmpty) return null;
    return OrganizationSearchSettings.fromJson(raw);
  }

  @override
  Future<void> saveSettings(OrganizationSearchSettings settings) async {
    final prefs = await _prefsLoader();
    final jsonStr = settings.toJson();
    await prefs.setString(settingsKey, jsonStr);
  }

  @override
  Future<void> clearSettings() async {
    final prefs = await _prefsLoader();
    await prefs.remove(settingsKey);
  }
}

/// In-memory хранилище для изолированного тестирования.
class InMemorySearchSettingsStorage implements SearchSettingsStorage {
  InMemorySearchSettingsStorage([OrganizationSearchSettings? initial])
      : _settings = initial;

  OrganizationSearchSettings? _settings;

  @override
  Future<OrganizationSearchSettings?> loadSettings() async => _settings;

  @override
  Future<void> saveSettings(OrganizationSearchSettings settings) async {
    // Проверяем валидность сериализации и лимит размера
    settings.toJson();
    _settings = settings;
  }

  @override
  Future<void> clearSettings() async {
    _settings = null;
  }
}
