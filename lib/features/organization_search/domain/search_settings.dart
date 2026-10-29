import 'dart:convert';

import 'search_filter_criteria.dart';
import 'search_scope.dart';

/// Сохраняемые настройки поиска, фильтрации и положения прокрутки.
///
/// Ограниченный объём: хранит исключительно настройки источника, поисковые
/// критерии и смещение скролла (scrollOffset).
/// Не дублирует и не хранит список или содержимое файлов библиотеки.
class OrganizationSearchSettings {
  const OrganizationSearchSettings({
    this.scope = const SearchScope.all(),
    this.filters = const SearchFilterCriteria(),
    this.scrollOffset = 0.0,
  });

  /// Максимальный допустимый размер сериализованных настроек (16 КБ),
  /// предотвращающий раздувание хранилища.
  static const int maxSerializedBytes = 16 * 1024;

  final SearchScope scope;
  final SearchFilterCriteria filters;
  final double scrollOffset;

  OrganizationSearchSettings copyWith({
    SearchScope? scope,
    SearchFilterCriteria? filters,
    double? scrollOffset,
  }) {
    return OrganizationSearchSettings(
      scope: scope ?? this.scope,
      filters: filters ?? this.filters,
      scrollOffset: scrollOffset ?? this.scrollOffset,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'scope': scope.toMap(),
      'filters': filters.toMap(),
      'scroll_offset': scrollOffset,
    };
  }

  factory OrganizationSearchSettings.fromMap(Map<String, dynamic> map) {
    final scopeMap = map['scope'] as Map<String, dynamic>?;
    final filtersMap = map['filters'] as Map<String, dynamic>?;
    final scroll = (map['scroll_offset'] as num?)?.toDouble() ?? 0.0;

    return OrganizationSearchSettings(
      scope: scopeMap != null
          ? SearchScope.fromMap(scopeMap)
          : const SearchScope.all(),
      filters: filtersMap != null
          ? SearchFilterCriteria.fromMap(filtersMap)
          : const SearchFilterCriteria(),
      scrollOffset: scroll < 0 ? 0.0 : scroll,
    );
  }

  String toJson() {
    final jsonStr = jsonEncode(toMap());
    if (jsonStr.length > maxSerializedBytes) {
      throw StateError(
        'Search settings payload exceeded maximum allowed size of $maxSerializedBytes bytes',
      );
    }
    return jsonStr;
  }

  factory OrganizationSearchSettings.fromJson(String jsonStr) {
    if (jsonStr.trim().isEmpty) {
      return const OrganizationSearchSettings();
    }
    if (jsonStr.length > maxSerializedBytes) {
      // Защита от поврежденных или аномально больших данных
      return const OrganizationSearchSettings();
    }
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        return OrganizationSearchSettings.fromMap(decoded);
      }
    } catch (_) {
      // Игнорируем ошибки парсинга и возвращаем настройки по умолчанию
    }
    return const OrganizationSearchSettings();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrganizationSearchSettings &&
          runtimeType == other.runtimeType &&
          scope == other.scope &&
          filters == other.filters &&
          scrollOffset == other.scrollOffset;

  @override
  int get hashCode => Object.hash(scope, filters, scrollOffset);

  @override
  String toString() =>
      'OrganizationSearchSettings(scope: $scope, query: "${filters.query}", scroll: $scrollOffset)';
}
