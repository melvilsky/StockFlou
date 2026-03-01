import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerWidget extends StatefulWidget {
  final String videoPath;
  final bool hasAudio;

  const VideoPlayerWidget({
    super.key,
    required this.videoPath,
    this.hasAudio = false,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _controller;
  bool _isInit = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  @override
  void didUpdateWidget(VideoPlayerWidget oldWidget) {
    if (oldWidget.videoPath != widget.videoPath) {
      _isInit = false;
      _initPlayer(oldController: _controller);
    }
    super.didUpdateWidget(oldWidget);
  }

  Future<void> _initPlayer({VideoPlayerController? oldController}) async {
    final newController = VideoPlayerController.file(File(widget.videoPath));
    _controller = newController;

    if (oldController != null) {
      await oldController.dispose();
    }

    try {
      await newController.initialize();
      if (mounted && _controller == newController) {
        setState(() {
          _isInit = true;
        });
      }
    } catch (_) {
      // ignore
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInit) {
      return Container(
        color: Theme.of(context).colorScheme.outlineVariant,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return AspectRatio(
      aspectRatio: _controller.value.aspectRatio,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          VideoPlayer(_controller),

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
            child: _PlaybackControls(controller: _controller),
          ),
        ],
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
