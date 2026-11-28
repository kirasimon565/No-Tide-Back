import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/constants/asset_catalog.dart';
import '../models/chat_message.dart';
import '../models/chat_thread.dart';
import '../models/evidence_item.dart';
import '../models/ntb_ast_node.dart';
import '../models/player_profile.dart';
import 'ntb_expression.dart';

/// Everything the interpreter needs from the outside world (UI, audio,
/// haptics, persistence). Implemented by the Riverpod controller so the engine
/// stays free of widget code and is unit-testable.
abstract class NtbRuntime {
  /// Queue a message/thought/system line into the local mirror.
  void onMessage(ChatMessage message);

  /// Update a thread's presence, preview and unread badge.
  void onThreadUpdate(
    String threadId, {
    ThreadStatus? status,
    ChatMessage? message,
    /// Who is typing, when the script knows. A group thread has no single
    /// sender, so without this the indicator can only say "Someone".
    String? typingCharacter,
  });

  /// `@notification` — banner ping, possibly for a thread the player is not in.
  void onNotification({required String threadId, required String senderName, required String text});

  /// `@ui open`
  void onUiOpen(String threadId);

  /// `@environment` changes.
  void onEnvironment({
    String? time,
    String? location,
    String? weather,
    String? network,
  });

  /// `@image` / `@video` / `@audio` derived evidence: file notes are also
  /// vault entries when the multimedia package is owned.
  void onEvidence(EvidenceItem item);

  /// `@react_message`
  void onReaction({
    required String threadId,
    required String targetMessageId,
    required String senderId,
    required String emoji,
  });

  /// `@sound` (one-shot) and `@music` / `@stop_music`.
  void onSound(String file);
  void onMusic(String file, {bool loop = true, double volume = 0.5});
  void onStopMusic({double fadeOut = 1});

  /// `@vibration` and `@camera effect="shake" | "glitch"`.
  void onVibration(String pattern);
  void onCameraEffect(String effect, double duration);

  /// `@show_text` / `@fade_in` / `@fade_out`.
  void onShowText(String text, double duration);
  void onFade({required bool toBlack, double duration = 1});

  /// `@network request` / `@network response` terminal readout.
  void onNetwork({String? request, String? response});

  /// Persist a checkpoint (`@autosave`, choice resolution, scene change).
  void onCheckpoint({required int instructionPointer, required String sceneLabel, bool force = false});

  /// `@unlock_achievement`
  void onAchievement(String id, String title, String description);

  /// `@end_scene`
  void onEndScene(String title, String? nextEpisode);

  /// `@custom action="launch_hacking_tool"` → returns "success" | "fail".
  Future<String> onLaunchHackingTool({
    required String puzzleId,
    required String difficulty,
    required String targetFile,
  });

  /// `@custom action="database_lookup"`
  void onDatabaseLookup(String query);

  /// Coin gate for `@choice_locked`. Returns `true` when the action is
  /// unlocked (Multimedia Package owned — free — or enough coins spent).
  Future<bool?> requestPremiumUnlock({required String choiceId, required int cost, required String text});

  /// Choice drawer. Returns the chosen node, or null when the script must
  /// simply halt (end of content).
  Future<NtbNode?> requestChoice(List<NtbNode> options);

  /// Pause until the player taps a chosen reply.
  Future<void> waitForPlayerInput(String prompt);

  bool get isMuted;

  PlayerProfile get profile;

  /// Current in-game clock (from `@environment time=`), stamped on messages.
  String get currentTime;

  /// Dynamic string interpolation for {player_name}, {they}, {them},
  /// {their} and {bro_sis}.
  String interpolate(String text);
}

enum InterpreterStatus { idle, running, awaitingChoice, awaitingInput, awaitingPuzzle, ended, paused }

