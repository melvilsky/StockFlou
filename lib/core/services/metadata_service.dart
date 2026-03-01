import 'dart:convert';
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

  /// Reads GPS coordinates and creation date from a file's EXIF data.
  /// Works for both photos (JPEG, PNG) and videos (MOV, MP4).
  static Future<({double? lat, double? lon, DateTime? date, bool hasAudio})>
  readExifLocationAndDate(String filePath) async {
    try {
      final result = await Process.run('exiftool', [
        '-json',
        '-n', // numeric GPS values
        '-GPSLatitude',
        '-GPSLongitude',
        '-DateTimeOriginal',
        '-CreateDate',
        '-AudioChannels',
        '-AudioFormat',
        '-AudioSampleRate',
        filePath,
      ]);

      if (result.exitCode != 0) {
        debugPrint('exiftool read failed: ${result.stderr}');
        return (lat: null, lon: null, date: null, hasAudio: false);
      }

      final List<dynamic> json = jsonDecode(result.stdout as String);
      if (json.isEmpty)
        return (lat: null, lon: null, date: null, hasAudio: false);
      final data = json[0] as Map<String, dynamic>;

      // Audio
      final channels = data['AudioChannels'];
      final format = data['AudioFormat'];
      final sampleRate = data['AudioSampleRate'];
      final bool hasAudio =
          (channels != null && channels.toString() != '0') ||
          (format != null &&
              format.toString().isNotEmpty &&
              format.toString() != 'none') ||
          (sampleRate != null && sampleRate.toString() != '0');

      // GPS
      final lat = _toDouble(data['GPSLatitude']);
      final lon = _toDouble(data['GPSLongitude']);

      // Date: prefer DateTimeOriginal, fallback to CreateDate
      DateTime? date;
      final dateStr =
          (data['DateTimeOriginal'] ?? data['CreateDate']) as String?;
      if (dateStr != null &&
          dateStr.isNotEmpty &&
          dateStr != '0000:00:00 00:00:00') {
        // exiftool format: "2024:01:15 14:30:00" or with timezone
        final cleaned = dateStr
            .replaceFirst(RegExp(r'[+-]\d{2}:\d{2}$'), '') // strip timezone
            .trim();
        final parts = cleaned.split(' ');
        if (parts.length >= 2) {
          final datePart = parts[0].replaceAll(':', '-');
          final timePart = parts[1];
          date = DateTime.tryParse('${datePart}T$timePart');
        }
      }

      return (lat: lat, lon: lon, date: date, hasAudio: hasAudio);
    } catch (e) {
      debugPrint('Error reading EXIF: $e');
      return (lat: null, lon: null, date: null, hasAudio: false);
    }
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
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
