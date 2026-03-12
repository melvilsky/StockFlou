import 'dart:io';
import 'package:csv/csv.dart';

import '../../models/app_file.dart';

class CsvMetadataService {
  /// Exports a list of [AppFile]s to a CSV string.
  static String exportToCsv(List<AppFile> files) {
    // Define the headers
    final List<List<dynamic>> rows = [
      [
        'Filename',
        'Title',
        'Keywords',
        'IsEditorial',
        'EditorialCity',
        'EditorialCountry',
        'EditorialDate',
      ],
    ];

    // Add data rows
    for (final file in files) {
      final dateStr = file.editorialDate != null
          ? DateTime.fromMillisecondsSinceEpoch(
              file.editorialDate!,
            ).toIso8601String()
          : '';

      rows.add([
        file.filename,
        file.metadataTitle ?? '',
        file.metadataKeywords ?? '',
        file.isEditorial ? 'true' : 'false',
        file.editorialCity ?? '',
        file.editorialCountry ?? '',
        dateStr,
      ]);
    }

    // Convert to CSV string (RFC 4180)
    return const ListToCsvConverter().convert(rows);
  }

  /// Exports and saves the [files] to a single CSV file at [outputPath].
  static Future<void> exportToFile(
    List<AppFile> files,
    String outputPath,
  ) async {
    final csvString = exportToCsv(files);
    final file = File(outputPath);
    await file.writeAsString(csvString);
  }

  /// Parses a CSV file and returns a list of update maps where keys are header names.
  static Future<List<Map<String, String>>> importFromFile(
    String inputPath,
  ) async {
    final file = File(inputPath);
    if (!await file.exists()) {
      throw Exception('File not found at $inputPath');
    }

    final csvString = await file.readAsString();
    final List<List<dynamic>> rows = const CsvToListConverter().convert(
      csvString,
    );

    if (rows.isEmpty) return [];

    // First row is assumed to be headers
    final headers = rows.first.map((h) => h.toString().trim()).toList();
    final List<Map<String, String>> result = [];

    // Parse data rows
    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      final map = <String, String>{};

      for (int j = 0; j < headers.length; j++) {
        if (j < row.length) {
          map[headers[j]] = row[j]?.toString() ?? '';
        } else {
          map[headers[j]] = '';
        }
      }
      result.add(map);
    }

    return result;
  }
}
