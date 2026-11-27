import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/auth_store_provider.dart';
import '../../providers/episode_wait_provider.dart';
import '../../providers/game_state_provider.dart';
import '../widgets/episode_stinger.dart';
import '../widgets/store_modal_sheet.dart';
import 'episode_waiting_screen.dart';

/// Wraps the app and swaps to the stinger screen the moment `@end_scene`
/// raises an ending, whichever route is currently on top.
class EpisodeEndScreenGate extends ConsumerWidget {
  const EpisodeEndScreenGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final EpisodeEnding? ending = ref.watch(
      gameStateProvider.select((GameScreenState state) => state.ending),
    );
    if (ending == null) return child;
    return const EpisodeEndScreen();
  }
}

/// Screen 9 — the episode-end stinger.
///
/// Executes the tail of `episode_01_part_4.ntb` in order:
///
///   `@autosave slot="ep1_complete"`      → cloud checkpoint, top-strip toast
///   `@unlock_achievement ach_ep1_clear`  → achievement banner
///   `@fade_out duration="3"`             → fade to #000000
///   `@stop_music fade_out="2"`           → crossfade
///   `@music bgm_to_be_continued.mp3`
///   `@fade_in` + `@show_text` × 4        → NO TIDE BACK → EPISODE 2 … → IN DEVELOPMENT
///                                          → "hang in there until the next episode."
///   `@fade_out duration="2"`             → hand off to the waiting hub
///
/// The cards are the ones the interpreter captured from the script (see
/// [GameScreenState.showTextCards]); [defaultStingerCards] is the fallback for a
/// player who arrives here from a finished save rather than a live playthrough.
class EpisodeEndScreen extends ConsumerStatefulWidget {
  const EpisodeEndScreen({super.key});

  @override
  ConsumerState<EpisodeEndScreen> createState() => _EpisodeEndScreenState();
}

class _EpisodeEndScreenState extends ConsumerState<EpisodeEndScreen> {
  bool _synced = false;
  bool _stingerDone = false;
  bool _forceSyncStarted = false;

  @override
  void initState() {
    super.initState();
    unawaited(_forceSync());
  }

  /// `@autosave` already ran inside the interpreter; this is the belt-and-braces
  /// commit that guarantees the checkpoint exists before the hub is reachable.
  Future<void> _forceSync() async {
    if (_forceSyncStarted) return;
    _forceSyncStarted = true;
    try {
      await ref
          .read(gameStateProvider.notifier)
          .autosaveNow(slotId: 'ep1_complete', force: true);
    } finally {
      if (mounted) setState(() => _synced = true);
    }
  }

  void _openWaitingHub() {
    if (!mounted || _stingerDone) return;
    setState(() => _stingerDone = true);
    final EpisodeEnding? ending = ref.read(gameStateProvider).ending;
    Navigator.of(context).pushReplacement(
      episodeWaitingRoute(achievementTitle: ending?.title),
    );
  }

  @override
  Widget build(BuildContext context) {
    final GameScreenState game = ref.watch(gameStateProvider);
    final EpisodeEnding? ending = game.ending;

    final List<StingerCard> cards = game.showTextCards.isEmpty
        ? defaultStingerCards
        : game.showTextCards
            .map(
              (ShowTextLine line) => StingerCard(
                text: line.text,
                duration: line.duration <= 0 ? 3 : line.duration,
                isItalic: line.text.trim().endsWith('.'),
                color: line.text.trim().endsWith('.')
                    ? AppColors.textSecondary
                    : null,
              ),
            )
            .toList(growable: false);

    // Only celebrate an achievement the script actually unlocked. This used to
    // fall back to a generic "Episode Complete" toast, so finishing showed an
    // award card for something the save did not contain.
    final bool cleared = game.achievements.contains('ach_ep1_clear');

    return EpisodeStinger(
      cards: cards,
      synced: _synced,
      showAchievementToast: cleared,
      achievementTitle: cleared ? 'The Contract' : null,
      achievementDescription: cleared
          ? 'Completed Episode 1: The Contract.'
          : null,
      onFinished: _openWaitingHub,
    );
  }
}

/// Fallback ending summary, kept for the (rare) case where a player reaches the
/// end while offline and wants to see the trust/case recap before the hub.
///
/// Reachable from the waiting hub's overflow menu; not part of the stinger.
class EpisodeEndSummary extends ConsumerWidget {
  const EpisodeEndSummary({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GameScreenState game = ref.watch(gameStateProvider);
    final EpisodeWaitState wait = ref.watch(episodeWaitProvider);

    return Scaffold(
      backgroundColor: AppColors.bootBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'EPISODE 1 SUMMARY',
          style: AppTypography.monoLabel.copyWith(fontSize: 11.5),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: <Widget>[
          Text(
            game.ending?.title ?? 'END OF EPISODE 1: THE CONTRACT',
            style: AppTypography.monoBase.copyWith(
              fontSize: 17,
              height: 1.4,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              NtbSummaryTag(
                'ACH: THE CONTRACT',
                color: AppColors.accentPremium,
              ),
              const SizedBox(width: 8),
              NtbSummaryTag(
                wait.evidenceLabel,
                color: AppColors.accentTide,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('TRUST SUMMARY', style: AppTypography.monoLabel),
          const SizedBox(height: 12),
          for (final String key in AppConfig.trustCharacters)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 92,
                    child: Text(
                      AppConfig.characterNames[key] ?? key,
                      style: AppTypography.label.copyWith(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: ((wait.trust[key] ?? 0) / AppConfig.maxTrust)
                            .clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: AppColors.surfaceElevated,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.forCharacter(key),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${wait.trust[key] ?? 0}',
                      textAlign: TextAlign.right,
                      style: AppTypography.monoCaption.copyWith(
                        fontSize: 10,
                        color: AppColors.forCharacter(key),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          if (!ref.watch(economyProvider).multimediaUnlocked)
            OutlinedButton.icon(
              onPressed: () =>
                  showStoreModalSheet(context, focusMultimedia: true),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accentPremium,
                side: BorderSide(
                  color: AppColors.accentPremium.withValues(alpha: 0.5),
                ),
                minimumSize: const Size.fromHeight(46),
              ),
              icon: const Icon(Icons.workspace_premium_rounded, size: 17),
              label: const Text('UNLOCK BONUS FILES & PRIVATE DMS'),
            ),
        ],
      ),
    );
  }
}

/// Minimal tag used by [EpisodeEndSummary] without importing the full widget set.
class NtbSummaryTag extends StatelessWidget {
  const NtbSummaryTag(this.label, {required this.color, super.key});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: AppTypography.monoCaption.copyWith(
          fontSize: 8.5,
          letterSpacing: 0.9,
          color: color,
        ),
      ),
    );
  }
}
