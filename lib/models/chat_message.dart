import 'package:flutter/foundation.dart';

import '../core/constants/asset_catalog.dart';

enum MessageType {
  text,
  image,
  video,
  audio,
  system,
  thought,
  reaction,
  attachmentDoc,

  /// A player pick rendered into the thread (@reply resolution).
  playerReply;

  static MessageType fromId(String? id) => switch ((id ?? '').toLowerCase()) {
        'image' => MessageType.image,
        'video' => MessageType.video,
        'audio' => MessageType.audio,
        'system' => MessageType.system,
        'thought' => MessageType.thought,
        'reaction' => MessageType.reaction,
        'doc' || 'document' => MessageType.attachmentDoc,
        'player_reply' => MessageType.playerReply,
        _ => MessageType.text,
      };
}

/// One rendered line in a thread — the local mirror of everything the
/// interpreter has already executed. Persisted as JSON in an AppDatabase
/// document; the shape is intentionally identical to the Isar collection spec
/// from the design document (isarId / scriptMessageId / sequenceOrder...).
@immutable
class ChatMessage {
  const ChatMessage({
    required this.scriptMessageId,
    required this.threadId,
    required this.senderId,
    required this.messageType,
    required this.bodyText,
    required this.sequenceOrder,
    this.mediaFile,
    this.mediaCaption,
    this.isEncrypted = false,
    this.isDecrypted = false,
    this.audioDuration,
    this.reactionEmoji,
    this.reactionTargetId,
    this.inGameTimestamp = '',
    this.senderNameOverride,
  });

  /// Stable id from the script (`m001`, `mm_p1_f1_msg`, ...) or generated for
  /// player replies (`p_<millis>`).
  final String scriptMessageId;
  final String threadId;
  final String senderId;
  final MessageType messageType;
  final String bodyText;
  final int sequenceOrder;

  /// Bare file name as written in the script (e.g. `img_maya_pier_selfie.jpg`).
  final String? mediaFile;
  final String? mediaCaption;
  final bool isEncrypted;
  final bool isDecrypted;
  final String? audioDuration;
  final String? reactionEmoji;

  /// For @react_message: which script message id the emoji attaches to.
  final String? reactionTargetId;
  final String inGameTimestamp;
  final String? senderNameOverride;

  bool get isPlayer => senderId == 'player';

  String? get mediaPath =>
      mediaFile == null ? null : AssetCatalog.resolve(mediaFile!);

  bool get isImage =>
      messageType == MessageType.image || messageType == MessageType.attachmentDoc;
  bool get isVideo => messageType == MessageType.video;
  bool get isAudio => messageType == MessageType.audio;

  /// Encrypted media that has not been decrypted yet renders the glitch plate.
  bool get needsDecryption => isEncrypted && !isDecrypted;

  ChatMessage copyWith({
    bool? isDecrypted,
    String? inGameTimestamp,
    int? sequenceOrder,
  }) =>
      ChatMessage(
        scriptMessageId: scriptMessageId,
        threadId: threadId,
        senderId: senderId,
        messageType: messageType,
        bodyText: bodyText,
        sequenceOrder: sequenceOrder ?? this.sequenceOrder,
        mediaFile: mediaFile,
        mediaCaption: mediaCaption,
        isEncrypted: isEncrypted,
        isDecrypted: isDecrypted ?? this.isDecrypted,
        audioDuration: audioDuration,
        reactionEmoji: reactionEmoji,
        reactionTargetId: reactionTargetId,
        inGameTimestamp: inGameTimestamp ?? this.inGameTimestamp,
        senderNameOverride: senderNameOverride,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'scriptMessageId': scriptMessageId,
        'threadId': threadId,
        'senderId': senderId,
        'messageType': messageType.name,
        'bodyText': bodyText,
        'sequenceOrder': sequenceOrder,
        'mediaFile': mediaFile,
        'mediaCaption': mediaCaption,
        'isEncrypted': isEncrypted,
        'isDecrypted': isDecrypted,
        'audioDuration': audioDuration,
        'reactionEmoji': reactionEmoji,
        'reactionTargetId': reactionTargetId,
        'inGameTimestamp': inGameTimestamp,
        'senderNameOverride': senderNameOverride,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        scriptMessageId: json['scriptMessageId'] as String,
        threadId: json['threadId'] as String,
        senderId: (json['senderId'] as String?) ?? 'system',
        messageType: MessageType.fromId(json['messageType'] as String?),
        bodyText: (json['bodyText'] as String?) ?? '',
        sequenceOrder: (json['sequenceOrder'] as num?)?.toInt() ?? 0,
        mediaFile: json['mediaFile'] as String?,
        mediaCaption: json['mediaCaption'] as String?,
        isEncrypted: (json['isEncrypted'] as bool?) ?? false,
        isDecrypted: (json['isDecrypted'] as bool?) ?? false,
        audioDuration: json['audioDuration'] as String?,
        reactionEmoji: json['reactionEmoji'] as String?,
        reactionTargetId: json['reactionTargetId'] as String?,
        inGameTimestamp: (json['inGameTimestamp'] as String?) ?? '',
        senderNameOverride: json['senderNameOverride'] as String?,
      );
}
