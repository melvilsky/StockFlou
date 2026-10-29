import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Creates a player controller for the given file path.
///
/// Tests substitute it to control initialization without a real decoder.
typedef VideoControllerFactory =
    VideoPlayerController Function(String videoPath);

VideoPlayerController _defaultControllerFactory(String videoPath) =>
    VideoPlayerController.file(File(videoPath));

/// Visible states of the preview.
enum _PreviewState { loading, ready, error }

class VideoPlayerWidget extends StatefulWidget {
  final String videoPath;
  final bool hasAudio;

  /// Creates the controller for [videoPath]. Tests pass their own factory.
  final VideoControllerFactory controllerFactory;

  const VideoPlayerWidget({
    super.key,
    required this.videoPath,
    this.hasAudio = false,
    this.controllerFactory = _defaultControllerFactory,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  /// A single attempt may not stay in the loading state longer than this.
  static const Duration _initTimeout = Duration(seconds: 30);

  /// Controller of the current attempt. Null when no attempt is running.
  VideoPlayerController? _controller;

  Timer? _initTimer;

  /// Number of the current attempt. Late answers of older attempts are ignored.
  int _attempt = 0;

  _PreviewState _state = _PreviewState.loading;

  @override
  void initState() {
    super.initState();
    _startAttempt();
  }

  @override
  void didUpdateWidget(VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoPath != widget.videoPath) {
      // The build of this frame follows immediately, so the state is changed
      // without setState.
      _startAttempt();
    }
  }

  /// Starts a new attempt for the current path and drops the previous one.
  void _startAttempt() {
    final int attempt = ++_attempt;
    _initTimer?.cancel();
    _initTimer = null;

    final VideoPlayerController? previous = _controller;
    _controller = null;
    if (previous != null) {
      _release(previous);
    }

    _state = _PreviewState.loading;

    final VideoPlayerController controller = widget.controllerFactory(
      widget.videoPath,
    );
    _controller = controller;
    controller.addListener(_onControllerChanged);
    _initTimer = Timer(_initTimeout, () => _fail(attempt, controller));
    _initialize(attempt, controller);
  }

  Future<void> _initialize(
    int attempt,
    VideoPlayerController controller,
  ) async {
    try {
      await controller.initialize();
    } catch (_) {
      _fail(attempt, controller);
      return;
    }
    if (!_isCurrent(attempt, controller)) {
      return;
    }
    _initTimer?.cancel();
    _initTimer = null;
    setState(() => _state = _PreviewState.ready);
  }

  /// Shows the error state for the given attempt and releases its controller.
  void _fail(int attempt, VideoPlayerController controller) {
    if (!_isCurrent(attempt, controller)) {
      return;
    }
    _initTimer?.cancel();
    _initTimer = null;

    final VideoPlayerController? previous = _controller;
    _controller = null;
    setState(() => _state = _PreviewState.error);
    if (previous != null) {
      _release(previous);
    }
  }

  /// Reports an error announced by the controller itself.
  void _onControllerChanged() {
    final VideoPlayerController? controller = _controller;
    if (controller == null) {
      return;
    }
    if (controller.value.hasError) {
      _fail(_attempt, controller);
    }
  }

  /// True while the given attempt still owns the preview.
  bool _isCurrent(int attempt, VideoPlayerController controller) =>
      mounted && attempt == _attempt && identical(controller, _controller);

  /// Stops the given controller and releases it once its widgets are gone.
  void _release(VideoPlayerController controller) {
    controller.removeListener(_onControllerChanged);
    // The previous video must not keep playing while the new one is loading.
    unawaited(controller.pause());
    // The controller is disposed after the frame in which the widgets using it
    // are unmounted: they must not call methods of a disposed controller.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  }

  void _retry() {
    if (_state == _PreviewState.loading) {
      return;
    }
    setState(_startAttempt);
  }

  @override
  void dispose() {
    _initTimer?.cancel();
    _initTimer = null;
    final VideoPlayerController? controller = _controller;
    _controller = null;
    if (controller != null) {
      controller.removeListener(_onControllerChanged);
      unawaited(controller.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? controller = _controller;
    if (_state == _PreviewState.error) {
      return _buildError(context);
    }
    if (_state != _PreviewState.ready || controller == null) {
      return _buildLoading(context);
    }

    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          VideoPlayer(controller),

          // Audio icon
          if (widget.hasAudio)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(
                  Icons.volume_up,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            )
          else
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(
                  Icons.volume_off,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),

          // Controls wrapper
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _PlaybackControls(controller: controller),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.outlineVariant,
      child: const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildError(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.outlineVariant,
      child: Center(
        // The panel can be narrow, so the content scrolls instead of
        // overflowing.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 28,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 8),
              Text(
                'Не удалось открыть видео',
                style: theme.textTheme.titleSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Файл может быть недоступен или его формат не поддерживается',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Повторить'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaybackControls extends StatefulWidget {
  final VideoPlayerController controller;

  const _PlaybackControls({required this.controller});

  @override
  State<_PlaybackControls> createState() => _PlaybackControlsState();
}

class _PlaybackControlsState extends State<_PlaybackControls> {
  bool _isHovering = false;

  void _listener() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_listener);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_listener);
    super.dispose();
  }

  @override
  void didUpdateWidget(_PlaybackControls old) {
    if (old.controller != widget.controller) {
      old.controller.removeListener(_listener);
      widget.controller.addListener(_listener);
    }
    super.didUpdateWidget(old);
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = widget.controller.value.isPlaying;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: AnimatedOpacity(
        opacity: _isHovering || !isPlaying ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          color: Colors.black26,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!isPlaying)
                Expanded(
                  child: Center(
                    child: IconButton(
                      iconSize: 48,
                      color: Colors.white,
                      icon: const Icon(Icons.play_circle_fill),
                      onPressed: () => widget.controller.play(),
                    ),
                  ),
                )
              else
                Expanded(
                  child: Center(
                    child: IconButton(
                      iconSize: 48,
                      color: Colors.white.withAlpha(150),
                      icon: const Icon(Icons.pause_circle_filled),
                      onPressed: () => widget.controller.pause(),
                    ),
                  ),
                ),

              // Timeline bar
              VideoProgressIndicator(
                widget.controller,
                allowScrubbing: true,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                colors: VideoProgressColors(
                  playedColor: Theme.of(context).colorScheme.primary,
                  bufferedColor: Colors.white30,
                  backgroundColor: Colors.white30,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
