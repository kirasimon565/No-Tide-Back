import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_config.dart';
import '../../core/constants/asset_catalog.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../models/evidence_item.dart';
import '../../providers/auth_store_provider.dart';
import '../../providers/game_state_provider.dart';
import '../widgets/common_widgets.dart';
import '../widgets/store_modal_sheet.dart';
import 'home_hub_screen.dart';

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

/// Screen 9 — Episode end & next episode stinger.
///
/// Reached from `@end_scene`. Shows the achievement, the evidence counter and
/// the trust summary, plays the COMING SOON stinger, and forces a cloud sync.
class EpisodeEndScreen extends ConsumerStatefulWidget {
  const EpisodeEndScreen({super.key});

  @override
  ConsumerState<EpisodeEndScreen> createState() => _EpisodeEndScreenState();
}

class _EpisodeEndScreenState extends ConsumerState<EpisodeEndScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  bool _synced = false;
  bool _showStinger = false;

  @override
  void initState() {
    super.initState();
    _fade.forward();
    unawaited(_forceSync());
    Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _showStinger = true);
    });
  }

  Future<void> _forceSync() async {
    await ref.read(gameStateProvider.notifier).autosaveNow(slotId: 'ep1_complete', force: true);
    if (mounted) setState(() => _synced = true);
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GameScreenState game = ref.watch(gameStateProvider);
    final EpisodeEnding? ending = game.ending;
    final PlayerEconomyState economy = ref.watch(economyProvider);
    final Map<String, int> trust = ending?.trust ??
        <String, int>{
          'jessica': game.save?.trust('jessica') ?? 0,
          'beatrice': game.save?.trust('beatrice') ?? 0,
          'abigail': game.save?.trust('abigail') ?? 0,
          'maya': game.save?.trust('maya') ?? 0,
          'kathy': game.save?.trust('kathy') ?? 0,
          'kai': game.save?.trust('kai') ?? 0,
        };

    return Scaffold(
      backgroundColor: AppColors.bootBlack,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Image.asset(
              AssetCatalog.titleBackground,
              fit: BoxFit.cover,
              color: Colors.black.withValues(alpha: 0.62),
              colorBlendMode: BlendMode.darken,
            ),
          ),
          const Positioned.fill(child: ScanlineOverlay(opacity: 0.05)),
          FadeTransition(
            opacity: _fade,
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 30),
                children: <Widget>[
                  Text('EPISODE COMPLETE',
                      style: AppTypography.monoCaption.copyWith(letterSpacing: 5)),
                  const SizedBox(height: 10),
                  Text(
                    ending?.title.replaceFirst('END OF ', '') ??
                        'EPISODE 1: THE CONTRACT',
                    style: AppTypography.monoBase.copyWith(
                      fontSize: 21,
                      height: 1.35,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: <Widget>[
                      NtbTag(
                        'ACH: THE CONTRACT',
                        color: AppColors.accentPremium,
                        filled: true,
                        icon: Icons.emoji_events_rounded,
                      ),
                      const SizedBox(width: 8),
                      NtbTag(
                        'EVIDENCE ${game.evidence.length}/${AppConfig.evidenceGoal}',
                        color: game.evidence.length >= AppConfig.evidenceGoal
                            ? AppColors.accentSuccess
                            : AppColors.accentTide,
                        filled: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // Trust summary
                  NtbCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('TRUST SUMMARY', style: AppTypography.monoLabel),
                        const SizedBox(height: 14),
                        for (final String key in AppConfig.trustCharacters)
                          _TrustBar(
                            name: AppConfig.characterNames[key] ?? key,
                            value: trust[key] ?? 0,
                            color: AppColors.forCharacter(key),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Evidence recap
                  NtbCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Text('CASE BOARD', style: AppTypography.monoLabel),
                            const Spacer(),
                            Text(
                              '${game.evidence.length} ITEMS',
                              style: AppTypography.monoCaption.copyWith(fontSize: 9),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (game.evidence.isEmpty)
                          Text(
                            'No evidence logged this run. Replay with different '
                            'choices to build a fuller picture.',
                            style: AppTypography.bodySmall.copyWith(height: 1.5),
                          )
                        else
                          ...game.evidence.map(
                            (EvidenceItem item) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Icon(
                                    item.isMultimediaBonus
                                        ? Icons.workspace_premium_rounded
                                        : Icons.circle,
                                    size: item.isMultimediaBonus ? 12 : 5,
                                    color: item.isMultimediaBonus
                                        ? AppColors.accentPremium
                                        : AppColors.accentTide,
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      item.title.toUpperCase(),
                                      style: AppTypography.monoCaption.copyWith(
                                        fontSize: 10,
                                        height: 1.5,
                                        letterSpacing: 0.6,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Cloud sync status
                  NtbCard(
                    color: AppColors.surfacePhone,
                    child: Row(
                      children: <Widget>[
                        Icon(
                          _synced ? Icons.cloud_done_rounded : Icons.cloud_sync_rounded,
                          size: 18,
                          color: _synced ? AppColors.accentSuccess : AppColors.accentTide,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _synced
                                ? 'CLOUD SAVE COMMITTED • players/{uid}/saves/ep1_complete'
                                : 'SYNCING CHECKPOINT...',
                            style: AppTypography.monoCaption.copyWith(fontSize: 9, height: 1.6),
                          ),
                        ),
                        if (!_synced)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Stinger
                  AnimatedOpacity(
                    opacity: _showStinger ? 1 : 0,
                    duration: const Duration(milliseconds: 900),
                    child: Column(
                      children: <Widget>[
                        Text(
                          'COMING SOON',
                          style: AppTypography.monoCaption.copyWith(
                            letterSpacing: 6,
                            color: AppColors.accentCrimson,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${AppConfig.nextEpisodeTitle.toUpperCase()} — IN DEVELOPMENT',
                          textAlign: TextAlign.center,
                          style: AppTypography.monoBase.copyWith(
                            fontSize: 14,
                            letterSpacing: 1.8,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'hang in there until the next episode.',
                          textAlign: TextAlign.center,
                          style: AppTypography.bodySmall.copyWith(
                            fontStyle: FontStyle.italic,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),

                  if (!economy.multimediaUnlocked) ...<Widget>[
                    OutlinedButton.icon(
                      onPressed: () => showStoreModalSheet(context, focusMultimedia: true),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accentPremium,
                        side: BorderSide(
                          color: AppColors.accentPremium.withValues(alpha: 0.5),
                        ),
                      ),
                      icon: const Icon(Icons.workspace_premium_rounded, size: 18),
                      label: const Text('UNLOCK BONUS FILES & PRIVATE DMS'),
                    ),
                    const SizedBox(height: 10),
                  ],
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute<void>(builder: (BuildContext _) => const HomeHubScreen()),
                      (Route<dynamic> route) => route.isFirst,
                    ),
                    icon: const Icon(Icons.home_rounded, size: 18),
                    label: const Text('RETURN TO HUB'),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Replay with different choices to unlock alternate evidence and trust outcomes.',
                    textAlign: TextAlign.center,
                    style: AppTypography.monoCaption.copyWith(fontSize: 9, height: 1.6),
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

class _TrustBar extends StatelessWidget {
  const _TrustBar({required this.name, required this.value, required this.color});

  final String name;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final double ratio = (value / AppConfig.maxTrust).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 84,
            child: Text(
              name,
              style: AppTypography.label.copyWith(fontSize: 11.5, color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: AppColors.surfaceElevated,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
          const SizedBox(width: 9),
          SizedBox(
            width: 26,
            child: Text(
              '$value',
              textAlign: TextAlign.right,
              style: AppTypography.monoCaption.copyWith(fontSize: 10, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
