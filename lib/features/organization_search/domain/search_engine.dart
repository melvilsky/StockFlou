import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pool/pool.dart';

import '../../../models/app_file.dart';
import 'search_filter_criteria.dart';
import 'search_result_item.dart';
import 'search_scope.dart';

/// Функция проверки физической доступности файла на диске.
/// Может возвращать как [bool], так и [Future<bool>].
typedef FileAccessibilityProbe = FutureOr<bool> Function(String path);

/// Ядро логики поиска и фильтрации по источнику и свойствам файлов.
class SearchEngine {
  const SearchEngine();

  /// Отбирает файлы, относящиеся к заданной области поиска [scope].
  ///
  /// Гарантии:
  /// - Режим [scope.includeSubfolders] учитывается для папок и проектов;
  /// - При пересечении корней проекта один и тот же [AppFile.id] не дублируется;
  /// - Разные файлы с одинаковыми именами ([AppFile.filename]), но разными [AppFile.id],
  ///   считаются независимыми и оба входят в выдачу;
  /// - Недоступность диска или источника не означает пустую коллекцию и не удаляет членство.
  Future<List<AppFile>> resolveFilesForScope({
    required SearchScope scope,
    required List<AppFile> allFiles,
    required Future<List<String>> Function(String projectId) getProjectFolders,
    required Future<List<String>> Function(String collectionId)
        getCollectionFileIds,
    required Future<List<String>> Function() getSelectionFileIds,
  }) async {
    switch (scope.type) {
      case SearchScopeType.folder:
        return _resolveFolderFiles(
          folderPath: scope.folderPath,
          includeSubfolders: scope.includeSubfolders,
          allFiles: allFiles,
        );

      case SearchScopeType.project:
        final folders = await getProjectFolders(scope.projectId);
        return _resolveProjectFiles(
          folderPaths: folders,
          includeSubfolders: scope.includeSubfolders,
          allFiles: allFiles,
        );

      case SearchScopeType.collection:
        final fileIds = await getCollectionFileIds(scope.collectionId);
        return _resolveCollectionFiles(
          fileIds: fileIds,
          allFiles: allFiles,
        );

      case SearchScopeType.selection:
        final fileIds = await getSelectionFileIds();
        return _resolveCollectionFiles(
          fileIds: fileIds,
          allFiles: allFiles,
        );

      case SearchScopeType.all:
        final seen = <String>{};
        final result = <AppFile>[];
        for (final file in allFiles) {
          if (seen.add(file.id)) {
            result.add(file);
          }
        }
        return result;
    }
  }

  /// Асинхронно фильтрует файлы с неблокирующей проверкой доступности на диске.
  ///
  /// Ограниченный параллелизм [concurrency] (по умолчанию 16) предотвращает
  /// исчерпание системных дескрипторов файлов и не блокирует основной UI поток Flutter.
  /// Проверка дисковой доступности выполняется только для файлов, прошедших
  /// строгие фильтры метаданных.
  Future<List<SearchResultItem>> filterFilesAsync({
    required List<AppFile> files,
    required SearchFilterCriteria criteria,
    FileAccessibilityProbe? fileExistsProbe,
    int concurrency = 16,
  }) async {
    final probe = fileExistsProbe ?? _defaultAsyncFileExists;
    final candidates = _filterByMetadata(files, criteria);

    if (candidates.isEmpty) return const [];

    final pool = Pool(concurrency);
    try {
      final checked = await Future.wait(
        candidates.map((file) async {
          final isAccessible =
              await pool.withResource(() async => await probe(file.path));
          return (file: file, isAccessible: isAccessible);
        }),
      );

      final results = <SearchResultItem>[];
      for (final item in checked) {
        if (criteria.isAccessible != null &&
            item.isAccessible != criteria.isAccessible) {
          continue;
        }
        results.add(
          SearchResultItem(
            file: item.file,
            isAccessible: item.isAccessible,
          ),
        );
      }
      return results;
    } finally {
      pool.close();
    }
  }

  /// Синхронный метод фильтрации для простых юнит-тестов движка.
  List<SearchResultItem> filterFiles({
    required List<AppFile> files,
    required SearchFilterCriteria criteria,
    bool Function(String path)? fileExistsProbe,
  }) {
    final probe = fileExistsProbe ?? _defaultSyncFileExists;
    final candidates = _filterByMetadata(files, criteria);

    final results = <SearchResultItem>[];
    for (final file in candidates) {
      final isAccessible = probe(file.path);
      if (criteria.isAccessible != null &&
          isAccessible != criteria.isAccessible) {
        continue;
      }
      results.add(
        SearchResultItem(
          file: file,
          isAccessible: isAccessible,
        ),
      );
    }
    return results;
  }

  // ─── Вспомогательная фильтрация метаданных в памяти ──────────────────────────

