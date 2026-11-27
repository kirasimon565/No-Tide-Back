import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_tide_back/providers/app_providers.dart';
import 'package:no_tide_back/services/game_store.dart';
import 'package:no_tide_back/core/theme/app_colors.dart';
import 'package:no_tide_back/core/theme/app_typography.dart';
import 'package:no_tide_back/models/chat_message.dart';
import 'package:no_tide_back/services/isar_service.dart';
import 'package:no_tide_back/services/local_store.dart';

import 'stub_firebase.dart';
import 'package:no_tide_back/ui/screens/chat_room_screen.dart';
import 'package:no_tide_back/ui/screens/evidence_vault_screen.dart';
import 'package:no_tide_back/ui/screens/hacking_tool_screen.dart';
import 'package:no_tide_back/ui/screens/phone_inbox_screen.dart';
import 'package:no_tide_back/ui/screens/player_setup_screen.dart';
import 'package:no_tide_back/ui/screens/studio_intro_screen.dart';
import 'package:no_tide_back/ui/widgets/message_bubble.dart';

/// Every screen is mounted once, so a layout exception (overflow, null
/// provider, bad asset path) fails CI instead of shipping. The screens read
/// their state from providers that are seeded from the local mirror, which is
/// empty in a test — exactly the first-launch path.
Widget _host(Widget child, {_OfflineGameStore? store}) {
  return ProviderScope(
    // No explicit type annotation: Riverpod 3 renamed the override type.
    overrides: [
      if (store != null) gameStoreProvider.overrideWithValue(store),
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
  // The screens hydrate from the local mirror. Opening it against the in-memory
  // preferences mock exercises the real first-launch path (empty store, seeded
  // threads) instead of the "database unavailable" guard.
  //
  // Firebase is not initialised in a widget test, so the economy comes from the
  // local fallback and the cloud-backed services are replaced with stubs.
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalStore.open();
    await IsarService.open();
  });

  late _OfflineGameStore offlineStore;

  setUp(() {
    offlineStore = _OfflineGameStore();
  });

  group('screen smoke tests', () {
    testWidgets('studio intro renders the logo and boot readout', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_host(StudioIntroScreen(onFinished: () {}, firebaseReady: false), store: offlineStore));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(StudioIntroScreen), findsOneWidget);
      // Screen 0 runs its own boot timeline (audio + 1 s skip delay + a poll
      // loop), so the assertion is that it builds and paints; unmount cleanly.
      expect(find.byType(StudioIntroScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 8));
    });

    testWidgets('player setup renders the identity form', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      await tester.pumpWidget(_host(const PlayerSetupScreen(), store: offlineStore));
      await tester.pump(const Duration(milliseconds: 300));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      expect(find.byType(PlayerSetupScreen), findsOneWidget);
      expect(find.byType(TextField), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('phone inbox renders the thread list', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      await tester.pumpWidget(_host(const PhoneInboxScreen(), store: offlineStore));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(PhoneInboxScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('chat room opens a seeded thread', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      await tester.pumpWidget(_host(const ChatRoomScreen(threadId: 'group_island'), store: offlineStore));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ChatRoomScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hacking tool renders the puzzle grid', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      await tester.pumpWidget(_host(
        const HackingToolScreen(
          puzzleId: 'p_maya_vent',
          difficulty: 'medium',
          targetFile: 'img_maya_vent_hallway.jpg',
          manual: true,
        ),
        store: offlineStore,
      ));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(HackingToolScreen), findsOneWidget);
      final List<Object> errors = <Object>[];
      Object? pending = tester.takeException();
      while (pending != null) {
        errors.add(pending);
        pending = tester.takeException();
      }
      // ignore: avoid_print
      for (final Object e in errors) print('LAYOUT ERROR hacking_tool: $e');
      expect(errors, isEmpty);
      // The puzzle owns a 1 Hz countdown timer; unmount before teardown so the
      // periodic timer is cancelled by dispose() instead of leaking.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('evidence vault renders the case board', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      await tester.pumpWidget(_host(const EvidenceVaultScreen(), store: offlineStore));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(EvidenceVaultScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('message bubble lays out each message type', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      await tester.pumpWidget(_host(
        store: offlineStore,
        Scaffold(
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
                sequenceOrder: 1,
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
                sequenceOrder: 2,
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
        checked++;
        if (entry.endsWith('/')) {
          final Directory dir = Directory(entry);
          expect(dir.existsSync(), isTrue, reason: '$entry is missing');
          expect(dir.listSync(recursive: true).whereType<File>().toList(), isNotEmpty,
              reason: '$entry is empty');
          continue;
        }
        if (!File(entry).existsSync()) missing.add(entry);
      }

      expect(checked, greaterThan(10), reason: 'pubspec asset scan found too few entries');
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

/// GameStore with no Firebase app: every cloud call falls back to the local
/// values, which is what the app does on a signed-out device.
class _OfflineGameStore extends GameStore {
  _OfflineGameStore()
      : super(auth: StubFirebaseAuth(), firestore: StubFirestore());

  @override
  Stream<Map<String, dynamic>?> watchPlayer() =>
      Stream<Map<String, dynamic>?>.value(<String, dynamic>{
        'coins': 120,
        'multimediaUnlocked': false,
      });

  @override
  Future<Map<String, dynamic>?> fetchPlayer() async => <String, dynamic>{
        'coins': 120,
        'multimediaUnlocked': false,
      };

  @override
  Future<bool> spendCoins(int cost) async => false;

  @override
  Future<User?> signInWithGoogle() async => null;
}
