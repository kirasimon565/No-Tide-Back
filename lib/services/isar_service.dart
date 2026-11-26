import '../core/constants/asset_catalog.dart';
import '../models/chat_message.dart';
import '../models/chat_thread.dart';
import '../models/evidence_item.dart';
import '../models/game_save_state.dart';
import '../models/player_profile.dart';
import 'local_store.dart';

/// Database layer for the offline mirror.
///
/// Names and query shapes follow the Isar collection design from the spec
/// (ChatThread / ChatMessage / EvidenceItem / GameSaveState) so the storage
/// engine is an implementation detail: the rest of the app only sees typed
/// collections.
class IsarService {
  IsarService(this._store);

  final LocalStore _store;

  static IsarService? _instance;

  /// Null when the mirror has not been opened yet (tests, early frames).
  static IsarService? get available => _instance;

  static IsarService get instance {
    final IsarService? existing = _instance;
    if (existing == null) {
      throw StateError('IsarService.open() must run before use');
    }
    return existing;
  }

  static Future<IsarService> open() async {
    final IsarService? existing = _instance;
    if (existing != null) return existing;
    final LocalStore store = await LocalStore.open();
    final IsarService service = IsarService(store);
    _instance = service;
    return service;
  }

  // ------------------------------------------------------------------ threads
  List<ChatThread> loadThreads() {
    final List<Map<String, dynamic>> rows = _store.readThreads();
    if (rows.isEmpty) return ChatThreads.seed;
    final Map<String, ChatThread> byId = <String, ChatThread>{
      for (final ChatThread thread in ChatThreads.seed) thread.threadId: thread,
    };
    for (final Map<String, dynamic> row in rows) {
      final ChatThread parsed = ChatThread.fromJson(row);
      final ChatThread? seed = byId[parsed.threadId];
      byId[parsed.threadId] = seed == null
          ? parsed
          : parsed.copyWith(
              displayName: seed.displayName,
              avatarAsset: seed.avatarAsset,
              badge: seed.badge,
              category: seed.category,
              isGroup: seed.isGroup,
              sortOrder: seed.sortOrder,
            );
    }
    final List<ChatThread> result = byId.values.toList()
      ..sort((ChatThread a, ChatThread b) => a.sortOrder.compareTo(b.sortOrder));
    return result;
  }

  Future<void> saveThreads(Iterable<ChatThread> threads) => _store.writeThreads(
        threads.map((ChatThread t) => t.toJson()).toList(),
      );

  // ----------------------------------------------------------------- messages
  /// Messages of one thread, ordered by sequence for a stable timeline.
  List<ChatMessage> loadMessages(String threadId) {
    final List<ChatMessage> messages = _store
        .readMessages(threadId)
        .map(ChatMessage.fromJson)
        .toList()
      ..sort((ChatMessage a, ChatMessage b) =>
          a.sequenceOrder.compareTo(b.sequenceOrder));
    return messages;
  }

  Future<void> saveMessages(String threadId, List<ChatMessage> messages) =>
      _store.writeMessages(
        threadId,
        messages.map((ChatMessage m) => m.toJson()).toList(),
      );

  /// Latest message preview per thread for the inbox list.
  Map<String, ChatMessage> latestMessagePerThread() {
    final Map<String, ChatMessage> latest = <String, ChatMessage>{};
    for (final String threadId in _store.knownThreadsWithMessages()) {
      final List<ChatMessage> messages = loadMessages(threadId);
      if (messages.isEmpty) continue;
      latest[threadId] = messages.last;
    }
    return latest;
  }

  int unreadCountFor(String threadId) => 0;

  Future<void> clearMessages() => _store.clearAllMessages();

  // ----------------------------------------------------------------- evidence
  List<EvidenceItem> loadEvidence() {
    final List<EvidenceItem> items =
        _store.readEvidence().map(EvidenceItem.fromJson).toList()
          ..sort((EvidenceItem a, EvidenceItem b) {
            final int byCase = a.caseNumber.compareTo(b.caseNumber);
            return byCase != 0 ? byCase : a.unlockedAt.compareTo(b.unlockedAt);
          });
    return items;
  }

  Future<void> saveEvidence(List<EvidenceItem> items) => _store.writeEvidence(
        items.map((EvidenceItem e) => e.toJson()).toList(),
      );

  // -------------------------------------------------------------------- saves
  GameSaveState? loadSave(String slotId) {
    final Map<String, dynamic>? raw = _store.readSave(slotId);
    if (raw == null) return null;
    return GameSaveState.fromJson(raw);
  }

  Future<void> saveGame(String slotId, GameSaveState save) =>
      _store.writeSave(slotId, save.copyWith(slotId: slotId).toJson());

  List<String> saveSlots() => _store.knownSaveSlots();

  Future<void> deleteSave(String slotId) => _store.deleteSave(slotId);

  GameSaveState? get activeSave => loadSave('active');

  Future<void> saveActive(GameSaveState save) => saveGame('active', save);

  // ------------------------------------------------------------------ profile
  PlayerProfile loadProfile() =>
      PlayerProfile.fromJson(_store.readProfile());

  /// True when a profile document exists locally (Screen 3 completed).
  bool readProfileRaw() => _store.readProfile() != null;

  Future<void> saveProfile(PlayerProfile profile) =>
      _store.writeProfile(profile.toJson());

  // -------------------------------------------------------------------- flags
  bool get isOnboarded => _store.isOnboarded;

  Future<void> setOnboarded(bool value) => _store.setFlag('onboarded', value);

  Future<void> wipe() async {
    await _store.wipe();
    _instance = null;
  }

  /// Convenience for the diagnostics sheet.
  Map<String, dynamic> debugSnapshot() => _store.debugSnapshot();

  /// Resolves a media reference (kept here so the UI never builds paths).
  static String resolveAsset(String file) => AssetCatalog.resolve(file);
}
