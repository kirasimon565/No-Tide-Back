import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/ntb_interpreter.dart';
import '../models/chat_message.dart';
import '../models/chat_thread.dart';
import '../models/evidence_item.dart';
import '../models/game_save_state.dart';
import '../models/ntb_ast_node.dart';
import '../models/player_profile.dart';
import '../services/cloud_save_service.dart';
import '../services/isar_service.dart';
import 'app_providers.dart';
import 'auth_store_provider.dart';

/// Immutable view of the simulated phone (Screen 4 / 5 chrome).
class GameScreenState {
  const GameScreenState({
    this.threads = const <ChatThread>[],
    this.openThreadId,
    this.evidence = const <EvidenceItem>[],
    this.environmentTime = '07:42 AM',
    this.environmentLocation = 'Home - Bedroom',
    this.environmentWeather = 'Clear',
    this.networkStatus = 'ONLINE',
    this.batteryLevel = 82,
    this.signalStrength = 4,
    this.unreadByThread = const <String, int>{},
    this.pendingNotification,
    this.activeChoice,
    this.pendingChoiceCost,
    this.pendingChoiceId,
    this.interpreterStatus = InterpreterStatus.idle,
    this.puzzleRequest,
    this.fadeToBlack = false,
    this.showTextBanner,
    this.cameraEffect,
    this.ending,
    this.achievements = const <String>[],
    this.isMuted = false,
    this.paceMultiplier = 1.0,
    this.isRunning = false,
    this.lastSyncedAt,
    this.save,
  });

  final List<ChatThread> threads;
  final String? openThreadId;
  final List<EvidenceItem> evidence;
  final String environmentTime;
  final String environmentLocation;
  final String environmentWeather;
  final String networkStatus;
  final int batteryLevel;
  final int signalStrength;
  final Map<String, int> unreadByThread;

  /// In-app banner for a ping in a thread the player is not looking at.
  final InAppNotification? pendingNotification;

  /// Options of the choice drawer currently on screen.
  final List<NtbNode>? activeChoice;
  final int? pendingChoiceCost;
  final String? pendingChoiceId;
  final InterpreterStatus interpreterStatus;
  final HackingRequest? puzzleRequest;

  final bool fadeToBlack;
  final String? showTextBanner;
  final String? cameraEffect;
  final EpisodeEnding? ending;
  final List<String> achievements;
  final bool isMuted;
  final double paceMultiplier;
  final bool isRunning;
  final DateTime? lastSyncedAt;
  final GameSaveState? save;

  int get unreadTotal =>
      unreadByThread.values.fold<int>(0, (int sum, int v) => sum + v);

  int get evidenceCount => evidence.length;

  List<ChatThread> threadsFor(ChatCategory? category) {
    final List<ChatThread> source = category == null
        ? threads
        : threads.where((ChatThread t) => t.category == category).toList();
    return List<ChatThread>.unmodifiable(source);
  }

  ChatThread? thread(String? id) {
    if (id == null) return null;
    for (final ChatThread t in threads) {
      if (t.threadId == id) return t;
    }
    return null;
  }

