import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../models/chat_thread.dart';
import '../../providers/auth_store_provider.dart';
import '../../providers/chat_threads_provider.dart';
import '../../providers/game_state_provider.dart';
import '../widgets/chat_room_screen_route.dart';
import '../widgets/common_widgets.dart';
import '../widgets/store_modal_sheet.dart';
import 'evidence_vault_screen.dart';
import 'hacking_tool_screen.dart';

/// Screen 4 — Simulated phone inbox.
///
/// The always-on chrome for the game: status bar, thread list and the bottom
/// dock (Messages / Evidence / Hacking Tool / Cloud Save).
enum _InboxTab { all, island, home }

class PhoneInboxScreen extends ConsumerStatefulWidget {
  const PhoneInboxScreen({super.key});

  @override
  ConsumerState<PhoneInboxScreen> createState() => _PhoneInboxScreenState();
}

class _PhoneInboxScreenState extends ConsumerState<PhoneInboxScreen> {
  _InboxTab _tab = _InboxTab.all;

  ChatCategory? get _category => switch (_tab) {
        _InboxTab.all => null,
        _InboxTab.island => ChatCategory.island,
        _InboxTab.home => ChatCategory.home,
      };

  Future<void> _openThread(ChatThread thread) async {
    await ref.read(gameStateProvider.notifier).openThread(thread.threadId);
    if (!mounted) return;
    await Navigator.of(context).push(
      chatRoomRoute(thread.threadId),
    );
    // Returning to the inbox clears the open thread so unread badges resume.
    ref.read(gameStateProvider.notifier).closeThread();
  }

