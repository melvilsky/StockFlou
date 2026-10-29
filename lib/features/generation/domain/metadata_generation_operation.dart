/// Immutable context snapshot captured at the start of metadata generation.
///
/// Freezes target identity, path, credentials, and editorial settings so that
/// subsequent user interactions (such as selecting another file or editing
/// inspector fields) cannot mutate or redirect the in-flight operation.
class MetadataGenerationContext {
  final String? targetId;
  final String targetPath;
  final String userContext;
  final String apiKey;
  final int keywordCount;
  final bool isEditorial;
  final String city;
  final String country;
  final DateTime? date;

  const MetadataGenerationContext({
    this.targetId,
    required this.targetPath,
    required this.userContext,
    required this.apiKey,
    required this.keywordCount,
    required this.isEditorial,
    this.city = '',
    this.country = '',
    this.date,
  });

  /// Formatted user context applying the 150-char truncation rule.
  String? get formattedUserContext {
    final trimmed = userContext.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.length > 150) {
      return '${trimmed.substring(0, 147)}...';
    }
    return trimmed;
  }

  /// Creates a copy of this context with updated fields (e.g. enriched with EXIF).
  MetadataGenerationContext copyWith({
    String? targetId,
    String? targetPath,
    String? userContext,
    String? apiKey,
    int? keywordCount,
    bool? isEditorial,
    String? city,
    String? country,
    DateTime? date,
  }) {
    return MetadataGenerationContext(
      targetId: targetId ?? this.targetId,
      targetPath: targetPath ?? this.targetPath,
      userContext: userContext ?? this.userContext,
      apiKey: apiKey ?? this.apiKey,
      keywordCount: keywordCount ?? this.keywordCount,
      isEditorial: isEditorial ?? this.isEditorial,
      city: city ?? this.city,
      country: country ?? this.country,
      date: date ?? this.date,
    );
  }

  /// Appends location and date to the title according to editorial rules.
  String formatFinalTitle(String fetchedTitle) {
    if (!isEditorial) return fetchedTitle;
    return appendEditorialToTitle(
      title: fetchedTitle,
      city: city,
      country: country,
      date: date,
    );
  }
}

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Formats a date into "Month day year" format (e.g. "October 25 2026").
String formatEditorialDate(DateTime date) {
  return '${_months[date.month - 1]} ${date.day} ${date.year}';
}

/// Appends location and date to the end of the title
/// following Adobe Stock editorial guidelines.
String appendEditorialToTitle({
  required String title,
  required String city,
  required String country,
  required DateTime? date,
}) {
  var newTitle = title.trim();
  if (newTitle.endsWith('.')) {
    newTitle = newTitle.substring(0, newTitle.length - 1);
  }

  final locationParts = <String>[];
  if (city.isNotEmpty) locationParts.add(city);
  if (country.isNotEmpty) locationParts.add(country);

  String suffix = '';
  if (locationParts.isNotEmpty) {
    suffix += ' - ${locationParts.join(', ')}';
  }
  if (date != null) {
    suffix += '. ${formatEditorialDate(date)}';
  }

  if (suffix.isNotEmpty) {
    if (newTitle.endsWith(suffix)) {
      return '$newTitle.';
    }
    return '$newTitle$suffix.';
  }

  return newTitle.isEmpty ? '' : '$newTitle.';
}

/// Title that should be stored and written for [title].
///
/// Editorial files keep city, country and date in the title, so "save all"
/// does not drop the location the user picked during attribution.
String metadataTitleForWrite({
  required String? title,
  required bool isEditorial,
  String? city,
  String? country,
  int? editorialDateMillis,
}) {
  final raw = title?.trim() ?? '';
  if (!isEditorial || raw.isEmpty) return raw;
  return appendEditorialToTitle(
    title: raw,
    city: city?.trim() ?? '',
    country: country?.trim() ?? '',
    date:
        editorialDateMillis == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(editorialDateMillis),
  );
}