  GameScreenState copyWith({
    List<ChatThread>? threads,
    String? openThreadId,
    bool clearOpenThread = false,
    List<EvidenceItem>? evidence,
    String? environmentTime,
    String? environmentLocation,
    String? environmentWeather,
    String? networkStatus,
    int? batteryLevel,
    int? signalStrength,
    Map<String, int>? unreadByThread,
    InAppNotification? pendingNotification,
    bool clearNotification = false,
    List<NtbNode>? activeChoice,
    bool clearChoice = false,
    int? pendingChoiceCost,
    String? pendingChoiceId,
    InterpreterStatus? interpreterStatus,
    HackingRequest? puzzleRequest,
    bool clearPuzzle = false,
    bool? fadeToBlack,
    String? showTextBanner,
    bool clearTextBanner = false,
    String? cameraEffect,
    bool clearCameraEffect = false,
    EpisodeEnding? ending,
    bool clearEnding = false,
    List<String>? achievements,
    bool? isMuted,
    double? paceMultiplier,
    bool? isRunning,
    DateTime? lastSyncedAt,
    GameSaveState? save,
  }) =>
      GameScreenState(
        threads: threads ?? this.threads,
        openThreadId: clearOpenThread ? null : (openThreadId ?? this.openThreadId),
        evidence: evidence ?? this.evidence,
        environmentTime: environmentTime ?? this.environmentTime,
        environmentLocation: environmentLocation ?? this.environmentLocation,
        environmentWeather: environmentWeather ?? this.environmentWeather,
        networkStatus: networkStatus ?? this.networkStatus,
        batteryLevel: batteryLevel ?? this.batteryLevel,
        signalStrength: signalStrength ?? this.signalStrength,
        unreadByThread: unreadByThread ?? this.unreadByThread,
        pendingNotification:
            clearNotification ? null : (pendingNotification ?? this.pendingNotification),
        activeChoice: clearChoice ? null : (activeChoice ?? this.activeChoice),
        pendingChoiceCost: pendingChoiceCost ?? this.pendingChoiceCost,
        pendingChoiceId: pendingChoiceId ?? this.pendingChoiceId,
        interpreterStatus: interpreterStatus ?? this.interpreterStatus,
        puzzleRequest: clearPuzzle ? null : (puzzleRequest ?? this.puzzleRequest),
        fadeToBlack: fadeToBlack ?? this.fadeToBlack,
        showTextBanner:
            clearTextBanner ? null : (showTextBanner ?? this.showTextBanner),
        cameraEffect: clearCameraEffect ? null : (cameraEffect ?? this.cameraEffect),
        ending: clearEnding ? null : (ending ?? this.ending),
        achievements: achievements ?? this.achievements,
        isMuted: isMuted ?? this.isMuted,
        paceMultiplier: paceMultiplier ?? this.paceMultiplier,
        isRunning: isRunning ?? this.isRunning,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        save: save ?? this.save,
      );
}

class InAppNotification {
  const InAppNotification({
    required this.threadId,
    required this.senderName,
    required this.text,
    this.at = const Duration(seconds: 4),
  });

  final String threadId;
  final String senderName;
  final String text;
  final Duration at;
}

class HackingRequest {
  const HackingRequest({
    required this.puzzleId,
    required this.difficulty,
    required this.targetFile,
    required this.completer,
  });

  final String puzzleId;
  final String difficulty;
  final String targetFile;

  /// Resolves the suspended `@custom action="launch_hacking_tool"`.
  final Completer<String> completer;
}

class EpisodeEnding {
  const EpisodeEnding({
    required this.title,
    this.nextEpisode,
    this.evidenceCount = 0,
    this.trust = const <String, int>{},
  });

  final String title;
  final String? nextEpisode;
  final int evidenceCount;
  final Map<String, int> trust;
}

/// Owns the interpreter, the local mirror and every directive side effect.
class GameStateNotifier extends Notifier<GameScreenState> implements NtbRuntime {
  IsarService? _db;
  NtbInterpreter? _interpreter;
  NtbProgram? _program;
  PlayerProfile _profile = const PlayerProfile();

  /// True once the player has completed Screen 3, so a cloud checkpoint never
  /// overwrites an existing profile with the default one.
  bool _profileSet = false;
  final Map<String, List<ChatMessage>> _messages = <String, List<ChatMessage>>{};
  Completer<NtbNode?>? _choiceCompleter;
  Completer<void>? _inputCompleter;
  bool _syncing = false;
  String _saveSlot = 'active';

  IsarService get db {
    final IsarService? service = _db;
    if (service == null) throw StateError('Local mirror is not open yet');
    return service;
  }

