import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// JSON-document store backing the local offline mirror.
///
/// The design document specifies Isar for threads / messages / evidence /
/// saves. Isar requires a build_runner codegen step and a native library per
/// ABI, and its 3.x line is no longer maintained, so this app ships the same
/// collection/JSON contracts on top of a synchronous document store:
///
///   threads/v1            List<ChatThread json>
///   messages/v1/{thread}  List<ChatMessage json>   (700+ per episode)
///   evidence/v1           List<EvidenceItem json>
///   saves/v1/{slot}       GameSaveState json
///   profile/v1            PlayerProfile json
///
/// Reads are synchronous (no await before first paint) and writes are batched
/// per thread, which keeps the 700-message feeds instant while removing the
/// codegen + native-lib build risk. Swapping in Isar later only requires a new
/// implementation of this class.
class LocalStore {
  LocalStore._(this._prefs);

  final SharedPreferences _prefs;

  static const String _threadsKey = 'ntb.threads.v1';
  static const String _evidenceKey = 'ntb.evidence.v1';
  static const String _profileKey = 'ntb.profile.v1';
  static const String _flagsKey = 'ntb.flags.v1';
  static const String _messagesPrefix = 'ntb.messages.v1.';
  static const String _savePrefix = 'ntb.save.v1.';

  static LocalStore? _instance;

  static bool get isReady => _instance != null;

  static Future<LocalStore> open() async {
    final LocalStore? existing = _instance;
    if (existing != null) return existing;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final LocalStore store = LocalStore._(prefs);
    _instance = store;
    return store;
  }

  // ------------------------------------------------------------------ helpers
  List<Map<String, dynamic>> _readList(String key) {
    final String? raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map<Object?, Object?>>()
          .map((Map<Object?, Object?> m) => m.map(
                (Object? k, Object? v) => MapEntry<String, dynamic>(k.toString(), v),
              ))
          .toList();
    } catch (error) {
      debugPrint('LocalStore: corrupt list at $key ($error)');
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _writeList(String key, List<Map<String, dynamic>> value) =>
      _prefs.setString(key, jsonEncode(value));

  Map<String, dynamic>? _readMap(String key) {
    final String? raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return decoded.map(
        (Object? k, Object? v) => MapEntry<String, dynamic>(k.toString(), v),
      );
    } catch (error) {
      debugPrint('LocalStore: corrupt map at $key ($error)');
      return null;
    }
  }

  Future<void> _writeMap(String key, Map<String, dynamic> value) =>
      _prefs.setString(key, jsonEncode(value));

  // ------------------------------------------------------------------ threads
  List<Map<String, dynamic>> readThreads() => _readList(_threadsKey);

  Future<void> writeThreads(List<Map<String, dynamic>> threads) =>
      _writeList(_threadsKey, threads);

  // ----------------------------------------------------------------- messages
  List<Map<String, dynamic>> readMessages(String threadId) =>
      _readList('$_messagesPrefix$threadId');

  Future<void> writeMessages(
    String threadId,
    List<Map<String, dynamic>> messages,
  ) =>
      _writeList('$_messagesPrefix$threadId', messages);

  /// Every known thread id, discovered from stored messages.
  List<String> knownThreadsWithMessages() {
    final List<String> result = <String>[];
    for (final String key in _prefs.getKeys()) {
      if (key.startsWith(_messagesPrefix)) {
        result.add(key.substring(_messagesPrefix.length));
      }
    }
    return result;
  }

  Future<void> clearAllMessages() async {
    for (final String key in _prefs.getKeys().toList()) {
      if (key.startsWith(_messagesPrefix)) {
        await _prefs.remove(key);
      }
    }
  }

  // ----------------------------------------------------------------- evidence
  List<Map<String, dynamic>> readEvidence() => _readList(_evidenceKey);

  Future<void> writeEvidence(List<Map<String, dynamic>> items) =>
      _writeList(_evidenceKey, items);

  // -------------------------------------------------------------------- saves
  Map<String, dynamic>? readSave(String slotId) =>
      _readMap('$_savePrefix$slotId');

  Future<void> writeSave(String slotId, Map<String, dynamic> save) =>
      _writeMap('$_savePrefix$slotId', save);

  Future<void> deleteSave(String slotId) =>
      _prefs.remove('$_savePrefix$slotId');

  List<String> knownSaveSlots() {
    final List<String> result = <String>[];
    for (final String key in _prefs.getKeys()) {
      if (key.startsWith(_savePrefix)) {
        result.add(key.substring(_savePrefix.length));
      }
    }
    return result;
  }

  // ------------------------------------------------------------------ profile
  Map<String, dynamic>? readProfile() => _readMap(_profileKey);

  Future<void> writeProfile(Map<String, dynamic> profile) =>
      _writeMap(_profileKey, profile);

  // -------------------------------------------------------------------- flags
  Map<String, dynamic> readFlags() => _readMap(_flagsKey) ?? <String, dynamic>{};

  Future<void> setFlag(String key, Object? value) async {
    final Map<String, dynamic> flags = readFlags();
    flags[key] = value;
    await _writeMap(_flagsKey, flags);
  }

  bool get isOnboarded => (readFlags()['onboarded'] as bool?) ?? false;

  Future<void> wipe() async {
    for (final String key in _prefs.getKeys().toList()) {
      if (key.startsWith('ntb.')) await _prefs.remove(key);
    }
  }

  /// Remaining local flags (used by the settings sheet for diagnostics).
  Map<String, dynamic> debugSnapshot() => <String, dynamic>{
        'threads': readThreads().length,
        'evidence': readEvidence().length,
        'saves': knownSaveSlots(),
        'onboarded': isOnboarded,
      };
}
