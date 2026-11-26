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
    final User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _listenToPlayerDoc(user.uid);
      // Pull once so the pills and the two-way unlock check are correct on the
      // very first frame, not only when Firestore pushes the first snapshot.
      Future<void>.microtask(refresh);
    }
    return PlayerEconomyState(user: user);
  }

  GameStore get _store => ref.read(gameStoreProvider);

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
        state = state.copyWith(lastError: error.toString(), isSyncing: false);
      },
    );
  }

  /// Google sign-in. Returns true on success.
  Future<bool> signIn() async {
    state = state.copyWith(isLoading: true, lastError: null);
    try {
      final User? user = await _store.signInWithGoogle();
      if (user == null) {
        state = state.copyWith(isLoading: false, lastError: 'Sign-in cancelled');
        return false;
      }
      state = state.copyWith(user: user, isLoading: false);
      _listenToPlayerDoc(user.uid);

      // Restore cloud save into the local mirror immediately.
      final cloud = await ref.read(cloudSaveServiceProvider.future);
      await cloud.restoreInto(user.uid);
      return true;
    } catch (error) {
      state = state.copyWith(isLoading: false, lastError: error.toString());
      return false;
    }
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
    if (result.success) {
      await _store.applyPurchase(result);
      await refresh();
    }
    return result;
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
