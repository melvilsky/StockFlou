import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:stock_flow/core/services/metadata_service.dart';

/// End-to-end check against the real exiftool binary and a generated JPEG.
/// Runs only when exiftool is installed; skipped silently otherwise (the
/// mandatory suite in metadata_service_test.dart uses the injected runner).
Future<void> main() async {
  final exiftoolAvailable = await MetadataService.isExiftoolAvailable();
  if (!exiftoolAvailable) return;

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('metadata_service_it_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<File> createTestJpeg(String name) async {
    final image = img.Image(width: 8, height: 8);
    final bytes = img.encodeJpg(image, quality: 90);
    final file = File('${tempDir.path}/$name');
    await file.writeAsBytes(bytes);
    return file;
  }

  test('writes, reads back, then explicitly clears the description', () async {
    const description = '«цитата» "quoted"\nline two';
    final file = await createTestJpeg('test image.jpg');

    final written = await MetadataService.writeMetadata(
      filePath: file.path,
      title: 'Заголовок "q"',
      keywords: 'mountains, two words, city',
      description: description,
    );
    expect(written, isTrue);

    final read = await MetadataService.readMetadata(filePath: file.path);
    expect(read.success, isTrue, reason: read.errorMessage ?? '');
    // Title comes from XMP, the whole description including newline survives.
    expect(read.title, 'Заголовок "q"');
    expect(read.description, description);
    expect(read.keywords, ['mountains', 'two words', 'city']);

    final cleared = await MetadataService.writeMetadata(
      filePath: file.path,
      title: 'Заголовок "q"',
      keywords: 'mountains, two words, city',
      description: '',
    );
    expect(cleared, isTrue);

    final readAfterClear = await MetadataService.readMetadata(
      filePath: file.path,
    );
    expect(readAfterClear.success, isTrue);
    expect(
      readAfterClear.description,
      isNull,
      reason: 'explicitly cleared description must read back absent',
    );
    expect(readAfterClear.title, 'Заголовок "q"');
    expect(readAfterClear.keywords, ['mountains', 'two words', 'city']);
  });

  test('JPEG without metadata reads as success with empty fields', () async {
    final file = await createTestJpeg('clean.jpg');

    final read = await MetadataService.readMetadata(filePath: file.path);
    expect(read.success, isTrue);
    expect(read.title, isNull);
    expect(read.description, isNull);
    expect(read.keywords, isEmpty);
  });
}
