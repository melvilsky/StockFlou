import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../models/app_file.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/services/metadata_service.dart';

class CsvImportPreviewDialog extends ConsumerStatefulWidget {
  final List<Map<String, String>> parsedData;
  final List<AppFile> dbFiles;

  const CsvImportPreviewDialog({
    super.key,
    required this.parsedData,
    required this.dbFiles,
  });

  @override
  ConsumerState<CsvImportPreviewDialog> createState() =>
      _CsvImportPreviewDialogState();
}

class _CsvImportPreviewDialogState
    extends ConsumerState<CsvImportPreviewDialog> {
  bool _isImporting = false;
  int _matchedCount = 0;
  List<AppFile> _filesToUpdate = [];

  @override
  void initState() {
    super.initState();
    _analyzeMatches();
  }

  void _analyzeMatches() {
    // We match rows back to the database files using 'Filename' and sometimes path
    // But CSV only has Filename by default in our export. Let's match by filename.
    final matched = <AppFile>[];

    for (final row in widget.parsedData) {
      final filename = row['Filename']?.trim();
      if (filename == null || filename.isEmpty) continue;

      // Find all DB files with this filename (could be multiple in different paths, but we just take first match for simplicity or try path matching if path was included)
      final dbFile = widget.dbFiles
          .where((f) => f.filename == filename)
          .firstOrNull;

      if (dbFile != null) {
        // Build updated AppFile
        final bool isEditorial = row['IsEditorial']?.toLowerCase() == 'true';
        final int? editDate = row['EditorialDate']?.trim().isNotEmpty == true
            ? DateTime.tryParse(row['EditorialDate']!)?.millisecondsSinceEpoch
            : null;

        matched.add(
          dbFile.copyWith(
            metadataTitle: row['Title']?.trim(),
            metadataKeywords: row['Keywords']?.trim(),
            isEditorial: isEditorial,
            editorialCity: row['EditorialCity']?.trim(),
            editorialCountry: row['EditorialCountry']?.trim(),
            editorialDate: editDate,
          ),
        );
      }
    }

    setState(() {
      _filesToUpdate = matched;
      _matchedCount = matched.length;
    });
  }

  Future<void> _performImport() async {
    setState(() => _isImporting = true);

    try {
      final dbHelper = DatabaseHelper.instance;

      // Update each file in DB and EXIF if needed
      for (final file in _filesToUpdate) {
        // 1. Write to file using metadata_service (this handles writing to actual physical file)
        await MetadataService.writeMetadata(
          filePath: file.path,
          title: file.metadataTitle ?? '',
          keywords: file.metadataKeywords ?? '',
          description: file.metadataDescription,
        );

        // 2. Persist to DB
        await dbHelper.updateFile(file);
      }

      if (mounted) {
        Navigator.of(context).pop(true); // Success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при применении метаданных: $e')),
        );
        setState(() => _isImporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Превью импорта CSV'),
      content: _isImporting
          ? const SizedBox(
              height: 100,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Применяем метаданные...'),
                  ],
                ),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Найдено строк в CSV: ${widget.parsedData.length}'),
                const SizedBox(height: 8),
                Text(
                  'Совпало с файлами в базе: $_matchedCount',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _matchedCount > 0 ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(height: 16),
                if (_matchedCount > 0)
                  const Text(
                    'Внимание: существующие метаданные совпавших файлов будут перезаписаны данными из CSV.',
                    style: TextStyle(color: Colors.orange),
                  ),
              ],
            ),
      actions: _isImporting
          ? null
          : [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false), // Cancel
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: _matchedCount > 0 ? _performImport : null,
                child: const Text('Импортировать'),
              ),
            ],
    );
  }
}
