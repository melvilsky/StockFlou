import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../../models/file_metadata_result.dart';

/// Signature for the process launcher used to invoke ExifTool. Tests can
/// substitute a fake run; production code uses [Process.run].
typedef ExiftoolProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

class MetadataService {
  /// Writes IPTC/XMP metadata to a file using exiftool.
  /// This assumes exiftool is available in the system PATH.
  ///
  /// Legacy boolean wrapper around [writeMetadataDetailed].
  static Future<bool> writeMetadata({
    required String filePath,
    required String title,
    required String keywords,
    String? description,
    String? city,
    String? country,
    DateTime? shootDate,
    ExiftoolProcessRunner? runProcess,
  }) async {
    final result = await writeMetadataDetailed(
      filePath: filePath,
      title: title,
      keywords: keywords,
      description: description,
      city: city,
      country: country,
      shootDate: shootDate,
      runProcess: runProcess,
    );
    return result.success;
  }

  /// Same input fields as [writeMetadata], but reports the failure reason.
  ///
  /// [title] and [keywords] are values to write (empty values included).
  /// [description] == null means "leave description untouched",
  /// [description] == '' means "clear description".
  /// [city] and [country] follow the same rule: null leaves location tags
  /// untouched, an empty string clears them.
  /// [shootDate] == null leaves date tags untouched. The original EXIF
  /// DateTimeOriginal is not rewritten, so a calendar edit does not wipe
  /// the capture time.
  static Future<FileMetadataWriteResult> writeMetadataDetailed({
    required String filePath,
    required String title,
    required String keywords,
    String? description,
    String? city,
    String? country,
    DateTime? shootDate,
    ExiftoolProcessRunner? runProcess,
  }) async {
    // Split comma-separated keywords into individual -Keywords flags so
    // IPTC stores them as separate entries (not one long comma-joined string).
    final keywordList =
        keywords
            .split(',')
            .map((k) => k.trim())
            .where((k) => k.isNotEmpty)
            .toList();

    final descriptionArgs = switch (description) {
      null => const <String>[],
      '' => const ['-Caption-Abstract=', '-Description=', '-ImageDescription='],
      _ => [
        '-Caption-Abstract=$description',
        '-Description=$description',
        '-ImageDescription=$description',
      ],
    };

    final args = <String>[
      '-overwrite_original',
      '-ObjectName=$title',
      '-Title=$title',
      ...descriptionArgs,
      ..._locationArgs(city, const ['-IPTC:City=', '-XMP-photoshop:City=']),
      ..._locationArgs(country, const [
        '-IPTC:Country-PrimaryLocationName=',
        '-XMP-photoshop:Country=',
      ]),
      ..._shootDateArgs(shootDate),
      // Clear existing keywords first, then write all new ones individually
      '-Keywords=',
      '-Subject=',
      for (final kw in keywordList) '-Keywords=$kw',
      for (final kw in keywordList) '-Subject=$kw',
      filePath,
    ];

    try {
      final result = await _run(runProcess, args);

      if (result.exitCode == 0) {
        debugPrint('Successfully wrote metadata to $filePath');
        return const FileMetadataWriteResult.success();
      }
      final reason = _describeStderr(result.stderr);
      // Warnings alone (exit code 0) are treated as success above; a non-zero
      // exit code carries the ExifTool-reported reason in stderr.
      debugPrint('Metadata write failed for $filePath: $reason');
      return FileMetadataWriteResult.failure(
        _failureMessage(result.exitCode, reason),
      );
    } on ProcessException catch (e) {
      // ProcessException.toString includes the full command line with
      // metadata values; keep only the OS message.
      debugPrint('Metadata write failed for $filePath: ${e.message}');
      return FileMetadataWriteResult.failure(
        'Failed to run exiftool: ${e.message}',
      );
    } catch (e) {
      debugPrint('Metadata write failed for $filePath: $e');
      return FileMetadataWriteResult.failure('Failed to run exiftool: $e');
    }
  }

