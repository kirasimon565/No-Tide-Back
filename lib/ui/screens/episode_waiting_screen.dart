import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_config.dart';
import '../../core/constants/asset_catalog.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_store_provider.dart';
import '../../providers/episode_wait_provider.dart';
import '../../providers/game_state_provider.dart';
import '../widgets/chat_room_screen_route.dart';
import '../widgets/common_widgets.dart';
import '../widgets/store_modal_sheet.dart';
import 'evidence_vault_screen.dart';
import 'home_hub_screen.dart';
import 'phone_inbox_screen.dart';

/// Screen 9b — the Everbyte-style "Episode 2 in development" waiting hub.
///
/// Shown after the stinger and whenever a finished player taps RESUME RELAY.
/// Everything here is read-only except REPLAY, which deliberately keeps the
/// Firestore economy (coins + Multimedia Package) untouched.
class EpisodeWaitingScreen extends ConsumerStatefulWidget {
  const EpisodeWaitingScreen({
    this.fromStinger = false,
    this.achievementTitle,
    super.key,
  });

  /// True when this screen was pushed straight off the `@end_scene` stinger.
  final bool fromStinger;

  /// Title of the achievement the stinger just unlocked, echoed in the header.
  final String? achievementTitle;

  @override
  ConsumerState<EpisodeWaitingScreen> createState() =>
      _EpisodeWaitingScreenState();
}

