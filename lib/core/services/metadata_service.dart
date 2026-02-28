import 'dart:io';
import 'package:flutter/foundation.dart';

class MetadataService {
  /// Writes IPTC/XMP metadata to a file using exiftool.
  /// This assumes exiftool is available in the system PATH.
  static Future<bool> writeMetadata({
    required String filePath,
    required String title,
    required String keywords,
    String? description,
  }) async {
    try {
      // IPTC and XMP tags for Title, Description, and Keywords
      // -Title: IPTC:ObjectName, XMP-dc:Title
      // -Description: IPTC:Caption-Abstract, XMP-dc:Description
      // -Keywords: IPTC:Keywords, XMP-dc:Subject

      final result = await Process.run('exiftool', [
        '-overwrite_original',
        '-ObjectName=$title',
        '-Title=$title',
        if (description != null && description.isNotEmpty)
          '-Caption-Abstract=$description',
        if (description != null && description.isNotEmpty)
          '-Description=$description',
        '-Keywords=$keywords',
        '-Subject=$keywords',
        filePath,
      ]);

      if (result.exitCode == 0) {
        debugPrint('Successfully wrote metadata to $filePath');
        return true;
      } else {
        debugPrint('Failed to write metadata: ${result.stderr}');
        return false;
      }
    } catch (e) {
      debugPrint('Error calling exiftool: $e');
      return false;
    }
  }

  /// Check if exiftool is available on the system.
  static Future<bool> isExiftoolAvailable() async {
    try {
      final result = await Process.run('exiftool', ['-ver']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
