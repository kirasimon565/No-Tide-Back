import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_config.dart';
import '../../core/constants/asset_catalog.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../models/game_save_state.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_store_provider.dart';
import '../../providers/episode_wait_provider.dart';
import '../../providers/game_state_provider.dart';
import '../widgets/common_widgets.dart';
import '../widgets/store_modal_sheet.dart';
import 'episode_waiting_screen.dart';
import 'phone_inbox_screen.dart';
import 'player_setup_screen.dart';

/// Screen 2 — Main Menu / Home Hub.
class HomeHubScreen extends ConsumerStatefulWidget {
  const HomeHubScreen({super.key});

  @override
  ConsumerState<HomeHubScreen> createState() => _HomeHubScreenState();
}

class _HomeHubScreenState extends ConsumerState<HomeHubScreen> {
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(audioServiceProvider).playMusic('bgm_dread_silence.mp3', volume: 0.35);
    });
  }

  Future<void> _resume() async {
    if (_starting) return;

    // A finished Episode 1 has nowhere left to play: send the player to the
    // waiting hub instead of dropping them back onto the last scene.
    if (ref.read(episodeCompletedProvider)) {
      await _openWaitingHub();
      return;
    }

    setState(() => _starting = true);
    final GameStateNotifier notifier = ref.read(gameStateProvider.notifier);
    final program = (await ref.read(ntbProgramProvider.future)).program;
    await notifier.resume(program: program);
    if (!mounted) return;
    setState(() => _starting = false);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (BuildContext _) => const PhoneInboxScreen()),
    );
  }

  Future<void> _openWaitingHub() async {
    if (_starting) return;
    setState(() => _starting = true);
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 620),
        pageBuilder: (BuildContext context, Animation<double> a, Animation<double> b) =>
            const EpisodeWaitingScreen(),
        transitionsBuilder: (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondary,
          Widget child,
        ) =>
            FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
    if (mounted) setState(() => _starting = false);
  }

  Future<void> _newStory() async {
    final GameSaveState? existing = ref.read(gameStateProvider).save;
    if (existing != null) {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('OVERWRITE ACTIVE RELAY?'),
          content: Text(
            'This replaces your current run (${existing.label}). '
            'Coins and unlocks are kept — they live on your account.',
            style: AppTypography.bodySmall,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('KEEP'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('START OVER'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (BuildContext _) => const PlayerSetupScreen()),
    );
  }

  Future<void> _openStore({bool focusMultimedia = false}) async {
    await showStoreModalSheet(context, focusMultimedia: focusMultimedia);
  }

  Future<void> _openSaves() async {
    final GameStateNotifier notifier = ref.read(gameStateProvider.notifier);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfacePhone,
      builder: (BuildContext context) => _SavesSheet(
        slots: notifier.slots(),
        onLoad: (String slotId) async {
          Navigator.of(context).pop();
          await notifier.loadSlot(slotId);
          if (!mounted) return;
          await Navigator.of(this.context).push(
            MaterialPageRoute<void>(builder: (BuildContext _) => const PhoneInboxScreen()),
          );
        },
        onSave: (String slotId) async {
          await notifier.saveToSlot(slotId);
          if (context.mounted) Navigator.of(context).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final PlayerEconomyState economy = ref.watch(economyProvider);
    final AuthUserInfo? auth = ref.watch(authUserProvider).value;
    final GameScreenState game = ref.watch(gameStateProvider);

    return Scaffold(
      body: OceanBackdrop(
        intensity: 0.6,
        child: SafeArea(
          child: CustomScrollView(
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _TopBar(
                        economy: economy,
                        auth: auth,
                        onStore: () => _openStore(),
                        onMultimedia: () => _openStore(focusMultimedia: true),
                        onSignOut: () async {
                          await ref.read(economyProvider.notifier).signOut();
                          if (!mounted) return;
                          Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
                        },
                        onSync: () => ref.read(economyProvider.notifier).refresh(),
                      ),
                      const SizedBox(height: 22),
                      SectionHeading(
                        kicker: 'EPISODE SELECT',
                        title: 'The Contract',
                        trailing: Text(
                          '1 / ${AppConfig.totalEpisodes}',
                          style: AppTypography.monoCaption,
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(child: _EpisodeCarousel(game: game)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 26, 20, 40),
                  child: Column(
                    children: <Widget>[
                      if (game.save != null)
                        _ResumeCard(
                          save: game.save!,
                          busy: _starting,
                          episodeComplete: ref.watch(episodeCompletedProvider),
                          onResume: _resume,
                        ),
                      if (game.save != null) const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _newStory,
                        icon: const Icon(Icons.restart_alt_rounded, size: 18),
                        label: const Text('NEW STORY'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _openSaves,
                        icon: const Icon(Icons.cloud_queue_rounded, size: 18),
                        label: const Text('SAVES & CHAPTERS'),
                      ),
                      const SizedBox(height: 18),
                      if (game.save == null)
                        FilledButton.icon(
                          onPressed: _newStory,
                          icon: const Icon(Icons.play_arrow_rounded, size: 20),
                          label: const Text('BEGIN EPISODE 1'),
                        ),
                      const SizedBox(height: 22),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: _MiniStat(
                              icon: Icons.folder_copy_outlined,
                              label: 'EVIDENCE',
                              value: '${game.evidence.length}',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _MiniStat(
                              icon: Icons.emoji_events_outlined,
                              label: 'ACHIEVEMENTS',
                              value: '${game.achievements.length}',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _MiniStat(
                              icon: economy.multimediaUnlocked
                                  ? Icons.workspace_premium_rounded
                                  : Icons.lock_outline_rounded,
                              label: 'PACK',
                              value: economy.multimediaUnlocked ? 'OWNED' : '—',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),
                      Text(
                        '${AppConfig.studioName.toUpperCase()}  •  v1.0.0',
                        style: AppTypography.monoCaption.copyWith(letterSpacing: 3),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.economy,
    required this.auth,
    required this.onStore,
    required this.onMultimedia,
    required this.onSignOut,
    required this.onSync,
  });

  final PlayerEconomyState economy;
  final AuthUserInfo? auth;
  final VoidCallback onStore;
  final VoidCallback onMultimedia;
  final VoidCallback onSignOut;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final bool signedIn = economy.isSignedIn;
    return Row(
      children: <Widget>[
        Tooltip(
          message: signedIn ? 'Tap to sync or sign out' : 'Play offline',
          child: InkWell(
            onTap: signedIn ? onSignOut : null,
            borderRadius: BorderRadius.circular(24),
            child: Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.accentTide.withValues(alpha: 0.5)),
                    gradient: const LinearGradient(
                      colors: <Color>[AppColors.bubbleOutgoing, AppColors.surfaceCard],
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: (auth?.photoUrl != null && auth!.photoUrl!.isNotEmpty)
                      ? Image.network(
                          auth!.photoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (BuildContext c, Object e, StackTrace? s) => Center(
                            child: Text(
                              auth!.initial,
                              style: AppTypography.label.copyWith(color: AppColors.accentTide),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            signedIn ? auth!.initial : 'O',
                            style: AppTypography.label.copyWith(color: AppColors.accentTide),
                          ),
                        ),
                ),
                const SizedBox(width: 9),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      signedIn ? 'CONNECTED' : 'CLOUD OFFLINE',
                      style: AppTypography.monoCaption.copyWith(
                        letterSpacing: 1.6,
                        color: signedIn ? AppColors.accentSuccess : AppColors.accentPremium,
                      ),
                    ),
                    SizedBox(
                      width: 130,
                      child: Text(
                        signedIn ? (auth?.email ?? '') : 'local session',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.monoCaption.copyWith(fontSize: 9.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        if (signedIn)
          IconButton(
            onPressed: onSync,
            icon: economy.isSyncing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded, size: 18, color: AppColors.textSecondary),
            tooltip: 'Force cloud sync',
          ),
        _PillButton(
          onTap: onStore,
          icon: Icons.monetization_on_outlined,
          label: '${economy.coins}',
          color: AppColors.accentPremium,
        ),
        const SizedBox(width: 8),
        _PillButton(
          onTap: onMultimedia,
          icon: economy.multimediaUnlocked
              ? Icons.star_rounded
              : Icons.lock_open_rounded,
          label: economy.multimediaUnlocked ? 'FULL ACCESS' : 'UNLOCK PACK',
          color: economy.multimediaUnlocked ? AppColors.accentPremium : AppColors.accentTide,
        ),
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.onTap,
    required this.icon,
    required this.label,
    required this.color,
  });

  final VoidCallback onTap;
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.38)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: AppTypography.monoCaption.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 9.5,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EpisodeCarousel extends StatelessWidget {
  const _EpisodeCarousel({required this.game});

  final GameScreenState game;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 246,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: AppConfig.totalEpisodes,
        separatorBuilder: (BuildContext context, int index) => const SizedBox(width: 14),
        itemBuilder: (BuildContext context, int index) {
          final bool isEpisode1 = index == 0;
          return SizedBox(
            width: 268,
            child: _EpisodeCard(
              index: index + 1,
              title: isEpisode1
                  ? 'EPISODE 1: THE CONTRACT'
                  : 'EPISODE ${index + 1}: ${_titles[index]}',
              locked: !isEpisode1,
              progress: isEpisode1
                  ? (game.save == null
                      ? 'READY'
                      : 'PART ${game.save!.partNumber} • ${game.save!.currentSceneLabel.toUpperCase()}')
                  : 'COMING SOON',
            ),
          );
        },
      ),
    );
  }

  static const List<String> _titles = <String>[
    'THE CONTRACT',
    'SIDE EFFECTS',
    'DEAD WATER',
    'THE FIFTH NAME',
    'NO TIDE BACK',
  ];
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    required this.index,
    required this.title,
    required this.locked,
    required this.progress,
  });

  final int index;
  final String title;
  final bool locked;
  final String progress;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset(
            index == 1 ? AssetCatalog.titleBackground : AssetCatalog.chatBackground,
            fit: BoxFit.cover,
            color: locked ? Colors.black.withValues(alpha: 0.72) : Colors.black.withValues(alpha: 0.28),
            colorBlendMode: BlendMode.darken,
            errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                const ColoredBox(color: AppColors.surfaceCard),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Colors.transparent,
                  AppColors.bgVoid.withValues(alpha: 0.86),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    NtbTag(
                      'EP ${index.toString().padLeft(2, '0')}',
                      color: locked ? AppColors.textMuted : AppColors.accentTide,
                      filled: true,
                    ),
                    const Spacer(),
                    if (locked)
                      const Icon(Icons.lock_rounded, size: 14, color: AppColors.textMuted),
                  ],
                ),
                const Spacer(),
                Text(
                  title,
                  style: AppTypography.monoBase.copyWith(
                    fontSize: 15,
                    height: 1.35,
                    letterSpacing: 1.7,
                    fontWeight: FontWeight.w700,
                    color: locked ? AppColors.textSecondary : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  progress,
                  style: AppTypography.monoCaption.copyWith(
                    color: locked ? AppColors.textMuted : AppColors.accentTide,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({
    required this.save,
    required this.onResume,
    this.busy = false,
    this.episodeComplete = false,
  });

  final GameSaveState save;
  final VoidCallback onResume;
  final bool busy;

  /// When true the card becomes the "Episode 2 in development" entry point.
  final bool episodeComplete;

  @override
  Widget build(BuildContext context) {
    final Color accent =
        episodeComplete ? AppColors.accentPremium : AppColors.accentTide;
    return NtbCard(
      borderColor: accent.withValues(alpha: 0.45),
      color: AppColors.surfaceCard,
      onTap: busy ? null : onResume,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                episodeComplete
                    ? Icons.sensors_off_rounded
                    : Icons.play_circle_fill_rounded,
                color: episodeComplete
                    ? AppColors.accentPremium
                    : AppColors.accentTide,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                episodeComplete ? 'WAITING FOR SIGNAL' : 'RESUME RELAY',
                style: AppTypography.monoLabel.copyWith(fontSize: 11.5),
              ),
              const Spacer(),
              Text(
                save.label,
                style: AppTypography.monoCaption.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (episodeComplete) ...<Widget>[
            Text(
              'EPISODE 1 COMPLETE • ${AppConfig.nextEpisodeTitle.toUpperCase()} '
              'IN DEVELOPMENT',
              style: AppTypography.monoCaption.copyWith(
                fontSize: 8.5,
                letterSpacing: 1.1,
                color: AppColors.accentPremium,
              ),
            ),
            const SizedBox(height: 8),
          ] else
            Row(
              children: <Widget>[
                _kv('SCENE', save.currentSceneLabel),
                const SizedBox(width: 16),
                _kv('EVIDENCE', '${save.evidenceCount}'),
                const SizedBox(width: 16),
                _kv('TIME', save.environmentTime),
              ],
            ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: busy ? null : onResume,
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.bgVoid),
                    )
                  : Text(
                      episodeComplete
                          ? 'ENTER WAITING HUB'
                          : 'CONTINUE FROM CHECKPOINT',
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String key, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(key, style: AppTypography.monoCaption.copyWith(fontSize: 9, letterSpacing: 1.4)),
            const SizedBox(height: 3),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.monoBase.copyWith(
                fontSize: 11.5,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      );
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return NtbCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(height: 10),
          Text(value, style: AppTypography.monoBase.copyWith(fontSize: 14, color: AppColors.textPrimary)),
          const SizedBox(height: 3),
          Text(label, style: AppTypography.monoCaption.copyWith(fontSize: 8.5, letterSpacing: 1.2)),
        ],
      ),
    );
  }
}

class _SavesSheet extends StatelessWidget {
  const _SavesSheet({
    required this.slots,
    required this.onLoad,
    required this.onSave,
  });

  final List<SaveSlotInfo> slots;
  final Future<void> Function(String slotId) onLoad;
  final Future<void> Function(String slotId) onSave;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SectionHeading(kicker: 'CLOUD SAVES', title: 'Saves & Chapters'),
            const SizedBox(height: 14),
            ...slots.map(
              (SaveSlotInfo slot) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: NtbCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        slot.isUsed ? Icons.save_rounded : Icons.save_outlined,
                        size: 18,
                        color: slot.isUsed ? AppColors.accentTide : AppColors.textMuted,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(slot.title, style: AppTypography.sectionTitle.copyWith(fontSize: 14)),
                            const SizedBox(height: 3),
                            Text(
                              slot.save?.label ?? 'No checkpoint stored',
                              style: AppTypography.monoCaption,
                            ),
                          ],
                        ),
                      ),
                      if (slot.isUsed)
                        TextButton(
                          onPressed: () => onLoad(slot.slotId),
                          child: const Text('LOAD'),
                        ),
                      TextButton(
                        onPressed: () => onSave(slot.slotId),
                        child: const Text('SAVE'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Slots sync to players/{uid}/saves in Cloud Firestore.',
              style: AppTypography.monoCaption.copyWith(fontSize: 9.5),
            ),
          ],
        ),
      ),
    );
  }
}
