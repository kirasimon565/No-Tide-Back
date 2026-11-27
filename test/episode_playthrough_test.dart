import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_tide_back/engine/ntb_interpreter.dart';
import 'package:no_tide_back/engine/ntb_parser.dart';
import 'package:no_tide_back/models/chat_message.dart';
import 'package:no_tide_back/models/chat_thread.dart';
import 'package:no_tide_back/models/evidence_item.dart';
import 'package:no_tide_back/models/ntb_ast_node.dart';
import 'package:no_tide_back/models/player_profile.dart';

/// Drives the real four-part episode script end to end with a scripted player.
///
/// This is the closest thing to a playthrough that runs without a device: it
/// catches unbalanced `@if` chains, dangling `@goto` targets, missing choice
/// bodies, directive argument regressions and interpolation crashes.
class _RecordingRuntime implements NtbRuntime {
  _RecordingRuntime({this.premiumUnlocked = false});

  final bool premiumUnlocked;

  final List<ChatMessage> messages = <ChatMessage>[];
  final List<String> notifications = <String>[];
  final List<String> evidence = <String>[];
  final List<String> achievements = <String>[];
  final List<String> uiOpens = <String>[];
  final List<String> threadsTouched = <String>[];
  final List<String> sounds = <String>[];
  final List<String> scenes = <String>[];

  int choiceCount = 0;
  int premiumChoices = 0;
  int puzzles = 0;
  int inputs = 0;
  bool ended = false;
  String? endTitle;

  @override
  void onMessage(ChatMessage message) => messages.add(message);

  @override
  void onThreadUpdate(String threadId, {ThreadStatus? status, ChatMessage? message}) {
    if (!threadsTouched.contains(threadId)) threadsTouched.add(threadId);
  }

  @override
  void onNotification({required String threadId, required String senderName, required String text}) {
    notifications.add('$threadId|$senderName|$text');
  }

  @override
  void onUiOpen(String threadId) => uiOpens.add(threadId);

  @override
  void onEnvironment({String? time, String? location, String? weather, String? network}) {}

  @override
  void onEvidence(EvidenceItem item) => evidence.add(item.evidenceId);

  @override
  void onReaction({
    required String threadId,
    required String targetMessageId,
    required String senderId,
    required String emoji,
  }) {}

  @override
  void onSound(String file) => sounds.add(file);

  @override
  void onMusic(String file, {bool loop = true, double volume = 0.5}) => sounds.add(file);

  @override
  void onStopMusic({double fadeOut = 1}) {}

  @override
  void onVibration(String pattern) {}

  @override
  void onCameraEffect(String effect, double duration) {}

  @override
  void onShowText(String text, double duration) {}

  @override
  void onFade({required bool toBlack, double duration = 1}) {}

  @override
  void onNetwork({String? request, String? response}) {}

  @override
  void onCheckpoint({
    required int instructionPointer,
    required String sceneLabel,
    bool force = false,
  }) {
    if (scenes.isEmpty || scenes.last != sceneLabel) scenes.add(sceneLabel);
  }

  @override
  void onAchievement(String id, String title, String description) => achievements.add(id);

  @override
  void onEndScene(String title, String? nextEpisode) {
    ended = true;
    endTitle = title;
  }

  @override
  Future<String> onLaunchHackingTool({
    required String puzzleId,
    required String difficulty,
    required String targetFile,
  }) async {
    puzzles++;
    return 'success';
  }

  @override
  void onDatabaseLookup(String query) {}

  @override
  Future<bool?> requestPremiumUnlock({
    required String choiceId,
    required int cost,
    required String text,
  }) async {
    premiumChoices++;
    return premiumUnlocked;
  }

  @override
  Future<NtbNode?> requestChoice(List<NtbNode> options) async {
    choiceCount++;
    // Always take the *last* option: the script branches differ per option, so
    // picking the tail walks a different path than picking the head.
    return options.last;
  }

  @override
  Future<void> waitForPlayerInput(String prompt) async => inputs++;

  @override
  bool get isMuted => false;

  @override
  PlayerProfile get profile => const PlayerProfile(
        playerName: 'Rae',
        gender: PlayerGender.female,
      );

  @override
  String get currentTime => '03:14';

  @override
  String interpolate(String text) {
    final String name = profile.playerName;
    return text
        .replaceAll('{player_name}', name)
        .replaceAll('{they}', profile.gender.pronounThey)
        .replaceAll('{them}', profile.gender.pronounThem)
        .replaceAll('{their}', profile.gender.pronounTheir)
        .replaceAll('{bro_sis}', profile.gender.broSis);
  }
}

