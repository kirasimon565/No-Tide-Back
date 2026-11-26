import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../widgets/common_widgets.dart';

/// Full-screen pinch-to-zoom viewer for evidence art and file notes.
Future<void> showMediaViewer(
  BuildContext context, {
  required String imagePath,
  required String title,
  String? description,
  String? tag,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (BuildContext context, Animation<double> animation, Animation<double> secondary) =>
          _MediaViewerPage(
        imagePath: imagePath,
        title: title,
        description: description,
        tag: tag,
      ),
      transitionsBuilder: (BuildContext context, Animation<double> animation, Animation<double> secondary, Widget child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class _MediaViewerPage extends StatelessWidget {
  const _MediaViewerPage({
    required this.imagePath,
    required this.title,
    this.description,
    this.tag,
  });

  final String imagePath;
  final String title;
  final String? description;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: <Widget>[
                  if (tag != null) NtbTag(tag!, color: AppColors.accentTide, filled: true),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.textPrimary,
                  ),
                ],
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                child: Center(
                  child: Image.asset(
                    imagePath,
                    fit: BoxFit.contain,
                    errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
                        _MissingAsset(path: imagePath),
                  ),
                ),
              ),
            ),
            if (description != null || title.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[Colors.transparent, Color(0xEE070B0E)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title.toUpperCase(),
                      style: AppTypography.mono.copyWith(
                        fontSize: 13,
                        letterSpacing: 1.6,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (description != null && description!.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(description!, style: AppTypography.bodySmall.copyWith(height: 1.6)),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MissingAsset extends StatelessWidget {
  const _MissingAsset({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.accentCrimson.withValues(alpha: 0.4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.broken_image_outlined, color: AppColors.accentCrimson),
            const SizedBox(height: 10),
            Text(
              'MEDIA OFFLINE\n$path',
              textAlign: TextAlign.center,
              style: AppTypography.monoCaption,
            ),
          ],
        ),
      );
}

/// Inline video player for `@video` attachments (encrypted clips included).
class InlineVideoPlayer extends StatefulWidget {
  const InlineVideoPlayer({
    required this.assetPath,
    this.autoplay = false,
    super.key,
  });

  final String assetPath;
  final bool autoplay;

  @override
  State<InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<InlineVideoPlayer> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final VideoPlayerController controller =
          VideoPlayerController.asset(widget.assetPath);
      await controller.initialize();
      await controller.setLooping(false);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      if (widget.autoplay) await controller.play();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Container(
        height: 150,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text('VIDEO UNAVAILABLE', style: AppTypography.monoCaption),
      );
    }
    final VideoPlayerController? controller = _controller;
    if (controller == null) {
      return Container(
        height: 150,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio == 0
            ? 16 / 9
            : controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            VideoPlayer(controller),
            GestureDetector(
              onTap: () {
                setState(() {
                  controller.value.isPlaying ? controller.pause() : controller.play();
                });
              },
              child: AnimatedOpacity(
                opacity: controller.value.isPlaying ? 0 : 1,
                duration: const Duration(milliseconds: 180),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.bgVoid.withValues(alpha: 0.6),
                    border: Border.all(color: AppColors.accentTide),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: AppColors.accentTide,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Simple waveform player for `@audio` voice notes.
class AudioWaveformBubble extends StatefulWidget {
  const AudioWaveformBubble({
    required this.assetPath,
    required this.duration,
    this.caption,
    this.accent = AppColors.accentTide,
    super.key,
  });

  final String assetPath;
  final String duration;
  final String? caption;
  final Color accent;

  @override
  State<AudioWaveformBubble> createState() => _AudioWaveformBubbleState();
}

class _AudioWaveformBubbleState extends State<AudioWaveformBubble> {
  bool _playing = false;

  static const List<double> _bars = <double>[
    0.3, 0.6, 0.9, 0.5, 0.35, 0.75, 1.0, 0.55, 0.4, 0.7,
    0.85, 0.45, 0.3, 0.65, 0.95, 0.6, 0.42, 0.5, 0.8, 0.35,
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            InkWell(
              onTap: () => setState(() => _playing = !_playing),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.accent.withValues(alpha: 0.14),
                  border: Border.all(color: widget.accent.withValues(alpha: 0.5)),
                ),
                child: Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 18,
                  color: widget.accent,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 30,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    for (int i = 0; i < _bars.length; i++)
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          height: 6 + _bars[i] * 22,
                          decoration: BoxDecoration(
                            color: widget.accent.withValues(
                              alpha: _playing ? 0.85 : 0.4,
                            ),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(widget.duration, style: AppTypography.monoCaption),
          ],
        ),
        if (widget.caption != null && widget.caption!.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            widget.caption!,
            style: AppTypography.bodySmall.copyWith(fontSize: 12, height: 1.5),
          ),
        ],
      ],
    );
  }
}
