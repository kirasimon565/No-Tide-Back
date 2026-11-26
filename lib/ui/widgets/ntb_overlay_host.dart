import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/game_state_provider.dart';

/// App-level overlay host for directives that paint above every screen:
/// `@fade_out` / `@fade_in`, `@show_text` and `@camera effect="glitch"`.
class NtbOverlayHost extends ConsumerWidget {
  const NtbOverlayHost({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GameScreenState state = ref.watch(gameStateProvider);

    return Stack(
      children: <Widget>[
        Positioned.fill(child: child),
        if (state.cameraEffect != null)
          Positioned.fill(
            child: IgnorePointer(
              child: _GlitchOverlay(effect: state.cameraEffect!),
            ),
          ),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: state.fadeToBlack ? 1 : 0,
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeInOut,
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
        if (state.showTextBanner != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    state.showTextBanner!,
                    textAlign: TextAlign.center,
                    style: AppTypography.monoBase
                        .copyWith(fontSize: 22, letterSpacing: 5, height: 1.4)
                        .copyWith(
                          color: state.showTextBanner!.toUpperCase().contains('EPISODE 2')
                              ? AppColors.accentCrimson
                              : AppColors.textPrimary,
                        ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _GlitchOverlay extends StatefulWidget {
  const _GlitchOverlay({required this.effect});

  final String effect;

  @override
  State<_GlitchOverlay> createState() => _GlitchOverlayState();
}

class _GlitchOverlayState extends State<_GlitchOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool shake = widget.effect == 'shake';
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final double t = _controller.value;
        if (shake) {
          return Transform.translate(
            offset: Offset(
              (t - 0.5) * 14 * (t > 0.5 ? 1 : -1),
              (t - 0.5) * 8,
            ),
            child: const ColoredBox(color: Color(0x11EF4444)),
          );
        }
        return Stack(
          children: <Widget>[
            Positioned(
              top: 120 + t * 240,
              left: 0,
              right: 0,
              child: Container(
                height: 26,
                color: AppColors.accentTide.withValues(alpha: 0.14),
              ),
            ),
            Positioned(
              top: 420 - t * 160,
              left: 0,
              right: 0,
              child: Container(
                height: 10,
                color: AppColors.accentCrimson.withValues(alpha: 0.18),
              ),
            ),
            const ColoredBox(color: Color(0x0A22D3EE)),
          ],
        );
      },
    );
  }
}
