import 'package:flutter/material.dart';

import '../screens/chat_room_screen.dart';

/// Fade-through route used by the inbox → chat transition.
Route<void> chatRoomRoute(String threadId) => PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (BuildContext context, Animation<double> animation, Animation<double> secondary) =>
          ChatRoomScreen(threadId: threadId),
      transitionsBuilder: (BuildContext context, Animation<double> animation, Animation<double> secondary, Widget child) {
        final Animation<double> curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.04, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