  @override
  GameScreenState build() {
    ref.onDispose(() {
      _interpreter?.requestStop();
    });
    // Hydrate synchronously from the local mirror so the first paint already
    // shows the inbox. Screen 0 guarantees the DB is open before any screen
    // reads this provider; the guard keeps widget tests able to build it.
    final IsarService? service = IsarService.available;
    _db = service;
    if (service == null) {
      return const GameScreenState(threads: ChatThreads.seed);
    }
    _profile = service.loadProfile();
    _profileSet = service.readProfileRaw() != null;
    final List<ChatThread> threads = service.loadThreads();
    final GameSaveState? save = service.activeSave;
    final List<EvidenceItem> evidence = service.loadEvidence();
    for (final ChatThread thread in threads) {
      _messages[thread.threadId] = service.loadMessages(thread.threadId);
    }

    return GameScreenState(
      threads: threads,
      evidence: evidence,
      save: save,
      environmentTime: save?.environmentTime ?? '07:42 AM',
      environmentLocation: save?.environmentLocation ?? 'Home - Bedroom',
      environmentWeather: save?.environmentWeather ?? 'Clear',
      achievements: save?.achievements ?? const <String>[],
      unreadByThread: const <String, int>{},
    );
  }

  // ------------------------------------------------------------------ profile
  PlayerProfile get profile => _profile;

  Future<void> saveProfile(PlayerProfile profile) async {
    _profile = profile;
    _profileSet = true;
    await db.saveProfile(profile);
    final AuthUserInfo? auth = ref.read(authUserProvider).value;
    if (auth != null && auth.isSignedIn) {
      await ref.read(gameStoreProvider).saveProfile(profile);
    }
  }

  // ------------------------------------------------------------- interpreter
  /// Starts a brand new playthrough at `:: ep1_start`.
  Future<void> startNewGame({NtbProgram? program}) async {
    final NtbProgram resolved =
        program ?? (await ref.read(ntbProgramProvider.future)).program;
    _program = resolved;

    await db.clearMessages();
    for (final ChatThread thread in ChatThreads.seed) {
      _messages[thread.threadId] = <ChatMessage>[];
    }
    _messages['system'] = <ChatMessage>[];

    await db.saveEvidence(<EvidenceItem>[]);
    await db.saveThreads(ChatThreads.seed);

    final GameSaveState fresh = GameSaveState.fresh.copyWith(
      slotId: 'active',
      variables: <String, dynamic>{
        ...GameSaveState.fresh.variables,
        'multimedia_package_owned':
            ref.read(economyProvider).multimediaUnlocked,
        'player_name': _profile.playerName,
      },
      updatedAt: DateTime.now(),
    );
    await db.saveActive(fresh);

    state = state.copyWith(
      threads: ChatThreads.seed,
      evidence: const <EvidenceItem>[],
      save: fresh,
      unreadByThread: const <String, int>{},
      environmentTime: '07:42 AM',
      environmentLocation: 'Home - Bedroom',
      environmentWeather: 'Clear',
      achievements: const <String>[],
      clearChoice: true,
      clearEnding: true,
      clearOpenThread: true,
      isRunning: false,
      interpreterStatus: InterpreterStatus.idle,
    );

    _interpreter = NtbInterpreter(
      program: resolved,
      runtime: this,
      initialVariables: fresh.variables,
      paceMultiplier: state.paceMultiplier,
    );
    await _interpreter!.run();
    _publishStatus();
  }

  /// Resumes the stored pointer (Home Hub → RESUME RELAY).
  Future<void> resume({NtbProgram? program}) async {
    final GameSaveState? save = state.save ?? db.activeSave;
    final NtbProgram? resolved = program ?? _program;
    if (save == null || resolved == null) {
      await startNewGame(program: program);
      return;
    }
    _program = resolved;
    _interpreter = NtbInterpreter(
      program: resolved,
      runtime: this,
      initialVariables: <String, dynamic>{
        ...save.variables,
        'multimedia_package_owned': ref.read(economyProvider).multimediaUnlocked,
      },
      startIndex: save.instructionPointerIndex.clamp(0, resolved.length - 1).toInt(),
      paceMultiplier: state.paceMultiplier,
    );
    state = state.copyWith(
      environmentTime: save.environmentTime,
      environmentLocation: save.environmentLocation,
      environmentWeather: save.environmentWeather,
      isRunning: true,
    );
    await _interpreter!.run();
    _publishStatus();
  }

  void _publishStatus() {
    final NtbInterpreter? interpreter = _interpreter;
    if (interpreter == null) return;
    state = state.copyWith(
      interpreterStatus: interpreter.status,
      isRunning: interpreter.status == InterpreterStatus.running,
    );
  }

