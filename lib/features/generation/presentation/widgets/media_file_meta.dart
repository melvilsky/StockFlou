import 'dart:io';
import 'dart:ui' as ui;

import '../../../../core/constants/app_constants.dart';

/// Дешёвые метаданные медиафайла: размер на диске и разрешение изображения.
///
/// Разрешение читается из заголовка файла (`ImageDescriptor.encoded`), поэтому
/// полное декодирование пикселей не выполняется. Для видео разрешение не
/// определяется — это ненадёжно без отдельного ffprobe-подобного шага.
class MediaFileMeta {
  final int? bytes;
  final int? width;
  final int? height;

  const MediaFileMeta({this.bytes, this.width, this.height});

  bool get hasDimensions => width != null && height != null;
}

/// Кэш метаданных в памяти по пути файла.
///
/// Сетка перестраивается часто, и читать длину/заголовок каждого файла на
/// каждый rebuild нельзя. Кэшируются и ошибки: недоступный или битый файл
/// возвращает пустой [MediaFileMeta], исключения наружу не выходят.
class MediaMetaCache {
  static final Map<String, Future<MediaFileMeta>> _cache = {};

  static Future<MediaFileMeta> load(String path) {
    return _cache.putIfAbsent(path, () => _load(path));
  }

  static Future<MediaFileMeta> _load(String path) async {
    int? bytes;
    try {
      bytes = await File(path).length();
    } catch (_) {
      bytes = null;
    }

    if (!AppConstants.isImage(path)) {
      return MediaFileMeta(bytes: bytes);
    }

    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromFilePath(path);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      return MediaFileMeta(
        bytes: bytes,
        width: descriptor.width,
        height: descriptor.height,
      );
    } catch (_) {
      return MediaFileMeta(bytes: bytes);
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}

/// Компактный размер файла, например `7,8 МБ`. `null` — размер неизвестен.
String? formatMediaBytes(int? bytes) {
  if (bytes == null || bytes < 0) return null;
  if (bytes < 1024) return '$bytes Б';

  const units = ['КБ', 'МБ', 'ГБ', 'ТБ'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 ? 0 : 1;
  final text = value
      .toStringAsFixed(digits)
      .replaceAll('.', ',')
      .replaceAll(RegExp(r',0+$'), '');
  return '$text ${units[unit]}';
}

/// Разрешение вида `6000 × 4000`. `null` — разрешение неизвестно.
String? formatMediaDimensions(MediaFileMeta? meta) {
  if (meta == null || !meta.hasDimensions) return null;
  return '${meta.width} × ${meta.height}';
}
