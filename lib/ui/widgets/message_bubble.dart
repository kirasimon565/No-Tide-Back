import 'package:flutter/material.dart';

import '../../core/constants/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../models/chat_message.dart';
import '../widgets/common_widgets.dart';
import '../widgets/media_viewer_overlay.dart';

/// Renders one line of the thread according to its directive type.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.message,
    required this.isGroup,
    this.onDecrypt,
    this.onReveal,
    super.key,
  });

  final ChatMessage message;
  final bool isGroup;
  final VoidCallback? onDecrypt;
  final ValueChanged<String>? onReveal;

  @override
  Widget build(BuildContext context) {
    switch (message.messageType) {
      case MessageType.system:
        return _SystemBanner(text: message.bodyText);
      case MessageType.thought:
        return _ThoughtCard(text: message.bodyText);
      case MessageType.playerReply:
        return _Outgoing(text: message.bodyText, timestamp: message.inGameTimestamp);
      case MessageType.image:
        return _Incoming(
          message: message,
          isGroup: isGroup,
          onDecrypt: onDecrypt,
          onReveal: onReveal,
          child: _ImageAttachment(message: message, onDecrypt: onDecrypt, onReveal: onReveal),
        );
      case MessageType.attachmentDoc:
        return _Incoming(
          message: message,
          isGroup: isGroup,
          onDecrypt: onDecrypt,
          onReveal: onReveal,
          child: _ImageAttachment(message: message, onDecrypt: onDecrypt, onReveal: onReveal),
        );
      case MessageType.video:
        return _Incoming(
          message: message,
          isGroup: isGroup,
          onDecrypt: onDecrypt,
          onReveal: onReveal,
          child: _VideoAttachment(message: message, onDecrypt: onDecrypt),
        );
      case MessageType.audio:
        return _Incoming(
          message: message,
          isGroup: isGroup,
          onDecrypt: onDecrypt,
          onReveal: onReveal,
          child: AudioWaveformBubble(
            assetPath: message.mediaPath ?? '',
            duration: message.audioDuration ?? '00:06',
            caption: message.mediaCaption,
            accent: AppColors.forCharacter(message.senderId),
          ),
        );
      case MessageType.reaction:
        return _SystemBanner(text: '${message.senderId} reacted ${message.reactionEmoji ?? '❤'}');
      case MessageType.text:
        return _Incoming(
          message: message,
          isGroup: isGroup,
          onDecrypt: onDecrypt,
          onReveal: onReveal,
          child: Text(
            message.bodyText,
            style: AppTypography.body,
          ),
        );
    }
  }
}

class _Incoming extends StatelessWidget {
  const _Incoming({
    required this.message,
    required this.isGroup,
    required this.child,
    this.onDecrypt,
    this.onReveal,
  });

  final ChatMessage message;
  final bool isGroup;
  final Widget child;
  final VoidCallback? onDecrypt;
  final ValueChanged<String>? onReveal;

  @override
  Widget build(BuildContext context) {
    final Color accent = AppColors.forCharacter(message.senderId);
    final String name = message.senderNameOverride ??
        (AppConfig.characterNames[message.senderId] ??
            _titleCase(message.senderId));

    return Padding(
      padding: const EdgeInsets.only(bottom: 10, right: 44),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (isGroup)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text(
                name,
                style: AppTypography.label.copyWith(
                  fontSize: 11.5,
                  color: accent,
                ),
              ),
            ),
          Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.bubbleIncoming,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
                bottomRight: Radius.circular(14),
                bottomLeft: Radius.circular(4),
              ),
              border: Border.all(color: AppColors.divider, width: 0.6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                child,
                const SizedBox(height: 5),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      message.inGameTimestamp,
                      style: AppTypography.monoCaption.copyWith(fontSize: 8.5),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (message.reactionEmoji != null)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.divider, width: 0.6),
                ),
                child: Text(
                  message.reactionEmoji!,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Outgoing extends StatelessWidget {
  const _Outgoing({required this.text, required this.timestamp});

  final String text;
  final String timestamp;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 56),
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: const BoxDecoration(
            color: AppColors.bubbleOutgoing,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
              bottomLeft: Radius.circular(14),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(text, style: AppTypography.body),
              const SizedBox(height: 5),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    timestamp,
                    style: AppTypography.monoCaption.copyWith(
                      fontSize: 8.5,
                      color: AppColors.accentTide.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: 5),
                  const ReadReceipt(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SystemBanner extends StatelessWidget {
  const _SystemBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final bool danger = text.contains('WARNING') ||
        text.contains('❌') ||
        text.contains('CONNECTION LOST') ||
        text.contains('INTERFERENCE');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: danger
                ? AppColors.accentCrimson.withValues(alpha: 0.10)
                : AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: danger
                  ? AppColors.accentCrimson.withValues(alpha: 0.45)
                  : AppColors.divider,
              width: 0.7,
            ),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: AppTypography.systemBanner.copyWith(
              color: danger ? AppColors.accentCrimson : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ThoughtCard extends StatelessWidget {
  const _ThoughtCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.accentTide.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.accentTide.withValues(alpha: 0.16),
            width: 0.8,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.visibility_outlined,
              size: 13,
              color: AppColors.accentTide.withValues(alpha: 0.55),
            ),
            const SizedBox(width: 9),
            Expanded(child: Text(text, style: AppTypography.thought)),
          ],
        ),
      ),
    );
  }
}

