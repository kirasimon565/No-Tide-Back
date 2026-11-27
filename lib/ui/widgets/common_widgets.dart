import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// ---------------------------------------------------------------------------
/// SHARED SURFACES — the "slate terminal" language.
/// ---------------------------------------------------------------------------
/// Rules of the system, so every screen looks like the same product:
///   • Base canvas is slate #1E252B, never black.
///   • Panels are flat fills with a one-pixel steel border. No drop shadows,
///     no rounded 16px "app cards" — corner radii stay at 0–6px.
///   • Exactly one accent (cyan) is used for anything the player can touch.
///   • Labels are Michroma, uppercase, letter-spaced. Copy is Inter.
///   • Decoration is a hairline rule with a leading tick, not an icon soup.

/// One-pixel steel rule with a short leading tick — the system's divider.
class RuleLabel extends StatelessWidget {
  const RuleLabel(this.text, {this.trailing, this.color, this.padding, super.key});

  final String text;
  final Widget? trailing;
  final Color? color;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final Color tint = color ?? AppColors.textMuted;
    return Padding(
      padding: padding ?? const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          Container(width: 10, height: 1, color: tint.withValues(alpha: 0.7)),
          const SizedBox(width: 8),
          Text(
            text.toUpperCase(),
            style: AppTypography.labelDim.copyWith(color: tint),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(height: 1, color: AppColors.divider.withValues(alpha: 0.7)),
          ),
          if (trailing != null) ...<Widget>[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}

/// Flat bordered panel. The workhorse of the redesign.
class SlatePanel extends StatelessWidget {
  const SlatePanel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = AppColors.surfaceCard,
    this.borderColor,
    this.accentEdge = false,
    this.onTap,
    this.radius = 4,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color? borderColor;

  /// Draws a 2px cyan bar down the left edge (selected / active row).
  final bool accentEdge;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final BorderRadius shape = BorderRadius.circular(radius);
    // The accent edge is a Positioned bar, not a stretched Row: panels are used
    // inside lists, where the incoming height constraint is unbounded and a
    // `CrossAxisAlignment.stretch` Row would blow up at layout time.
    final Widget body = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: color,
        borderRadius: shape,
        border: Border.all(
          color: borderColor ?? AppColors.divider.withValues(alpha: 0.9),
          width: 0.7,
        ),
      ),
      child: Stack(
        children: <Widget>[
          Padding(padding: padding, child: child),
          if (accentEdge)
            const Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 2,
              child: ColoredBox(color: AppColors.accentTide),
            ),
        ],
      ),
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: shape, onTap: onTap, child: body),
    );
  }
}

/// Frosted-glass chrome used by headers and the bottom docks.
class GlassChrome extends StatelessWidget {
  const GlassChrome({
    required this.child,
    this.bottomBorder = true,
    this.topBorder = false,
    this.tint,
    super.key,
  });

