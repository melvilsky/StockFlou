import '../../../models/app_file.dart';

/// Элемент выдачи поиска и фильтрации.
///
/// Хранит ссылку на [AppFile] и подтвержденный статус доступности на диске.
/// Независим для файлов с одинаковыми именами, но разными [AppFile.id].
class SearchResultItem {
  const SearchResultItem({
    required this.file,
    this.isAccessible = true,
    this.sourcePath,
  });

  final AppFile file;

  /// true — файл физически обнаружен на диске по пути [file.path].
  /// false — источник недоступен (например, отключен съемный диск).
  /// Недоступность источника не удаляет файл из коллекции и не очищает её.
  final bool isAccessible;

  /// Путь папки или источника, из которого файл был разрешен (опционально).
  final String? sourcePath;

  String get id => file.id;
  String get filename => file.filename;
  String get path => file.path;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchResultItem &&
          runtimeType == other.runtimeType &&
          file.id == other.file.id &&
          isAccessible == other.isAccessible;

  @override
  int get hashCode => Object.hash(file.id, isAccessible);

  @override
  String toString() =>
      'SearchResultItem(id: ${file.id}, name: ${file.filename}, accessible: $isAccessible)';
}
