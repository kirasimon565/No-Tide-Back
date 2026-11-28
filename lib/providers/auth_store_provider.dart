import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/store_skus.dart';
import '../services/game_store.dart';
import 'app_providers.dart';

/// Economy snapshot mirrored from players/{uid} in Cloud Firestore.
class PlayerEconomyState {
  const PlayerEconomyState({
    this.user,
    this.coins = 0,
    this.multimediaUnlocked = false,
    this.isLoading = false,
    this.isSyncing = false,
    this.lastError,
  });

  final User? user;
  final int coins;
  final bool multimediaUnlocked;
  final bool isLoading;
  final bool isSyncing;
  final String? lastError;

  bool get isSignedIn => user != null;

  /// Two-way unlock: free when the Multimedia Package is owned, otherwise the
  /// player needs enough coins.
  bool canUnlockChoice(int coinCost) => multimediaUnlocked || coins >= coinCost;

  PlayerEconomyState copyWith({
    User? user,
    int? coins,
    bool? multimediaUnlocked,
    bool? isLoading,
    bool? isSyncing,
    String? lastError,
  }) =>
      PlayerEconomyState(
        user: user ?? this.user,
        coins: coins ?? this.coins,
        multimediaUnlocked: multimediaUnlocked ?? this.multimediaUnlocked,
        isLoading: isLoading ?? this.isLoading,
        isSyncing: isSyncing ?? this.isSyncing,
        lastError: lastError ?? this.lastError,
      );
}

class EconomyNotifier extends Notifier<PlayerEconomyState> {
  StreamSubscription<Map<String, dynamic>?>? _sub;

  @override
  PlayerEconomyState build() {
    ref.onDispose(() => _sub?.cancel());
    final User? user = _currentUser;
    if (user != null) {
      _listenToPlayerDoc(user.uid);
      // Pull once so the pills and the two-way unlock check are correct on the
      // very first frame, not only when Firestore pushes the first snapshot.
      Future<void>.microtask(refresh);
    }
    return PlayerEconomyState(user: user);
  }

  GameStore get _store => ref.read(gameStoreProvider);

  /// Firebase is optional: widget tests and a device with a broken
  /// google-services.json run without it. Reading auth must never throw.
  static User? get _currentUser {
    try {
      return FirebaseAuth.instance.currentUser;
    } catch (_) {
      return null;
    }
  }

  void _listenToPlayerDoc(String uid) {
    unawaited(_sub?.cancel());
    _sub = _store.watchPlayer().listen(
      (Map<String, dynamic>? data) {
        if (data == null) return;
        state = state.copyWith(
          coins: (data['coins'] as num?)?.toInt() ?? 0,
          multimediaUnlocked: (data['multimediaUnlocked'] as bool?) ?? false,
          isSyncing: false,
        );
      },
      onError: (Object error) {
        state = state.copyWith(lastError: _readable(error), isSyncing: false);
      },
    );
  }

  /// Google sign-in. Returns true on success.
  ///
  /// Authentication and cloud sync are two different things. The Firebase
  /// session is what lets purchases and saves follow the player; the
  /// Firestore document is only the sync target. A `permission-denied` here
  /// used to be reported as a failed *login* and bounced the player back to
  /// the splash with an opaque error, when in fact they were signed in and
  /// simply had no cloud mirror yet.
  Future<bool> signIn() async {
    state = state.copyWith(isLoading: true, lastError: null);
    User? user;
    try {
      user = await _store.signInWithGoogle();
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        lastError: _store.lastAuthError ?? _readable(error),
      );
      return false;
    }
    if (user == null) {
      state = state.copyWith(
        isLoading: false,
        lastError: _store.lastAuthError ?? 'Sign-in cancelled',
      );
      return false;
    }

    // Signed in. From here on nothing may turn this into a failure.
    state = state.copyWith(user: user, isLoading: false, lastError: null);
    _listenToPlayerDoc(user.uid);

    try {
      final cloud = await ref.read(cloudSaveServiceProvider.future);
      await cloud.restoreInto(user.uid);
    } catch (error) {
      // Cloud mirror unavailable (rules not deployed / offline). The local
      // relay keeps working; the hub shows CLOUD OFFLINE.
      state = state.copyWith(lastError: _readable(error), isSyncing: false);
    }
    return true;
  }

  /// `[cloud_firestore/permission-denied] The caller does not have permission…`
  /// → "Cloud save is locked…". Keeps the raw code for the log.
  String _readable(Object error) {
    final String raw = error.toString();
    if (raw.contains('permission-denied')) {
      return 'Cloud save is locked — Firestore rules are not deployed. '
          'Local play is unaffected.';
    }
    if (raw.contains('unavailable') || raw.contains('network')) {
      return 'Cloud save unreachable — playing on the local relay.';
    }
    return raw.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), '');
  }

  Future<void> signOut() async {
    await _sub?.cancel();
    _sub = null;
    await _store.signOut();
    state = const PlayerEconomyState();
  }

  /// Refresh from Firestore after a purchase round-trip or a manual sync.
  Future<void> refresh() async {
    state = state.copyWith(isSyncing: true);
    try {
      final Map<String, dynamic>? data = await _store.fetchPlayer();
      if (data != null) {
        state = state.copyWith(
          coins: (data['coins'] as num?)?.toInt() ?? state.coins,
          multimediaUnlocked:
              (data['multimediaUnlocked'] as bool?) ?? state.multimediaUnlocked,
          isSyncing: false,
        );
      } else {
        state = state.copyWith(isSyncing: false);
      }
    } catch (error) {
      state = state.copyWith(isSyncing: false, lastError: error.toString());
    }
  }

  /// Resolves a `@choice_locked` or Hacking Tool boost.
  ///
  /// Returns:
  ///   true  → unlocked (free with the pack, or coins were spent);
  ///   false → not enough coins, the caller must open the store sheet.
  Future<bool> unlockPremiumAction(int coinCost) async {
    if (state.multimediaUnlocked) return true;
    if (state.coins < coinCost) return false;
    final bool spent = await _store.spendCoins(coinCost);
    if (spent) {
      state = state.copyWith(coins: state.coins - coinCost);
    }
    return spent;
  }

  /// Buys a SKU and applies the verified entitlement to Firestore.
  Future<PurchaseResult> purchase(String sku) async {
    final PurchaseResult result = await _store.buy(sku);
    if (!result.success) return result;

    try {
      await _store.applyPurchase(result);
    } on PurchasePersistenceException catch (error) {
      // The charge is real. Keep the local grant (applyPurchase already did)
      // and return a message that never claims the cloud write worked.
      await refresh();
      return PurchaseResult(
        success: true,
        sku: result.sku,
        transactionId: result.transactionId,
        simulated: result.simulated,
        message: error.message,
        cloudSynced: false,
      );
    }
    await refresh();
    return PurchaseResult(
      success: true,
      sku: result.sku,
      transactionId: result.transactionId,
      simulated: result.simulated,
      message: result.message,
      cloudSynced: true,
    );
  }

  Future<bool> restore() async {
    final bool restored = await _store.restorePurchases();
    await refresh();
    return restored;
  }

  /// Debug-only helper used by the store sheet when no billing rail exists.
  Future<void> devGrant(String sku) async {
    final int? coins = StoreSkus.coinsForSku(sku);
    if (coins != null) {
      await _store.grantCoins(coins, sku: sku);
    } else if (sku == StoreSkus.multimediaPack) {
      await _store.grantMultimediaPackage(sku: sku);
    }
    await refresh();
  }
}

final economyProvider =
    NotifierProvider<EconomyNotifier, PlayerEconomyState>(EconomyNotifier.new);
