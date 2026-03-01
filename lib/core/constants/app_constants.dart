import 'package:path/path.dart' as p;

enum NavigationTab { workspace, recent, uploads, analytics, settings }

class AppConstants {
  static const List<String> imageExtensions = ['.jpg', '.jpeg', '.png'];
  static const List<String> videoExtensions = [
    '.mp4',
    '.mov',
    '.avi',
    '.mkv',
    '.m4v',
  ];

  static bool isVideo(String path) {
    final ext = p.extension(path).toLowerCase();
    return videoExtensions.contains(ext);
  }

  static bool isImage(String path) {
    final ext = p.extension(path).toLowerCase();
    return imageExtensions.contains(ext);
  }
}
