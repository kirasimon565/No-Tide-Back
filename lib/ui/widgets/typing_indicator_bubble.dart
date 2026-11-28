import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Three-dot bubble shown while `@typing` is ticking down.
class TypingIndicatorBubble extends StatefulWidget {
  const TypingIndicatorBubble({
    required this.name,
    this.accent = AppColors.accentTide,
    super.key,
  });

  final String name;
  final Color accent;

  @override
  State<TypingIndicatorBubble> createState() => _TypingIndicatorBubbleState();
}

class _TypingIndicatorBubbleState extends State<TypingIndicatorBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6, right: 60),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.bubbleIncoming,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomRight: Radius.circular(14),
            bottomLeft: Radius.circular(4),
          ),
          border: Border.all(color: AppColors.divider, width: 0.6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '${widget.name} is typing',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11.5,
                fontStyle: FontStyle.italic,
                color: widget.accent,
              ),
            ),
            const SizedBox(width: 8),
            AnimatedBuilder(
              animation: _controller,
              builder: (BuildContext context, Widget? child) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List<Widget>.generate(3, (int index) {
                    final double phase =
                        ((_controller.value * 3) - index).clamp(0.0, 1.0).toDouble();
                    final double opacity =
                        0.25 + 0.75 * (1 - (phase - 0.5).abs() * 2).clamp(0.0, 1.0).toDouble();
                    return Container(
                      width: 4.6,
                      height: 4.6,
                      margin: const EdgeInsets.only(left: 2.6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.accent.withValues(alpha: opacity),
                      ),
                    );
                  }),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
