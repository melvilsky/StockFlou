import '../../../models/app_file.dart';
import '../../../models/workflow_status.dart';

/// Категория медиафайла, подтверждаемая расширением файла.
enum MediaCategoryFilter {
  image,
  video,
  vector,
}

extension MediaCategoryFilterX on MediaCategoryFilter {
  static const imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.tif',
    '.tiff',
    '.heic',
    '.heif',
    '.bmp',
  };

  static const videoExtensions = {
    '.mp4',
    '.mov',
    '.avi',
    '.mkv',
    '.webm',
    '.m4v',
  };

  static const vectorExtensions = {
    '.svg',
    '.eps',
    '.ai',
  };

  bool matchesExtension(String ext) {
    final lower = ext.toLowerCase();
    switch (this) {
      case MediaCategoryFilter.image:
        return imageExtensions.contains(lower);
      case MediaCategoryFilter.video:
        return videoExtensions.contains(lower);
      case MediaCategoryFilter.vector:
        return vectorExtensions.contains(lower);
    }
  }
}

/// Критерии фильтрации и поиска по свойствам файлов.
///
/// ВАЖНО: Фильтры показывают только свойства, подтверждаемые текущей моделью [AppFile].
///
/// shortcut: В AppFile и WorkflowStatus отсутствует отдельный достоверный признак
/// записи метаданных на диск (EXIF/IPTC sync). Мы намеренно не синтезируем фильтр
/// «Не записано» из workflowStatus, так как workflowStatus отражает этап процесса
/// подготовки, а не факт физической записи на диск.
class SearchFilterCriteria {
  const SearchFilterCriteria({
    this.query = '',
    this.workflowStatuses,
    this.hasKeywords,
    this.hasTitle,
    this.hasDescription,
    this.isEditorial,
    this.isAiGenerated,
    this.mediaCategory,
    this.isAccessible,
  });

  /// Строка поиска без учета регистра. Ищет по:
  /// - имени файла ([AppFile.filename])
  /// - названию ([AppFile.metadataTitle])
  /// - описанию ([AppFile.metadataDescription])
  /// - ключевым словам ([AppFile.metadataKeywords])
  final String query;

  /// Фильтр по этапам подготовки (workflow status).
  final Set<WorkflowStatus>? workflowStatuses;

  /// true — есть ключи, false — без ключей, null — любые.
  final bool? hasKeywords;

  /// true — есть заголовок, false — без заголовка, null — любые.
  final bool? hasTitle;

  /// true — есть описание, false — без описания, null — любые.
  final bool? hasDescription;

  /// true — только редакционные (isEditorial или тег editorial),
  /// false — только коммерческие, null — любые.
  final bool? isEditorial;

  /// true — только сгенерированные AI (тег ai_generated),
  /// false — без тега AI, null — любые.
  final bool? isAiGenerated;

  /// Фильтр по категории медиа (фото/видео/вектор), подтверждаемой расширением.
  final MediaCategoryFilter? mediaCategory;

  /// true — только физически доступные на диске, false — недоступные, null — любые.
  final bool? isAccessible;

  bool get isEmpty =>
      query.trim().isEmpty &&
      (workflowStatuses == null || workflowStatuses!.isEmpty) &&
      hasKeywords == null &&
      hasTitle == null &&
      hasDescription == null &&
      isEditorial == null &&
      isAiGenerated == null &&
      mediaCategory == null &&
      isAccessible == null;

