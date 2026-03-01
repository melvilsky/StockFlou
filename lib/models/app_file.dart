class AppFile {
  final String id;
  final String path;
  final String filename;
  final String? metadataTitle;
  final String? metadataDescription;
  final String? metadataKeywords;
  final bool isEditorial;
  final String? editorialCity;
  final String? editorialCountry;
  final int? editorialDate;
  final int createdAt;

  AppFile({
    required this.id,
    required this.path,
    required this.filename,
    this.metadataTitle,
    this.metadataDescription,
    this.metadataKeywords,
    this.isEditorial = false,
    this.editorialCity,
    this.editorialCountry,
    this.editorialDate,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'path': path,
      'filename': filename,
      'metadata_title': metadataTitle,
      'metadata_description': metadataDescription,
      'metadata_keywords': metadataKeywords,
      'is_editorial': isEditorial ? 1 : 0,
      'editorial_city': editorialCity,
      'editorial_country': editorialCountry,
      'editorial_date': editorialDate,
      'created_at': createdAt,
    };
  }

  factory AppFile.fromMap(Map<String, dynamic> map) {
    return AppFile(
      id: map['id'] as String,
      path: map['path'] as String,
      filename: map['filename'] as String,
      metadataTitle: map['metadata_title'] as String?,
      metadataDescription: map['metadata_description'] as String?,
      metadataKeywords: map['metadata_keywords'] as String?,
      isEditorial: (map['is_editorial'] as int?) == 1,
      editorialCity: map['editorial_city'] as String?,
      editorialCountry: map['editorial_country'] as String?,
      editorialDate: map['editorial_date'] as int?,
      createdAt: map['created_at'] as int,
    );
  }
}
