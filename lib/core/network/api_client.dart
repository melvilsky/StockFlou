import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';

import '../../models/generation_options.dart';

/// Выполняется в отдельном isolate, чтобы не блокировать UI.
Uint8List? _resizeImageInIsolate(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) return null;
  final resized = image.width > image.height
      ? img.copyResize(image, width: 1600)
      : img.copyResize(image, height: 1600);
  return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
}

class ApiClient {
  static const String _baseUrl =
      'https://www.aistockkeywords.com/api/public/v1/';
  final Dio _dio;
  final FcNativeVideoThumbnail _videoThumbnail = FcNativeVideoThumbnail();

  ApiClient() : _dio = Dio(BaseOptions(baseUrl: _baseUrl));

  bool _isVideo(String path) {
    final ext = p.extension(path).toLowerCase();
    return ['.mp4', '.mov', '.avi', '.mkv', '.m4v'].contains(ext);
  }

  Future<Map<String, dynamic>> generateMetadata({
    required String apiKey,
    required String filePath,
    required GenerationOptions options,
  }) async {
    File file = File(filePath);
    String uploadPath = filePath;

    final tempDir = await getTemporaryDirectory();
    final stockFlouTemp = Directory(p.join(tempDir.path, 'stockflou_temp'));
    if (!await stockFlouTemp.exists()) {
      await stockFlouTemp.create(recursive: true);
    }

    if (_isVideo(filePath)) {
      // Это видео: извлекаем кадр из середины
      final tempThumbPath = p.join(
        stockFlouTemp.path,
        'vid_thumb_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      final success = await _videoThumbnail.getVideoThumbnail(
        srcFile: filePath,
        destFile: tempThumbPath,
        width: 1600,
        height: 1600,
        format: 'jpeg',
        quality: 85,
        // Извлечь из середины не всегда возможно напрямую параметром позиции,
        // но плагин по умолчанию берет кадр, который может служить превью (например, из метаданных видео или первого кадра).
      );

      if (success == true && await File(tempThumbPath).exists()) {
        uploadPath = tempThumbPath;
      } else {
        throw Exception('Failed to generate thumbnail for video: $filePath');
      }
    } else {
      // Это картинка: Ресайз в отдельном isolate, чтобы не подвисал UI
      if (file.lengthSync() > 4 * 1024 * 1024) {
        final bytes = await file.readAsBytes();
        final resizedBytes = await compute(
          _resizeImageInIsolate,
          bytes,
          debugLabel: 'resizeImage',
        );
        if (resizedBytes != null && resizedBytes.isNotEmpty) {
          final tempPath = p.join(
            stockFlouTemp.path,
            'resized_${DateTime.now().millisecondsSinceEpoch}.jpg',
          );
          await File(tempPath).writeAsBytes(resizedBytes);
          uploadPath = tempPath;
        }
      }
    }

    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          uploadPath,
          filename: uploadPath.split(Platform.pathSeparator).last,
        ),
      });

      final queryParams = <String, dynamic>{
        'apiKey': apiKey,
        ...options.toMap(),
      };

      final response = await _dio.post(
        'generate-metadata',
        queryParameters: queryParams,
        data: formData,
      );

      return response.data;
    } on DioException catch (e) {
      if (e.response != null) {
        throw Exception(
          'API Error: ${e.response?.statusCode} - ${e.response?.data}',
        );
      } else {
        throw Exception('Network Error: ${e.message}');
      }
    } finally {
      // Clean up temp file if it was created
      if (uploadPath != filePath) {
        try {
          final tempFile = File(uploadPath);
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (e) {
          // Ignore deletion errors
        }
      }
    }
  }
}
