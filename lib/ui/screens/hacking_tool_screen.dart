import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/asset_catalog.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_store_provider.dart';
import '../../providers/game_state_provider.dart';
import '../widgets/common_widgets.dart';
import '../widgets/media_viewer_overlay.dart';
import '../widgets/store_modal_sheet.dart';

/// Screen 6 — Hacking & Decryption Tool.
///
/// Launched either by `@custom action="launch_hacking_tool"` (script pause) or
/// by tapping an encrypted attachment. The signal-alignment puzzle scales with
/// the script's `difficulty`, and the auto-bypass button follows the two-way
/// unlock rule (free with the Multimedia Package, otherwise coins).
class HackingToolScreen extends ConsumerStatefulWidget {
  const HackingToolScreen({
    required this.puzzleId,
    required this.difficulty,
    required this.targetFile,
    this.manual = false,
    super.key,
  });

  final String puzzleId;
  final String difficulty;
  final String targetFile;

  /// Manual runs (from the inbox dock) never resume the script.
  final bool manual;

  @override
  ConsumerState<HackingToolScreen> createState() => _HackingToolScreenState();
}

class _HackingToolScreenState extends ConsumerState<HackingToolScreen> {
  final List<String> _log = <String>[];
  final Random _random = math.Random();

  int _nodes = 6;
  int _matched = 0;
  int _secondsLeft = 45;
  Timer? _timer;
  bool _finished = false;
  bool _succeeded = false;
  double _progress = 0;

  // The alignment target and the player's current offset (0..100).
  double _target = 50;
  double _offset = 0;

  @override
  void initState() {
    super.initState();
    _configureForDifficulty();
    _seedLog();
    _startTimer();
  }

  void _configureForDifficulty() {
    switch (widget.difficulty.toLowerCase()) {
      case 'hard':
        _nodes = 10;
        _secondsLeft = 35;
        break;
      case 'medium':
        _nodes = 8;
        _secondsLeft = 40;
        break;
      default:
        _nodes = 6;
        _secondsLeft = 45;
    }
    _target = 20 + _random.nextDouble() * 60;
    _offset = _random.nextDouble() * 100;
  }

