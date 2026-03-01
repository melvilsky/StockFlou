import 'package:flutter/material.dart';

/// Область, реагирующая на один клик через [Listener].
/// Обходит проблемы с распознаванием жеста на macOS (одиночный клик не срабатывает).
class SingleClickArea extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;

  const SingleClickArea({super.key, required this.child, this.onTap});

  @override
  State<SingleClickArea> createState() => _SingleClickAreaState();
}

class _SingleClickAreaState extends State<SingleClickArea> {
  Offset? _downPosition;
  int? _downPointer;
  DateTime? _downTime;

  static const int _maxTapDurationMs = 400;
  static const double _maxTapSlop = 20;

  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons != 1) return; // только левая кнопка
    _downPosition = event.position;
    _downPointer = event.pointer;
    _downTime = DateTime.now();
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_downPosition == null ||
        _downPointer != event.pointer ||
        widget.onTap == null) {
      _downPosition = null;
      _downPointer = null;
      _downTime = null;
      return;
    }
    final duration = DateTime.now().difference(_downTime!).inMilliseconds;
    final distance = (event.position - _downPosition!).distance;
    _downPosition = null;
    _downPointer = null;
    _downTime = null;
    if (duration <= _maxTapDurationMs && distance <= _maxTapSlop) {
      widget.onTap!();
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_downPointer == event.pointer) {
      _downPosition = null;
      _downPointer = null;
      _downTime = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: widget.child,
    );
  }
}
