import 'dart:io';
import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../models/generation_options.dart';

class ApiClient {
  static const String _baseUrl =
      'https://www.aistockkeywords.com/api/public/v1';
  final Dio _dio;

  ApiClient() : _dio = Dio(BaseOptions(baseUrl: _baseUrl));

  Future<Map<String, dynamic>> generateMetadata({
    required String apiKey,
    required String filePath,
    required GenerationOptions options,
  }) async {
    File file = File(filePath);
    String uploadPath = filePath;

    // Server-side limits are around 4.5MB (Vercel/serverless).
    // Most stock photos are much larger. Downscale for the AI.
    if (file.lengthSync() > 4 * 1024 * 1024) {
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image != null) {
        // Resize to max 1600px on the longest side
        img.Image resized;
        if (image.width > image.height) {
          resized = img.copyResize(image, width: 1600);
        } else {
          resized = img.copyResize(image, height: 1600);
        }

        final tempDir = await getTemporaryDirectory();
        final stockFlouTemp = Directory(p.join(tempDir.path, 'stockflou_temp'));
        if (!await stockFlouTemp.exists()) {
          await stockFlouTemp.create(recursive: true);
        }

        final tempPath = p.join(
          stockFlouTemp.path,
          'resized_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        final resizedBytes = img.encodeJpg(resized, quality: 85);
        await File(tempPath).writeAsBytes(resizedBytes);
        uploadPath = tempPath;
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
        '/generate-metadata',
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
