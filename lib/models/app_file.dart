class AppFile {
  final String id;
  final String path;
  final String filename;
  final String? metadataTitle;
  final String? metadataDescription;
  final String? metadataKeywords;
  final int createdAt;

  AppFile({
    required this.id,
    required this.path,
    required this.filename,
    this.metadataTitle,
    this.metadataDescription,
    this.metadataKeywords,
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
      createdAt: map['created_at'] as int,
    );
  }
}