/// Real file loader so the test parses the shipping scripts, not a fixture.
Future<NtbProgram> _parseRealEpisode() {
  final NtbParser parser = NtbParser(
    assetLoader: (String path) async => File(path).readAsString(),
  );
  return parser.parseEpisode();
}

/// Runs the episode with a hard instruction budget so a control-flow bug fails
/// the test instead of hanging CI.
Future<_RecordingRuntime> _play({
  bool premiumUnlocked = false,
}) async {
  final NtbProgram program = await _parseRealEpisode();
  final _RecordingRuntime runtime = _RecordingRuntime(premiumUnlocked: premiumUnlocked);
  final NtbInterpreter interpreter = NtbInterpreter(
    program: program,
    runtime: runtime,
    paceMultiplier: 0, // no real waiting in tests
  );

  // `run()` returns whenever it needs the player; keep going until the script
  // ends, the interpreter parks, or the budget is exhausted.
  for (int i = 0; i < 400; i++) {
    await interpreter.run();
    if (runtime.ended) break;
    final InterpreterStatus status = interpreter.status;
    if (status == InterpreterStatus.ended) break;
    if (status == InterpreterStatus.paused || status == InterpreterStatus.idle) break;
    if (status == InterpreterStatus.awaitingChoice ||
        status == InterpreterStatus.awaitingInput) {
      interpreter.resume();
      continue;
    }
    break;
  }
  return runtime;
}

void main() {
  group('Episode 1 playthrough (real scripts)', () {
    test('parses all four parts into one program', () async {
      final NtbProgram program = await _parseRealEpisode();
      expect(program.partStartIndex.keys, containsAll(<int>[1, 2, 3, 4]));
      expect(program.instructions.length, greaterThan(1000));
      expect(program.sceneIndex.length, 38);
      // Part ordering is strictly increasing.
      final List<int> starts = program.partStartIndex.values.toList()..sort();
      expect(starts.first, 0);
      expect(starts, orderedEquals(starts.toSet().toList()));
    });

    test('every @goto target resolves to a scene label', () async {
      final NtbParser parser = NtbParser(
        assetLoader: (String path) async => File(path).readAsString(),
      );
      final NtbProgram program = await parser.parseEpisode();
      expect(parser.warnings.where((String w) => w.contains('goto')), isEmpty);

      final Set<String> labels = program.sceneIndex.keys.toSet();
      int gotos = 0;
      for (final NtbNode node in program.instructions) {
        if (node.name != 'goto') continue;
        gotos++;
        final String target = node.param('label', node.freeArgs).trim();
        expect(labels, contains(target), reason: 'line ${node.lineNumber} → $target');
      }
      expect(gotos, 68);
    });

    test('plays from the first scene to the stinger without premium', () async {
      final _RecordingRuntime run = await _play();

      expect(run.messages, isNotEmpty, reason: 'no dialogue was emitted');
      expect(run.choiceCount, greaterThan(10), reason: 'choices never fired');
      expect(run.scenes.length, greaterThan(20), reason: 'too few scenes visited');
      expect(run.ended || run.endTitle != null, isTrue, reason: 'episode never ended');

      // Content sanity: no unresolved script tokens leaked into the UI.
      for (final ChatMessage message in run.messages) {
        expect(message.bodyText, isNot(contains('{player_name}')));
        expect(message.bodyText, isNot(contains('{they}')));
        expect(message.bodyText, isNot(contains('{them}')));
        expect(message.bodyText, isNot(contains('{their}')));
        expect(message.bodyText, isNot(contains('{bro_sis}')));
      }
      expect(
        run.messages.any((ChatMessage m) => m.bodyText.contains('Rae')),
        isTrue,
        reason: 'player name was never interpolated',
      );
    });

    test('multimedia-owned run unlocks the premium branches', () async {
      final _RecordingRuntime locked = await _play();
      final _RecordingRuntime unlocked = await _play(premiumUnlocked: true);

      expect(unlocked.premiumChoices, greaterThan(0));
      // Owning the pack opens bonus scenes, so the unlocked run must not be
      // shorter than the coin-gated one.
      expect(
        unlocked.messages.length + unlocked.evidence.length,
        greaterThanOrEqualTo(locked.messages.length + locked.evidence.length),
      );
    });

    test('emits evidence, notifications and sound cues', () async {
      final _RecordingRuntime run = await _play();
      expect(run.evidence, isNotEmpty, reason: '@add_evidence never fired');
      expect(run.notifications, isNotEmpty, reason: '@notification never fired');
      expect(run.sounds, isNotEmpty, reason: '@sound/@music never fired');
      expect(run.achievements, isNotEmpty, reason: '@unlock_achievement never fired');
    });
  });
}