  void _seedLog() {
    _log.addAll(<String>[
      '> target aquired: ${widget.targetFile.isEmpty ? 'unknown.bin' : widget.targetFile}',
      '> jammer interference: ${70 + _random.nextInt(20)}%',
      '> loading frame 01 of 04...',
      '> frame 02 is toast. frame 03 looks fixable.',
      '> align the relay to the carrier frequency to rebuild pixels.',
    ]);
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted || _finished) return;
      setState(() {
        _secondsLeft--;
        if (_secondsLeft <= 0) {
          _finish(success: false);
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _finish({required bool success, bool bypass = false}) {
    if (_finished) return;
    setState(() {
      _finished = true;
      _succeeded = success;
    });
    _timer?.cancel();

    if (success) {
      ref.read(audioServiceProvider).playSfx('hack_success.mp3');
      ref.read(hapticsServiceProvider).vibrate('double');
    } else {
      ref.read(audioServiceProvider).playSfx('hack_fail.mp3');
      ref.read(hapticsServiceProvider).vibrate('error');
    }

    if (!widget.manual) {
      ref.read(gameStateProvider.notifier).resolvePuzzle(success ? 'success' : 'fail');
    }

    if (mounted) {
      Future<void>.delayed(const Duration(milliseconds: 650), () {
        if (!mounted) return;
        Navigator.of(context).pop();
      });
    }
  }

  void _tryMatch() {
    if (_finished) return;
    final double delta = (_offset - _target).abs();
    if (delta <= 6) {
      setState(() {
        _matched++;
        _progress = _matched / _nodes;
        _target = 10 + _random.nextDouble() * 80;
        if (_matched >= _nodes) {
          _finish(success: true);
        }
      });
    } else {
      setState(() {
        _matched = math.max(0, _matched - 1);
        _progress = _matched / _nodes;
        _secondsLeft = math.max(1, _secondsLeft - 2);
        _log.add('> misalignment. signal drift -2s.');
      });
    }
  }

  Future<void> _autoBypass() async {
    final PlayerEconomyState economy = ref.read(economyProvider);
    if (economy.multimediaUnlocked) {
      _finish(success: true, bypass: true);
      return;
    }
    final bool spent =
        await ref.read(economyProvider.notifier).unlockPremiumAction(10);
    if (!mounted) return;
    if (spent) {
      _finish(success: true, bypass: true);
      return;
    }
    await showStoreModalSheet(context, missingCoins: 10);
    if (!mounted) return;
    final PlayerEconomyState after = ref.read(economyProvider);
    if (after.multimediaUnlocked || after.coins >= 10) {
      final bool retry =
          await ref.read(economyProvider.notifier).unlockPremiumAction(10);
      if (retry && mounted) _finish(success: true, bypass: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final PlayerEconomyState economy = ref.watch(economyProvider);

    return Scaffold(
      backgroundColor: AppColors.bgVoid,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Image.asset(
              AssetCatalog.hackingBackground,
              fit: BoxFit.cover,
              opacity: const AlwaysStoppedAnimation<double>(0.22),
              errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                  const ColoredBox(color: AppColors.bgVoid),
            ),
          ),
          const Positioned.fill(child: ScanlineOverlay(opacity: 0.06)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text('DECRYPTION TOOL', style: AppTypography.monoLabel),
                      const Spacer(),
                      NtbTag(
                        '${widget.difficulty.toUpperCase()} • $_secondsLeft S',
                        color: _secondsLeft <= 10
                            ? AppColors.accentCrimson
                            : AppColors.accentTide,
                        filled: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    widget.targetFile.isEmpty ? 'UNKNOWN FILE' : widget.targetFile,
                    style: AppTypography.mono.copyWith(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TerminalProgress(
                    value: _progress,
                    label: 'FRAME RECONSTRUCTION  ${(_progress * 100).round()}%',
                    color: _succeeded ? AppColors.accentSuccess : AppColors.accentTide,
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: _TerminalLog(lines: _log),
                  ),
                  const SizedBox(height: 14),
                  if (!_finished) ...<Widget>[
                    Text('RELAY ALIGNMENT', style: AppTypography.monoLabel),
                    const SizedBox(height: 8),
                    _AlignmentGrid(
                      nodes: _nodes,
                      matched: _matched,
                      offset: _offset,
                      target: _target,
                      onChanged: (double value) => setState(() => _offset = value),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _tryMatch,
                        icon: const Icon(Icons.bolt_rounded, size: 18),
                        label: const Text('LOCK FREQUENCY'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _autoBypass,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.accentPremium,
                          side: BorderSide(
                            color: AppColors.accentPremium.withValues(alpha: 0.5),
                          ),
                        ),
                        icon: Icon(
                          economy.multimediaUnlocked
                              ? Icons.star_rounded
                              : Icons.monetization_on_outlined,
                          size: 17,
                        ),
                        label: Text(
                          economy.multimediaUnlocked
                              ? 'FREE WITH MULTIMEDIA PACK'
                              : '🪙 10 COINS — AUTO-DECRYPT',
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () => _finish(success: false),
                      child: Text(
                        'ABORT / RETURN',
                        style: AppTypography.monoCaption.copyWith(
                          letterSpacing: 2,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ] else
                    _ResultPanel(
                      success: _succeeded,
                      onReveal: _succeeded
                          ? () => showMediaViewer(
                                context,
                                imagePath: 'assets/images/evidence/img_hack1_decrypted_frame.jpg',
                                title: 'Decrypted frame 03/04',
                                description:
                                    'Night vision frame: biohazard crate, someone strapped '
                                    'to a gurney, and a woman in a black jacket at the keypad.',
                                tag: 'EVIDENCE',
                              )
                          : null,
                      onReturn: () => Navigator.of(context).pop(),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TerminalLog extends StatelessWidget {
  const _TerminalLog({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bootBlack.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accentTide.withValues(alpha: 0.22)),
      ),
      child: ListView.builder(
        reverse: true,
        itemCount: lines.length,
        itemBuilder: (BuildContext context, int index) {
          final String line = lines[lines.length - 1 - index];
          final bool warning = line.contains('⚠') || line.contains('misalignment');
          return Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              line,
              style: AppTypography.monoBody.copyWith(
                fontSize: 11,
                color: warning ? AppColors.accentCrimson : AppColors.textSecondary,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AlignmentGrid extends StatelessWidget {
  const _AlignmentGrid({
    required this.nodes,
    required this.matched,
    required this.offset,
    required this.target,
    required this.onChanged,
  });

  final int nodes;
  final int matched;
  final double offset;
  final double target;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final double delta = (offset - target).abs();
    final bool aligned = delta <= 6;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: BoxDecoration(
        color: AppColors.bootBlack.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: aligned
              ? AppColors.accentSuccess.withValues(alpha: 0.6)
              : AppColors.accentTide.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(nodes, (int index) {
              final bool done = index < matched;
              return Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: done ? AppColors.accentSuccess : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: done ? AppColors.accentSuccess : AppColors.accentTide,
                    width: 1.1,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          // The carrier wave with the hidden frequency marker.
          SizedBox(
            height: 54,
            child: CustomPaint(
              painter: _WaveformPainter(
                target: target,
                offset: offset,
                aligned: aligned,
              ),
              size: const Size(double.infinity, 54),
            ),
          ),
          Slider(
            value: offset.clamp(0.0, 100.0).toDouble(),
            onChanged: onChanged,
            activeColor: aligned ? AppColors.accentSuccess : AppColors.accentTide,
            inactiveColor: AppColors.surfaceElevated,
          ),
          Text(
            aligned ? 'CARRIER LOCKED — TAP TO CAPTURE' : 'SEARCHING FOR CARRIER...',
            style: AppTypography.monoCaption.copyWith(
              fontSize: 9,
              letterSpacing: 1.4,
              color: aligned ? AppColors.accentSuccess : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.target,
    required this.offset,
    required this.aligned,
  });

  final double target;
  final double offset;
  final bool aligned;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = aligned
          ? AppColors.accentSuccess.withValues(alpha: 0.9)
          : AppColors.accentTide.withValues(alpha: 0.75);

    final Path path = Path();
    for (double x = 0; x <= size.width; x += 3) {
      final double phase = (x / size.width) * math.pi * 6;
      final double amplitude = 12 *
          (1 - (x / size.width - offset / 100).abs()).clamp(0.2, 1.0).toDouble();
      final double y = size.height / 2 + math.sin(phase) * amplitude;
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);

    // target marker
    final double targetX = size.width * (target / 100);
    canvas.drawLine(
      Offset(targetX, 0),
      Offset(targetX, size.height),
      Paint()
        ..color = AppColors.accentCrimson.withValues(alpha: 0.55)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      oldDelegate.offset != offset || oldDelegate.aligned != aligned;
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({
    required this.success,
    required this.onReturn,
    this.onReveal,
  });

  final bool success;
  final VoidCallback onReturn;
  final VoidCallback? onReveal;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: success
              ? AppColors.accentSuccess.withValues(alpha: 0.5)
              : AppColors.accentCrimson.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            success ? '✅ FRAME 03/04 RECOVERED' : '⚠️ PARTIAL FIX — PACKET LOSS',
            style: AppTypography.mono.copyWith(
              fontSize: 13,
              color: success ? AppColors.accentSuccess : AppColors.accentCrimson,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            success
                ? 'One frame survived the jammer. The image is in your evidence vault.'
                : 'The signal was too degraded. You caught a shape and a doorway — nothing conclusive.',
            style: AppTypography.bodySmall.copyWith(height: 1.6),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              if (onReveal != null)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onReveal,
                    icon: const Icon(Icons.image_outlined, size: 17),
                    label: const Text('VIEW FRAME'),
                  ),
                ),
              if (onReveal != null) const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: onReturn,
                  child: const Text('RETURN TO CHAT'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
