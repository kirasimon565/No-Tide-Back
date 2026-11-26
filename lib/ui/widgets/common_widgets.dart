import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Hairline rule used between list rows.
class NtbDivider extends StatelessWidget {
  const NtbDivider({this.indent = 0, super.key});

  final double indent;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(left: indent),
        child: const Divider(height: 1, thickness: 0.6, color: AppColors.divider),
      );
}

/// Monospace label chip (EPISODE 1, CONNECTED, MOST POPULAR...).
class NtbTag extends StatelessWidget {
  const NtbTag(
    this.label, {
    this.color = AppColors.accentTide,
    this.filled = false,
    this.icon,
    super.key,
  });

  final String label;
  final Color color;
  final bool filled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: filled ? 0.5 : 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: AppTypography.mono.copyWith(
              fontSize: 10,
              height: 1.1,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Static CRT scanlines over dark surfaces.
class ScanlineOverlay extends StatelessWidget {
  const ScanlineOverlay({this.opacity = 0.05, this.spacing = 3, super.key});

  final double opacity;
  final double spacing;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(
          painter: _ScanlinePainter(opacity: opacity, spacing: spacing),
          size: Size.infinite,
        ),
      );
}

class _ScanlinePainter extends CustomPainter {
  _ScanlinePainter({required this.opacity, required this.spacing});

  final double opacity;
  final double spacing;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..strokeWidth = 0.6;
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_ScanlinePainter oldDelegate) =>
      oldDelegate.opacity != opacity || oldDelegate.spacing != spacing;
}

/// Faint ocean swell behind the boot / splash screens.
class OceanBackdrop extends StatelessWidget {
  const OceanBackdrop({this.child, this.intensity = 1, super.key});

  final Widget? child;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const ColoredBox(color: AppColors.bgVoid),
        RepaintBoundary(
          child: CustomPaint(
            painter: _WavePainter(intensity: intensity),
            size: Size.infinite,
          ),
        ),
        ScanlineOverlay(opacity: 0.035 * intensity),
        if (child != null) child!,
      ],
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.intensity});

  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint glow = Paint()
      ..shader = const RadialGradient(
        colors: <Color>[Color(0x2222D3EE), Color(0x00070B0E)],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.5, size.height * 0.28),
          radius: size.width * 0.9,
        ),
      );
    canvas.drawRect(Offset.zero & size, glow);

    for (int i = 0; i < 5; i++) {
      final double y = size.height * (0.62 + i * 0.055);
      final Path path = Path()..moveTo(0, y);
      final double amp = (12 + i * 5) * intensity;
      for (double x = 0; x <= size.width; x += 8) {
        path.lineTo(
          x,
          y + math.sin((x / size.width) * math.pi * 3 + i) * amp,
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..color = AppColors.accentTide.withValues(
            alpha: 0.10 - i * 0.015,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) => false;
}

/// Small "double check" read receipt for player messages.
class ReadReceipt extends StatelessWidget {
  const ReadReceipt({this.color = AppColors.accentTide, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.done_all_rounded, size: 12, color: color.withValues(alpha: 0.85)),
        ],
      );
}

/// Rounded surface used by every card in the app.
class NtbCard extends StatelessWidget {
  const NtbCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = AppColors.surfaceCard,
    this.borderColor,
    this.onTap,
    this.radius = 16,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color? borderColor;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ?? AppColors.divider,
          width: borderColor == null ? 0.6 : 1,
        ),
      ),
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

/// Circle avatar built from a bundled character portrait.
class CharacterAvatar extends StatelessWidget {
  const CharacterAvatar({
    required this.assetPath,
    this.size = 46,
    this.label,
    this.accent = AppColors.accentTide,
    this.showStatus = false,
    this.isOnline = false,
    this.isGroup = false,
    super.key,
  });

  final String assetPath;
  final double size;
  final String? label;
  final Color accent;
  final bool showStatus;
  final bool isOnline;
  final bool isGroup;

  @override
  Widget build(BuildContext context) {
    final Widget core = assetPath.isEmpty || isGroup
        ? Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: <Color>[AppColors.bubbleOutgoing, AppColors.surfaceElevated],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: accent.withValues(alpha: 0.5)),
            ),
            child: Icon(
              isGroup ? Icons.hub_rounded : Icons.person_rounded,
              size: size * 0.48,
              color: accent,
            ),
          )
        : ClipOval(
            child: Image.asset(
              assetPath,
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: (size * 3).round(),
              errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
                  Container(
                width: size,
                height: size,
                color: AppColors.surfaceElevated,
                alignment: Alignment.center,
                child: Text(
                  _firstLetter(label ?? '?'),
                  style: AppTypography.label.copyWith(color: accent),
                ),
              ),
            ),
          );

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: <Widget>[
          core,
          if (showStatus)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: size * 0.26,
                height: size * 0.26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isOnline ? AppColors.accentSuccess : AppColors.textMuted,
                  border: Border.all(color: AppColors.surfacePhone, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Section heading with a monospace kicker.
class SectionHeading extends StatelessWidget {
  const SectionHeading({required this.kicker, required this.title, this.trailing, super.key});

  final String kicker;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(kicker, style: AppTypography.monoLabel),
              const SizedBox(height: 4),
              Text(title, style: AppTypography.sectionTitle),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// A glitchy loading bar with a percentage readout, used by the terminal.
class TerminalProgress extends StatelessWidget {
  const TerminalProgress({required this.value, this.label, this.color = AppColors.accentTide, super.key});

  final double value;
  final String? label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (label != null) ...<Widget>[
          Text(label!, style: AppTypography.monoCaption),
          const SizedBox(height: 6),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0).toDouble(),
            minHeight: 6,
            backgroundColor: AppColors.surfaceElevated,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

String _firstLetter(String value) {
  final String trimmed = value.trim();
  return trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
}