  @override
  Widget build(BuildContext context) {
    final GameScreenState game = ref.watch(gameStateProvider);
    final PlayerEconomyState economy = ref.watch(economyProvider);
    final List<ChatThread> threads = ref.watch(visibleThreadsProvider(_category));

    return Scaffold(
      backgroundColor: AppColors.bgVoid,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _StatusBar(
              game: game,
              coins: economy.coins,
              onVault: () => _push(const EvidenceVaultScreen()),
              onStore: () => showStoreModalSheet(context),
              onClose: () => Navigator.of(context).maybePop(),
            ),
            _TabStrip(
              current: _tab,
              unreadTotal: game.unreadTotal,
              onChanged: (_InboxTab tab) => setState(() => _tab = tab),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.accentTide,
                backgroundColor: AppColors.surfaceCard,
                onRefresh: () => ref.read(economyProvider.notifier).refresh(),
                child: threads.isEmpty
                    ? ListView(
                        children: <Widget>[
                          const SizedBox(height: 120),
                          Center(
                            child: Text(
                              '> NO ACTIVE RELAYS',
                              style: AppTypography.monoCaption.copyWith(letterSpacing: 2),
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: threads.length,
                        separatorBuilder: (BuildContext context, int index) =>
                            const NtbDivider(indent: 78),
                        itemBuilder: (BuildContext context, int index) {
                          final ChatThread thread = threads[index];
                          return _ThreadTile(
                            thread: thread,
                            unread: game.unreadByThread[thread.threadId] ?? 0,
                            onTap: () => _openThread(thread),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _BottomDock(
        unreadTotal: game.unreadTotal,
        evidenceCount: game.evidence.length,
        onInbox: () {},
        onVault: () => _push(const EvidenceVaultScreen()),
        onHacking: () => _push(
          const HackingToolScreen(
            puzzleId: 'manual_relay_probe',
            difficulty: 'medium',
            targetFile: 'vid_abigail_corrupted_01.mp4',
            manual: true,
          ),
        ),
        onCloud: () => _showCloudSheet(context),
      ),
    );
  }

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (BuildContext _) => screen));
  }

  Future<void> _showCloudSheet(BuildContext context) async {
    final GameScreenState game = ref.read(gameStateProvider);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfacePhone,
      builder: (BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SectionHeading(kicker: 'CLOUD RELAY', title: 'Save status'),
              const SizedBox(height: 16),
              _cloudRow('LAST CHECKPOINT', game.save?.environmentTime ?? '—'),
              _cloudRow('SCENE', game.save?.currentSceneLabel ?? 'ep1_start'),
              _cloudRow(
                'PART',
                '${game.save?.partNumber ?? 1} of 4',
              ),
              _cloudRow(
                'LAST SYNC',
                game.lastSyncedAt == null
                    ? 'not synced this session'
                    : '${game.lastSyncedAt!.hour.toString().padLeft(2, '0')}:'
                        '${game.lastSyncedAt!.minute.toString().padLeft(2, '0')}',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  await ref.read(gameStateProvider.notifier).autosaveNow(force: true);
                  if (context.mounted) Navigator.of(context).pop();
                },
                icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                label: const Text('FORCE CLOUD SYNC'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cloudRow(String key, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 130,
              child: Text(key, style: AppTypography.monoCaption.copyWith(fontSize: 9.5)),
            ),
            Expanded(
              child: Text(
                value,
                style: AppTypography.mono.copyWith(fontSize: 11.5, color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
      );
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.game,
    required this.coins,
    required this.onVault,
    required this.onStore,
    required this.onClose,
  });

  final GameScreenState game;
  final int coins;
  final VoidCallback onVault;
  final VoidCallback onStore;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final bool interfering = game.signalStrength <= 2;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 10, 10),
      decoration: const BoxDecoration(
        color: AppColors.surfacePhone,
        border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.6)),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
            color: AppColors.textSecondary,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      game.environmentTime,
                      style: AppTypography.mono.copyWith(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        game.environmentLocation.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.monoCaption.copyWith(fontSize: 8.5, letterSpacing: 1.2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: <Widget>[
                    Icon(
                      interfering ? Icons.warning_amber_rounded : Icons.cell_tower_rounded,
                      size: 11,
                      color: interfering ? AppColors.accentCrimson : AppColors.accentSuccess,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      interfering ? 'RELAY INTERFERENCE' : game.networkStatus,
                      style: AppTypography.monoCaption.copyWith(
                        fontSize: 8.5,
                        letterSpacing: 1,
                        color: interfering ? AppColors.accentCrimson : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onVault,
            icon: const Icon(Icons.folder_copy_outlined, size: 17),
            color: AppColors.textSecondary,
            tooltip: 'Evidence vault',
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          ),
          IconButton(
            onPressed: onStore,
            icon: const Icon(Icons.monetization_on_outlined, size: 17),
            color: AppColors.accentPremium,
            tooltip: 'Store ($coins coins)',
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          ),
          _SignalBars(strength: game.signalStrength),
          const SizedBox(width: 6),
          _Battery(level: game.batteryLevel),
        ],
      ),
    );
  }
}

class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.strength});

  final int strength;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        for (int i = 0; i < 4; i++)
          Container(
            width: 2.6,
            height: 4.0 + i * 3.0,
            margin: const EdgeInsets.only(left: 1.6),
            decoration: BoxDecoration(
              color: i < strength ? AppColors.accentTide : AppColors.textMuted.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        if (strength >= 3) ...<Widget>[
          const SizedBox(width: 4),
          Text('5G', style: AppTypography.monoCaption.copyWith(fontSize: 8)),
        ],
      ],
    );
  }
}

class _Battery extends StatelessWidget {
  const _Battery({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 18,
          height: 9,
          padding: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.textSecondary, width: 1),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: (level / 100).clamp(0.05, 1.0).toDouble(),
              child: Container(
                decoration: BoxDecoration(
                  color: level < 20 ? AppColors.accentCrimson : AppColors.textSecondary,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text('$level%', style: AppTypography.monoCaption.copyWith(fontSize: 7.5)),
      ],
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.current,
    required this.onChanged,
    required this.unreadTotal,
  });