/// Executes a linked [NtbProgram] instruction by instruction.
///
/// The interpreter is deliberately a *pull* state machine: [run] loops until it
/// hits something that needs the player, then returns. This keeps Riverpod in
/// charge of ownership and makes save/resume trivial (resume = run(index)).
class NtbInterpreter {
  NtbInterpreter({
    required this.program,
    required this.runtime,
    Map<String, dynamic>? initialVariables,
    int startIndex = 0,
    this.paceMultiplier = 1.0,
  })  : _variables = <String, dynamic>{
          ...GameSaveStateDefaults.variables,
          ...?initialVariables,
        },
        _index = startIndex;

  final NtbProgram program;
  final NtbRuntime runtime;

  /// 1.0 = authored pacing. The reader offers 1x / 2x / instant.
  double paceMultiplier;

  final Map<String, dynamic> _variables;
  int _index;
  bool _running = false;
  bool _stopRequested = false;
  InterpreterStatus _status = InterpreterStatus.idle;
  String? _pendingChoiceId;
  String _sceneLabel = 'ep1_start';



  Map<String, dynamic> get variables => Map<String, dynamic>.unmodifiable(_variables);
  int get instructionPointer => _index;
  InterpreterStatus get status => _status;
  String get sceneLabel => _sceneLabel;
  String? get pendingChoiceId => _pendingChoiceId;

  /// Exposed so the UI can echo trust/flag changes in the debug drawer.
  Object? variable(String key) => _variables[key];

  void requestStop() => _stopRequested = true;

  void _set(String key, Object? value) => _variables[key] = value;

  /// Resume after a UI state change (choice made, puzzle finished, tap).
  void resume() {
    _status = InterpreterStatus.running;
  }

  // ---------------------------------------------------------------------------
  // Main loop
  // ---------------------------------------------------------------------------

