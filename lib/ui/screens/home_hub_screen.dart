import 'dart:async';

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
    String? failure;
    try {
      // The program load is a real async boundary (asset parse, first run).
      // Whatever happens, the button must not stay on "SYNCING...": the flag is
      // cleared in `finally` and a failure is reported instead of swallowed.
      final program = (await ref.read(ntbProgramProvider.future)
              .timeout(const Duration(seconds: 20)))
          .program;
      await notifier.resume(program: program);
    } catch (error) {
      failure = '$error';
      debugPrint('HomeHubScreen._resume failed: $error');
    }
    if (!mounted) return;
    setState(() => _starting = false);

    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('RELAY SYNC FAILED — $failure'),
          backgroundColor: AppColors.surfaceCard,
        ),
      );
      return;
    }

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
    final bool hasSave = game.save != null;
    final bool complete = ref.watch(episodeCompletedProvider);

    return Scaffold(
      backgroundColor: AppColors.bgVoid,
      body: OceanBackdrop(
        intensity: 0.55,
        child: SafeArea(
          child: CustomScrollView(
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _TopBar(
                        economy: economy,
                        auth: auth,
                        onStore: () => _openStore(),
                        onMultimedia: () => _openStore(focusMultimedia: true),
                        onResync: () => ref.read(economyProvider.notifier).refresh(),
                        onSignOut: () async {
                          // The avatar was a one-tap sign-out: no label, no
                          // confirmation, straight back to the splash.
                          final bool? confirmed = await showDialog<bool>(
                            context: context,
                            builder: (BuildContext context) => AlertDialog(
                              backgroundColor: AppColors.surfaceCard,
                              title: Text(
                                'SIGN OUT?',
                                style: AppTypography.label.copyWith(fontSize: 12),
                              ),
                              content: Text(
                                'Coins, the Multimedia Package and your saves stay on '
                                'your Google uid. Sign in again to pick them back up.',
                                style: AppTypography.bodySmall.copyWith(
                                  fontSize: 12.5,
                                  height: 1.5,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              actions: <Widget>[
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(false),
                                  child: const Text('STAY'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(true),
                                  child: const Text('SIGN OUT'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed != true) return;
                          await ref.read(economyProvider.notifier).signOut();
                          if (!context.mounted) return;
                          Navigator.of(context)
                              .popUntil((Route<dynamic> route) => route.isFirst);
                        },
                      ),
                      const SizedBox(height: 26),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text('EPISODE SELECT', style: AppTypography.kicker),
                                const SizedBox(height: 8),
                                Text(
                                  'The Contract',
                                  style: AppTypography.displayTitle.copyWith(fontSize: 26),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '01 / ${AppConfig.totalEpisodes.toString().padLeft(2, '0')}',
                            style: AppTypography.labelDim.copyWith(fontSize: 9),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(height: 1, color: AppColors.divider.withValues(alpha: 0.8)),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(child: _EpisodeCarousel(game: game)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 24, 18, 36),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (hasSave)
                        _ResumeCard(
                          save: game.save!,
                          busy: _starting,
                          episodeComplete: complete,
                          onResume: _resume,
                        )
                      else
                        _StartCard(onStart: _newStory, busy: _starting),
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: ConsoleButton(
                              label: 'NEW STORY',
                              icon: Icons.restart_alt_rounded,
                              height: 46,
                              onPressed: _newStory,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ConsoleButton(
                              label: 'SAVES',
                              icon: Icons.inventory_2_outlined,
                              height: 46,
                              onPressed: _openSaves,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      RuleLabel('RELAY STATUS'),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: _MiniStat(
                              label: 'EVIDENCE',
                              value: '${game.evidence.length}',
                              accent: AppColors.accentTide,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _MiniStat(
                              label: 'ACHIEVEMENTS',
                              value: '${game.achievements.length}',
                              accent: AppColors.accentTide,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _MiniStat(
                              label: 'PACK',
                              value: economy.multimediaUnlocked ? 'OWNED' : 'LOCKED',
                              accent: economy.multimediaUnlocked
                                  ? AppColors.accentSuccess
                                  : AppColors.accentPremium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: Text(
                          '${AppConfig.studioName.toUpperCase()}  •  v1.0.0',
                          style: AppTypography.labelDim.copyWith(
                            fontSize: 7.5,
                            letterSpacing: 2.4,
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
    required this.onResync,
  });

  final PlayerEconomyState economy;
  final AuthUserInfo? auth;
  final VoidCallback onStore;
  final VoidCallback onMultimedia;
  final VoidCallback onSignOut;

  /// Long-press: pull the balance back down from Firestore.
  final VoidCallback onResync;

  @override
  Widget build(BuildContext context) {
    final bool signedIn = economy.isSignedIn;
    return Row(
      children: <Widget>[
        // Identity disc. Signed in → Google avatar; offline → hollow ring.
        GestureDetector(
          onTap: signedIn ? onSignOut : null,
          onLongPress: signedIn ? onResync : null,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surfaceCard,
              border: Border.all(
                color: signedIn ? AppColors.accentTide.withValues(alpha: 0.55) : AppColors.divider,
                width: 0.9,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: (signedIn && (auth?.photoUrl ?? '').isNotEmpty)
                ? Image.network(
                    auth!.photoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (BuildContext c, Object e, StackTrace? st) => Center(
                      child: Text(
                        auth!.initial,
                        style: AppTypography.label.copyWith(fontSize: 12),
                      ),
                    ),
                  )
                : Center(
                    child: Text(
                      signedIn ? auth!.initial : '·',
                      style: AppTypography.label.copyWith(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  signedIn ? 'CLOUD LINKED' : 'CLOUD OFFLINE',
                  maxLines: 1,
                  style: AppTypography.label.copyWith(
                    fontSize: 8.5,
                    color: signedIn ? AppColors.accentTide : AppColors.accentPremium,
                    letterSpacing: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  signedIn ? 'tap: account' : 'local session',
                  maxLines: 1,
                  style: AppTypography.bodySmall.copyWith(
                    fontSize: 10,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Coin plate.
        GestureDetector(
          onTap: onStore,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.surfaceCard.withValues(alpha: 0.7),
              border: Border.all(
                color: AppColors.accentPremium.withValues(alpha: 0.35),
                width: 0.7,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.monetization_on_outlined,
                  size: 13,
                  color: AppColors.accentPremium.withValues(alpha: 0.9),
                ),
                const SizedBox(width: 6),
                Text(
                  '${economy.coins}',
                  style: AppTypography.label.copyWith(
                    fontSize: 10,
                    color: AppColors.accentPremium,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onMultimedia,
          // The plate is icon + short label, but screen readers still get the
          // full meaning.
          child: Semantics(
            label: economy.multimediaUnlocked
                ? 'Multimedia package owned'
                : 'Unlock the Multimedia Package',
            button: true,
            child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: economy.multimediaUnlocked
                  ? AppColors.accentSuccess.withValues(alpha: 0.12)
                  : Colors.transparent,
              border: Border.all(
                color: (economy.multimediaUnlocked
                        ? AppColors.accentSuccess
                        : AppColors.accentTide)
                    .withValues(alpha: 0.45),
                width: 0.7,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  economy.multimediaUnlocked
                      ? Icons.lock_open_rounded
                      : Icons.lock_outline_rounded,
                  size: 12,
                  color: economy.multimediaUnlocked
                      ? AppColors.accentSuccess
                      : AppColors.accentTide,
                ),
                const SizedBox(width: 6),
                Text(
                  economy.multimediaUnlocked ? 'OWNED' : 'PACK',
                  style: AppTypography.labelDim.copyWith(
                    fontSize: 8,
                    color: economy.multimediaUnlocked
                        ? AppColors.accentSuccess
                        : AppColors.accentTide,
                  ),
                ),
              ],
            ),
          ),
          ),
        ),
      ],
    );
  }
}

class _EpisodeCarousel extends StatelessWidget {
  const _EpisodeCarousel({required this.game});

  final GameScreenState game;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 214,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: AppConfig.totalEpisodes,
        separatorBuilder: (BuildContext context, int index) => const SizedBox(width: 12),
        itemBuilder: (BuildContext context, int index) {
          final bool isEpisode1 = index == 0;
          return SizedBox(
            width: 250,
            child: _EpisodeCard(
              index: index + 1,
              title: isEpisode1
                  ? 'THE CONTRACT'
                  : _titles[index],
              locked: !isEpisode1,
              progress: isEpisode1
                  ? (game.save == null
                      ? 'READY TO BEGIN'
                      : 'PART ${game.save!.partNumber}  •  ${game.save!.currentSceneLabel.toUpperCase()}')
                  : 'IN DEVELOPMENT',
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
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: locked
              ? AppColors.divider.withValues(alpha: 0.7)
              : AppColors.accentTide.withValues(alpha: 0.45),
          width: 0.8,
        ),
        borderRadius: BorderRadius.circular(2),
        color: AppColors.surfaceCard,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // The art is already a night scene; the old 55 % black blend plus a
          // 35–90 % slate wash crushed it to flat black. Show the frame, and
          // only darken the lower third where the title sits.
          Image.asset(
            index == 1 ? AssetCatalog.titleBackground : AssetCatalog.chatBackground,
            fit: BoxFit.cover,
            // The interesting part of the plate is the rig above the water, not
            // the sea band the 250×214 crop used to land on.
            alignment: index == 1 ? const Alignment(0.0, -0.35) : Alignment.center,
            color: Colors.black.withValues(alpha: locked ? 0.58 : 0.18),
            colorBlendMode: BlendMode.darken,
            errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                const ColoredBox(color: AppColors.surfaceCard),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const <double>[0.0, 0.52, 1.0],
                colors: <Color>[
                  AppColors.slateHeader.withValues(alpha: 0.05),
                  AppColors.slateHeader.withValues(alpha: 0.55),
                  AppColors.slateHeader.withValues(alpha: 0.96),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    StatusPill(
                      'EP ${index.toString().padLeft(2, '0')}',
                      color: locked ? AppColors.textMuted : AppColors.accentTide,
                      filled: !locked,
                    ),
                    const Spacer(),
                    if (locked)
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 13,
                        color: AppColors.textMuted.withValues(alpha: 0.8),
                      ),
                  ],
                ),
                const Spacer(),
                Container(width: 22, height: 1, color: AppColors.divider),
                const SizedBox(height: 12),
                Text(
                  'EPISODE ${index.toString().padLeft(2, '0')}',
                  style: AppTypography.labelDim.copyWith(fontSize: 7.5),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.title.copyWith(
                    fontSize: 17,
                    height: 1.3,
                    color: locked ? AppColors.textMuted : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  progress,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelDim.copyWith(
                    fontSize: 7.5,
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

  /// When true the plate becomes the "Episode 2 in development" entry point.
  final bool episodeComplete;

  @override
  Widget build(BuildContext context) {
    final Color accent =
        episodeComplete ? AppColors.accentPremium : AppColors.accentTide;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border.all(color: accent.withValues(alpha: 0.4), width: 0.8),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      episodeComplete
                          ? Icons.sensors_off_rounded
                          : Icons.play_arrow_rounded,
                      color: accent,
                      size: 17,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      episodeComplete ? 'WAITING FOR SIGNAL' : 'RESUME RELAY',
                      style: AppTypography.label.copyWith(
                        fontSize: 10,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        save.label.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: AppTypography.labelDim.copyWith(fontSize: 7),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (episodeComplete)
                  Text(
                    'EPISODE 1 COMPLETE\n'
                    '${AppConfig.nextEpisodeTitle.toUpperCase()} IN DEVELOPMENT',
                    style: AppTypography.labelDim.copyWith(
                      fontSize: 8,
                      height: 2,
                      color: AppColors.accentPremium,
                    ),
                  )
                else
                  Row(
                    children: <Widget>[
                      _kv('SCENE', save.currentSceneLabel),
                      _sep(),
                      _kv('EVIDENCE', '${save.evidenceCount}'),
                      _sep(),
                      _kv('TIME', save.environmentTime),
                    ],
                  ),
              ],
            ),
          ),
          Container(height: 0.8, color: accent.withValues(alpha: 0.28)),
          ConsoleButton(
            label: busy
                ? 'SYNCING...'
                : (episodeComplete ? 'ENTER WAITING HUB' : 'CONTINUE FROM CHECKPOINT'),
            busy: busy,
            icon: busy ? null : Icons.login_rounded,
            height: 46,
            onPressed: busy ? null : onResume,
          ),
        ],
      ),
    );
  }

  Widget _sep() => Container(
        width: 0.8,
        height: 22,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        color: AppColors.divider.withValues(alpha: 0.7),
      );

  Widget _kv(String key, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(key, style: AppTypography.labelDim.copyWith(fontSize: 7.5)),
            const SizedBox(height: 5),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.body.copyWith(
                fontSize: 13,
                color: AppColors.textPrimary,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      );
}

/// First-launch counterpart of [_ResumeCard]: no checkpoint yet.
class _StartCard extends StatelessWidget {
  const _StartCard({required this.onStart, this.busy = false});

  final VoidCallback onStart;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border.all(
          color: AppColors.accentTide.withValues(alpha: 0.35),
          width: 0.8,
        ),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'NO RELAY ON THIS DEVICE',
                  style: AppTypography.label.copyWith(
                    fontSize: 10,
                    color: AppColors.accentTide,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Register a name, pick your pronouns, and the first scene '
                  'opens on its own. About 45 minutes to the contract.',
                  style: AppTypography.bodySmall.copyWith(height: 1.55),
                ),
              ],
            ),
          ),
          Container(height: 0.8, color: AppColors.accentTide.withValues(alpha: 0.25)),
          ConsoleButton(
            label: busy ? 'OPENING...' : 'BEGIN EPISODE 1',
            busy: busy,
            icon: busy ? null : Icons.play_arrow_rounded,
            height: 46,
            onPressed: busy ? null : onStart,
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 11, 11, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard.withValues(alpha: 0.55),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.8), width: 0.7),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(width: 12, height: 1, color: accent),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.label.copyWith(
              fontSize: 12,
              color: accent,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 5),
          Text(label, style: AppTypography.labelDim.copyWith(fontSize: 7)),
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
            Center(
              child: Container(
                width: 36,
                height: 2,
                margin: const EdgeInsets.only(bottom: 18),
                color: AppColors.divider,
              ),
            ),
            Text('CLOUD SAVES', style: AppTypography.kicker),
            const SizedBox(height: 8),
            Text('Saves & Chapters', style: AppTypography.displayTitle.copyWith(fontSize: 22)),
            const SizedBox(height: 16),
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
