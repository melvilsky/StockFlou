import 'workflow_status.dart';

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
  final WorkflowStatus workflowStatus;
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
    this.workflowStatus = WorkflowStatus.newFile,
    required this.createdAt,
  });

  AppFile copyWith({
    String? id,
    String? path,
    String? filename,
    Object? metadataTitle = _sentinel,
    Object? metadataDescription = _sentinel,
    Object? metadataKeywords = _sentinel,
    bool? isEditorial,
    Object? editorialCity = _sentinel,
    Object? editorialCountry = _sentinel,
    Object? editorialDate = _sentinel,
    WorkflowStatus? workflowStatus,
    int? createdAt,
  }) {
    return AppFile(
      id: id ?? this.id,
      path: path ?? this.path,
      filename: filename ?? this.filename,
      metadataTitle: metadataTitle == _sentinel
          ? this.metadataTitle
          : metadataTitle as String?,
      metadataDescription: metadataDescription == _sentinel
          ? this.metadataDescription
          : metadataDescription as String?,
      metadataKeywords: metadataKeywords == _sentinel
          ? this.metadataKeywords
          : metadataKeywords as String?,
      isEditorial: isEditorial ?? this.isEditorial,
      editorialCity: editorialCity == _sentinel
          ? this.editorialCity
          : editorialCity as String?,
      editorialCountry: editorialCountry == _sentinel
          ? this.editorialCountry
          : editorialCountry as String?,
      editorialDate: editorialDate == _sentinel
          ? this.editorialDate
          : editorialDate as int?,
      workflowStatus: workflowStatus ?? this.workflowStatus,
      createdAt: createdAt ?? this.createdAt,
    );
  }

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
      'workflow_status': workflowStatus.storageValue,
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
      workflowStatus: workflowStatusFromStorage(map['workflow_status'] as String?),
      createdAt: map['created_at'] as int,
    );
  }
}

/// Sentinel value for nullable copyWith fields.
const _sentinel = Object();