  final Widget child;
  final bool bottomBorder;
  final bool topBorder;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.of(context).disableAnimations;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: reduceMotion ? 0 : 14,
          sigmaY: reduceMotion ? 0 : 14,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: (tint ?? AppColors.surfacePhone).withValues(alpha: 0.92),
            border: Border(
              bottom: bottomBorder
                  ? BorderSide(color: AppColors.divider.withValues(alpha: 0.8), width: 0.7)
                  : BorderSide.none,
              top: topBorder
                  ? BorderSide(color: AppColors.divider.withValues(alpha: 0.8), width: 0.7)
                  : BorderSide.none,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Standard screen header: 56px glass bar, leading accent tick, Michroma title,
/// optional trailing actions. Replaces every hand-rolled AppBar.
class ConsoleHeader extends StatelessWidget {
  const ConsoleHeader({
    required this.title,
    this.onBack,
    this.actions = const <Widget>[],
    this.showBack = true,
    this.subtitle,
    super.key,
  });

  final String title;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final bool showBack;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final double topPad = MediaQuery.of(context).padding.top;
    return GlassChrome(
      child: Padding(
        padding: EdgeInsets.only(top: topPad),
        child: SizedBox(
          height: 56,
          child: Row(
            children: <Widget>[
              if (showBack)
                _ChromeIcon(
                  icon: Icons.close_rounded,
                  onTap: onBack ?? () => Navigator.of(context).maybePop(),
                  tooltip: 'Close',
                )
              else
                const SizedBox(width: 14),
              const SizedBox(width: 2),
              Container(width: 2, height: 14, color: AppColors.accentTide),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.label.copyWith(
                        color: AppColors.textPrimary,
                        letterSpacing: 2.4,
                      ),
                    ),
                    if (subtitle != null) ...<Widget>[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelDim.copyWith(fontSize: 8),
                      ),
                    ],
                  ],
                ),
              ),
              ...actions,
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bare 40px icon button used inside [ConsoleHeader] and docks.
class _ChromeIcon extends StatelessWidget {
  const _ChromeIcon({required this.icon, required this.onTap, this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 18, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

/// Primary action: transparent plate, cyan hairline border, gradient wash from
/// the left, Michroma lettering. The Dreadmoor "CONFIRM IDENTITY" button.
class ConsoleButton extends StatefulWidget {
  const ConsoleButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.danger = false,
    this.height = 52,
    this.expand = true,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final bool danger;
  final double height;
  final bool expand;

  @override
  State<ConsoleButton> createState() => _ConsoleButtonState();
}

class _ConsoleButtonState extends State<ConsoleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onPressed != null && !widget.busy;
    final Color accent = widget.danger ? AppColors.accentCrimson : AppColors.accentTide;
    final double alpha = enabled ? 1 : 0.35;

    final Widget plate = AnimatedContainer(
      duration: const Duration(milliseconds: 110),
      height: widget.height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            accent.withValues(alpha: (_pressed ? 0.26 : 0.13) * alpha),
            Colors.transparent,
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        border: Border.all(color: accent.withValues(alpha: 0.55 * alpha), width: 0.8),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (widget.busy)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                valueColor: AlwaysStoppedAnimation<Color>(accent.withValues(alpha: alpha)),
              ),
            )
          else if (widget.icon != null)
            Icon(widget.icon, size: 16, color: accent.withValues(alpha: alpha)),
          if (widget.busy || widget.icon != null) const SizedBox(width: 12),
          Flexible(
            child: Text(
              widget.label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.button.copyWith(color: accent.withValues(alpha: alpha)),
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled
          ? (_) {
              setState(() => _pressed = false);
              widget.onPressed!.call();
            }
          : null,
      onTapCancel: () => setState(() => _pressed = false),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(width: widget.expand ? double.infinity : null, child: plate),
    );
  }
}

/// Secondary action: hairline-only plate.
class GhostButton extends StatelessWidget {
  const GhostButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 48,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          side: BorderSide(color: AppColors.divider.withValues(alpha: 0.9), width: 0.8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 15, color: AppColors.textSecondary),
              const SizedBox(width: 10),
            ],
            Flexible(
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.button.copyWith(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Status pill: bordered capsule, Michroma micro text, optional icon dot.
class StatusPill extends StatelessWidget {
  const StatusPill(
    this.label, {
    this.color = AppColors.accentTide,
    this.icon,
    this.filled = false,
    super.key,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.14) : Colors.transparent,
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.7),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 6),
          ],
          Text(
            label.toUpperCase(),
            style: AppTypography.labelDim.copyWith(
              fontSize: 8.5,
              color: color,
              letterSpacing: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kept for compatibility: the old `NtbTag` name is used across the chat and
/// store screens. Same visual language, crisp corners.
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
  Widget build(BuildContext context) =>
      StatusPill(label, color: color, icon: icon, filled: filled);
}

/// Kept for compatibility: `NtbCard` now maps onto [SlatePanel].
class NtbCard extends StatelessWidget {
  const NtbCard({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color = AppColors.surfaceCard,
    this.borderColor,
    this.onTap,
    this.radius = 4,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color? borderColor;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) => SlatePanel(
        padding: padding,
        color: color,
        borderColor: borderColor,
        onTap: onTap,
        radius: radius,
        child: child,
      );
}

/// One-pixel rule.
class HRule extends StatelessWidget {
  const HRule({this.padding = EdgeInsets.zero, super.key});
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Container(height: 1, color: AppColors.divider.withValues(alpha: 0.8)),
      );
}

/// Kept for compatibility with older screens.
class NtbDivider extends StatelessWidget {
  const NtbDivider({this.indent = 0, super.key});
  final double indent;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(left: indent),
        child: const HRule(),
      );
}

/// Ghosted ASCII texture for empty / dormant states. Pure canvas paint, so it
/// costs nothing and never needs an asset.
class SlateNoise extends StatelessWidget {
  const SlateNoise({this.opacity = 0.05, this.spacing = 4, super.key});

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
      ..color = Colors.black.withValues(alpha: opacity)
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_ScanlinePainter old) =>
      old.opacity != opacity || old.spacing != spacing;
}

/// Kept for compatibility: the old scanline overlay.
class ScanlineOverlay extends StatelessWidget {
  const ScanlineOverlay({this.opacity = 0.05, this.spacing = 3, super.key});

  final double opacity;
  final double spacing;

  @override
  Widget build(BuildContext context) =>
      SlateNoise(opacity: opacity, spacing: spacing);
}

/// Ambient backdrop: flat slate, a barely-there vignette, scanlines. The old
/// ocean-wave hero art is gone — the palette carries the mood, not decoration.
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
            painter: _VignettePainter(intensity: intensity),
            size: Size.infinite,
          ),
        ),
        SlateNoise(opacity: 0.035 * intensity),
        if (child != null) child!,
      ],
    );
  }
}

