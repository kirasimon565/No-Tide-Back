import 'package:flutter/foundation.dart';

/// The nine simulated phone threads. The ids are the exact `chat="..."` values
/// used by the .ntb scripts and must not change.
enum ChatCategory { island, home }

@immutable
class ChatThread {
  const ChatThread({
    required this.threadId,
    required this.displayName,
    required this.avatarAsset,
    required this.category,
    this.isGroup = false,
    this.badge,
    this.onlineStatus = ThreadStatus.offline,
    this.lastMessagePreview = '',
    this.lastUpdatedInGameTime = '',
    this.unreadCount = 0,
    this.isLockedOrLost = false,
    this.sortOrder = 0,
  });

  final String threadId;
  final String displayName;

  /// Avatar file name inside assets/images/characters (or null for the group).
  final String? avatarAsset;
  final ChatCategory category;
  final bool isGroup;

  /// Small role badge under the name ("Cousin", "B.H. Operations", ...).
  final String? badge;
  final ThreadStatus onlineStatus;
  final String lastMessagePreview;
  final String lastUpdatedInGameTime;
  final int unreadCount;

  /// Set during the Episode 1 relay blackout so the thread renders as lost.
  final bool isLockedOrLost;
  final int sortOrder;

  String get avatarPath =>
      avatarAsset == null ? '' : 'assets/images/characters/$avatarAsset';

  ChatThread copyWith({
    String? displayName,
    String? avatarAsset,
    ChatCategory? category,
    bool? isGroup,
    String? badge,
    ThreadStatus? onlineStatus,
    String? lastMessagePreview,
    String? lastUpdatedInGameTime,
    int? unreadCount,
    bool? isLockedOrLost,
    int? sortOrder,
  }) =>
      ChatThread(
        threadId: threadId,
        displayName: displayName ?? this.displayName,
        avatarAsset: avatarAsset ?? this.avatarAsset,
        category: category ?? this.category,
        isGroup: isGroup ?? this.isGroup,
        badge: badge ?? this.badge,
        onlineStatus: onlineStatus ?? this.onlineStatus,
        lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
        lastUpdatedInGameTime: lastUpdatedInGameTime ?? this.lastUpdatedInGameTime,
        unreadCount: unreadCount ?? this.unreadCount,
        isLockedOrLost: isLockedOrLost ?? this.isLockedOrLost,
        sortOrder: sortOrder ?? this.sortOrder,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'threadId': threadId,
        'displayName': displayName,
        'avatarAsset': avatarAsset,
        'category': category.name,
        'isGroup': isGroup,
        'badge': badge,
        'onlineStatus': onlineStatus.name,
        'lastMessagePreview': lastMessagePreview,
        'lastUpdatedInGameTime': lastUpdatedInGameTime,
        'unreadCount': unreadCount,
        'isLockedOrLost': isLockedOrLost,
        'sortOrder': sortOrder,
      };

  factory ChatThread.fromJson(Map<String, dynamic> json) => ChatThread(
        threadId: json['threadId'] as String,
        displayName: (json['displayName'] as String?) ?? '',
        avatarAsset: json['avatarAsset'] as String?,
        category: (json['category'] as String?) == 'home'
            ? ChatCategory.home
            : ChatCategory.island,
        isGroup: (json['isGroup'] as bool?) ?? false,
        badge: json['badge'] as String?,
        onlineStatus: ThreadStatus.fromId(json['onlineStatus'] as String?),
        lastMessagePreview: (json['lastMessagePreview'] as String?) ?? '',
        lastUpdatedInGameTime: (json['lastUpdatedInGameTime'] as String?) ?? '',
        unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
        isLockedOrLost: (json['isLockedOrLost'] as bool?) ?? false,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      );
}

enum ThreadStatus {
  online,
  offline,
  typing;

  static ThreadStatus fromId(String? id) => switch ((id ?? '').toLowerCase()) {
        'online' => ThreadStatus.online,
        'typing' || 'typing...' => ThreadStatus.typing,
        _ => ThreadStatus.offline,
      };

  String get label => switch (this) {
        ThreadStatus.online => 'Online',
        ThreadStatus.offline => 'Offline',
        ThreadStatus.typing => 'Typing...',
      };
}

/// Canonical seed for the nine threads (Screen 4 inbox).
abstract final class ChatThreads {
  static const List<ChatThread> seed = <ChatThread>[
    ChatThread(
      threadId: 'group_island',
      displayName: 'Sector Four / Island Group',
      avatarAsset: null,
      category: ChatCategory.island,
      isGroup: true,
      badge: 'SECTOR FOUR',
      sortOrder: 0,
    ),
    ChatThread(
      threadId: 'dm_abigail',
      displayName: 'Abigail',
      avatarAsset: 'avatar_abigail.png',
      category: ChatCategory.island,
      badge: 'PHOTOGRAPHER',
      sortOrder: 1,
    ),
    ChatThread(
      threadId: 'dm_beatrice',
      displayName: 'Beatrice',
      avatarAsset: 'avatar_beatrice.png',
      category: ChatCategory.island,
      badge: 'COUSIN',
      sortOrder: 2,
    ),
    ChatThread(
      threadId: 'dm_jessica',
      displayName: 'Jessica',
      avatarAsset: 'avatar_jessica.png',
      category: ChatCategory.island,
      badge: 'SCIENTIST',
      sortOrder: 3,
    ),
    ChatThread(
      threadId: 'dm_maya',
      displayName: 'Maya',
      avatarAsset: 'avatar_maya.png',
      category: ChatCategory.island,
      sortOrder: 4,
    ),
    ChatThread(
      threadId: 'dm_kathy',
      displayName: 'Kathy',
      avatarAsset: 'avatar_kathy.png',
      category: ChatCategory.island,
      badge: 'B.H. OPERATIONS',
      sortOrder: 5,
    ),
    ChatThread(
      threadId: 'dm_kai',
      displayName: 'Captain Kai',
      avatarAsset: 'avatar_kai.png',
      category: ChatCategory.island,
      badge: 'MARITIME',
      sortOrder: 6,
    ),
    ChatThread(
      threadId: 'dm_mom',
      displayName: 'Mom',
      avatarAsset: 'avatar_mom.png',
      category: ChatCategory.home,
      badge: 'HOME',
      sortOrder: 7,
    ),
    ChatThread(
      threadId: 'dm_sister',
      displayName: 'Chloe (Sister)',
      avatarAsset: 'avatar_sister.png',
      category: ChatCategory.home,
      badge: 'HOME',
      sortOrder: 8,
    ),
  ];

  /// Fallback used by `@system_message chat="system"` (public records lookups).
  static const ChatThread system = ChatThread(
    threadId: 'system',
    displayName: 'SYSTEM',
    avatarAsset: null,
    category: ChatCategory.island,
    sortOrder: 99,
  );

  static ChatThread? byId(String threadId) {
    for (final ChatThread t in seed) {
      if (t.threadId == threadId) return t;
    }
    return null;
  }

  static String displayNameFor(String threadId) =>
      byId(threadId)?.displayName ?? (threadId == 'system' ? 'SYSTEM' : threadId);

  /// `dm_abigail` -> `abigail`; `group_island` -> `group_island`.
  static String characterForThread(String threadId) =>
      threadId.startsWith('dm_') ? threadId.substring(3) : threadId;

  /// `abigail` -> `Abigail`, as the script's `sender=` attribute is lowercase.
  static String displayNameForCharacter(String characterId) {
    if (characterId.isEmpty) return '';
    return characterId[0].toUpperCase() + characterId.substring(1);
  }
}
