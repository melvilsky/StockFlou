import 'app_file.dart';

/// Причины, по которым строка CSV не применяется при импорте.
class CsvImportReason {
  const CsvImportReason._();

  /// Нет файла с таким именем в каталоге.
  static const String fileNotFound = 'Файл не найден в каталоге';

  /// В каталоге несколько файлов с таким именем.
  static const String ambiguousName = 'Неоднозначное имя, укажите Path';

  /// Path указан, но он не абсолютный.
  static const String relativePath = 'Относительный путь, укажите полный Path';

  /// Path указан, но в каталоге нет файла с таким путём.
  static const String pathNotFound = 'Файл не найден по указанному Path';

  /// В каталоге несколько файлов с таким путём.
  static const String ambiguousPath = 'Неоднозначный Path';

  /// Имя файла в строке не совпадает с найденным по Path.
  static const String filenameMismatch =
      'Имя файла не совпадает с найденным по Path';

  /// Несколько строк CSV указывают на один и тот же материал.
  static const String duplicateTarget =
      'Несколько строк указывают на один файл';

  /// IsEditorial содержит не `true`/`false`.
  static const String invalidBoolean = 'Некорректное значение IsEditorial';

  /// EditorialDate не является датой ISO-8601.
  static const String invalidDate = 'Некорректная дата EditorialDate';
}

/// Строка CSV, которую можно применить к материалу каталога.
class CsvImportChange {
  const CsvImportChange({
    required this.recordNumber,
    required this.file,
    required this.sourceFilename,
    required this.sourcePath,
  });

  /// Номер записи в CSV с учётом строки заголовка (заголовок — запись 1).
  final int recordNumber;

  /// Материал каталога с применёнными значениями из CSV.
  final AppFile file;

  /// Имя файла из строки CSV.
  final String sourceFilename;

  /// Path из строки CSV (пустая строка, если колонки не было).
  final String sourcePath;
}

/// Строка CSV, которая не будет применена.
class CsvImportProblem {
  const CsvImportProblem({
    required this.recordNumber,
    required this.reason,
    required this.sourceFilename,
    required this.sourcePath,
  });

  /// Номер записи в CSV с учётом строки заголовка (заголовок — запись 1).
  final int recordNumber;

  /// Почему строка пропущена.
  final String reason;

  /// Имя файла из строки CSV.
  final String sourceFilename;

  /// Path из строки CSV (пустая строка, если колонки не было).
  final String sourcePath;
}

/// Результат сопоставления строк CSV с материалами каталога.
class CsvImportPlan {
  const CsvImportPlan({
    required this.changes,
    required this.problems,
    required this.totalRecords,
  });

  /// Однозначные изменения, которые можно применить.
  final List<CsvImportChange> changes;

  /// Строки, которые будут пропущены.
  final List<CsvImportProblem> problems;

  /// Всего записей данных в CSV (без строки заголовка).
  final int totalRecords;

  bool get hasChanges => changes.isNotEmpty;

  bool get hasProblems => problems.isNotEmpty;
}