class _EpisodeWaitingScreenState extends ConsumerState<EpisodeWaitingScreen> {
  bool _replaying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(audioServiceProvider)
          .playMusic('bgm_to_be_continued.mp3', loop: true, volume: 0.3);
    });
  }

  Future<void> _openThread(String threadId) async {
    ref.read(gameStateProvider.notifier).openThread(threadId);
    await Navigator.of(context).push(chatRoomRoute(threadId, readOnly: true));
  }

  Future<void> _replay() async {
    if (_replaying) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: AppColors.surfaceCard,
        title: Text(
          'REPLAY EPISODE 1?',
          style: AppTypography.monoLabel.copyWith(fontSize: 12),
        ),
        content: Text(
          'A new broadcast starts from the first scene. Your messages and case '
          'files are rebuilt as you play, and different choices surface '
          'different evidence.\n\n'
          'Your coins and Multimedia Package stay exactly as they are — they '
          'live on your account, not in this run.',
          style: AppTypography.bodySmall.copyWith(height: 1.6),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('STAY HERE'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'REPLAY',
              style: AppTypography.label.copyWith(color: AppColors.accentTide),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _replaying = true);
    try {
      final GameStateNotifier notifier = ref.read(gameStateProvider.notifier);
      final NtbParserResult parsed = await ref.read(ntbProgramProvider.future);
      final program = parsed.program;
      // Coins/unlocks are re-asserted from Firestore into the fresh variables
      // block, so the replay can never spend a stale local flag.
      await ref.read(economyProvider.notifier).refresh();
      await notifier.startNewGame(program: program);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (BuildContext _) => const PhoneInboxScreen()),
        (Route<dynamic> route) => route.isFirst,
      );
    } finally {
      if (mounted) setState(() => _replaying = false);
    }
  }

  Future<void> _copyFollowLink(BuildContext context) async {
    await Clipboard.setData(
      const ClipboardData(text: EpisodeWaitConfig.studioFollowUrl),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.surfaceCard,
        content: Text(
          'STUDIO LINK COPIED • ${EpisodeWaitConfig.studioFollowUrl}',
          style: AppTypography.monoCaption.copyWith(fontSize: 9, height: 1.5),
        ),
      ),
    );
  }

  void _backToHub() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (BuildContext _) => const HomeHubScreen()),
      (Route<dynamic> route) => route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    final EpisodeWaitState wait = ref.watch(episodeWaitProvider);
    final PlayerEconomyState economy = ref.watch(economyProvider);
    final GameScreenState game = ref.watch(gameStateProvider);

    return Scaffold(
      backgroundColor: AppColors.bgVoid,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Image.asset(
              AssetCatalog.titleBackground,
              fit: BoxFit.cover,
              color: AppColors.slateHeader.withValues(alpha: 0.9),
              colorBlendMode: BlendMode.darken,
              errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
                  const ColoredBox(color: AppColors.bgVoid),
            ),
          ),
          const Positioned.fill(child: ScanlineOverlay(opacity: 0.04)),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 10, 0, 34),
              children: <Widget>[
                if (widget.fromStinger) _JustFinishedStrip(wait: wait),
                _RelayBanner(wait: wait),
                const SizedBox(height: 16),
                _EpisodeProgressCard(wait: wait),
                const SizedBox(height: 20),
                _SectionLabel(
                  kicker: 'LAST KNOWN STATUS • ${wait.lastKnownTime}',
                  title: 'WHERE EVERYONE IS',
                ),
                const SizedBox(height: 10),
                _StatusCarousel(
                  statuses: EpisodeWaitConfig.lastKnownStatus,
                  onOpenThread: _openThread,
                ),
                const SizedBox(height: 22),
                _SectionLabel(
                  kicker: 'SIGNAL DEAD • NO NEW MESSAGES',
                  title: 'WHILE YOU WAIT',
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: <Widget>[
                      _ActionTile(
                        icon: Icons.forum_rounded,
                        label: 'REVIEW CHAT LOGS',
                        detail: 'READ-ONLY PHONE MODE • '
                            '${game.threads.length} THREADS',
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (BuildContext _) => const PhoneInboxScreen(),
                            ),
                          );
                        },
                      ),
                      _ActionTile(
                        icon: Icons.inventory_2_rounded,
                        label: 'OPEN EVIDENCE VAULT',
                        detail: '${wait.evidenceLabel} • CASE BOARD',
                        accent: AppColors.accentTide,
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (BuildContext _) => const EvidenceVaultScreen(),
                            ),
                          );
                        },
                      ),
                      _ActionTile(
                        icon: Icons.restart_alt_rounded,
                        label: _replaying ? 'STARTING BROADCAST...' : 'REPLAY EPISODE 1',
                        detail: 'KEEPS ${economy.coins} COINS'
                            '${economy.multimediaUnlocked ? ' + MULTIMEDIA PACK' : ''}',
                        accent: AppColors.accentPremium,
                        onTap: _replaying ? null : _replay,
                      ),
                      _ActionTile(
                        icon: Icons.podcasts_rounded,
                        label: 'FOLLOW EYESWATCHING GAMES',
                        detail: 'EPISODE 2 RELEASE ALERTS',
                        accent: AppColors.accentSuccess,
                        trailing: Icons.content_copy_rounded,
                        onTap: () => _copyFollowLink(context),
                      ),
                      if (!economy.multimediaUnlocked)
                        _ActionTile(
                          icon: Icons.workspace_premium_rounded,
                          label: 'BONUS FILES & PRIVATE DMS',
                          detail: 'MULTIMEDIA PACKAGE',
                          accent: AppColors.accentPremium,
                          onTap: () => showStoreModalSheet(
                            context,
                            focusMultimedia: true,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GhostButton(
                    label: 'Return to main menu',
                    icon: Icons.grid_view_rounded,
                    height: 46,
                    onPressed: _backToHub,
                  ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: Text(
                    'NO TIDE BACK • ${AppConfig.studioName.toUpperCase()}',
                    style: AppTypography.monoCaption.copyWith(
                      fontSize: 8.5,
                      letterSpacing: 2.2,
                      color: AppColors.textMuted,
                    ),
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

/// Thin confirmation strip shown only when arriving straight off the stinger.
class _JustFinishedStrip extends StatelessWidget {
  const _JustFinishedStrip({required this.wait});

  final EpisodeWaitState wait;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.accentSuccess.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.accentSuccess.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.check_circle_rounded,
            size: 15,
            color: AppColors.accentSuccess,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'PROGRESS SAVED TO CLOUD • EPISODE 1 LOCKED IN',
              style: AppTypography.monoCaption.copyWith(
                fontSize: 8.5,
                letterSpacing: 1.1,
                color: AppColors.accentSuccess,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Crimson "relay offline" pill over a pulsing sonar sweep.
class _RelayBanner extends StatefulWidget {
  const _RelayBanner({required this.wait});

  final EpisodeWaitState wait;

  @override
  State<_RelayBanner> createState() => _RelayBannerState();
}

class _RelayBannerState extends State<_RelayBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  )..repeat();

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.slateHeader.withValues(alpha: 0.82),
            border: Border.all(
              color: AppColors.accentCrimson.withValues(alpha: 0.35),
              width: 0.8,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _sweep,
                builder: (BuildContext context, Widget? child) {
                  return CustomPaint(
                    painter: _SonarPainter(progress: _sweep.value),
                    size: Size.infinite,
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.accentCrimson,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          EpisodeWaitConfig.relayBanner,
                          style: AppTypography.label.copyWith(
                            fontSize: 9.5,
                            letterSpacing: 1.4,
                            color: AppColors.accentCrimson,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    EpisodeWaitConfig.relayBannerDetail,
                    style: AppTypography.labelDim.copyWith(
                      fontSize: 7.5,
                      letterSpacing: 1.8,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      const Icon(
                        Icons.radar_rounded,
                        size: 13,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'LAST KNOWN COORDINATES',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelDim.copyWith(fontSize: 7),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        EpisodeWaitConfig.lastKnownCoordinates,
                        style: AppTypography.labelDim.copyWith(
                          fontSize: 7,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _SonarPainter extends CustomPainter {
  _SonarPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final Offset center = Offset(size.width * 0.82, size.height * 0.18);
    final double maxRadius = size.width * 0.55;

    // Static rings.
    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (int i = 1; i <= 3; i++) {
      ring.color = AppColors.accentCrimson.withValues(alpha: 0.12 - i * 0.02);
      canvas.drawCircle(center, maxRadius * (i / 3.4), ring);
    }

    // Expanding pulse.
    final double radius = maxRadius * progress;
    ring.color = AppColors.accentCrimson.withValues(alpha: 0.28 * (1 - progress));
    ring.strokeWidth = 1.4;
    canvas.drawCircle(center, radius, ring);

    // Sweep line.
    final double angle = progress * 2 * math.pi - math.pi / 2;
    final Paint sweep = Paint()
      ..shader = LinearGradient(
        colors: <Color>[
          AppColors.accentCrimson.withValues(alpha: 0.0),
          AppColors.accentCrimson.withValues(alpha: 0.22),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius));
    canvas.drawLine(
      center,
      center + Offset(math.cos(angle), math.sin(angle)) * maxRadius,
      sweep,
    );
  }

  @override
  bool shouldRepaint(covariant _SonarPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _EpisodeProgressCard extends StatelessWidget {
  const _EpisodeProgressCard({required this.wait});

  final EpisodeWaitState wait;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: NtbCard(
        color: AppColors.surfacePhone.withValues(alpha: 0.86),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                NtbTag(
                  'EPISODE 1 COMPLETED',
                  color: AppColors.accentSuccess,
                  filled: true,
                  icon: Icons.check_rounded,
                ),
                const SizedBox(width: 8),
                Text(
                  '${wait.completionPercent}%',
                  style: AppTypography.monoLabel.copyWith(
                    fontSize: 11,
                    color: AppColors.accentSuccess,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: wait.completionPercent / 100,
                minHeight: 5,
                backgroundColor: AppColors.surfaceElevated,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.accentSuccess,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    AppConfig.nextEpisodeTitle.toUpperCase(),
                    style: AppTypography.monoBase.copyWith(
                      fontSize: 12.5,
                      letterSpacing: 1.6,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                NtbTag(
                  'IN DEVELOPMENT',
                  color: AppColors.accentPremium,
                  filled: false,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'hang in there until the next episode.',
              style: AppTypography.bodySmall.copyWith(
                fontStyle: FontStyle.italic,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.kicker, required this.title});

  final String kicker;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            kicker,
            style: AppTypography.monoCaption.copyWith(
              fontSize: 8.5,
              letterSpacing: 1.6,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: AppTypography.monoLabel.copyWith(
              fontSize: 11.5,
              letterSpacing: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontally swipeable "last known status" cards.
class _StatusCarousel extends StatelessWidget {
  const _StatusCarousel({required this.statuses, required this.onOpenThread});

  final List<CharacterStatus> statuses;
  final ValueChanged<String> onOpenThread;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 168,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: statuses.length,
        separatorBuilder: (BuildContext _, int __) => const SizedBox(width: 10),
        itemBuilder: (BuildContext context, int index) {
          final CharacterStatus status = statuses[index];
          return _StatusCard(
            status: status,
            onTap: status.threadId == null
                ? null
                : () => onOpenThread(status.threadId!),
          );
        },
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, this.onTap});

  final CharacterStatus status;
  final VoidCallback? onTap;

  static const Map<String, (IconData, Color)> _signals = <String, (IconData, Color)>{
    'lost': (Icons.signal_wifi_off_rounded, AppColors.accentCrimson),
    'severed': (Icons.link_off_rounded, AppColors.accentCrimson),
    'unreachable': (Icons.portable_wifi_off_rounded, AppColors.accentPremium),
    'standing_by': (Icons.anchor_rounded, AppColors.accentTide),
    'safe': (Icons.home_rounded, AppColors.accentSuccess),
  };

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) =
        _signals[status.signal] ?? (Icons.help_rounded, AppColors.textMuted);
    final Color accent = AppColors.forCharacter(status.characterId);

    return SizedBox(
      width: 208,
      child: NtbCard(
        color: AppColors.surfaceCard.withValues(alpha: 0.82),
        borderColor: color.withValues(alpha: 0.32),
        padding: const EdgeInsets.fromLTRB(13, 13, 13, 11),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                CharacterAvatar(
                  assetPath: AssetCatalog.avatar(status.characterId),
                  size: 30,
                  label: status.names,
                  accent: accent,
                ),
                const Spacer(),
                Icon(icon, size: 15, color: color),
              ],
            ),
            const SizedBox(height: 11),
            Text(
              status.names.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.monoLabel.copyWith(
                fontSize: 9.5,
                letterSpacing: 1.1,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              status.location,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.monoCaption.copyWith(
                fontSize: 8.5,
                height: 1.5,
                letterSpacing: 0.8,
                color: AppColors.textSecondary,
              ),
            ),
            const Spacer(),
            Text(
              status.condition,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.monoCaption.copyWith(
                fontSize: 8.5,
                letterSpacing: 1.2,
                color: color,
              ),
            ),
            if (onTap != null) ...<Widget>[
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  Text(
                    'OPEN LOG',
                    style: AppTypography.monoCaption.copyWith(
                      fontSize: 7.5,
                      letterSpacing: 1.1,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(width: 3),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 12,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.detail,
    this.onTap,
    this.accent = AppColors.textPrimary,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback? onTap;
  final Color accent;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: SlatePanel(
        color: AppColors.surfaceCard.withValues(alpha: 0.6),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        onTap: onTap,
        accentEdge: enabled,
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              size: 17,
              color: enabled ? accent : AppColors.textMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.label.copyWith(
                      fontSize: 9.5,
                      letterSpacing: 1.3,
                      color: enabled ? AppColors.textPrimary : AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelDim.copyWith(fontSize: 7),
                  ),
                ],
              ),
            ),
            Icon(
              trailing ?? Icons.chevron_right_rounded,
              size: 16,
              color: enabled ? AppColors.textMuted : AppColors.surfaceElevated,
            ),
          ],
        ),
      ),
    );
  }
}

/// Convenience route used by the stinger hand-off and the Home Hub.
Route<void> episodeWaitingRoute({String? achievementTitle}) {
  return PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 700),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (BuildContext context, Animation<double> animation, Animation<double> secondary) {
      return EpisodeWaitingScreen(
        fromStinger: true,
        achievementTitle: achievementTitle,
      );
    },
    transitionsBuilder: (
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondary,
      Widget child,
    ) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}
