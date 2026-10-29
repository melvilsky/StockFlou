import '../../../models/app_file.dart';

/// Computes the tag list for a material after its title/description/keywords
/// were generated.
///
/// Generating metadata with AI says nothing about the material's origin:
/// [AppTags.aiGenerated] and all user tags are carried over unchanged. The
/// editorial tag follows the generation mode ([isEditorial]).
///
/// Pure function: copies [currentTags], never mutates it.
List<String> tagsAfterMetadataGeneration({
  required List<String> currentTags,
  required bool isEditorial,
}) {
  final tags = List<String>.of(currentTags);
  if (isEditorial) {
    if (!tags.contains(AppTags.editorial)) tags.add(AppTags.editorial);
  } else {
    tags.remove(AppTags.editorial);
  }
  return tags;
}
