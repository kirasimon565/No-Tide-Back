import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/asset_catalog.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../engine/ntb_interpreter.dart';
import '../../models/chat_message.dart';
import '../../models/chat_thread.dart';
import '../../models/ntb_ast_node.dart';
import '../../providers/auth_store_provider.dart';
import '../../providers/chat_threads_provider.dart';
import '../../providers/game_state_provider.dart';
import '../widgets/choice_drawer.dart';
import '../widgets/common_widgets.dart';
import '../widgets/message_bubble.dart';
import '../widgets/store_modal_sheet.dart';
import '../widgets/typing_indicator_bubble.dart';
import 'hacking_tool_screen.dart';

/// Screen 5 — Chat room where the `.ntb` script plays out.
class ChatRoomScreen extends ConsumerStatefulWidget {
  const ChatRoomScreen({
    required this.threadId,
    this.readOnly = false,
    super.key,
  });

  final String threadId;

  /// Archive mode: the thread scrolls like history, and the choice drawer /
  /// composer / puzzle push are suppressed. Used by the waiting hub's
  /// "Review Chat Logs" so re-reading cannot advance or spend anything.
  final bool readOnly;

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  final ScrollController _scrollController = ScrollController();
  int _lastMessageCount = 0;
  bool _budgetSheetOpen = false;
  String? _pushedPuzzleId;
  bool _pushingPuzzle = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_scrollController.hasClients) return;
    final double target = _scrollController.position.maxScrollExtent;
    if (animate) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  Future<void> _handlePremiumBudget(GameScreenState game) async {
    if (widget.readOnly) return;
    if (_budgetSheetOpen) return;
    final int? cost = game.pendingChoiceCost;
    if (cost == null || cost <= 0) return;
    _budgetSheetOpen = true;
    await showStoreModalSheet(context, missingCoins: cost);
    if (!mounted) return;
    _budgetSheetOpen = false;
    // If the player topped up, retry the blocked option.
    final PlayerEconomyState economy = ref.read(economyProvider);
    if (economy.multimediaUnlocked || economy.coins >= cost) {
      await ref.read(gameStateProvider.notifier).retryPendingChoice();
    }
  }

  Future<void> _onChoiceSelected(NtbNode option) async {
    if (option.name == 'choice_locked') {
      final bool unlocked = await ref
          .read(economyProvider.notifier)
          .unlockPremiumAction(option.intParam('cost', 10));
      if (!unlocked) {
        if (!mounted) return;
        await showStoreModalSheet(
          context,
          missingCoins: option.intParam('cost', 10),
        );
        if (!mounted) return;
        // After topping up, retry by re-selecting the same option.
        final PlayerEconomyState economy = ref.read(economyProvider);
        if (economy.multimediaUnlocked ||
            economy.coins >= option.intParam('cost', 10)) {
          await _onChoiceSelected(option);
        }
        return;
      }
    }
    await ref.read(gameStateProvider.notifier).chooseOption(option);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  Future<void> _openHacking(String targetFile) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => HackingToolScreen(
          puzzleId: 'manual_decrypt_${DateTime.now().millisecondsSinceEpoch}',
          difficulty: 'medium',
          targetFile: targetFile,
          manual: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final GameScreenState game = ref.watch(gameStateProvider);
    final ChatThread thread = game.thread(widget.threadId) ??
        ChatThreads.byId(widget.threadId) ??
        ChatThreads.seed.first;
    final List<ChatMessage> messages = ref.watch(threadMessagesProvider(widget.threadId));
    final PlayerEconomyState economy = ref.watch(economyProvider);

    if (messages.length != _lastMessageCount) {
      _lastMessageCount = messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }

    // Budget gate → open the store sheet over the chat without losing the
    // script position.
    if (game.pendingChoiceCost != null && (game.pendingChoiceCost ?? 0) > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handlePremiumBudget(game));
    }

    // Puzzle hand-off (script-driven, not manual). Guarded by puzzle id so a
    // rebuild cannot push the tool twice.
    final HackingRequest? puzzle = game.puzzleRequest;
    if (puzzle != null && _pushedPuzzleId != puzzle.puzzleId && !_pushingPuzzle) {
      _pushedPuzzleId = puzzle.puzzleId;
      _pushingPuzzle = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final NavigatorState navigator = Navigator.of(context);
        await navigator.push(
          MaterialPageRoute<void>(
            builder: (BuildContext _) => HackingToolScreen(
              puzzleId: puzzle.puzzleId,
              difficulty: puzzle.difficulty,
              targetFile: puzzle.targetFile,
            ),
          ),
        );
        _pushingPuzzle = false;
        _pushedPuzzleId = null;
      });
    }

    final bool typing = thread.onlineStatus == ThreadStatus.typing;

    return Scaffold(
      backgroundColor: AppColors.bgVoid,
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: const AssetImage(AssetCatalog.chatBackground),
            opacity: 0.10,
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              AppColors.bgVoid.withValues(alpha: 0.6),
              BlendMode.darken,
            ),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              _ChatHeader(thread: thread, economy: economy, playerName: ref.read(gameStateProvider.notifier).profile.playerName),
              Expanded(
                child: Stack(
                  children: <Widget>[
                    ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
                      itemCount: messages.length + (typing ? 1 : 0),
                      itemBuilder: (BuildContext context, int index) {
                        if (index >= messages.length) {
                          return TypingIndicatorBubble(
                            name: _displayName(thread.threadId, thread),
                            accent: AppColors.forCharacter(
                              ChatThreads.characterForThread(thread.threadId),
                            ),
                          );
                        }
                        final ChatMessage message = messages[index];
                        return MessageBubble(
                          message: message,
                          isGroup: thread.isGroup,
                          onDecrypt: message.needsDecryption
                              ? () => _openHacking(message.mediaFile ?? '')
                              : null,
                        );
                      },
                    ),
                    if (messages.isEmpty)
                      Center(
                        child: Text(
                          '> NO MESSAGES ON THIS RELAY YET',
                          style: AppTypography.monoCaption.copyWith(letterSpacing: 1.6),
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.readOnly)
                _ReadOnlyFooter(thread: thread)
              else if (game.activeChoice != null && game.activeChoice!.isNotEmpty)
                ChoiceDrawer(
                  options: game.activeChoice!,
                  economy: economy,
                  onSelected: _onChoiceSelected,
                )
              else if (game.interpreterStatus == InterpreterStatus.awaitingInput)
                _TapToContinue(
                  onTap: () => ref.read(gameStateProvider.notifier).tapToContinue(),
                )
              else
                _Composer(
                  muted: game.isMuted,
                  onMute: () => ref.read(gameStateProvider.notifier).toggleMute(),
                  pace: game.paceMultiplier,
                  onPace: (double value) =>
                      ref.read(gameStateProvider.notifier).setPace(value),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _displayName(String threadId, ChatThread thread) {
    if (thread.isGroup) return 'Someone';
    final String id = ChatThreads.characterForThread(threadId);
    return id.isEmpty ? thread.displayName : id[0].toUpperCase() + id.substring(1);
  }
}

class _ChatHeader extends ConsumerWidget {
  const _ChatHeader({
    required this.thread,
    required this.economy,
    required this.playerName,
  });

  final ChatThread thread;
  final PlayerEconomyState economy;
  final String playerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Color accent = AppColors.forCharacter(
      ChatThreads.characterForThread(thread.threadId),
    );
    final String status = switch (thread.onlineStatus) {
      ThreadStatus.online => 'Online',
      ThreadStatus.offline => 'Offline',
      ThreadStatus.typing => 'Typing...',
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 10, 8),
      decoration: const BoxDecoration(
        color: AppColors.surfacePhone,
        border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.7)),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 17),
            color: AppColors.textSecondary,
          ),
          CharacterAvatar(
            assetPath: thread.avatarPath,
            label: thread.displayName,
            isGroup: thread.isGroup,
            size: 38,
            accent: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  thread.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label.copyWith(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: <Widget>[
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: thread.onlineStatus == ThreadStatus.offline
                            ? AppColors.textMuted
                            : (thread.onlineStatus == ThreadStatus.typing
                                ? AppColors.accentCrimson
                                : AppColors.accentSuccess),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      status,
                      style: AppTypography.monoCaption.copyWith(
                        fontSize: 9,
                        color: thread.onlineStatus == ThreadStatus.typing
                            ? AppColors.accentTide
                            : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () => showStoreModalSheet(
              context,
              focusMultimedia: !economy.multimediaUnlocked,
            ),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.accentPremium.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.accentPremium.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    economy.multimediaUnlocked ? Icons.star_rounded : Icons.monetization_on_outlined,
                    size: 13,
                    color: AppColors.accentPremium,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    economy.multimediaUnlocked ? 'FULL' : '${economy.coins}',
                    style: AppTypography.monoCaption.copyWith(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accentPremium,
                    ),
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

class _TapToContinue extends StatelessWidget {
  const _TapToContinue({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.touch_app_rounded, size: 18),
          label: const Text('TAP TO CONTINUE'),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.muted,
    required this.onMute,
    required this.pace,
    required this.onPace,
  });

  final bool muted;
  final VoidCallback onMute;
  final double pace;
  final ValueChanged<double> onPace;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: const BoxDecoration(
          color: AppColors.surfacePhone,
          border: Border(top: BorderSide(color: AppColors.divider, width: 0.7)),
        ),
        child: Row(
          children: <Widget>[
            IconButton(
              onPressed: onMute,
              icon: Icon(
                muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                size: 18,
              ),
              color: muted ? AppColors.textMuted : AppColors.textSecondary,
              tooltip: muted ? 'Unmute relay' : 'Mute relay',
            ),
            Expanded(
              child: Container(
                height: 38,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(color: AppColors.divider, width: 0.7),
                ),
                child: Text(
                  'Awaiting transmission...',
                  style: AppTypography.bodySmall.copyWith(
                    fontSize: 12.5,
                    fontStyle: FontStyle.italic,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<double>(
              tooltip: 'Playback pacing',
              color: AppColors.surfaceCard,
              onSelected: onPace,
              itemBuilder: (BuildContext context) => <PopupMenuEntry<double>>[
                const PopupMenuItem<double>(value: 1, child: Text('1x (authored pacing)')),
                const PopupMenuItem<double>(value: 2, child: Text('2x faster')),
                const PopupMenuItem<double>(value: 6, child: Text('6x faster')),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(color: AppColors.divider, width: 0.7),
                ),
                child: Text(
                  '${pace.toStringAsFixed(0)}x',
                  style: AppTypography.monoCaption.copyWith(fontSize: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// Footer shown in read-only archive mode instead of the composer.
class _ReadOnlyFooter extends StatelessWidget {
  const _ReadOnlyFooter({required this.thread});

  final ChatThread thread;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 14),
      decoration: const BoxDecoration(
        color: AppColors.surfacePhone,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.lock_clock_rounded, size: 13, color: AppColors.textMuted),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              'READ-ONLY ARCHIVE • NO SIGNAL TO ${thread.displayName.toUpperCase()}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.monoCaption.copyWith(
                fontSize: 8.5,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