  List<AppFile> _filterByMetadata(
    List<AppFile> files,
    SearchFilterCriteria criteria,
  ) {
    final trimmedQuery = criteria.query.trim().toLowerCase();
    final hasQuery = trimmedQuery.isNotEmpty;
    final results = <AppFile>[];

    for (final file in files) {
      // 1. Поиск по строке (имя, название, описание, ключи)
      if (hasQuery) {
        final matchesFilename =
            file.filename.toLowerCase().contains(trimmedQuery);
        final matchesTitle =
            (file.metadataTitle ?? '').toLowerCase().contains(trimmedQuery);
        final matchesDesc = (file.metadataDescription ?? '')
            .toLowerCase()
            .contains(trimmedQuery);
        final matchesKeywords = (file.metadataKeywords ?? '')
            .toLowerCase()
            .contains(trimmedQuery);

        if (!matchesFilename &&
            !matchesTitle &&
            !matchesDesc &&
            !matchesKeywords) {
          continue;
        }
      }

      // 2. Статус workflow
      if (criteria.workflowStatuses != null &&
          criteria.workflowStatuses!.isNotEmpty) {
        if (!criteria.workflowStatuses!.contains(file.workflowStatus)) {
          continue;
        }
      }

      // 3. Наличие ключевых слов («Без ключей»)
      if (criteria.hasKeywords != null) {
        final hasKw = file.metadataKeywords != null &&
            file.metadataKeywords!.trim().isNotEmpty;
        if (hasKw != criteria.hasKeywords) {
          continue;
        }
      }

      // 4. Наличие названия
      if (criteria.hasTitle != null) {
        final hasT = file.metadataTitle != null &&
            file.metadataTitle!.trim().isNotEmpty;
        if (hasT != criteria.hasTitle) {
          continue;
        }
      }

      // 5. Наличие описания
      if (criteria.hasDescription != null) {
        final hasD = file.metadataDescription != null &&
            file.metadataDescription!.trim().isNotEmpty;
        if (hasD != criteria.hasDescription) {
          continue;
        }
      }

      // 6. Редакционный статус (Editorial)
      if (criteria.isEditorial != null) {
        final isEd = file.isEditorial || file.hasEditorialTag;
        if (isEd != criteria.isEditorial) {
          continue;
        }
      }

      // 7. Сгенерировано AI
      if (criteria.isAiGenerated != null) {
        final isAi = file.isAiGenerated;
        if (isAi != criteria.isAiGenerated) {
          continue;
        }
      }

      // 8. Категория медиафайла по расширению
      if (criteria.mediaCategory != null) {
        final ext = p.extension(file.path);
        if (!criteria.mediaCategory!.matchesExtension(ext)) {
          continue;
        }
      }

      results.add(file);
    }

    return results;
  }

  // ─── Вспомогательные методы разрешения источников ───────────────────────────

  List<AppFile> _resolveFolderFiles({
    required String folderPath,
    required bool includeSubfolders,
    required List<AppFile> allFiles,
  }) {
    if (folderPath.isEmpty) return const [];
    final canonicalFolder = p.canonicalize(folderPath);

    final seen = <String>{};
    final result = <AppFile>[];

    for (final file in allFiles) {
      if (_isFileInFolder(
        filePath: file.path,
        canonicalFolder: canonicalFolder,
        includeSubfolders: includeSubfolders,
      )) {
        if (seen.add(file.id)) {
          result.add(file);
        }
      }
    }

    return result;
  }

  List<AppFile> _resolveProjectFiles({
    required List<String> folderPaths,
    required bool includeSubfolders,
    required List<AppFile> allFiles,
  }) {
    if (folderPaths.isEmpty) return const [];
    final canonicalRoots = folderPaths.map(p.canonicalize).toList();

    final seen = <String>{};
    final result = <AppFile>[];

    for (final file in allFiles) {
      for (final root in canonicalRoots) {
        if (_isFileInFolder(
          filePath: file.path,
          canonicalFolder: root,
          includeSubfolders: includeSubfolders,
        )) {
          if (seen.add(file.id)) {
            result.add(file);
          }
          break;
        }
      }
    }

    return result;
  }

  List<AppFile> _resolveCollectionFiles({
    required List<String> fileIds,
    required List<AppFile> allFiles,
  }) {
    if (fileIds.isEmpty) return const [];

    final fileMap = <String, AppFile>{};
    for (final file in allFiles) {
      fileMap[file.id] = file;
    }

    final result = <AppFile>[];
    for (final id in fileIds) {
      final file = fileMap[id];
      if (file != null) {
        result.add(file);
      }
    }

    return result;
  }

  bool _isFileInFolder({
    required String filePath,
    required String canonicalFolder,
    required bool includeSubfolders,
  }) {
    final fileCanonical = p.canonicalize(filePath);
    final fileDir = p.canonicalize(p.dirname(filePath));

    if (!includeSubfolders) {
      return p.equals(fileDir, canonicalFolder);
    } else {
      return p.equals(fileDir, canonicalFolder) ||
          p.isWithin(canonicalFolder, fileCanonical);
    }
  }

  static bool _defaultSyncFileExists(String path) {
    return File(path).existsSync();
  }

  static Future<bool> _defaultAsyncFileExists(String path) {
    return File(path).exists();
  }
}
