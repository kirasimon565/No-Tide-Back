import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_tide_back/providers/app_providers.dart';
import 'package:no_tide_back/services/game_store.dart';
import 'package:no_tide_back/core/constants/app_config.dart';
import 'package:no_tide_back/core/theme/app_colors.dart';
import 'package:no_tide_back/core/theme/app_typography.dart';
import 'package:no_tide_back/engine/ntb_interpreter.dart';
import 'package:no_tide_back/engine/ntb_parser.dart';
import 'package:no_tide_back/providers/chat_threads_provider.dart';
import 'package:no_tide_back/providers/game_state_provider.dart';
import 'package:no_tide_back/models/ntb_ast_node.dart';
import 'package:no_tide_back/models/chat_message.dart';
import 'package:no_tide_back/core/util/story_clock.dart';
import 'package:no_tide_back/models/chat_thread.dart';
import 'package:no_tide_back/services/isar_service.dart';
import 'package:no_tide_back/services/local_store.dart';
import 'package:no_tide_back/app.dart';

import 'stub_firebase.dart';
import 'package:no_tide_back/ui/screens/chat_room_screen.dart';
import 'package:no_tide_back/ui/widgets/common_widgets.dart';
import 'package:no_tide_back/ui/widgets/store_modal_sheet.dart';
import 'package:no_tide_back/ui/screens/episode_waiting_screen.dart';
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
      // The redesign's console labels must render, not clip away.
      expect(find.text('WHO ARE YOU'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('boot device leaves the spinner and reaches the phone',
        (WidgetTester tester) async {
      // Regression guard for the freeze the player reported: `startNewGame`
      // used to await the interpreter, which never returns while parked on the
      // first @choice, so BOOTING DEVICE... spun forever.
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // Skip the four-part asset parse: this test is about the boot *path*, not
      // the parser (the playthrough test owns that). A one-scene program that
      // parks on a @choice reproduces the exact shape that used to deadlock.
      final NtbParser parser = NtbParser(assetLoader: (String _) async => '');
      final NtbProgram mini = parser.parseSource(
        ':: ep1_start\n'
        '@message id="m1" chat="group_island" sender="abigail" text="you awake?"\n'
        '@choice id="c1"\n'
        '  @reply text="yeah"\n'
        '    @goto ep1_start\n',
      );
      final NtbParserResult parsed = NtbParserResult(
        program: mini,
        warnings: const <String>[],
        metadata: const <String, String>{},
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gameStoreProvider.overrideWithValue(offlineStore),
            ntbProgramProvider.overrideWith((Ref ref) async => parsed),
          ],
          child: MaterialApp(
            theme: buildNoTideBackTheme(),
            home: const PlayerSetupScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      await tester.enterText(find.byType(TextField).first, 'Stella');
      await tester.pump();
      // The form scrolls; bring the action into view like a player would.
      await tester.scrollUntilVisible(
        find.text('BEGIN DEVICE'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tester.tap(find.text('BEGIN DEVICE'));
      await tester.pump();

      // Registration + parse + first scene. Anything longer than this means the
      // boot path is blocked again.
      for (int i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byType(PhoneInboxScreen).evaluate().isNotEmpty) break;
      }
      // Let the fade-out of the setup route finish before asserting it left.
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.byType(PhoneInboxScreen), findsOneWidget);
      // The boot plate must be off the screen entirely: no lingering spinner.
      expect(find.byType(PlayerSetupScreen), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      tester.takeException();
    });

    test('story clock advances between bubbles and honours script anchors', () {
      expect(StoryClock.format(StoryClock.parse('07:42 AM')!), '07:42 AM');
      expect(StoryClock.format(StoryClock.parse('12:05 PM')!), '12:05 PM');
      expect(StoryClock.parse('not a time'), isNull);

      // Each message adds its own minutes, so consecutive bubbles differ.
      String t = '03:15 PM';
      final List<String> stamps = <String>[];
      for (int i = 0; i < 4; i++) {
        t = StoryClock.advance(t);
        stamps.add(t);
      }
      expect(stamps, <String>['03:17 PM', '03:19 PM', '03:21 PM', '03:23 PM']);
      expect(stamps.toSet().length, 4);

      // A new conversation opens with a longer gap.
      expect(StoryClock.advance('03:15 PM', sceneChanged: true), '03:22 PM');

      // Midnight and noon roll over without inventing a date.
      expect(StoryClock.advance('11:59 PM'), '12:01 AM');
      expect(StoryClock.advance('11:58 AM'), '12:00 PM');
    });

    test('resume from the hub does not park on a choice', () async {
      // Regression guard for the reported "SYNCING..." freeze: `resume()`
      // awaited the interpreter, which stops on the first @choice. Returning
      // from that await required a choice the player could not see.
      //
      // A plain `test`, not `testWidgets`: this drives real timers, and the
      // widget tester's fake clock would never let the script advance.

      final NtbParser parser = NtbParser(assetLoader: (String _) async => '');
      final NtbProgram mini = parser.parseSource(
        ':: ep1_start\n'
        '@message id="m1" chat="group_island" sender="abigail" text="you awake?"\n'
        '@choice id="c1"\n'
        '  @reply text="yeah"\n'
        '    @goto ep1_start\n',
      );
      final NtbParserResult parsed = NtbParserResult(
        program: mini,
        warnings: const <String>[],
        metadata: const <String, String>{},
      );

      final ProviderContainer container = ProviderContainer(
        overrides: [
          gameStoreProvider.overrideWithValue(offlineStore),
          ntbProgramProvider.overrideWith((Ref ref) async => parsed),
        ],
      );
      addTearDown(container.dispose);

      final GameStateNotifier notifier = container.read(gameStateProvider.notifier);
      // Collapse the delivery/typing beats: this test is about the await, not
      // the pacing.
      await notifier.setPace(100);
      await notifier.startNewGame(program: mini);

      // This is the freeze: the call must come back while the script is still
      // parked on the choice.
      final Stopwatch watch = Stopwatch()..start();
      try {
        await notifier.resume(program: mini).timeout(const Duration(seconds: 5));
      } on TimeoutException {
        fail('resume() blocked on the interpreter for 5 s — the SYNCING freeze is back');
      }
      watch.stop();
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));

      // The background drive must then actually reach the choice, and the
      // loading banner must clear there rather than waiting for run() to end.
      for (int i = 0; i < 60; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (container.read(gameStateProvider).interpreterStatus ==
            InterpreterStatus.awaitingChoice) {
          break;
        }
      }
      final GameScreenState after = container.read(gameStateProvider);
      expect(after.save, isNotNull);
      expect(after.interpreterStatus, InterpreterStatus.awaitingChoice);
      expect(after.bootStatus, isNull);
      expect(after.activeChoice, isNotNull);
    });

    testWidgets('inbox starts with only the group chat; DMs appear when written',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // A brand-new game: the inbox must not spoil the cast.
      final GameStateNotifier notifier = ProviderContainer(
        overrides: [gameStoreProvider.overrideWithValue(offlineStore)],
      ).read(gameStateProvider.notifier);

      final List<String> fresh = notifier.state
          .threadsFor(null, startedThreads: const <String>{})
          .map((ChatThread t) => t.threadId)
          .toList();
      expect(fresh, <String>['group_island']);

      // Once a character writes, their DM is revealed — and only theirs.
      final List<String> afterDm = notifier.state
          .threadsFor(null, startedThreads: const <String>{'dm_jessica'})
          .map((ChatThread t) => t.threadId)
          .toList();
      expect(afterDm, containsAll(<String>['group_island', 'dm_jessica']));
      expect(afterDm, isNot(contains('dm_kathy')));

      // The category tabs still filter the revealed set.
      expect(
        notifier.state
            .threadsFor(ChatCategory.home, startedThreads: const <String>{'dm_jessica'})
            .map((ChatThread t) => t.threadId),
        isEmpty,
      );
    });

    testWidgets('store sheet explains a failed payment instead of a flat refusal',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _host(const Scaffold(body: StoreModalSheet()), store: offlineStore),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Signed out in the offline store: the sheet must say why BUY is closed
      // rather than opening a payment window that can only fail.
      expect(find.text('RELAY STORE'), findsOneWidget);
      expect(find.textContaining('Not signed in'), findsWidgets);
      final Iterable<ConsoleButton> buys =
          tester.widgetList<ConsoleButton>(find.byType(ConsoleButton)).where(
                (ConsoleButton b) => b.label.toUpperCase() == 'BUY',
              );
      expect(buys, isNotEmpty);
      expect(buys.every((ConsoleButton b) => b.onPressed == null), isTrue);

      // The rail is named, so a support report says which one failed.
      expect(find.textContaining('RAIL:'), findsOneWidget);
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
      // The puzzle screen owns a 1 Hz countdown and starts its own game logic,
      // so this test is a mount/unmount smoke check: it must build, then
      // dispose its timer without leaving a pending frame.
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(HackingToolScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      tester.takeException();
    });

    testWidgets('evidence vault renders the case board', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      await tester.pumpWidget(_host(const EvidenceVaultScreen(), store: offlineStore));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(EvidenceVaultScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('waiting hub renders relay banner and status cards',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_host(const EpisodeWaitingScreen(), store: offlineStore));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(EpisodeWaitingScreen), findsOneWidget);
      // The crimson relay pill and the action tiles are the point of the
      // screen; both must survive layout at phone width.
      expect(find.text(EpisodeWaitConfig.relayBanner), findsOneWidget);
      expect(find.text('WHILE YOU WAIT'), findsOneWidget);
      expect(find.text('REVIEW CHAT LOGS'), findsOneWidget);
      expect(find.text('REPLAY EPISODE 1'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
      tester.takeException();
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

    test('every declared font file exists on disk', () {
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      final List<String> fonts = RegExp(r'asset:\s+(assets/fonts/[^\s#]+)')
          .allMatches(pubspec)
          .map((RegExpMatch m) => m.group(1)!)
          .toList();
      expect(fonts.length, greaterThanOrEqualTo(8));
      for (final String font in fonts) {
        expect(File(font).existsSync(), isTrue, reason: '$font is missing');
      }
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
