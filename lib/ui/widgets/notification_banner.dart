import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/game_state_provider.dart';
import 'chat_room_screen_route.dart';

/// Interactive top banner raised by `@notification` when the player is reading a
/// different thread. Tapping it jumps straight into the pinged chat.
class NotificationBannerHost extends ConsumerStatefulWidget {
  const NotificationBannerHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<NotificationBannerHost> createState() => _NotificationBannerHostState();
}

class _NotificationBannerHostState extends ConsumerState<NotificationBannerHost> {
  InAppNotification? _shown;
  Timer? _timer;

  void _scheduleDismiss(InAppNotification notification) {
    _timer?.cancel();
    _timer = Timer(notification.at, () {
      if (!mounted) return;
      ref.read(gameStateProvider.notifier).dismissNotification();
    });
  }

  Future<void> _open(InAppNotification notification) async {
    final GameStateNotifier notifier = ref.read(gameStateProvider.notifier);
    notifier.dismissNotification();
    await notifier.openThread(notification.threadId);
    if (!mounted) return;
    // Already inside a chat: open the pinged thread on top of the stack.
    final NavigatorState navigator = Navigator.of(context);
    if (navigator.canPop()) {
      await navigator.push(chatRoomRoute(notification.threadId));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GameScreenState state = ref.watch(gameStateProvider);
    final InAppNotification? notification = state.pendingNotification;

    if (notification != null && notification != _shown) {
      _shown = notification;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleDismiss(notification));
    }

    return Stack(
      children: <Widget>[
        Positioned.fill(child: widget.child),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: AnimatedSlide(
              offset: notification == null ? const Offset(0, -1.4) : Offset.zero,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: notification == null ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: notification == null
                    ? const SizedBox(height: 0)
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _open(notification),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceCard,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: AppColors.accentTide.withValues(alpha: 0.55),
                                ),
                                boxShadow: const <BoxShadow>[
                                  BoxShadow(
                                    color: Color(0x66000000),
                                    blurRadius: 18,
                                    offset: Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: <Widget>[
                                  const Icon(
                                    Icons.notifications_active_rounded,
                                    size: 17,
                                    color: AppColors.accentTide,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          '${notification.senderName.toUpperCase()} • NEW MESSAGE',
                                          style: AppTypography.monoCaption.copyWith(
                                            fontSize: 8.5,
                                            letterSpacing: 1.2,
                                            color: AppColors.accentTide,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          notification.text,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTypography.bodySmall.copyWith(
                                            fontSize: 12.5,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                    onPressed: () =>
                                        ref.read(gameStateProvider.notifier).dismissNotification(),
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 15,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