  SearchFilterCriteria copyWith({
    String? query,
    Set<WorkflowStatus>? workflowStatuses,
    bool? hasKeywords,
    bool? hasTitle,
    bool? hasDescription,
    bool? isEditorial,
    bool? isAiGenerated,
    MediaCategoryFilter? mediaCategory,
    bool? isAccessible,
    bool clearWorkflowStatuses = false,
    bool clearHasKeywords = false,
    bool clearHasTitle = false,
    bool clearHasDescription = false,
    bool clearIsEditorial = false,
    bool clearIsAiGenerated = false,
    bool clearMediaCategory = false,
    bool clearIsAccessible = false,
  }) {
    return SearchFilterCriteria(
      query: query ?? this.query,
      workflowStatuses: clearWorkflowStatuses
          ? null
          : (workflowStatuses ?? this.workflowStatuses),
      hasKeywords:
          clearHasKeywords ? null : (hasKeywords ?? this.hasKeywords),
      hasTitle: clearHasTitle ? null : (hasTitle ?? this.hasTitle),
      hasDescription:
          clearHasDescription ? null : (hasDescription ?? this.hasDescription),
      isEditorial:
          clearIsEditorial ? null : (isEditorial ?? this.isEditorial),
      isAiGenerated:
          clearIsAiGenerated ? null : (isAiGenerated ?? this.isAiGenerated),
      mediaCategory:
          clearMediaCategory ? null : (mediaCategory ?? this.mediaCategory),
      isAccessible:
          clearIsAccessible ? null : (isAccessible ?? this.isAccessible),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'query': query,
      if (workflowStatuses != null && workflowStatuses!.isNotEmpty)
        'workflow_statuses':
            workflowStatuses!.map((s) => s.storageValue).toList(),
      if (hasKeywords != null) 'has_keywords': hasKeywords,
      if (hasTitle != null) 'has_title': hasTitle,
      if (hasDescription != null) 'has_description': hasDescription,
      if (isEditorial != null) 'is_editorial': isEditorial,
      if (isAiGenerated != null) 'is_ai_generated': isAiGenerated,
      if (mediaCategory != null) 'media_category': mediaCategory!.name,
      if (isAccessible != null) 'is_accessible': isAccessible,
    };
  }

  factory SearchFilterCriteria.fromMap(Map<String, dynamic> map) {
    Set<WorkflowStatus>? statuses;
    if (map['workflow_statuses'] is List) {
      statuses = (map['workflow_statuses'] as List)
          .map((e) => workflowStatusFromStorage(e as String?))
          .toSet();
    }

    MediaCategoryFilter? mediaCat;
    if (map['media_category'] is String) {
      final name = map['media_category'] as String;
      mediaCat = MediaCategoryFilter.values.firstWhere(
        (e) => e.name == name,
        orElse: () => MediaCategoryFilter.image,
      );
    }

    return SearchFilterCriteria(
      query: map['query'] as String? ?? '',
      workflowStatuses: statuses,
      hasKeywords: map['has_keywords'] as bool?,
      hasTitle: map['has_title'] as bool?,
      hasDescription: map['has_description'] as bool?,
      isEditorial: map['is_editorial'] as bool?,
      isAiGenerated: map['is_ai_generated'] as bool?,
      mediaCategory: mediaCat,
      isAccessible: map['is_accessible'] as bool?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SearchFilterCriteria) return false;
    if (query != other.query ||
        hasKeywords != other.hasKeywords ||
        hasTitle != other.hasTitle ||
        hasDescription != other.hasDescription ||
        isEditorial != other.isEditorial ||
        isAiGenerated != other.isAiGenerated ||
        mediaCategory != other.mediaCategory ||
        isAccessible != other.isAccessible) {
      return false;
    }
    if (workflowStatuses == null && other.workflowStatuses == null) return true;
    if (workflowStatuses == null || other.workflowStatuses == null) return false;
    return workflowStatuses!.length == other.workflowStatuses!.length &&
        workflowStatuses!.containsAll(other.workflowStatuses!);
  }

  @override
  int get hashCode => Object.hash(
        query,
        workflowStatuses == null ? null : Object.hashAll(workflowStatuses!),
        hasKeywords,
        hasTitle,
        hasDescription,
        isEditorial,
        isAiGenerated,
        mediaCategory,
        isAccessible,
      );

  @override
  String toString() =>
      'SearchFilterCriteria(query: "$query", statuses: $workflowStatuses, '
      'hasKeywords: $hasKeywords, isEditorial: $isEditorial, isAi: $isAiGenerated, '
      'mediaCat: $mediaCategory, isAccessible: $isAccessible)';
}
