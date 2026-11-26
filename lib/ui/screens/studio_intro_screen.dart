import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/asset_catalog.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/app_providers.dart';
import '../../services/audio_service.dart';

/// Screen 0 — EyesWatching Games boot sequence.
///
/// Pure black, logo fade-in with a 1.0 → 1.03 slow zoom, held for ~1.5s while
/// Firebase, the local mirror and the episode scripts finish loading, then a
/// 0.8s fade directly into the auth screen. Tap anywhere after one second to
/// fast-forward.
class StudioIntroScreen extends ConsumerStatefulWidget {
  const StudioIntroScreen({
    required this.onFinished,
    this.firebaseReady = true,
    super.key,
  });

  final VoidCallback onFinished;
  final bool firebaseReady;

  @override
  ConsumerState<StudioIntroScreen> createState() => _StudioIntroScreenState();
}

class _StudioIntroScreenState extends ConsumerState<StudioIntroScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fadeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  late final AnimationController _zoomController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  );

  bool _allowSkip = false;
  bool _outroStarted = false;

  @override
  void initState() {
    super.initState();
    _fadeController.forward();
    _zoomController.forward();
    _playBootAudio();

    Future<void>.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(() => _allowSkip = true);
    });

    _driveSequence();
  }

  void _playBootAudio() {
    final AudioService audio = ref.read(audioServiceProvider);
    // Low sonar/ocean pulse: reuse the ambient dread bed at low volume.
    audio.playMusic('bgm_ambient_dread.mp3', loop: true, volume: 0.25);
  }

  Future<void> _driveSequence() async {
    // Hold the logo while the real boot work happens; never exceed 6s.
    final DateTime start = DateTime.now();
    while (mounted) {
      final BootState boot = ref.read(bootControllerProvider).value ??
          const BootState();
      final int elapsed = DateTime.now().difference(start).inMilliseconds;
      if (boot.isReady && elapsed >= 1500) break;
      if (elapsed >= 6000) break;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    await _finish();
  }

  Future<void> _finish() async {
    if (_outroStarted || !mounted) return;
    _outroStarted = true;
    await ref.read(audioServiceProvider).stopMusic(fadeOut: 0.8);
    await _fadeController.reverse().orCancel.catchError((Object _) {});
    if (mounted) widget.onFinished();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _zoomController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final BootState boot =
        ref.watch(bootControllerProvider).value ?? const BootState();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_allowSkip) _finish();
      },
      child: ColoredBox(
        color: AppColors.bootBlack,
        child: Stack(
          children: <Widget>[
            Center(
              child: AnimatedBuilder(
                animation: Listenable.merge(<Listenable>[_fadeController, _zoomController]),
                builder: (BuildContext context, Widget? child) {
                  final double zoom = 1.0 + 0.03 * Curves.easeOut.transform(_zoomController.value);
                  return Opacity(
                    opacity: _fadeController.value.clamp(0.0, 1.0),
                    child: Transform.scale(scale: zoom, child: child),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: ShaderMask(
                    shaderCallback: (Rect bounds) => RadialGradient(
                      colors: <Color>[
                        Colors.white,
                        Colors.white.withValues(alpha: 0.82),
                        Colors.white.withValues(alpha: 0.25),
                      ],
                      stops: const <double>[0.55, 0.82, 1],
                    ).createShader(bounds),
                    blendMode: BlendMode.dstIn,
                    child: Image.asset(
                      AssetCatalog.studioLogo,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),

            // Boot readout (bottom) — keeps the "silently initialising" feeling
            // honest about what is actually happening.
            Positioned(
              left: 24,
              right: 24,
              bottom: 44,
              child: AnimatedOpacity(
                opacity: _fadeController.value > 0.9 ? 1 : 0,
                duration: const Duration(milliseconds: 500),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(boot.status, style: AppTypography.monoCaption),
                    const SizedBox(height: 8),
                    Text(
                      widget.firebaseReady
                          ? '> CLOUD RELAY LINKED'
                          : '> OFFLINE MODE / LOCAL RELAY ONLY',
                      style: AppTypography.monoCaption.copyWith(
                        color: widget.firebaseReady
                            ? AppColors.accentTide.withValues(alpha: 0.7)
                            : AppColors.accentPremium.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (_allowSkip)
                      Text(
                        'TAP TO SKIP',
                        style: AppTypography.monoCaption.copyWith(
                          letterSpacing: 3,
                          color: AppColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