  Future<void> run() async {
    if (_running) return;
    _running = true;
    _stopRequested = false;
    _status = InterpreterStatus.running;

    try {
      while (_index < program.instructions.length && !_stopRequested) {
        final NtbNode node = program.instructions[_index];

        if (node.isSceneLabel) {
          _sceneLabel = node.sceneLabel;
          _variables['current_part'] = node.partNumber;
          _variables['current_scene'] = node.sceneLabel;
          runtime.onCheckpoint(
            instructionPointer: _index,
            sceneLabel: node.sceneLabel,
          );
          _index++;
          continue;
        }

        int? jump = await _execute(node);

        if (jump != null) {
          _index = jump;
          continue;
        }

        if (_status == InterpreterStatus.running) {
          _index++;
        } else {
          // Blocked: the runtime kicked off a UI interaction (choice, puzzle,
          // tap-to-continue). Stop looping; the caller resumes with run().
          break;
        }
      }
    } finally {
      _running = false;
      if (_index >= program.instructions.length) {
        _status = InterpreterStatus.ended;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Instruction dispatch
  // ---------------------------------------------------------------------------

  /// Returns a jump target when the instruction changes control flow.
  Future<int?> _execute(NtbNode node) async {
    switch (node.name) {
      // ---------------------------------------------------------------- state
      case 'set':
        _executeSet(node);
        return null;

      case 'if':
        return _enterIfChain(node);

      case 'elseif':
      case 'else':
        // A branch is chosen up-front by _enterIfChain; if we get here while a
        // branch is already running we jump past the rest of the chain.
        return _skipToChainEnd(node);

      case 'endif':
        return null;

      case 'goto':
        return _jump(node.param('label', node.freeArgs).trim());

      // --------------------------------------------------------------- chat
      case 'message':
        await _executeMessage(node);
        return null;

      case 'thought':
        await _executeThought(node);
        return null;

      case 'system_message':
        await _executeSystem(node);
        return null;

      case 'image':
      case 'video':
      case 'audio':
        await _executeMedia(node);
        return null;

      case 'typing':
        await _executeTyping(node);
        return null;

      case 'delay':
        await _wait(node.doubleParam('seconds', 1));
        return null;

      case 'notification':
        await _executeNotification(node);
        return null;

      case 'react_message':
        runtime.onReaction(
          threadId: _threadFor(node.param('chat', node.param('thread'))),
          targetMessageId: node.param('target'),
          senderId: node.param('sender', 'abigail'),
          emoji: node.param('emoji', '❤'),
        );
        return null;

      case 'ui':
        if (node.has('open')) {
          _variables['current_chat'] = node.param('open');
          runtime.onUiOpen(node.param('open'));
        }
        return null;

      case 'online':
      case 'offline':
        runtime.onThreadUpdate(
          _threadForCharacter(node.param('character')),
          status: node.name == 'online' ? ThreadStatus.online : ThreadStatus.offline,
        );
        return null;

      case 'environment':
        runtime.onEnvironment(
          time: node.has('time') ? node.param('time') : null,
          location: node.has('location') ? node.param('location') : null,
          weather: node.has('weather') ? node.param('weather') : null,
          network: node.has('network') ? node.param('network') : null,
        );
        return null;

      case 'character':
        // Metadata only: characters are seeded by the app shell.
        return null;

      case 'add_evidence':
        _executeAddEvidence(node);
        return null;

      // -------------------------------------------------------------- audio
      case 'sound':
        if (!runtime.isMuted) runtime.onSound(node.param('file'));
        return null;

      case 'music':
        if (!runtime.isMuted) {
          runtime.onMusic(
            node.param('file'),
            loop: node.boolParam('loop', true),
            volume: node.doubleParam('volume', 0.5),
          );
        }
        return null;

      case 'stop_music':
        runtime.onStopMusic(fadeOut: node.doubleParam('fade_out', 1));
        return null;

      // ------------------------------------------------------------ hardware
      case 'vibration':
        runtime.onVibration(node.param('pattern', 'short'));
        return null;

      case 'camera':
        runtime.onCameraEffect(
          node.param('effect', 'shake'),
          node.doubleParam('duration', 1),
        );
        return null;

      // --------------------------------------------------------------- flow
      case 'choice':
        return await _executeChoice(node);

      case 'wait_input':
        _status = InterpreterStatus.awaitingInput;
        runtime.onCheckpoint(
          instructionPointer: _index,
          sceneLabel: _sceneLabel,
          force: true,
        );
        await runtime.waitForPlayerInput(node.param('prompt'));
        _status = InterpreterStatus.running;
        return null;

      case 'custom':
        return await _executeCustom(node);

      case 'network':
        runtime.onNetwork(
          request: node.has('request') ? node.param('request') : null,
          response: node.has('response') ? node.param('response') : null,
        );
        return null;

      case 'autosave':
        _variables['save_slot'] = node.param('slot', 'active');
        runtime.onCheckpoint(
          instructionPointer: _index,
          sceneLabel: _sceneLabel,
          force: true,
        );
        return null;

      case 'unlock_achievement':
        runtime.onAchievement(
          node.param('id'),
          node.param('title'),
          node.param('description'),
        );
        return null;

      case 'fade_in':
        runtime.onFade(toBlack: false, duration: node.doubleParam('duration', 1));
        return null;

      case 'fade_out':
        runtime.onFade(toBlack: true, duration: node.doubleParam('duration', 1));
        await _wait(node.doubleParam('duration', 1));
        return null;

      case 'show_text':
        runtime.onShowText(
          node.param('text'),
          node.doubleParam('duration', 3),
        );
        await _wait(node.doubleParam('duration', 3));
        return null;

      case 'end_scene':
        _status = InterpreterStatus.ended;
        _variables['episode_complete'] = true;
        runtime.onCheckpoint(
          instructionPointer: _index,
          sceneLabel: _sceneLabel,
          force: true,
        );
        runtime.onEndScene(
          node.param('title', 'END OF EPISODE'),
          node.has('next_episode') ? node.param('next_episode') : null,
        );
        return null;

      default:
        debugPrint('[ntb] unhandled directive @${node.name} '
            '(part ${node.partNumber}:${node.lineNumber})');
        return null;
    }
  }

  /// Index of the `@endif` that closes the chain opened by the node at
  /// [startIndex]. Nested `@if`s live at a deeper indent, so an indent match is
  /// enough to find the right one.
  int _matchingEndif(int startIndex) {
    final int indent = program.instructions[startIndex].indent;
    for (int cursor = startIndex + 1; cursor < program.instructions.length; cursor++) {
      final NtbNode candidate = program.instructions[cursor];
      if (candidate.indent == indent && candidate.name == 'endif') {
        return cursor;
      }
      if (candidate.indent < indent) return cursor;
    }
    return program.instructions.length;
  }

  /// Branch nodes (`@elseif` / `@else`) of the chain opened at [startIndex].
  List<int> _chainBranches(int startIndex, int endifIndex) {
    final int indent = program.instructions[startIndex].indent;
    final List<int> branches = <int>[];
    for (int cursor = startIndex + 1; cursor < endifIndex; cursor++) {
      final NtbNode candidate = program.instructions[cursor];
      if (candidate.indent == indent &&
          (candidate.name == 'elseif' || candidate.name == 'else')) {
        branches.add(cursor);
      }
    }
    return branches;
  }

  /// Chooses one branch of an `@if` chain and jumps to its body.
  int? _enterIfChain(NtbNode node) {
    final int endifIndex = _matchingEndif(_index);
    final List<int> branches = _chainBranches(_index, endifIndex);

    if (_evaluate(node.freeArgs)) {
      return null; // run the @if body
    }

    for (final int branch in branches) {
      final NtbNode candidate = program.instructions[branch];
      if (candidate.name == 'elseif') {
        if (_evaluate(candidate.freeArgs)) {
          return branch + 1; // run the @elseif body
        }
      } else {
        return branch + 1; // @else body
      }
    }

    // No branch matched: continue after the whole chain.
    return endifIndex;
  }

  /// Jump past the remainder of the chain that owns [node].
  int? _skipToChainEnd(NtbNode node) {
    final int indent = node.indent;
    for (int cursor = _index + 1; cursor < program.instructions.length; cursor++) {
      final NtbNode candidate = program.instructions[cursor];
      if (candidate.indent == indent && candidate.name == 'endif') {
        return cursor;
      }
      if (candidate.indent < indent) return cursor;
    }
    return program.instructions.length;
  }

  int? _jump(String label) {
    if (label.isEmpty) return null;
    final int? target = program.indexOfScene(label);
    if (target == null) {
      debugPrint('[ntb] @goto unknown scene "$label"');
      return null;
    }
    return target;
  }

  bool _evaluate(String expression) =>
      NtbExpression(expression).evaluate(_variables);

  void _executeSet(NtbNode node) {
    final String body = node.freeArgs.trim();
    if (body.isEmpty) return;

    // `@set trust_abigail +1` / `@set trust_abigail -2`
    final RegExpMatch? delta =
        RegExp(r'^([A-Za-z_][A-Za-z0-9_]*)\s*([+-])\s*(\d+(?:\.\d+)?)$')
            .firstMatch(body);
    if (delta != null) {
      final String key = delta.group(1)!;
      final double amount = double.parse(delta.group(3)!);
      final num current = _asNum(_variables[key]);
      final num next =
          delta.group(2) == '+' ? current + amount : current - amount;
      _set(key, _normalizeNumber(next));
      if (key == 'evidence_count') _syncEvidenceCountMirror();
      return;
    }

    // `@set flag = true` / `@set trust_kai += 1`
    final RegExpMatch? assign =
        RegExp(r'^([A-Za-z_][A-Za-z0-9_]*)\s*(\+=|-=|=)\s*(.+)$')
            .firstMatch(body);
    if (assign != null) {
      final String key = assign.group(1)!;
      final String op = assign.group(2)!;
      final Object? value = _parseValue(assign.group(3)!.trim());
      if (op == '=') {
        _set(key, value);
      } else {
        final num current = _asNum(_variables[key]);
        final num amount = _asNum(value);
        _set(key, _normalizeNumber(op == '+=' ? current + amount : current - amount));
      }
      if (key == 'evidence_count') _syncEvidenceCountMirror();
      return;
    }

    // `@set achievement_x (bare flag)`
    _set(body, true);
  }

  void _syncEvidenceCountMirror() {
    final Object? count = _variables['evidence_count'];
    if (count is num) {
      _variables['evidence_count'] = count;
    }
  }

  static num _asNum(Object? value) {
    if (value is num) return value;
    if (value is bool) return value ? 1 : 0;
    return num.tryParse(value?.toString() ?? '') ?? 0;
  }

  static num _normalizeNumber(num value) =>
      value == value.roundToDouble() ? value.round() : value;

  Object? _parseValue(String raw) {
    final String lower = raw.toLowerCase();
    if (lower == 'true') return true;
    if (lower == 'false') return false;
    if (lower == 'null') return null;
    if (raw.startsWith('"') && raw.endsWith('"') && raw.length >= 2) {
      return runtime.interpolate(raw.substring(1, raw.length - 1));
    }
    final num? number = num.tryParse(raw);
    if (number != null) return number;
    return _variables[raw];
  }

  // ---------------------------------------------------------------------------
  // Chat directives
  // ---------------------------------------------------------------------------

  String _threadFor(String? chat) {
    final String id = (chat ?? 'group_island').trim();
    if (id.isEmpty || id == 'null') return 'group_island';
    if (id == 'system') return 'system';
    return id;
  }

  String _threadForCharacter(String? character) {
    final String id = (character ?? '').toLowerCase();
    if (id.isEmpty) return 'group_island';
    return 'dm_$id';
  }

  String _resolveSender(NtbNode node, String threadId) {
    final String sender = node.param('sender');
    if (sender.isNotEmpty) return sender.toLowerCase();
    return ChatThreads.characterForThread(threadId);
  }

  Future<void> _executeMessage(NtbNode node) async {
    final String threadId = _threadFor(node.param('chat'));
    final String sender = _resolveSender(node, threadId);
    final String text = runtime.interpolate(node.param('text'));

    final ChatMessage message = ChatMessage(
      scriptMessageId: node.param('id', 'msg_${node.lineNumber}'),
      threadId: threadId,
      senderId: sender,
      messageType: MessageType.text,
      bodyText: text,
      sequenceOrder: _index,
      inGameTimestamp: runtime.currentTime,
    );
    await _awaitDelivery(node, threadId, typingCharacter: sender);
    runtime.onMessage(message);
    runtime.onThreadUpdate(threadId, message: message);

    await _wait(node.doubleParam('wait', 0.15));
  }

  Future<void> _executeThought(NtbNode node) async {
    final String threadId = node.has('chat')
        ? _threadFor(node.param('chat'))
        : _threadFor(_variables['current_chat']?.toString());
    final ChatMessage message = ChatMessage(
      scriptMessageId: node.has('id') ? node.param('id') : 'thought_${node.lineNumber}',
      threadId: threadId,
      senderId: 'player',
      messageType: MessageType.thought,
      bodyText: runtime.interpolate(node.param('text')),
      sequenceOrder: _index,
      inGameTimestamp: runtime.currentTime,
    );
    // Thoughts are the player's own; they land immediately.
    runtime.onMessage(message);
    await _wait(node.doubleParam('wait', 0));
  }

  Future<void> _executeSystem(NtbNode node) async {
    final String threadId = _threadFor(node.param('chat'));
    final ChatMessage message = ChatMessage(
      scriptMessageId: node.param('id', 'sys_${node.lineNumber}'),
      threadId: threadId,
      senderId: 'system',
      messageType: MessageType.system,
      bodyText: runtime.interpolate(node.param('text')),
      sequenceOrder: _index,
      inGameTimestamp: runtime.currentTime,
    );
    runtime.onMessage(message);
    runtime.onThreadUpdate(threadId, message: message);
    await _wait(node.doubleParam('wait', 0));
  }

  Future<void> _executeMedia(NtbNode node) async {
    final String threadId = _threadFor(node.param('chat'));
    final String sender = _resolveSender(node, threadId);
    final String file = node.param('file');
    final bool encrypted = node.boolParam('encrypted', false);

    final MessageType type = switch (node.name) {
      'image' => MessageType.image,
      'video' => MessageType.video,
      'audio' => MessageType.audio,
      _ => MessageType.text,
    };

    final ChatMessage message = ChatMessage(
      scriptMessageId: node.param('id', '${node.name}_${node.lineNumber}'),
      threadId: threadId,
      senderId: sender,
      messageType: type,
      bodyText: '',
      sequenceOrder: _index,
      mediaFile: file,
      mediaCaption: runtime.interpolate(node.param('caption')),
      isEncrypted: encrypted,
      audioDuration: node.has('duration') ? node.param('duration') : null,
      inGameTimestamp: runtime.currentTime,
    );

    await _awaitDelivery(node, threadId);
    runtime.onMessage(message);
    runtime.onThreadUpdate(threadId, message: message);

    // A media file also becomes a vault entry when it is a document/scene
    // artefact (the scripts tag those ids with `doc_` or `img_`).
    if (file.startsWith('doc_') || encrypted) {
      runtime.onEvidence(
        EvidenceItem(
          evidenceId: node.param('id', file),
          episodeNumber: (num.tryParse('${_variables['episode'] ?? 1}') ?? 1).toInt(),
          title: runtime.interpolate(node.param('caption')).split(' - ').first,
          description: runtime.interpolate(node.param('caption')),
          unlockedAt: DateTime.now(),
          imageAsset: file,
          sourceCharacter: sender,
          isMultimediaBonus: true,
        ),
      );
    }

    await _wait(node.doubleParam('wait', 0.4));
  }

  Future<void> _executeTyping(NtbNode node) async {
    final String character = node.param('character').toLowerCase();
    final String threadId = node.has('chat')
        ? _threadFor(node.param('chat'))
        : _threadForCharacter(character);

    runtime.onThreadUpdate(
      threadId,
      status: ThreadStatus.typing,
      typingCharacter: character.isEmpty ? null : character,
    );
    await _wait(node.doubleParam('duration', 2));
    runtime.onThreadUpdate(threadId, status: ThreadStatus.online);
  }

  Future<void> _executeNotification(NtbNode node) async {
    final String threadId = _threadFor(node.param('chat'));
    runtime.onNotification(
      threadId: threadId,
      senderName: runtime.interpolate(node.param('sender', ChatThreads.displayNameFor(threadId))),
      text: runtime.interpolate(node.param('text')),
    );
    await _wait(node.doubleParam('delay', 0.6));
  }

  // ---------------------------------------------------------------------------
  // Choices
  // ---------------------------------------------------------------------------

  Future<int?> _executeChoice(NtbNode node) async {
    final String choiceId = node.param('id', 'choice_${node.lineNumber}');

    // Options are (in order): @reply, @choice_locked, @choice_if-gated blocks.
    final List<NtbNode> candidates = node.children
        .where((NtbNode child) =>
            child.name == 'reply' ||
            child.name == 'choice_locked' ||
            child.name == 'choice_if')
        .toList(growable: false);

    final List<NtbNode> visible = <NtbNode>[];

    for (final NtbNode candidate in candidates) {
      if (candidate.name == 'choice_if') {
        // The gate applies to its child @reply (or the node itself).
        NtbNode? option;
        for (final NtbNode child in candidate.children) {
          if (child.name == 'reply' || child.name == 'choice_locked') {
            option = child;
            break;
          }
        }
        if (!_evaluate(candidate.freeArgs)) continue;
        final NtbNode target = option ?? candidate;
        if (!_isDuplicateChoice(target, visible)) visible.add(target);
      } else {
        visible.add(candidate);
      }
    }

    if (visible.isEmpty) {
      debugPrint('[ntb] choice $choiceId has no visible options');
      return null;
    }

    _pendingChoiceId = choiceId;
    _status = InterpreterStatus.awaitingChoice;

    final NtbNode? chosen = await runtime.requestChoice(visible);
    _pendingChoiceId = null;
    _status = InterpreterStatus.running;

    if (chosen == null) {
      // Player dismissed / app resumed elsewhere: halt cleanly.
      _status = InterpreterStatus.paused;
      return null;
    }

    // Premium gate.
    if (chosen.name == 'choice_locked') {
      final int cost = chosen.intParam('cost', 10);
      final bool? unlocked = await runtime.requestPremiumUnlock(
        choiceId: chosen.param('id', choiceId),
        cost: cost,
        text: runtime.interpolate(chosen.param('text')),
      );
      if (unlocked != true) {
        // Store sheet was dismissed without a purchase: keep the drawer open
        // by impressing the same choice again.
        _status = InterpreterStatus.awaitingChoice;
        return await _executeChoice(node);
      }
      _variables['last_premium_choice'] = chosen.param('id');
      _variables['coins_spent_${chosen.param('id')}'] = cost;
    }

    // Render the player's pick into the thread.
    final String threadId = _threadFor(
      chosen.param('chat', _variables['current_chat']?.toString() ?? 'group_island'),
    );
    // Prefer the thread currently on screen.
    final String outThread = _activeThreadOverride ?? threadId;

    final ChatMessage reply = ChatMessage(
      scriptMessageId: 'p_${DateTime.now().millisecondsSinceEpoch}',
      threadId: outThread,
      senderId: 'player',
      messageType: MessageType.playerReply,
      bodyText: runtime.interpolate(chosen.param('text')),
      sequenceOrder: _index,
      inGameTimestamp: runtime.currentTime,
    );
    runtime.onMessage(reply);
    runtime.onThreadUpdate(outThread, message: reply);

    // Nested body of the chosen option runs first, then the block after it.
    final List<NtbNode> body = chosen.children
        .where((NtbNode c) => c.name == 'set' || c.name == 'goto')
        .toList(growable: false);

    int? goto;
    for (final NtbNode action in body) {
      if (action.name == 'set') {
        _executeSet(action);
      } else if (action.name == 'goto') {
        goto = _jump(action.param('label', action.freeArgs).trim());
      }
    }

    // Choice resolution is always a checkpoint.
    runtime.onCheckpoint(
      instructionPointer: _index,
      sceneLabel: _sceneLabel,
      force: true,
    );

    if (goto != null) return goto;

    // No explicit jump: continue after the whole choice block.
    return program.blockEnd(_index);
  }

  bool _isDuplicateChoice(NtbNode candidate, List<NtbNode> visible) {
    final String id = candidate.param('id');
    if (id.isEmpty) return false;
    return visible.any((NtbNode v) => v.param('id') == id);
  }

  /// Set by the controller so player replies land in the visible thread.
  String? _activeThreadOverride;
  set activeThread(String? threadId) => _activeThreadOverride = threadId;

  // ---------------------------------------------------------------------------
  // Custom actions
  // ---------------------------------------------------------------------------

  Future<int?> _executeCustom(NtbNode node) async {
    switch (node.param('action')) {
      case 'launch_hacking_tool':
        _status = InterpreterStatus.awaitingPuzzle;
        runtime.onCheckpoint(
          instructionPointer: _index,
          sceneLabel: _sceneLabel,
          force: true,
        );
        final String result = await runtime.onLaunchHackingTool(
          puzzleId: node.param('puzzle_id', 'ep1_puzzle'),
          difficulty: node.param('difficulty', 'easy'),
          targetFile: node.param('target_file', ''),
        );
        _set('puzzle_result', result);
        _status = InterpreterStatus.running;
        _index++;
        // Skip the @wait_input that pairs with the puzzle.
        while (_index < program.instructions.length &&
            program.instructions[_index].name == 'wait_input') {
          _index++;
        }
        return _index;

      case 'database_lookup':
        runtime.onDatabaseLookup(node.param('query'));
        await _wait(1);
        return null;

      default:
        debugPrint('[ntb] unknown custom action "${node.param('action')}"');
        return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Evidence
  // ---------------------------------------------------------------------------

  void _executeAddEvidence(NtbNode node) {
    final String id = node.param('id');
    final int episode =
        (num.tryParse('${_variables['episode'] ?? 1}') ?? 1).toInt();
    runtime.onEvidence(
      EvidenceItem(
        evidenceId: id,
        episodeNumber: episode,
        title: runtime.interpolate(node.param('title', id)),
        description: runtime.interpolate(node.param('description')),
        unlockedAt: DateTime.now(),
        imageAsset: node.has('image') ? node.param('image') : null,
        sourceCharacter: node.has('source') ? node.param('source') : null,
        caseNumber: _nextCaseNumber(),
      ),
    );
    // Note: the scripts follow @add_evidence with `@set evidence_count +1`,
    // so the counter is not advanced here. The vault length is authoritative.
  }

  int _nextCaseNumber() {
    final num current = _asNum(_variables['evidence_case_seq']);
    final int next = current.toInt() + 1;
    _variables['evidence_case_seq'] = next;
    return next;
  }

  // ---------------------------------------------------------------------------
  // Timing
  // ---------------------------------------------------------------------------

  /// Pause *before* a bubble lands, so a thread reads like a conversation.
  ///
  /// The scripts carry no `delay=` attributes: 285 of the first 285 `@message`
  /// nodes in part 1 have `wait="0"`, so every thread arrived instantly and in
  /// one frame. This derives the pause from the message itself — a long
  /// paragraph takes longer to "type" than a two-word reply — and scales with
  /// the player's pace setting.
  Future<void> _awaitDelivery(
    NtbNode node,
    String threadId, {
    String? typingCharacter,
  }) async {
    final double target = () {
      if (node.has('delay')) return node.doubleParam('delay', 0);
      final int length = runtime.interpolate(node.param('text')).length;
      // 0.35 s floor for a reaction, +~28 ms per character, capped at 2.2 s so a
      // wall of text never feels like a hang.
      return (0.35 + (length * 0.028)).clamp(0.35, 2.2).toDouble();
    }();
    if (target <= 0) return;

    // Show the "typing" state for the first part of the gap, then land the
    // bubble. `_executeTyping` exists in the scripts but is rare, so without
    // this the indicator almost never appeared.
    final double typingFor = math.min(target * 0.7, 1.4);
    if (typingFor > 0.15) {
      // Name the sender of the bubble that is about to land.
      runtime.onThreadUpdate(
        threadId,
        status: ThreadStatus.typing,
        typingCharacter: typingCharacter,
      );
      await _wait(typingFor);
      runtime.onThreadUpdate(threadId, status: ThreadStatus.online);
    }
    await _wait(target - typingFor);
  }

  Future<void> _wait(double seconds) async {
    if (seconds <= 0) return;
    final double scaled = seconds / math.max(paceMultiplier, 0.1);
    await Future<void>.delayed(
      Duration(milliseconds: (scaled * 1000).round().clamp(0, 600000).toInt()),
    );
  }
}

/// Default variable seed; mirrors the `@set` preamble in part 1.
abstract final class GameSaveStateDefaults {
  static const Map<String, dynamic> variables = <String, dynamic>{
    'episode': 1,
    'current_part': 1,
    'current_scene': 'ep1_start',
    'trust_jessica': 5,
    'trust_abigail': 7,
    'trust_beatrice': 6,
    'trust_maya': 7,
    'trust_kathy': 3,
    'trust_kai': 4,
    'home_safe': true,
    'evidence_count': 0,
    'maya_photo_clue': false,
    'sister_suspicious': false,
    'suspicion': 0,
    'stress': 0,
    'multimedia_package_owned': false,
    'kathy_trust_up': false,
    'kai_trust_up': false,
  };
}

/// Convenience used by the controller to know where `doc_*` art lives.
@visibleForTesting
String debugResolveAsset(String file) => AssetCatalog.resolve(file);
