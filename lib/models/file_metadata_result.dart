/// Result of a detailed metadata write attempt via ExifTool.
class FileMetadataWriteResult {
  final bool success;

  /// Human-readable failure reason, set exactly when [success] is false.
  final String? errorMessage;

  const FileMetadataWriteResult.success() : success = true, errorMessage = null;

  const FileMetadataWriteResult.failure(this.errorMessage) : success = false;
}

/// Result of reading the core metadata fields (title, description, keywords)
/// from a file via ExifTool.
class FileMetadataReadResult {
  final bool success;

  /// null means the field is absent in the file, not an error.
  final String? title;
  final String? description;
  final List<String> keywords;

  /// Human-readable failure reason, set exactly when [success] is false.
  final String? errorMessage;

  const FileMetadataReadResult.success({
    this.title,
    this.description,
    this.keywords = const <String>[],
  }) : success = true,
       errorMessage = null;

  const FileMetadataReadResult.failure(this.errorMessage)
    : success = false,
      title = null,
      description = null,
      keywords = const <String>[];
}