  Future<void> chooseOption(NtbNode option) async {
    final Completer<NtbNode?>? completer = _choiceCompleter;
    _choiceCompleter = null;
    state = state.copyWith(clearChoice: true, pendingChoiceCost: -1, pendingChoiceId: '');
    completer?.complete(option);
    await _interpreter?.run();
    _publishStatus();
  }

  void dismissChoice() {
    final Completer<NtbNode?>? completer = _choiceCompleter;
    _choiceCompleter = null;
    state = state.copyWith(clearChoice: true);
    completer?.complete(null);
    _publishStatus();
  }

  /// Called by the store sheet: retry the blocked premium option.
  Future<void> retryPendingChoice() async {
    await _interpreter?.run();
    _publishStatus();
  }

  void tapToContinue() {
    final Completer<void>? completer = _inputCompleter;
    _inputCompleter = null;
    _publishStatus();
    completer?.complete();
  }

  Future<void> setPace(double multiplier) async {
    state = state.copyWith(paceMultiplier: multiplier);
    _interpreter?.paceMultiplier = multiplier;
  }

  Future<void> toggleMute() async {
    final bool muted = !state.isMuted;
    ref.read(audioServiceProvider).setMuted(muted);
    state = state.copyWith(isMuted: muted);
  }

  // -------------------------------------------------------------------- inbox
  Future<void> openThread(String threadId) async {
    final Map<String, int> unread = Map<String, int>.from(state.unreadByThread)
      ..remove(threadId);
    state = state.copyWith(
      openThreadId: threadId,
      unreadByThread: unread,
      clearNotification: true,
    );
    _interpreter?.activeThread = threadId;
    await _persistThreadState();
  }

  void closeThread() {
    state = state.copyWith(clearOpenThread: true);
    _interpreter?.activeThread = null;
  }

  List<ChatMessage> messagesFor(String threadId) =>
      List<ChatMessage>.unmodifiable(
        _messages[threadId] ?? const <ChatMessage>[],
      );

  void dismissNotification() => state = state.copyWith(clearNotification: true);

  /// Auto-dismiss the in-app banner after its display window.
  void scheduleNotificationDismissal(Duration after) {
    Timer(after, () {
      if (state.pendingNotification != null) dismissNotification();
    });
  }

  // ------------------------------------------------------------ save handling
  Future<void> autosaveNow({String? slotId, bool force = false}) async {
    if (_syncing) return;
    _syncing = true;
    final bool forceSync = force;
    try {
      final NtbInterpreter? interpreter = _interpreter;
      final GameSaveState next = (state.save ?? GameSaveState.fresh).copyWith(
        slotId: slotId ?? _saveSlot,
        episodeNumber: 1,
        partNumber: (interpreter?.variables['current_part'] as num?)?.toInt() ?? 1,
        currentSceneLabel: interpreter?.sceneLabel ?? state.save?.currentSceneLabel,
        instructionPointerIndex: interpreter?.instructionPointer ?? 0,
        environmentTime: state.environmentTime,
        environmentLocation: state.environmentLocation,
        environmentWeather: state.environmentWeather,
        variables: <String, dynamic>{
          ...?interpreter?.variables,
          'multimedia_package_owned': ref.read(economyProvider).multimediaUnlocked,
          'player_name': _profile.playerName,
        },
        unlockedEvidenceIds:
            state.evidence.map((EvidenceItem e) => e.evidenceId).toList(),
        achievements: state.achievements,
        updatedAt: DateTime.now(),
      );

      await db.saveGame(next.slotId, next);
      if (next.slotId == 'active') await db.saveActive(next);
      state = state.copyWith(save: next);

      final AuthUserInfo? auth = ref.read(authUserProvider).value;
      if (auth != null && auth.isSignedIn) {
        final String uid = auth.uid!;
        final CloudSaveService cloud =
            await ref.read(cloudSaveServiceProvider.future);
        if (next.slotId == 'active') {
          await cloud.pushActiveSave(
            uid,
            next,
            profile: _profileSet ? _profile : null,
          );
        } else {
          await cloud.pushSlot(uid, next.slotId, next);
        }
        if (forceSync) {
          await cloud.pushEvidence(uid, state.evidence);
        }
        state = state.copyWith(lastSyncedAt: DateTime.now());
      }
      await _persistThreadState();
    } catch (error) {
      // Offline is fine: the local mirror already has the checkpoint.
      // ignore: avoid_print
      print('GameStateNotifier.autosaveNow: $error');
    } finally {
      _syncing = false;
    }
  }

