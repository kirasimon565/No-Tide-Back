import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// One title card of the "COMING SOON" stinger.
class StingerCard {
  const StingerCard({
    required this.text,
    required this.duration,
    this.isItalic = false,
    this.color,
  });

  final String text;

  /// Authored hold time (`@show_text duration=`), in seconds.
  final double duration;

  final bool isItalic;
  final Color? color;
}

/// The four cards from `episode_01_part_4.ntb` lines 498-501.
///
/// This is the fallback used when the interpreter did not deliver the cards
/// (for example when the player opens the hub from a completed save rather
/// than at the end of a live playthrough).
const List<StingerCard> defaultStingerCards = <StingerCard>[
  StingerCard(text: 'NO TIDE BACK', duration: 3),
  StingerCard(text: 'EPISODE 2: SIDE EFFECTS', duration: 3),
  StingerCard(text: 'IN DEVELOPMENT', duration: 3),
  StingerCard(
    text: 'hang in there until the next episode.',
    duration: 4,
    isItalic: true,
    color: AppColors.textSecondary,
  ),
];

/// Executes the end-of-episode stinger on a pure-black canvas.
///
/// Timeline (matches the script's directives):
///   `@autosave` / `@unlock_achievement` → achievement toast + cloud sync
///   `@fade_out duration="3"`            → 3 s fade to #000000
///   `@stop_music fade_out="2"`          → audio crossfade
///   `@music bgm_to_be_continued.mp3`
///   `@fade_in duration="2"`             → cards begin
///   `@show_text` × 4                    → one card each, authored hold time
///   `@fade_out duration="2"`            → out, then [onFinished]
class EpisodeStinger extends StatefulWidget {
  const EpisodeStinger({
    required this.cards,
    required this.onFinished,
    this.achievementTitle,
    this.achievementDescription,
    this.synced = false,
    this.showAchievementToast = true,
    this.fadeOutDuration = 3,
    this.cardsFadeInDuration = 2,
    this.finalFadeOutDuration = 2,
    super.key,
  });

  final List<StingerCard> cards;
  final VoidCallback onFinished;

  /// `@unlock_achievement title=` / `description=`.
  final String? achievementTitle;
  final String? achievementDescription;

  /// Drives the toast tick: flips to true once the cloud checkpoint commits.
  final bool synced;

  final bool showAchievementToast;

  /// `@fade_out duration=` before the cards.
  final double fadeOutDuration;

  /// `@fade_in duration=` before the first card.
  final double cardsFadeInDuration;

  /// `@fade_out duration=` after the last card.
  final double finalFadeOutDuration;

  @override
  State<EpisodeStinger> createState() => _EpisodeStingerState();
}