class _VignettePainter extends CustomPainter {
  _VignettePainter({required this.intensity});
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint glow = Paint()
      ..shader = RadialGradient(
        radius: 1.05,
        colors: <Color>[
          AppColors.accentTide.withValues(alpha: 0.05 * intensity),
          AppColors.slateBackground.withValues(alpha: 0.9),
        ],
        stops: const <double>[0.0, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, glow);
  }

  @override
  bool shouldRepaint(_VignettePainter old) => old.intensity != intensity;
}

/// Small "double check" read receipt for player messages.
class ReadReceipt extends StatelessWidget {
  const ReadReceipt({this.color = AppColors.accentTide, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) => Icon(
        Icons.done_all_rounded,
        size: 12,
        color: color.withValues(alpha: 0.85),
      );
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
              color: AppColors.surfaceElevated,
              border: Border.all(color: accent.withValues(alpha: 0.45), width: 0.8),
            ),
            child: Icon(
              isGroup ? Icons.groups_2_outlined : Icons.person_outline_rounded,
              size: size * 0.44,
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

/// Console section heading: cyan kicker over a ruled title.
class SectionHeading extends StatelessWidget {
  const SectionHeading({
    required this.kicker,
    required this.title,
    this.trailing,
    super.key,
  });

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
              Text(kicker.toUpperCase(), style: AppTypography.kicker),
              const SizedBox(height: 6),
              Text(title, style: AppTypography.title.copyWith(fontSize: 24)),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Terminal-style progress readout.
class TerminalProgress extends StatelessWidget {
  const TerminalProgress({
    required this.value,
    this.label,
    this.color = AppColors.accentTide,
    super.key,
  });

  final double value;
  final String? label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (label != null) ...<Widget>[
          Text(label!.toUpperCase(), style: AppTypography.labelDim),
          const SizedBox(height: 8),
        ],
        Container(
          height: 2,
          color: AppColors.divider,
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value.clamp(0.0, 1.0),
            child: ColoredBox(color: color),
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