  Future<void> _persistThreadState() async {
    await db.saveThreads(state.threads);
    for (final MapEntry<String, List<ChatMessage>> entry in _messages.entries) {
      await db.saveMessages(entry.key, entry.value);
    }
    await db.saveEvidence(state.evidence);
  }

  /// Loads a cloud/local slot (Saves & Chapters modal).
  Future<void> loadSlot(String slotId) async {
    GameSaveState? save = db.loadSave(slotId);
    final AuthUserInfo? auth = ref.read(authUserProvider).value;
    if (auth != null && auth.isSignedIn) {
      final CloudSaveService cloud =
          await ref.read(cloudSaveServiceProvider.future);
      save = await cloud.loadSlot(auth.uid!, slotId) ?? save;
    }
    if (save == null) return;
    _saveSlot = 'active';
    await db.saveActive(save.copyWith(slotId: 'active'));
    state = state.copyWith(
      save: save,
      environmentTime: save.environmentTime,
      environmentLocation: save.environmentLocation,
      environmentWeather: save.environmentWeather,
      achievements: save.achievements,
    );
    await resume();
  }

  List<SaveSlotInfo> slots() {
    final List<SaveSlotInfo> result = <SaveSlotInfo>[];
    for (int i = 1; i <= 3; i++) {
      final String id = 'save_slot_$i';
      result.add(
        SaveSlotInfo(
          slotId: id,
          title: 'Slot $i',
          subtitle: db.loadSave(id) == null ? 'EMPTY' : 'SAVED',
          save: db.loadSave(id),
        ),
      );
    }
    return result;
  }

  Future<void> saveToSlot(String slotId) => autosaveNow(slotId: slotId, force: true);

  Future<void> resetProgress() async {
    await db.clearMessages();
    await db.deleteSave('active');
    for (int i = 1; i <= 3; i++) {
      await db.deleteSave('save_slot_$i');
    }
    await db.saveEvidence(<EvidenceItem>[]);
    _messages.clear();
    state = GameScreenState(threads: ChatThreads.seed);
  }

  // ------------------------------------------------------------------ evidence
  void _addEvidence(EvidenceItem item) {
    if (state.evidence.any((EvidenceItem e) => e.evidenceId == item.evidenceId)) {
      return;
    }
    final List<EvidenceItem> next = <EvidenceItem>[...state.evidence, item];
    state = state.copyWith(evidence: next);
    unawaited(db.saveEvidence(next));
  }

  // ------------------------------------------------------- NtbRuntime plumbing
  @override
  bool get isMuted => state.isMuted;

  @override
  String get currentTime => state.environmentTime;

  @override
  String interpolate(String text) {
    if (text.isEmpty) return text;
    String result = text;
    _profile.interpolationTokens.forEach((String key, String value) {
      result = result.replaceAll('{$key}', value);
    });
    return result;
  }

  @override
  void onMessage(ChatMessage message) {
    final List<ChatMessage> bucket =
        _messages.putIfAbsent(message.threadId, () => <ChatMessage>[]);
    final ChatMessage stamped = message.inGameTimestamp.isEmpty
        ? message.copyWith(inGameTimestamp: state.environmentTime)
        : message;
    bucket.add(stamped);
  }

  @override
  void onThreadUpdate(
    String threadId, {
    ThreadStatus? status,
    ChatMessage? message,
  }) {
    final List<ChatThread> next = state.threads.map((ChatThread thread) {
      if (thread.threadId != threadId) return thread;
      final bool isOpen = state.openThreadId == threadId;
      return thread.copyWith(
        onlineStatus: status ?? thread.onlineStatus,
        lastMessagePreview: message == null
            ? thread.lastMessagePreview
            : (message.bodyText.isEmpty
                ? (message.mediaCaption ?? '[media]')
                : message.bodyText),
        lastUpdatedInGameTime:
            message == null ? thread.lastUpdatedInGameTime : state.environmentTime,
        unreadCount: message == null
            ? thread.unreadCount
            : (isOpen ? 0 : thread.unreadCount + 1),
      );
    }).toList();

    final Map<String, int> unread = Map<String, int>.from(state.unreadByThread);
    if (message != null && state.openThreadId != threadId) {
      unread[threadId] = (unread[threadId] ?? 0) + 1;
    }

    state = state.copyWith(threads: next, unreadByThread: unread);
  }

