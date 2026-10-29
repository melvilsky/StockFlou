import 'package:flutter_test/flutter_test.dart';
import 'package:stock_flow/features/generation/domain/generation_tags.dart';
import 'package:stock_flow/models/app_file.dart';

void main() {
  group('tagsAfterMetadataGeneration', () {
    test('empty tags without editorial mode stay empty', () {
      final result = tagsAfterMetadataGeneration(
        currentTags: const [],
        isEditorial: false,
      );
      expect(result, isEmpty);
    });

    test('user tags are kept and ai_generated is not added', () {
      final result = tagsAfterMetadataGeneration(
        currentTags: const ['sunset', 'nature'],
        isEditorial: false,
      );
      expect(result, ['sunset', 'nature']);
      expect(result.contains(AppTags.aiGenerated), isFalse);
    });

    test('existing ai_generated tag is preserved', () {
      final result = tagsAfterMetadataGeneration(
        currentTags: [AppTags.aiGenerated, 'model', 'portrait'],
        isEditorial: false,
      );
      expect(result, [AppTags.aiGenerated, 'model', 'portrait']);
    });

    test('editorial mode adds only the editorial tag', () {
      final result = tagsAfterMetadataGeneration(
        currentTags: const ['sunset'],
        isEditorial: true,
      );
      expect(result, ['sunset', AppTags.editorial]);
      expect(result.contains(AppTags.aiGenerated), isFalse);
    });

    test('non-editorial mode removes only the editorial tag', () {
      final result = tagsAfterMetadataGeneration(
        currentTags: const [AppTags.editorial, 'sunset', 'another-tag'],
        isEditorial: false,
      );
      expect(result, ['sunset', 'another-tag']);
      expect(result.contains(AppTags.aiGenerated), isFalse);
    });

    test('input list is not mutated', () {
      final tags = <String>['sunset', AppTags.editorial];
      final snapshot = List<String>.from(tags);
      tagsAfterMetadataGeneration(currentTags: tags, isEditorial: true);
      expect(tags, snapshot);
    });

    test('two materials with different AI origin get independent results', () {
      final afterAi = tagsAfterMetadataGeneration(
        currentTags: const [AppTags.aiGenerated, 'mountain'],
        isEditorial: true,
      );
      final afterNormal = tagsAfterMetadataGeneration(
        currentTags: const ['mountain'],
        isEditorial: true,
      );
      expect(afterAi, [AppTags.aiGenerated, 'mountain', AppTags.editorial]);
      expect(afterNormal, ['mountain', AppTags.editorial]);
      expect(afterNormal.contains(AppTags.aiGenerated), isFalse);
    });

    test('applying twice does not add a duplicate editorial tag', () {
      final first = tagsAfterMetadataGeneration(
        currentTags: const ['sunset'],
        isEditorial: true,
      );
      final second = tagsAfterMetadataGeneration(
        currentTags: first,
        isEditorial: true,
      );
      expect(second, ['sunset', AppTags.editorial]);
    });
  });
}
