import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_message.dart';
import '../models/evidence_item.dart';
import '../models/chat_thread.dart';
import 'game_state_provider.dart';

/// Reactive views over the local message mirror.
///
/// [gameStateProvider] owns every write (the interpreter appends there); these
/// selectors rebuild only the widgets that care about a single thread, which is
/// what keeps a 700-message feed scrolling smoothly.
///
/// Note: the notifier mutates its message buckets in place for throughput and
/// bumps [GameScreenState] on each directive, so a plain `ref.watch` here is
/// enough to stay current.
final threadMessagesProvider = Provider.family<List<ChatMessage>, String>((Ref ref, String threadId) {
  ref.watch(gameStateProvider);
  final GameStateNotifier notifier = ref.read(gameStateProvider.notifier);
  final List<ChatMessage> messages = notifier.messagesFor(threadId);

  final List<ChatMessage> decorated = <ChatMessage>[];
  for (final ChatMessage message in messages) {
    final String? emoji = notifier.reactionFor(message.scriptMessageId);
    decorated.add(
      emoji == null
          ? message
          : ChatMessage(
              scriptMessageId: message.scriptMessageId,
              threadId: message.threadId,
              senderId: message.senderId,
              messageType: message.messageType,
              bodyText: message.bodyText,
              sequenceOrder: message.sequenceOrder,
              mediaFile: message.mediaFile,
              mediaCaption: message.mediaCaption,
              isEncrypted: message.isEncrypted,
              isDecrypted: message.isDecrypted,
              audioDuration: message.audioDuration,
              reactionEmoji: emoji,
              reactionTargetId: message.reactionTargetId,
              inGameTimestamp: message.inGameTimestamp,
              senderNameOverride: message.senderNameOverride,
            ),
    );
  }
  decorated.sort((ChatMessage a, ChatMessage b) =>
      a.sequenceOrder.compareTo(b.sequenceOrder));
  return List<ChatMessage>.unmodifiable(decorated);
});

/// Thread list for the inbox, filtered by tab.
final visibleThreadsProvider = Provider.family<List<ChatThread>, ChatCategory?>((Ref ref, ChatCategory? category) {
  final GameScreenState state = ref.watch(gameStateProvider);
  return state.threadsFor(category);
});

/// Currently open thread (null on the inbox).
final activeThreadProvider = Provider<ChatThread?>((Ref ref) {
  final GameScreenState state = ref.watch(gameStateProvider);
  return state.thread(state.openThreadId);
});

/// Unread badge total for the bottom dock.
final unreadTotalProvider = Provider<int>((Ref ref) {
  final GameScreenState state = ref.watch(gameStateProvider);
  return state.unreadTotal;
});

/// Evidence vault contents. [bonusOnly] limits the board to Multimedia
/// Package file notes.
final evidenceProvider = Provider.family<List<EvidenceItem>, bool>((Ref ref, bool bonusOnly) {
  final GameScreenState state = ref.watch(gameStateProvider);
  final List<EvidenceItem> items = bonusOnly
      ? state.evidence.where((EvidenceItem e) => e.isMultimediaBonus).toList()
      : state.evidence;
  return List<EvidenceItem>.unmodifiable(items);
});
