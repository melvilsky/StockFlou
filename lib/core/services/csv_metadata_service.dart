import 'dart:io';
import 'package:csv/csv.dart';

import '../../models/app_file.dart';
import '../../models/csv_import_plan.dart';

class CsvMetadataService {
  /// Заголовки колонок CSV в фиксированном порядке.
  ///
  /// Первые семь колонок — исторический формат StockFlow, [Description] и
  /// [Path] добавлены в конец, чтобы старые CSV продолжали импортироваться.
  static const List<String> csvHeaders = [
    'Filename',
    'Title',
    'Keywords',
    'IsEditorial',
    'EditorialCity',
    'EditorialCountry',
    'EditorialDate',
    'Description',
    'Path',
  ];

  /// Exports a list of [AppFile]s to a CSV string.
  static String exportToCsv(List<AppFile> files) {
    final List<List<dynamic>> rows = [csvHeaders];

    // Add data rows
    for (final file in files) {
      rows.add([
        file.filename,
        file.metadataTitle ?? '',
        file.metadataKeywords ?? '',
        file.isEditorial ? 'true' : 'false',
        file.editorialCity ?? '',
        file.editorialCountry ?? '',
        _formatDate(file.editorialDate),
        file.metadataDescription ?? '',
        file.path,
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

    return parseCsv(await file.readAsString());
  }

  /// Разбирает CSV-текст в список карт «колонка → значение».
  ///
  /// Бросает [FormatException] с понятным описанием при нарушении структуры
  /// CSV: пустые или повторяющиеся заголовки, отсутствие колонки `Filename`,
  /// неверное число колонок в записи, незакрытая кавычка.
  static List<Map<String, String>> parseCsv(String source) {
    final rows = _parseRows(source);
    if (rows.isEmpty) return [];

    // First row is headers
    final headers = rows.first.map((h) => h.trim()).toList();
    if (headers.any((h) => h.isEmpty)) {
      throw const FormatException('Пустое имя колонки в заголовке CSV.');
    }

    final uniqueHeaders = <String>{};
    for (final header in headers) {
      if (!uniqueHeaders.add(header)) {
        throw FormatException(
          'Повторяющаяся колонка «$header» в заголовке CSV.',
        );
      }
    }
    if (!uniqueHeaders.contains('Filename')) {
      throw const FormatException(
        'В заголовке CSV отсутствует колонка «Filename».',
      );
    }

    // Parse data rows
    final List<Map<String, String>> result = [];
    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length != headers.length) {
        throw FormatException(
          'Запись ${i + 1}: ожидается ${headers.length} колонок, '
          'получено ${row.length}.',
        );
      }
      result.add({for (int j = 0; j < headers.length; j++) headers[j]: row[j]});
    }

    return result;
  }

  /// Сопоставляет строки CSV с материалами каталога и считает будущие значения.
  ///
  /// Чистая функция: не обращается к диску и к базе. Возвращает однозначные
  /// изменения и список проблем; проблемные строки в изменения не попадают.
  static CsvImportPlan buildImportPlan(
    List<Map<String, String>> rows,
    List<AppFile> files,
  ) {
    // Колонка считается присутствующей, если она есть хотя бы в одной строке.
    final presentColumns = <String>{};
    for (final row in rows) {
      presentColumns.addAll(row.keys);
    }

    // Шаг 1: Однозначно сопоставляем строки с материалами каталога и считаем
    // цели по всем сопоставленным строкам ДО проверки значений.
    final matchResults = <_RowMatch>[];
    final targetCounts = <String, int>{};

    for (int i = 0; i < rows.length; i++) {
      // Номер записи считается с учётом заголовка: запись 1 — заголовок.
      final recordNumber = i + 2;
      final row = rows[i];
      final match = _matchTarget(row, files);
      matchResults.add(
        _RowMatch(
          recordNumber: recordNumber,
          row: row,
          file: match.file,
          reason: match.reason,
        ),
      );

      if (match.file != null) {
        targetCounts[match.file!.id] = (targetCounts[match.file!.id] ?? 0) + 1;
      }
    }

    final problems = <CsvImportProblem>[];
    final changes = <CsvImportChange>[];

    // Шаг 2: Исключаем повторные цели и проверяем значения остальных строк.
    for (final item in matchResults) {
      final row = item.row;
      final filename = row['Filename'] ?? '';
      final path = row['Path'] ?? '';

      if (item.file == null) {
        problems.add(
          CsvImportProblem(
            recordNumber: item.recordNumber,
            reason: item.reason!,
            sourceFilename: filename,
            sourcePath: path,
          ),
        );
        continue;
      }

      final targetId = item.file!.id;
      if ((targetCounts[targetId] ?? 0) > 1) {
        problems.add(
          CsvImportProblem(
            recordNumber: item.recordNumber,
            reason: CsvImportReason.duplicateTarget,
            sourceFilename: filename,
            sourcePath: path,
          ),
        );
        continue;
      }

      final applied = _applyValues(item.file!, row, presentColumns);
      if (applied.file == null) {
        problems.add(
          CsvImportProblem(
            recordNumber: item.recordNumber,
            reason: applied.reason!,
            sourceFilename: filename,
            sourcePath: path,
          ),
        );
        continue;
      }

      changes.add(
        CsvImportChange(
          recordNumber: item.recordNumber,
          file: applied.file!,
          sourceFilename: filename,
          sourcePath: path,
        ),
      );
    }

    problems.sort((a, b) => a.recordNumber.compareTo(b.recordNumber));

    return CsvImportPlan(
      changes: changes,
      problems: problems,
      totalRecords: rows.length,
    );
  }

  /// Ищет материал, на который нацелена строка CSV.
  static _RowResult _matchTarget(Map<String, String> row, List<AppFile> files) {
    final filename = row['Filename'] ?? '';
    final path = row['Path'];

    if (path != null && path.isNotEmpty) {
      // Path — однозначный ключ: ищем только точное совпадение пути без trim.
      if (!path.startsWith('/')) {
        return const _RowResult(null, CsvImportReason.relativePath);
      }
      final matches = files.where((f) => f.path == path).toList();
      if (matches.isEmpty) {
        return const _RowResult(null, CsvImportReason.pathNotFound);
      }
      if (matches.length > 1) {
        return const _RowResult(null, CsvImportReason.ambiguousPath);
      }
      final file = matches.first;
      if (filename != file.filename) {
        return const _RowResult(null, CsvImportReason.filenameMismatch);
      }
      return _RowResult(file, null);
    }

    // Без Path (фактическое отсутствие/пустота) ищем только по точному имени файла.
    final matches = files.where((f) => f.filename == filename).toList();
    if (matches.isEmpty) {
      return const _RowResult(null, CsvImportReason.fileNotFound);
    }
    if (matches.length > 1) {
      return const _RowResult(null, CsvImportReason.ambiguousName);
    }
    return _RowResult(matches.first, null);
  }

  /// Применяет значения строки CSV к материалу.
  ///
  /// Отсутствующая колонка оставляет текущее значение без изменений, пустая
  /// присутствующая колонка очищает поле.
  static _RowResult _applyValues(
    AppFile file,
    Map<String, String> row,
    Set<String> presentColumns,
  ) {
    bool? isEditorial;
    if (presentColumns.contains('IsEditorial')) {
      final raw = (row['IsEditorial'] ?? '').trim().toLowerCase();
      if (raw == 'true') {
        isEditorial = true;
      } else if (raw == 'false') {
        isEditorial = false;
      } else {
        return const _RowResult(null, CsvImportReason.invalidBoolean);
      }
    }

    int? editorialDate;
    if (presentColumns.contains('EditorialDate')) {
      final raw = (row['EditorialDate'] ?? '').trim();
      if (raw.isNotEmpty) {
        final parsed = _parseStrictIsoDate(raw);
        if (parsed == null) {
          return const _RowResult(null, CsvImportReason.invalidDate);
        }
        editorialDate = parsed;
      }
    }

    var updated = file.copyWith(
      metadataTitle:
          presentColumns.contains('Title')
              ? _textValue(row['Title'])
              : file.metadataTitle,
      metadataDescription:
          presentColumns.contains('Description')
              ? _textValue(row['Description'])
              : file.metadataDescription,
      metadataKeywords:
          presentColumns.contains('Keywords')
              ? _textValue(row['Keywords'])
              : file.metadataKeywords,
      isEditorial: isEditorial,
      editorialCity:
          presentColumns.contains('EditorialCity')
              ? _optionalTextValue(row['EditorialCity'])
              : file.editorialCity,
      editorialCountry:
          presentColumns.contains('EditorialCountry')
              ? _optionalTextValue(row['EditorialCountry'])
              : file.editorialCountry,
      editorialDate:
          presentColumns.contains('EditorialDate')
              ? editorialDate
              : file.editorialDate,
    );

    if (isEditorial != null) {
      // Признак и тег «editorial» меняются согласованно; остальные теги — нет.
      updated =
          isEditorial
              ? updated.withTag(AppTags.editorial)
              : updated.withoutTag(AppTags.editorial);
    }

    return _RowResult(updated, null);
  }

  static final _isoDateRegex = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})'
    r'(?:[Tt](\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?'
    r'([Zz]|[+-]\d{2}:?\d{2})?)?$',
  );

  /// Разбирает дату в строгом подмножестве ISO-8601 с проверкой календарных
  /// границ и смещений.
  static int? _parseStrictIsoDate(String raw) {
    final match = _isoDateRegex.firstMatch(raw);
    if (match == null) return null;

    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);

    if (year < 1 || year > 9999) return null;
    if (month < 1 || month > 12) return null;
    final maxDays = _daysInMonth(year, month);
    if (day < 1 || day > maxDays) return null;

    final hourStr = match.group(4);
    if (hourStr == null) {
      // Только календарная дата YYYY-MM-DD
      return DateTime(year, month, day).millisecondsSinceEpoch;
    }

    final hour = int.parse(hourStr);
    final minute = int.parse(match.group(5)!);
    final second = int.parse(match.group(6)!);

    if (hour < 0 || hour > 23) return null;
    if (minute < 0 || minute > 59) return null;
    if (second < 0 || second > 59) return null;

    int microseconds = 0;
    final fracStr = match.group(7);
    if (fracStr != null) {
      microseconds = int.parse(fracStr.padRight(6, '0'));
    }
    final millisecond = microseconds ~/ 1000;
    final microsecond = microseconds % 1000;

    final tzStr = match.group(8);
    if (tzStr == null) {
      // Без часового пояса сохраняется локальная интерпретация
      return DateTime(
        year,
        month,
        day,
        hour,
        minute,
        second,
        millisecond,
        microsecond,
      ).millisecondsSinceEpoch;
    }

    if (tzStr == 'Z' || tzStr == 'z') {
      return DateTime.utc(
        year,
        month,
        day,
        hour,
        minute,
        second,
        millisecond,
        microsecond,
      ).millisecondsSinceEpoch;
    }

    final isNegative = tzStr.startsWith('-');
    final digits = tzStr.substring(1).replaceAll(':', '');
    final offsetHours = int.parse(digits.substring(0, 2));
    final offsetMinutes = int.parse(digits.substring(2, 4));

    if (offsetHours < 0 ||
        offsetHours > 23 ||
        offsetMinutes < 0 ||
        offsetMinutes > 59) {
      return null;
    }

    final utc = DateTime.utc(
      year,
      month,
      day,
      hour,
      minute,
      second,
      millisecond,
      microsecond,
    );
    final offset = Duration(hours: offsetHours, minutes: offsetMinutes);
    final moment = isNegative ? utc.add(offset) : utc.subtract(offset);
    return moment.millisecondsSinceEpoch;
  }

  static bool _isLeapYear(int year) {
    return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
  }

  static int _daysInMonth(int year, int month) {
    switch (month) {
      case 1:
      case 3:
      case 5:
      case 7:
      case 8:
      case 10:
      case 12:
        return 31;
      case 4:
      case 6:
      case 9:
      case 11:
        return 30;
      case 2:
        return _isLeapYear(year) ? 29 : 28;
      default:
        return 0;
    }
  }

  /// Текстовое значение: пустое значение очищает поле пустой строкой.
  static String _textValue(String? value) {
    if (value == null || value.isEmpty) return '';
    return value;
  }

  /// Необязательное значение: пустое значение очищает поле (null).
  static String? _optionalTextValue(String? value) {
    if (value == null || value.isEmpty) return null;
    return value;
  }

  static String _formatDate(int? milliseconds) {
    if (milliseconds == null) return '';
    return DateTime.fromMillisecondsSinceEpoch(milliseconds).toIso8601String();
  }

  /// Разбирает CSV-текст в строки значений (RFC 4180).
  ///
  /// Поддерживает переводы строк CRLF/LF/CR, кавычки с экранированием (`""`),
  /// запятые и переносы строк внутри значений. Полностью пустые строки
  /// отбрасываются.
  static List<List<String>> _parseRows(String source) {
    var text = source;
    if (text.startsWith('\uFEFF')) {
      // BOM снимается только в начале документа.
      text = text.substring(1);
    }

    final rows = <List<String>>[];
    final field = StringBuffer();
    var row = <String>[];
    var inQuotes = false;
    var quoteClosed = false;
    var i = 0;

    void endField() {
      row.add(field.toString());
      field.clear();
      quoteClosed = false;
    }

    void endRow() {
      endField();
      rows.add(row);
      row = <String>[];
    }

    while (i < text.length) {
      final char = text[i];

      if (inQuotes) {
        if (char == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i += 2;
            continue;
          }
          inQuotes = false;
          quoteClosed = true;
          i++;
          continue;
        }
        field.write(char);
        i++;
        continue;
      }

      if (char == '"') {
        if (field.isNotEmpty) {
          throw FormatException(
            'Запись ${rows.length + 1}: кавычка внутри некавыченного значения.',
          );
        }
        inQuotes = true;
        i++;
        continue;
      }

      if (quoteClosed) {
        if (char == ',') {
          endField();
          i++;
          continue;
        }
        if (char == '\r' || char == '\n') {
          if (char == '\r' && i + 1 < text.length && text[i + 1] == '\n') {
            i++;
          }
          endRow();
          i++;
          continue;
        }
        throw FormatException(
          'Запись ${rows.length + 1}: лишний символ «$char» '
          'после закрывающей кавычки.',
        );
      }

      if (char == ',') {
        endField();
        i++;
        continue;
      }

      if (char == '\r' || char == '\n') {
        if (char == '\r' && i + 1 < text.length && text[i + 1] == '\n') {
          i++;
        }
        endRow();
        i++;
        continue;
      }

      field.write(char);
      i++;
    }

    if (inQuotes) {
      throw const FormatException('CSV оборван: незакрытая кавычка.');
    }
    if (quoteClosed || field.isNotEmpty || row.isNotEmpty) {
      endRow();
    }

    return rows.where((r) => r.any((v) => v.isNotEmpty)).toList();
  }
}

/// Результат одной операции над строкой CSV: файл либо причина пропуска.
class _RowResult {
  const _RowResult(this.file, this.reason);

  final AppFile? file;
  final String? reason;
}

/// Промежуточное сопоставление строки CSV с материалом каталога.
class _RowMatch {
  const _RowMatch({
    required this.recordNumber,
    required this.row,
    required this.file,
    required this.reason,
  });

  final int recordNumber;
  final Map<String, String> row;
  final AppFile? file;
  final String? reason;
}
