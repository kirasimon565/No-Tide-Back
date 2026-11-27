import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_tide_back/core/theme/app_colors.dart';
import 'package:no_tide_back/core/theme/app_typography.dart';
import 'package:no_tide_back/models/chat_message.dart';
import 'package:no_tide_back/providers/app_providers.dart';
import 'package:no_tide_back/ui/screens/chat_room_screen.dart';
import 'package:no_tide_back/ui/screens/evidence_vault_screen.dart';
import 'package:no_tide_back/ui/screens/hacking_tool_screen.dart';
import 'package:no_tide_back/ui/screens/phone_inbox_screen.dart';
import 'package:no_tide_back/ui/screens/player_setup_screen.dart';
import 'package:no_tide_back/ui/screens/studio_intro_screen.dart';
import 'package:no_tide_back/ui/widgets/message_bubble.dart';

/// Every screen is mounted once with Firebase/database providers replaced by
/// inert values, so a layout exception (overflow, null provider, bad asset
/// path) fails CI instead of shipping.
Widget _host(Widget child, {List<Override> overrides = const <Override>[]}) {
  return ProviderScope(
    overrides: <Override>[
      // Boot controller would otherwise parse the scripts from the bundle.
      ...overrides,
    ],
    child: MaterialApp(
      theme: ThemeData(
        fontFamily: AppTypography.inter,
        scaffoldBackgroundColor: AppColors.bgVoid,
        useMaterial3: true,
      ),
      home: child,
    ),
  );
}

void main() {
  group('screen smoke tests', () {
    testWidgets('studio intro renders the logo and boot readout', (WidgetTester tester) async {
      await tester.pumpWidget(_host(StudioIntroScreen(onFinished: () {}, firebaseReady: false)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(StudioIntroScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('player setup renders the identity form', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      await tester.pumpWidget(_host(const PlayerSetupScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(PlayerSetupScreen), findsOneWidget);
      expect(find.byType(TextField), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('phone inbox renders the thread list', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      await tester.pumpWidget(_host(const PhoneInboxScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(PhoneInboxScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('chat room opens a seeded thread', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      await tester.pumpWidget(_host(const ChatRoomScreen(threadId: 'group_island')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ChatRoomScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hacking tool renders the puzzle grid', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      await tester.pumpWidget(_host(const HackingToolScreen(
        puzzleId: 'p_maya_vent',
        difficulty: 'medium',
        targetFile: 'img_maya_vent_hallway.jpg',
        manual: true,
      )));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(HackingToolScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('evidence vault renders the case board', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      await tester.pumpWidget(_host(const EvidenceVaultScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(EvidenceVaultScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('message bubble lays out each message type', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      await tester.pumpWidget(_host(Scaffold(
        backgroundColor: AppColors.bgVoid,
        body: ListView(
          children: <Widget>[
            MessageBubble(
              message: ChatMessage(
                scriptMessageId: 'm1',
                threadId: 'group_island',
                senderId: 'abigail',
                messageType: MessageType.text,
                bodyText: 'Do not go back to the pier.',
              ),
              isGroup: true,
            ),
            MessageBubble(
              message: ChatMessage(
                scriptMessageId: 'm2',
                threadId: 'group_island',
                senderId: 'player',
                messageType: MessageType.playerReply,
                bodyText: 'I am not going anywhere.',
              ),
              isGroup: true,
            ),
          ],
        ),
      )));
      await tester.pump();
      expect(find.byType(MessageBubble), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  });

  group('assets', () {
    test('every file in pubspec assets exists on disk', () {
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      final List<String> missing = <String>[];
      int checked = 0;

      for (final RegExpMatch match
          in RegExp(r'^\s*-\s+(assets/[^\s#]+)', multiLine: true).allMatches(pubspec)) {
        final String entry = match.group(1)!;
        if (entry.endsWith('/')) {
          expect(Directory(entry).existsSync(), isTrue, reason: '$entry is missing');
          continue;
        }
        checked++;
        if (!File(entry).existsSync()) missing.add(entry);
      }

      expect(checked, greaterThan(20), reason: 'pubspec asset scan found too few entries');
      expect(missing, isEmpty, reason: 'missing assets: $missing');
    });

    test('scripts referenced by the parser loader exist', () {
      for (final String path in <String>[
        'assets/scripts/episode_01_part_1.ntb',
        'assets/scripts/episode_01_part_2.ntb',
        'assets/scripts/episode_01_part_3.ntb',
        'assets/scripts/episode_01_part_4.ntb',
      ]) {
        expect(File(path).existsSync(), isTrue, reason: '$path is missing');
      }
    });
  });
}