  @override
  void onNotification({
    required String threadId,
    required String senderName,
    required String text,
  }) {
    ref.read(audioServiceProvider).playSfx('notification_chime.mp3');
    if (state.openThreadId == threadId) return;
    state = state.copyWith(
      pendingNotification: InAppNotification(
        threadId: threadId,
        senderName: senderName,
        text: text,
      ),
    );
  }

  @override
  void onUiOpen(String threadId) {
    final Map<String, int> unread = Map<String, int>.from(state.unreadByThread)
      ..remove(threadId);
    state = state.copyWith(openThreadId: threadId, unreadByThread: unread);
    _interpreter?.activeThread = threadId;
  }

  @override
  void onEnvironment({
    String? time,
    String? location,
    String? weather,
    String? network,
  }) {
    state = state.copyWith(
      environmentTime: time,
      environmentLocation: location,
      environmentWeather: weather,
      networkStatus: network,
    );
  }

  @override
  void onEvidence(EvidenceItem item) => _addEvidence(item);

  @override
  void onReaction({
    required String threadId,
    required String targetMessageId,
    required String senderId,
    required String emoji,
  }) {
    final List<ChatMessage> bucket = _messages.putIfAbsent(threadId, () => <ChatMessage>[]);
    final bool found =
        bucket.any((ChatMessage m) => m.scriptMessageId == targetMessageId);
    if (!found) return;
    // Reactions are stored inline on the target message; the UI renders the
    // emoji pill under the bubble.
    _reactions[targetMessageId] = emoji;
    _reactionSenders[targetMessageId] = senderId;
  }

  final Map<String, String> _reactions = <String, String>{};
  final Map<String, String> _reactionSenders = <String, String>{};

  String? reactionFor(String messageId) => _reactions[messageId];
  String? reactionSenderFor(String messageId) => _reactionSenders[messageId];

  @override
  void onSound(String file) {
    ref.read(audioServiceProvider).playSfx(file);
  }

  @override
  void onMusic(String file, {bool loop = true, double volume = 0.5}) {
    ref.read(audioServiceProvider).playMusic(file, loop: loop, volume: volume);
  }

  @override
  void onStopMusic({double fadeOut = 1}) {
    ref.read(audioServiceProvider).stopMusic(fadeOut: fadeOut);
  }

  @override
  void onVibration(String pattern) {
    ref.read(hapticsServiceProvider).vibrate(pattern);
  }

  @override
  void onCameraEffect(String effect, double duration) {
    state = state.copyWith(cameraEffect: effect);
    Future<void>.delayed(
      Duration(milliseconds: (duration * 1000).round()),
      () {
        if (state.cameraEffect == effect) {
          state = state.copyWith(clearCameraEffect: true);
        }
      },
    );
  }

  @override
  void onShowText(String text, double duration) {
    state = state.copyWith(showTextBanner: interpolate(text));
    Future<void>.delayed(
      Duration(milliseconds: (duration * 1000).round()),
      () {
        if (state.showTextBanner == interpolate(text)) {
          state = state.copyWith(clearTextBanner: true);
        }
      },
    );
  }

  @override
  void onFade({required bool toBlack, double duration = 1}) {
    state = state.copyWith(fadeToBlack: toBlack);
  }

  @override
  void onNetwork({String? request, String? response}) {
    if (request != null) state = state.copyWith(networkStatus: 'PINGING...');
    if (response != null) {
      state = state.copyWith(
        networkStatus: response.contains('TIMEOUT') ? 'RELAY INTERFERENCE' : response,
        signalStrength: response.contains('TIMEOUT') ? 1 : state.signalStrength,
      );
    }
  }

