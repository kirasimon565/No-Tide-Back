import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/app_config.dart';
import '../core/constants/store_skus.dart';
import '../models/chat_message.dart';
import '../models/evidence_item.dart';
import '../models/game_save_state.dart';
import '../models/player_profile.dart';
import 'isar_service.dart';

/// Keeps the local mirror and Firestore in sync.
///
/// Cloud schema (unchanged from the design document):
///   players/{uid}                     coins, multimediaUnlocked, profile, activeSave
///   players/{uid}/saves/{slotId}      full save snapshots (3 slots + ep1_complete)
///   players/{uid}/achievements/{id}   unlocked achievements
class CloudSaveService {
  CloudSaveService({
    required IsarService local,
    FirebaseFirestore? firestore,
  })  : _local = local,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final IsarService _local;
  final FirebaseFirestore _firestore;

  static const int maxSlots = 3;

  DocumentReference<Map<String, dynamic>> _playerDoc(String uid) =>
      _firestore.collection(StoreSkus.playersCollection).doc(uid);

  // ------------------------------------------------------------------- writes
  /// Pushes the active save as a merge so concurrent devices cannot clobber
  /// coins/entitlements stored on the same document.
  Future<void> pushActiveSave(
    String uid,
    GameSaveState save, {
    PlayerProfile? profile,
  }) async {
    final DateTime now = DateTime.now().toUtc();
    final GameSaveState stamped = save.copyWith(updatedAt: now, lastSyncedAt: now);
    await _local.saveGame(save.slotId, stamped);

    final Map<String, dynamic> payload = <String, dynamic>{
      FirestoreFields.activeSave: stamped.toJson(),
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
    };
    if (profile != null) {
      payload[FirestoreFields.profile] = profile.toJson();
    }
    try {
      await _playerDoc(uid).set(payload, SetOptions(merge: true));
    } catch (error) {
      debugPrint('CloudSaveService.pushActiveSave failed: $error');
      rethrow;
    }
  }

  /// Writes a named slot (save_slot_1..3 or ep1_complete).
  Future<void> pushSlot(String uid, String slotId, GameSaveState save) async {
    final GameSaveState stamped = save.copyWith(
      slotId: slotId,
      updatedAt: DateTime.now().toUtc(),
      lastSyncedAt: DateTime.now().toUtc(),
    );
    await _local.saveGame(slotId, stamped);
    try {
      await _playerDoc(uid)
          .collection(FirestoreFields.saves)
          .doc(slotId)
          .set(stamped.toJson());
    } catch (error) {
      debugPrint('CloudSaveService.pushSlot($slotId) failed: $error');
      rethrow;
    }
  }

  Future<void> pushEvidence(String uid, List<EvidenceItem> items) async {
    try {
      await _playerDoc(uid).set(<String, dynamic>{
        'evidenceIndex': items
            .map((EvidenceItem e) => <String, dynamic>{
                  'evidenceId': e.evidenceId,
                  'title': e.title,
                  'episode': e.episodeNumber,
                  'multimedia': e.isMultimediaBonus,
                  'unlockedAt': e.unlockedAt.toUtc().toIso8601String(),
                })
            .toList(),
        FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('CloudSaveService.pushEvidence failed: $error');
    }
  }

  Future<void> unlockAchievement(
    String uid,
    String id, {
    String title = '',
    String description = '',
  }) async {
    try {
      await _playerDoc(uid)
          .collection(FirestoreFields.achievements)
          .doc(id)
          .set(<String, dynamic>{
        'id': id,
        'title': title,
        'description': description,
        'unlockedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('CloudSaveService.unlockAchievement failed: $error');
    }
  }

  // -------------------------------------------------------------------- reads
  /// Pulls the cloud save into the local mirror. Returns null when the cloud
  /// has no active save yet (fresh install on a new device).
  Future<GameSaveState?> pullActiveSave(String uid) async {
    final DocumentSnapshot<Map<String, dynamic>> doc =
        await _playerDoc(uid).get();
    final Map<String, dynamic>? data = doc.data();
    if (data == null) return null;
    final Object? raw = data[FirestoreFields.activeSave];
    if (raw is! Map) return null;
    final GameSaveState save = GameSaveState.fromJson(
      raw.map((Object? k, Object? v) => MapEntry<String, dynamic>(k.toString(), v)),
    );
    await _local.saveGame('active', save.copyWith(lastSyncedAt: DateTime.now()));
    return save;
  }

  Future<Map<String, GameSaveState>> pullSlots(String uid) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot =
        await _playerDoc(uid).collection(FirestoreFields.saves).get();
    final Map<String, GameSaveState> slots = <String, GameSaveState>{};
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in snapshot.docs) {
      final GameSaveState save = GameSaveState.fromJson(doc.data());
      slots[doc.id] = save.copyWith(slotId: doc.id);
      await _local.saveGame(doc.id, save.copyWith(slotId: doc.id));
    }
    return slots;
  }

  /// Cloud → local restore for a fresh install: pulls the profile and the
  /// active save so the player resumes exactly where they left off.
  Future<PlayerProfile?> restoreInto(String uid) async {
    final DocumentSnapshot<Map<String, dynamic>> doc =
        await _playerDoc(uid).get();
    final Map<String, dynamic>? data = doc.data();
    if (data == null) return null;

    final Object? profileRaw = data[FirestoreFields.profile];
    if (profileRaw is Map) {
      final PlayerProfile profile = PlayerProfile.fromJson(
        profileRaw.map((Object? k, Object? v) => MapEntry<String, dynamic>(k.toString(), v)),
      );
      await _local.saveProfile(profile);
    }

    await pullActiveSave(uid);
    await pullSlots(uid);
    return _local.loadProfile();
  }

  /// Restores a specific slot into the active save (Saves & Chapters modal).
  Future<GameSaveState?> loadSlot(String uid, String slotId) async {
    final DocumentSnapshot<Map<String, dynamic>> doc =
        await _playerDoc(uid).collection(FirestoreFields.saves).doc(slotId).get();
    final Map<String, dynamic>? data = doc.data();
    if (data == null) {
      return _local.loadSave(slotId);
    }
    final GameSaveState save = GameSaveState.fromJson(data);
    await _local.saveGame(slotId, save);
    return save;
  }

  Future<void> deleteSlot(String uid, String slotId) async {
    await _local.deleteSave(slotId);
    try {
      await _playerDoc(uid).collection(FirestoreFields.saves).doc(slotId).delete();
    } catch (error) {
      debugPrint('CloudSaveService.deleteSlot failed: $error');
    }
  }

  /// Local-only thread messages are not uploaded (700+ messages per episode
  /// would blow past the 1 MB document limit); the script pointer is the
  /// source of truth and the feed is replayed locally.
  Future<void> mirrorMessagesSnapshot(String uid, Map<String, List<ChatMessage>> byThread) async {
    for (final MapEntry<String, List<ChatMessage>> entry in byThread.entries) {
      await _local.saveMessages(entry.key, entry.value);
    }
    debugPrint('CloudSaveService: mirrored ${byThread.length} threads for $uid');
  }
}