  /// Reads only the core metadata fields (title, description, keywords).
  ///
  /// Does not write to disk or update any database. Uses `-G0` so that the
  /// three priority groups are flat JSON keys: `XMP:Tag`, `IPTC:Tag`,
  /// `EXIF:Tag` — each meaning-sense field is picked in that order,
  /// skipping empty values instead of combining sets.
  static Future<FileMetadataReadResult> readMetadata({
    required String filePath,
    ExiftoolProcessRunner? runProcess,
  }) async {
    try {
      final result = await _run(runProcess, [
        '-json',
        '-G0',
        '-Objectname',
        '-Title',
        '-Caption-Abstract',
        '-Description',
        '-ImageDescription',
        '-Keywords',
        '-Subject',
        filePath,
      ]);

      if (result.exitCode != 0) {
        final reason = _describeStderr(result.stderr);
        debugPrint('Metadata read failed for $filePath: $reason');
        return FileMetadataReadResult.failure(
          reason.isEmpty
              ? 'exiftool exited with code ${result.exitCode}'
              : reason,
        );
      }

      final data = _parseJsonRoot(result.stdout as String);
      if (data == null) {
        debugPrint('Metadata read failed for $filePath: unexpected JSON');
        return const FileMetadataReadResult.failure(
          'exiftool returned unexpected or invalid JSON',
        );
      }

      return FileMetadataReadResult.success(
        title: _pickString(data, ['XMP:Title', 'IPTC:ObjectName']),
        description: _pickString(data, [
          'XMP:Description',
          'IPTC:Caption-Abstract',
          'EXIF:ImageDescription',
        ]),
        keywords: _pickKeywords(data, ['XMP:Subject', 'IPTC:Keywords']),
      );
    } on ProcessException catch (e) {
      debugPrint('Metadata read failed for $filePath: ${e.message}');
      return FileMetadataReadResult.failure(
        'Failed to run exiftool: ${e.message}',
      );
    } catch (e) {
      debugPrint('Metadata read failed for $filePath: $e');
      return FileMetadataReadResult.failure('Failed to run exiftool: $e');
    }
  }

  /// null leaves the tags untouched; any other value, including empty, is written.
  static List<String> _locationArgs(String? value, List<String> tags) {
    if (value == null) return const [];
    return [for (final tag in tags) '$tag$value'];
  }

  static List<String> _shootDateArgs(DateTime? date) {
    if (date == null) return const [];
    final value =
        '${date.year.toString().padLeft(4, '0')}:'
        '${date.month.toString().padLeft(2, '0')}:'
        '${date.day.toString().padLeft(2, '0')}';
    return ['-IPTC:DateCreated=$value', '-XMP-photoshop:DateCreated=$value'];
  }

  static String _failureMessage(int exitCode, String reason) {
    if (reason.isEmpty) return 'exiftool exited with code $exitCode';
    return reason;
  }

  static Future<ProcessResult> _run(
    ExiftoolProcessRunner? runProcess,
    List<String> args,
  ) {
    final runner = runProcess ?? Process.run;
    return runner('exiftool', args);
  }

  /// Decodes the ExifTool `-json` root: a list whose first element is the map
  /// for the requested file. null means invalid or empty output.
  static Map<String, dynamic>? _parseJsonRoot(String stdout) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(stdout);
    } on FormatException {
      return null;
    }
    if (decoded is! List || decoded.isEmpty) return null;
    final dynamic first = decoded.first;
    if (first is! Map<String, dynamic>) return null;
    return first;
  }

  /// First non-empty value among group keys; null when every value is absent.
  static String? _pickString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value == null) continue;
      final text = value.toString();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  /// List tags come back either as a JSON array (several values) or as a
  /// single string (one value); both are returned as one item per value.
  static List<String> _pickKeywords(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = data[key];
      if (value == null) continue;
      if (value is List) {
        final items = value.map((e) => e.toString()).toList();
        if (items.isEmpty) continue;
        return items;
      }
      if (value is String && value.isEmpty) continue;
      return [value.toString()];
    }
    return const <String>[];
  }

  /// Compact stderr excerpt for error reporting and logs, never full metadata.
  static String _describeStderr(Object? stderr) {
    final text = stderr?.toString().trim() ?? '';
    if (text.isEmpty) return '';
    const maxLength = 400;
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}…';
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
      if (json.isEmpty) {
        return (lat: null, lon: null, date: null, hasAudio: false);
      }
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
        final cleaned =
            dateStr
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