  @override
  void onCheckpoint({
    required int instructionPointer,
    required String sceneLabel,
    bool force = false,
  }) {
    final GameSaveState current = state.save ?? GameSaveState.fresh;
    state = state.copyWith(
      save: current.copyWith(
        currentSceneLabel: sceneLabel,
        instructionPointerIndex: instructionPointer,
      ),
    );
    // Debounced cloud sync: scene changes are cheap locally, but we only push
    // to Firestore on forced checkpoints (autosave / choice / scene start).
    if (force) {
      unawaited(autosaveNow());
    }
  }

  @override
  void onAchievement(String id, String title, String description) {
    if (state.achievements.contains(id)) return;
    state = state.copyWith(achievements: <String>[...state.achievements, id]);
    final AuthUserInfo? auth = ref.read(authUserProvider).value;
    if (auth != null && auth.isSignedIn) {
      final String uid = auth.uid!;
      unawaited(
        ref.read(cloudSaveServiceProvider.future).then(
              (CloudSaveService cloud) => cloud.unlockAchievement(
                uid,
                id,
                title: title,
                description: description,
              ),
            ),
      );
    }
  }

  @override
  void onEndScene(String title, String? nextEpisode) {
    state = state.copyWith(
      ending: EpisodeEnding(
        title: title,
        nextEpisode: nextEpisode,
        evidenceCount: state.evidence.length,
        trust: <String, int>{
          for (final String c in <String>[
            'jessica',
            'beatrice',
            'abigail',
            'maya',
            'kathy',
            'kai',
          ])
            c: (state.save?.trust(c) ?? 0),
        },
      ),
      isRunning: false,
    );
    unawaited(_forceCloudSync());
  }

  Future<void> _forceCloudSync() async {
    await autosaveNow(slotId: 'ep1_complete', force: true);
  }

  @override
  Future<String> onLaunchHackingTool({
    required String puzzleId,
    required String difficulty,
    required String targetFile,
  }) async {
    final Completer<String> completer = Completer<String>();
    state = state.copyWith(
      puzzleRequest: HackingRequest(
        puzzleId: puzzleId,
        difficulty: difficulty,
        targetFile: targetFile,
        completer: completer,
      ),
    );
    unawaited(autosaveNow());
    final String result = await completer.future;
    state = state.copyWith(clearPuzzle: true);
    return result;
  }

  /// Called by the hacking screen when the puzzle resolves.
  void resolvePuzzle(String result) {
    final HackingRequest? request = state.puzzleRequest;
    if (request == null) return;
    state = state.copyWith(clearPuzzle: true);
    request.completer.complete(result);
    unawaited(_runAfterPuzzle());
  }

  Future<void> _runAfterPuzzle() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await _interpreter?.run();
    _publishStatus();
  }

  @override
  void onDatabaseLookup(String query) {
    onSound('notification_chime.mp3');
  }

  @override
  Future<bool?> requestPremiumUnlock({
    required String choiceId,
    required int cost,
    required String text,
  }) async {
    final bool unlocked = await ref.read(economyProvider.notifier).unlockPremiumAction(cost);
    if (unlocked) {
      if (!ref.read(economyProvider).multimediaUnlocked) {
        onSound('hack_success.mp3');
      }
      return true;
    }
    // Not enough coins: ask the UI to open the store sheet, then retry.
    state = state.copyWith(
      pendingChoiceCost: cost,
      pendingChoiceId: choiceId,
    );
    return false;
  }

  @override
  Future<NtbNode?> requestChoice(List<NtbNode> options) async {
    final Completer<NtbNode?> completer = Completer<NtbNode?>();
    _choiceCompleter = completer;
    state = state.copyWith(
      activeChoice: options,
      interpreterStatus: InterpreterStatus.awaitingChoice,
    );
    return completer.future;
  }

  @override
  Future<void> waitForPlayerInput(String prompt) async {
    if (_inputCompleter != null) return;
    final Completer<void> completer = Completer<void>();
    _inputCompleter = completer;
    state = state.copyWith(interpreterStatus: InterpreterStatus.awaitingInput);
    await completer.future;
  }
}

final gameStateProvider =
    NotifierProvider<GameStateNotifier, GameScreenState>(GameStateNotifier.new);
