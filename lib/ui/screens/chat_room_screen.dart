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

  /// Set while the newest bubbles are below the fold, i.e. the player scrolled
  /// up to read. Drives the "jump to latest" pill.
  bool _newMessageUnread = false;

  bool _lastTyping = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// True while the player is parked near the bottom of the thread.
  ///
  /// Auto-scroll must not fight the player: reading back through the history
  /// used to snap back to the newest bubble the moment the script spoke again.
  bool get _pinnedToBottom {
    if (!_scrollController.hasClients) return true;
    final ScrollPosition position = _scrollController.position;
    return (position.maxScrollExtent - position.pixels) < 80;
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_scrollController.hasClients) return;
    _newMessageUnread = false;
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
      final bool grew = messages.length > _lastMessageCount;
      // Decide from the position *before* the new bubble is laid out.
      final bool wasPinned = _pinnedToBottom;
      _lastMessageCount = messages.length;
      if (grew) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (wasPinned) {
            _scrollToBottom();
          } else if (!_newMessageUnread) {
            setState(() => _newMessageUnread = true);
          }
        });
      }
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

    // A typing indicator is a content change too: follow it when pinned.
    if (typing != _lastTyping && _pinnedToBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
    _lastTyping = typing;

    return Scaffold(
      backgroundColor: AppColors.bgVoid,
      body: Container(
        color: AppColors.bgVoid,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: Opacity(
                opacity: 0.07,
                child: Image.asset(
                  AssetCatalog.chatBackground,
                  fit: BoxFit.cover,
                  errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                      const SizedBox.shrink(),
                ),
              ),
            ),
            Positioned.fill(child: SlateNoise(opacity: 0.05)),
            SafeArea(
              bottom: false,
              child: Column(
            children: <Widget>[
              _ChatHeader(thread: thread, economy: economy, playerName: ref.read(gameStateProvider.notifier).profile.playerName),
              Expanded(
                child: Stack(
                  children: <Widget>[
                    NotificationListener<ScrollNotification>(
                      onNotification: (ScrollNotification notification) {
                        // `ScrollEnd` is a scroll *activity*; the notification is
                        // `ScrollEndNotification`.
                        if (notification is ScrollEndNotification &&
                            _newMessageUnread &&
                            _pinnedToBottom) {
                          setState(() => _newMessageUnread = false);
                        }
                        return false;
                      },
                      child: ListView.builder(
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
                    ),
                    // Shown only when the player has scrolled up and the
                    // script kept talking underneath.
                    if (_newMessageUnread)
                      Positioned(
                        right: 14,
                        bottom: 10,
                        child: _JumpToLatest(onTap: () => _scrollToBottom()),
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
          ],
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

/// "New messages" pill: the thread is still running while the player reads back.
class _JumpToLatest extends StatelessWidget {
  const _JumpToLatest({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          border: Border.all(color: AppColors.accentTide.withValues(alpha: 0.6), width: 0.8),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.arrow_downward_rounded, size: 12, color: AppColors.accentTide),
            const SizedBox(width: 7),
            Text(
              'NEW MESSAGES',
              style: AppTypography.labelDim.copyWith(
                fontSize: 7.5,
                color: AppColors.accentTide,
              ),
            ),
          ],
        ),
      ),
    );
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
    final bool typing = thread.onlineStatus == ThreadStatus.typing;
    final String status = switch (thread.onlineStatus) {
      ThreadStatus.online => 'ONLINE',
      ThreadStatus.offline => 'OFFLINE',
      ThreadStatus.typing => 'TYPING',
    };

    return GlassChrome(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 10, 8),
        child: Row(
          children: <Widget>[
            InkResponse(
              onTap: () => Navigator.of(context).pop(),
              radius: 22,
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 15,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            CharacterAvatar(
              assetPath: thread.avatarPath,
              label: thread.displayName,
              isGroup: thread.isGroup,
              size: 34,
              accent: accent,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    thread.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.sectionTitle.copyWith(
                      fontSize: 14.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: <Widget>[
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: thread.onlineStatus == ThreadStatus.offline
                              ? AppColors.textMuted
                              : (typing ? AppColors.accentTide : AppColors.accentSuccess),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        status,
                        style: AppTypography.labelDim.copyWith(
                          fontSize: 7,
                          color: typing ? AppColors.accentTide : AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        thread.isGroup ? 'GROUP RELAY' : 'PRIVATE RELAY',
                        style: AppTypography.labelDim.copyWith(fontSize: 7),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => showStoreModalSheet(
                context,
                focusMultimedia: !economy.multimediaUnlocked,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: AppColors.accentPremium.withValues(alpha: 0.4),
                    width: 0.7,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      economy.multimediaUnlocked
                          ? Icons.workspace_premium_rounded
                          : Icons.monetization_on_outlined,
                      size: 12,
                      color: AppColors.accentPremium,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      economy.multimediaUnlocked ? 'PACK' : '${economy.coins}',
                      style: AppTypography.label.copyWith(
                        fontSize: 8.5,
                        color: AppColors.accentPremium,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.surfacePhone,
          border: Border(
            top: BorderSide(color: AppColors.divider.withValues(alpha: 0.9), width: 0.7),
          ),
        ),
        child: ConsoleButton(
          label: 'TAP TO CONTINUE',
          icon: Icons.touch_app_rounded,
          height: 46,
          onPressed: onTap,
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
        padding: const EdgeInsets.fromLTRB(8, 7, 10, 8),
        decoration: BoxDecoration(
          color: AppColors.surfacePhone,
          border: Border(
            top: BorderSide(color: AppColors.divider.withValues(alpha: 0.9), width: 0.7),
          ),
        ),
        child: Row(
          children: <Widget>[
            InkResponse(
              onTap: onMute,
              radius: 20,
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(
                  muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  size: 16,
                  color: muted ? AppColors.textMuted : AppColors.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: Container(
                height: 36,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: AppColors.divider.withValues(alpha: 0.8),
                    width: 0.7,
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Container(width: 5, height: 5, color: AppColors.accentTide),
                    const SizedBox(width: 8),
                    Text(
                      'AWAITING TRANSMISSION',
                      style: AppTypography.labelDim.copyWith(fontSize: 7),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<double>(
              tooltip: 'Playback pacing',
              color: AppColors.surfaceCard,
              onSelected: onPace,
              itemBuilder: (BuildContext context) => <PopupMenuEntry<double>>[
                const PopupMenuItem<double>(value: 1, child: Text('1x — authored pacing')),
                const PopupMenuItem<double>(value: 2, child: Text('2x — faster')),
                const PopupMenuItem<double>(value: 6, child: Text('6x — fastest')),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: AppColors.divider.withValues(alpha: 0.8),
                    width: 0.7,
                  ),
                ),
                child: Text(
                  '${pace.toStringAsFixed(0)}x',
                  style: AppTypography.label.copyWith(fontSize: 8.5),
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