class _ImageAttachment extends StatelessWidget {
  const _ImageAttachment({
    required this.message,
    this.onDecrypt,
    this.onReveal,
  });

  final ChatMessage message;
  final VoidCallback? onDecrypt;
  final ValueChanged<String>? onReveal;

  @override
  Widget build(BuildContext context) {
    final bool encrypted = message.needsDecryption;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        GestureDetector(
          onTap: encrypted
              ? null
              : () => showMediaViewer(
                    context,
                    imagePath: message.mediaPath ?? '',
                    title: message.mediaCaption ?? 'Attachment',
                    description: message.mediaCaption,
                    tag: 'FILE',
                  ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Container(
                  height: 168,
                  width: 250,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Image.asset(
                    encrypted
                        ? 'assets/images/overlays/overlay_vhs_static.png'
                        : (message.mediaPath ?? ''),
                    fit: BoxFit.cover,
                    errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
                        Container(
                      alignment: Alignment.center,
                      color: AppColors.surfaceElevated,
                      child: Text(
                        'MEDIA OFFLINE',
                        style: AppTypography.monoCaption.copyWith(fontSize: 9),
                      ),
                    ),
                  ),
                ),
                if (encrypted)
                  Container(
                    color: Colors.black.withValues(alpha: 0.45),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.lock_rounded, color: AppColors.accentTide, size: 20),
                        const SizedBox(height: 8),
                        Text(
                          'SIGNAL CORRUPTED',
                          style: AppTypography.monoCaption.copyWith(
                            letterSpacing: 2,
                            color: AppColors.accentTide,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (message.mediaCaption != null && message.mediaCaption!.isNotEmpty) ...<Widget>[
          const SizedBox(height: 7),
          Text(
            message.mediaCaption!,
            style: AppTypography.bodySmall.copyWith(fontSize: 12, height: 1.45),
          ),
        ],
        if (encrypted && onDecrypt != null) ...<Widget>[
          const SizedBox(height: 9),
          SizedBox(
            height: 34,
            child: FilledButton.icon(
              onPressed: onDecrypt,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: AppTypography.mono.copyWith(
                  fontSize: 10,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon: const Icon(Icons.terminal_rounded, size: 14),
              label: const Text('DECRYPT FILE'),
            ),
          ),
        ],
      ],
    );
  }
}

class _VideoAttachment extends StatelessWidget {
  const _VideoAttachment({required this.message, this.onDecrypt});

  final ChatMessage message;
  final VoidCallback? onDecrypt;

  @override
  Widget build(BuildContext context) {
    final bool encrypted = message.needsDecryption;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 250,
          height: 160,
          child: encrypted
              ? GestureDetector(
                  onTap: onDecrypt,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: Image.asset(
                            'assets/images/overlays/overlay_vhs_static.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.accentTide),
                        ),
                        child: Text(
                          'DECRYPT FILE',
                          style: AppTypography.monoCaption.copyWith(
                            letterSpacing: 2,
                            color: AppColors.accentTide,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : InlineVideoPlayer(assetPath: message.mediaPath ?? ''),
        ),
        if (message.mediaCaption != null && message.mediaCaption!.isNotEmpty) ...<Widget>[
          const SizedBox(height: 7),
          Text(
            message.mediaCaption!,
            style: AppTypography.monoCaption.copyWith(fontSize: 10, height: 1.5),
          ),
        ],
      ],
    );
  }
}

String _titleCase(String value) {
  if (value.isEmpty) return value;
  return value.substring(0, 1).toUpperCase() + value.substring(1);
}