  final _InboxTab current;
  final ValueChanged<_InboxTab> onChanged;
  final int unreadTotal;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: Row(
        children: <Widget>[
          for (final _InboxTab tab in _InboxTab.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: () => onChanged(tab),
                borderRadius: BorderRadius.circular(18),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: current == tab
                        ? AppColors.accentTide.withValues(alpha: 0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: current == tab ? AppColors.accentTide : AppColors.divider,
                    ),
                  ),
                  child: Text(
                    switch (tab) {
                      _InboxTab.all => 'ALL',
                      _InboxTab.island => 'ISLAND',
                      _InboxTab.home => 'HOME',
                    },
                    style: AppTypography.monoCaption.copyWith(
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w700,
                      color: current == tab ? AppColors.accentTide : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          const Spacer(),
          if (unreadTotal > 0)
            NtbTag('$unreadTotal NEW', color: AppColors.accentTide, filled: true),
        ],
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({
    required this.thread,
    required this.unread,
    required this.onTap,
  });

  final ChatThread thread;
  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color accent = AppColors.forCharacter(
      thread.threadId.startsWith('dm_') ? thread.threadId.substring(3) : thread.threadId,
    );
    final bool typing = thread.onlineStatus == ThreadStatus.typing;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 16, 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            CharacterAvatar(
              assetPath: thread.avatarPath,
              label: thread.displayName,
              isGroup: thread.isGroup,
              size: 48,
              accent: accent,
              showStatus: !thread.isGroup,
              isOnline: thread.onlineStatus != ThreadStatus.offline,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          thread.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.label.copyWith(
                            fontSize: 14.5,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (thread.badge != null) ...<Widget>[
                        const SizedBox(width: 7),
                        NtbTag(thread.badge!, color: accent, filled: false),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    typing
                        ? 'typing...'
                        : (thread.lastMessagePreview.isEmpty
                            ? 'Open the relay'
                            : thread.lastMessagePreview),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(
                      fontSize: 12.5,
                      color: typing
                          ? AppColors.accentTide
                          : (unread > 0 ? AppColors.textPrimary : AppColors.textMuted),
                      fontStyle: typing ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  thread.lastUpdatedInGameTime,
                  style: AppTypography.monoCaption.copyWith(fontSize: 8.5),
                ),
                const SizedBox(height: 6),
                if (unread > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.accentTide,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '$unread',
                      style: AppTypography.monoCaption.copyWith(
                        fontSize: 9,
                        color: AppColors.bgVoid,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else if (typing)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.4,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.accentTide),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomDock extends StatelessWidget {
  const _BottomDock({
    required this.unreadTotal,
    required this.evidenceCount,
    required this.onInbox,
    required this.onVault,
    required this.onHacking,
    required this.onCloud,
  });

  final int unreadTotal;
  final int evidenceCount;
  final VoidCallback onInbox;
  final VoidCallback onVault;
  final VoidCallback onHacking;
  final VoidCallback onCloud;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfacePhone,
        border: Border(top: BorderSide(color: AppColors.divider, width: 0.6)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: <Widget>[
              _DockItem(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'MESSAGES',
                active: true,
                badge: unreadTotal,
                onTap: onInbox,
              ),
              _DockItem(
                icon: Icons.folder_copy_outlined,
                label: 'EVIDENCE',
                badge: evidenceCount,
                onTap: onVault,
              ),
              _DockItem(
                icon: Icons.terminal_rounded,
                label: 'HACKING',
                onTap: onHacking,
              ),
              _DockItem(
                icon: Icons.cloud_queue_rounded,
                label: 'CLOUD',
                onTap: onCloud,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final Color color = active ? AppColors.accentTide : AppColors.textMuted;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Icon(icon, size: 20, color: color),
                if (badge > 0)
                  Positioned(
                    right: -8,
                    top: -5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.accentCrimson,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        badge > 99 ? '99+' : '$badge',
                        style: AppTypography.monoCaption.copyWith(
                          fontSize: 7.5,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: AppTypography.monoCaption.copyWith(
                fontSize: 8,
                letterSpacing: 1.1,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
