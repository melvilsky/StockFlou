import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

class WindowConfigService with WindowListener {
  static const String _keyWidth = 'window_width';
  static const String _keyHeight = 'window_height';
  static const String _keyX = 'window_x';
  static const String _keyY = 'window_y';

  static final double _defaultWidth = 1480;
  static final double _defaultHeight = 800;

  Future<void> init() async {
    windowManager.addListener(this);
  }

  void dispose() {
    windowManager.removeListener(this);
  }

  Future<WindowOptions> getStoredWindowOptions() async {
    final prefs = await SharedPreferences.getInstance();
    
    final width = prefs.getDouble(_keyWidth) ?? _defaultWidth;
    final height = prefs.getDouble(_keyHeight) ?? _defaultHeight;
    final x = prefs.getDouble(_keyX);
    final y = prefs.getDouble(_keyY);

    return WindowOptions(
      size: Size(width, height),
      minimumSize: const Size(900, 600),
      center: x == null || y == null, // Center if no position stored
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: const Color(0x00000000), // Colors.transparent not allowed here, using proper const
    );
  }
  
  Future<void> applyStoredPosition() async {
     final prefs = await SharedPreferences.getInstance();
     final x = prefs.getDouble(_keyX);
     final y = prefs.getDouble(_keyY);
     
     if (x != null && y != null) {
       await windowManager.setPosition(Offset(x, y));
     }
  }

  @override
  void onWindowResized() async {
    _saveDebounced();
  }

  @override
  void onWindowMoved() async {
    _saveDebounced();
  }

  bool _isSaving = false;
  
  void _saveDebounced() {
    if (_isSaving) return;
    _isSaving = true;
    Future.delayed(const Duration(milliseconds: 500), () async {
      _isSaving = false;
      await saveCurrentBounds();
    });
  }

  Future<void> saveCurrentBounds() async {
    try {
      final size = await windowManager.getSize();
      final position = await windowManager.getPosition();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyWidth, size.width);
      await prefs.setDouble(_keyHeight, size.height);
      await prefs.setDouble(_keyX, position.dx);
      await prefs.setDouble(_keyY, position.dy);
    } catch (e) {
      // Ignored during shutdown or startup errors
    }
  }
}