class _EpisodeStingerState extends State<EpisodeStinger>
    with TickerProviderStateMixin {
  /// Black veil: 0 = scene visible, 1 = pure black.
  late final AnimationController _veil = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (widget.fadeOutDuration * 1000).round()),
    value: 0,
  );

  /// Current card opacity.
  late final AnimationController _card = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
    value: 0,
  );

  int _index = -1;
  bool _closing = false;
  bool _done = false;
  bool _toastVisible = false;
  Timer? _timers;

  @override
  void initState() {
    super.initState();
    _run();
  }

  void _later(Duration duration, VoidCallback action) {
    _timers = Timer(duration, () {
      if (mounted) action();
    });
  }

  Future<void> _run() async {
    // @unlock_achievement toast slides in immediately, over the last scene.
    if (widget.showAchievementToast) {
      _later(const Duration(milliseconds: 250), () {
        setState(() => _toastVisible = true);
      });
    }

    // @fade_out duration="3"
    await _veil.animateTo(1, curve: Curves.easeInOut);
    if (!mounted) return;

    // @fade_in duration="2" — a short beat of black before the wordmark.
    await Future<void>.delayed(
      Duration(milliseconds: (widget.cardsFadeInDuration * 1000).round()),
    );
    if (!mounted) return;

    for (int i = 0; i < widget.cards.length; i++) {
      if (!mounted) return;
      setState(() => _index = i);
      await _card.animateTo(1, duration: const Duration(milliseconds: 700));
      if (!mounted) return;

      final StingerCard card = widget.cards[i];
      // Authored duration is the full hold, so the fade-out eats the tail.
      final double hold = math.max(card.duration - 0.7, 0.6);
      await Future<void>.delayed(Duration(milliseconds: (hold * 1000).round()));
      if (!mounted) return;

      await _card.animateTo(0, duration: const Duration(milliseconds: 600));
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    if (!mounted) return;

    // @fade_out duration="2" → hand over to the waiting hub.
    setState(() => _closing = true);
    await Future<void>.delayed(
      Duration(milliseconds: (widget.finalFadeOutDuration * 1000).round()),
    );
    if (!mounted || _done) return;
    _done = true;
    widget.onFinished();
  }

  @override
  void didUpdateWidget(covariant EpisodeStinger oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The save commit flipped to "synced" — no restart needed, the toast just
    // re-renders with its check mark.
  }

  @override
  void dispose() {
    _timers?.cancel();
    _veil.dispose();
    _card.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final StingerCard? card =
        (_index >= 0 && _index < widget.cards.length) ? widget.cards[_index] : null;

    return ColoredBox(
      color: AppColors.bootBlack,
      child: Stack(
        children: <Widget>[
          // Ocean mist drifting over the black.
          const Positioned.fill(
            child: _MistField(opacity: 0.22),
          ),

          if (card != null)
            Positioned.fill(
              child: Center(
                child: AnimatedBuilder(
                  animation: _card,
                  builder: (BuildContext context, Widget? child) {
                    return Opacity(
                      opacity: _card.value.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, (1 - _card.value) * 12),
                        child: child,
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 34),
                    child: _TitleCardView(card: card, isFirst: _index == 0),
                  ),
                ),
              ),
            ),

          // Achievement toast (@unlock_achievement), sliding from the top.
          if (widget.showAchievementToast && widget.achievementTitle != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: AnimatedSlide(
                  offset: _toastVisible ? Offset.zero : const Offset(0, -1.4),
                  duration: const Duration(milliseconds: 520),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: _toastVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 380),
                    child: _AchievementToast(
                      title: widget.achievementTitle!,
                      description: widget.achievementDescription ?? '',
                      synced: widget.synced,
                    ),
                  ),
                ),
              ),
            ),

          // Final fade to black before the hub takes over.
          if (_closing)
            const Positioned.fill(child: ColoredBox(color: AppColors.bootBlack)),

          // The authored "hold" veil: scene → black.
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _veil,
                builder: (BuildContext context, Widget? child) {
                  return ColoredBox(
                    color: AppColors.bootBlack.withValues(
                      alpha: _closing ? 1 : _veil.value.clamp(0.0, 1.0),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleCardView extends StatelessWidget {
  const _TitleCardView({required this.card, required this.isFirst});

  final StingerCard card;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    final bool isWordmark = isFirst;
    final Color color = card.color ?? AppColors.textPrimary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          card.text,
          textAlign: TextAlign.center,
          style: AppTypography.monoBase.copyWith(
            fontSize: isWordmark ? 30 : 19,
            height: 1.5,
            letterSpacing: isWordmark ? 7 : 4,
            fontWeight: isWordmark ? FontWeight.w700 : FontWeight.w500,
            fontStyle: card.isItalic ? FontStyle.italic : FontStyle.normal,
            color: color,
            shadows: card.isItalic
                ? <Shadow>[
                    // Faint tide glow behind the closing line.
                    Shadow(
                      color: AppColors.accentTide.withValues(alpha: 0.45),
                      blurRadius: 22,
                    ),
                  ]
                : null,
          ),
        ),
        if (isWordmark) ...<Widget>[
          const SizedBox(height: 18),
          Container(
            width: 54,
            height: 2,
            color: AppColors.accentCrimson.withValues(alpha: 0.75),
          ),
        ],
      ],
    );
  }
}

class _AchievementToast extends StatelessWidget {
  const _AchievementToast({
    required this.title,
    required this.description,
    required this.synced,
  });

  final String title;
  final String description;
  final bool synced;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.accentPremium.withValues(alpha: 0.45),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.accentPremium.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.emoji_events_rounded,
              size: 19,
              color: AppColors.accentPremium,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'ACHIEVEMENT UNLOCKED',
                  style: AppTypography.monoCaption.copyWith(
                    fontSize: 8.5,
                    letterSpacing: 1.6,
                    color: AppColors.accentPremium,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  title,
                  style: AppTypography.label.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (description.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: AppTypography.monoCaption.copyWith(
                      fontSize: 9,
                      height: 1.45,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            synced ? Icons.cloud_done_rounded : Icons.cloud_upload_rounded,
            size: 16,
            color: synced ? AppColors.accentSuccess : AppColors.textMuted,
          ),
        ],
      ),
    );
  }
}

/// Slow-drifting vertical mist / static, so pure black never looks dead.
class _MistField extends StatefulWidget {
  const _MistField({required this.opacity});

  final double opacity;

  @override
  State<_MistField> createState() => _MistFieldState();
}

class _MistFieldState extends State<_MistField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          return CustomPaint(
            painter: _MistPainter(
              progress: _controller.value,
              opacity: widget.opacity,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _MistPainter extends CustomPainter {
  _MistPainter({required this.progress, required this.opacity});

  final double progress;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final Paint paint = Paint()..blendMode = BlendMode.plus;

    for (int band = 0; band < 7; band++) {
      final double phase = progress * 2 * math.pi + band * 0.9;
      final double y = size.height * ((band / 7) + 0.04 * math.sin(phase));
      final double alpha =
          (0.035 + 0.03 * (0.5 + 0.5 * math.sin(phase * 1.7))) * opacity * 4;
      paint.color = AppColors.accentTide.withValues(alpha: alpha.clamp(0.0, 0.09));
      canvas.drawRect(
        Rect.fromLTWH(-20, y, size.width + 40, 1.2 + band * 0.25),
        paint,
      );
    }

    // A few drifting specks for the "static" read.
    for (int i = 0; i < 26; i++) {
      final double seed = i * 7.31;
      final double x = (size.width * ((seed % 97) / 97) +
              progress * size.width * 0.06) %
          size.width;
      final double y = size.height * (((seed * 3.7) % 100) / 100 + progress * 0.08) %
          size.height;
      paint.color = Colors.white.withValues(alpha: 0.05 * opacity * 3);
      canvas.drawCircle(Offset(x, y), 0.9, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MistPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.opacity != opacity;
}
