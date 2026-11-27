
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../core/constants/app_config.dart';
import 'store_channel.dart';
import '../core/constants/store_skus.dart';
import '../models/player_profile.dart';

/// Which billing rail this build talks to. Chosen at compile time:
///   flutter build apk --dart-define=NTB_STORE=amazon
/// Defaults to the Google Play / Xsolla rail.
enum StoreType {
  googlePlay,
  amazon,
  samsung,
  xsolla;

  static StoreType fromEnvironment() {
    const String raw = String.fromEnvironment('NTB_STORE', defaultValue: 'googleplay');
    return switch (raw.toLowerCase()) {
      'amazon' || 'amzn' => StoreType.amazon,
      'samsung' || 'galaxy' || 'galx' => StoreType.samsung,
      'xsolla' => StoreType.xsolla,
      _ => StoreType.googlePlay,
    };
  }

  String get installerPackage => switch (this) {
        StoreType.amazon => 'com.amazon.venezia',
        StoreType.samsung => 'com.sec.android.app.samsungapps',
        _ => 'com.android.vending',
      };

  String get label => switch (this) {
        StoreType.googlePlay => 'Google Play',
        StoreType.amazon => 'Amazon Appstore',
        StoreType.samsung => 'Samsung Galaxy Store',
        StoreType.xsolla => 'Xsolla',
      };
}

/// In-memory mirror of the player document, used when the app runs without a
/// configured Firebase project (or offline). The authoritative copy always
/// lives in Firestore; this only keeps the UI consistent within a session.
class _LocalPlayerCache {
  int coins = 0;
  bool multimediaUnlocked = false;
  Map<String, dynamic>? profile;
  final Set<String> purchases = <String>{};
}

/// Raised when a payment succeeded but the entitlement could not be persisted to
/// Firestore. Distinct from a failed purchase: the player *has* been charged.
class PurchasePersistenceException implements Exception {
  const PurchasePersistenceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PurchaseResult {
  const PurchaseResult({
    required this.success,
    this.sku,
    this.transactionId,
    this.cancelled = false,
    this.message,
    this.simulated = false,
    this.cloudSynced = false,
  });

  final bool success;
  final String? sku;
  final String? transactionId;
  final bool cancelled;
  final String? message;

  /// True when the entitlement came from a simulated purchase (debug builds
  /// without a billing rail available). Never trusted in release.
  final bool simulated;

  /// True once the entitlement is confirmed in `players/{uid}`. The UI must not
  /// tell the player their purchase is saved unless this is true.
  final bool cloudSynced;

  static PurchaseResult cancelledByUser() =>
      const PurchaseResult(success: false, cancelled: true, message: 'Purchase cancelled');

  static PurchaseResult failure(String message) =>
      PurchaseResult(success: false, message: message);
}

/// The single place that talks to Firebase Auth, Firestore (economy +
/// entitlements) and the billing rails.
///
/// Rule from the design document: balances and entitlements live in Cloud
/// Firestore under players/{uid}. They are *never* stored only on device, and
/// a purchase is only granted after the store confirms it.
class GameStore {
  GameStore({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  static const MethodChannel _xsollaChannel = MethodChannel(StoreSkus.xsollaChannel);

  /// Rail chosen at compile time. Only the fallback: [storeType] is the
  /// authority once the install source is known.
  final StoreType _compiledStoreType = StoreType.fromEnvironment();

  StoreType _storeType = StoreType.fromEnvironment();

  /// The rail this install should use.
  ///
  /// On a Galaxy or Amazon device this differs from the compiled value, which is
  /// what stopped those builds from charging at all: the RevenueCat key was
  /// selected from the *build flag*, so an Amazon install was handed the Google
  /// Play key (empty) and then reported "RevenueCat has no product".
  StoreType get storeType => _storeType;

  bool _purchasesConfigured = false;
  String? _configuredUid;
  final _LocalPlayerCache _local = _LocalPlayerCache();

  /// Resolves the rail from the install source. Called once during bootstrap;
  /// safe to call again (the installer never changes for a live install).
  Future<StoreType> resolveStoreType() async {
    final String? installer = await StoreChannel.installerPackage();
    _storeType = StoreChannel.resolve(installer, _compiledStoreType);
    if (_storeType != _compiledStoreType) {
      debugPrint(
        'GameStore: installed by ${installer ?? '(sideload)'} — '
        'using ${_storeType.label}, built for ${_compiledStoreType.label}',
      );
    }
    // A different rail can mean a different RevenueCat project key.
    _purchasesConfigured = false;
    return _storeType;
  }

  // ---------------------------------------------------------------------- auth
  User? get currentUser => _auth.currentUser;
  String? get uid => _auth.currentUser?.uid;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Google Sign-In → Firebase credential exchange.
  ///
  /// Failure modes are surfaced as text the player can act on instead of a
  /// silent `false`:
  ///   • `GoogleSignIn.signIn()` throwing `PlatformException(sign_in_failed,
  ///     …, 10)` — the SHA-1 of the signing certificate is not registered for
  ///     this package in the Firebase console / Google Cloud OAuth client.
  ///   • `[cloud_firestore/permission-denied]` — Firestore rules are not
  ///     deployed, so `players/{uid}` cannot be created. Sign-in itself
  ///     succeeded; we keep the session and let the economy fall back to the
  ///     local mirror rather than bouncing the player back to the splash.
  String? lastAuthError;

  Future<User?> signInWithGoogle() async {
    lastAuthError = null;
    final GoogleSignIn googleSignIn = GoogleSignIn(
      scopes: const <String>['email', 'profile'],
    );

    final GoogleSignInAccount? account;
    try {
      await googleSignIn.signOut();
      account = await googleSignIn.signIn();
    } on PlatformException catch (error) {
      lastAuthError = _authErrorFor(error);
      debugPrint('GameStore.signInWithGoogle: ${error.code} ${error.message}');
      rethrow;
    }

    if (account == null) {
      lastAuthError = 'Sign-in cancelled';
      return null;
    }

    final GoogleSignInAuthentication tokens = await account.authentication;
    final OAuthCredential credential = GoogleAuthProvider.credential(
      accessToken: tokens.accessToken,
      idToken: tokens.idToken,
    );

    final UserCredential result = await _auth.signInWithCredential(credential);
    final User? user = result.user;
    if (user == null) {
      lastAuthError = 'Firebase rejected the Google credential';
      return null;
    }

    // Firebase-first bootstrap. Both of these are best-effort: a rules or
    // network problem must not undo a successful authentication.
    try {
      await ensurePlayerDocument(user);
    } on FirebaseException catch (error) {
      lastAuthError = _firestoreErrorFor(error);
      debugPrint('GameStore.ensurePlayerDocument: ${error.code}');
    }
    try {
      await _configurePurchases(user.uid);
    } catch (error) {
      debugPrint('GameStore._configurePurchases: $error');
    }
    return user;
  }

  /// Turns the opaque platform codes into something the splash screen can show.
  static String _authErrorFor(PlatformException error) {
    final String detail = '${error.message ?? ''} ${error.details ?? ''}';
    if (error.code == 'sign_in_failed' && detail.contains('10')) {
      return 'Google rejected this install: the app signing SHA-1 is not '
          'registered for this package. Add it in Firebase → Project settings '
          '→ Your apps → SHA certificate fingerprints.';
    }
    if (error.code == 'network_error') {
      return 'No network. Play offline — your relay stays on this device.';
    }
    if (error.code == 'sign_in_canceled') {
      return 'Sign-in cancelled';
    }
    return 'Google sign-in failed (${error.code}). '
        'Check that the SHA-1 of this build is registered in Firebase.';
  }

  static String _firestoreErrorFor(FirebaseException error) {
    if (error.code == 'permission-denied') {
      return 'Cloud save is locked: the Firestore rules are not deployed for '
          'this project (\'permission-denied\'). Run '
          '`firebase deploy --only firestore:rules`.';
    }
    if (error.code == 'unavailable') {
      return 'Cloud save unreachable — playing on the local relay.';
    }
    return 'Cloud save error (${error.code}).';
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    _configuredUid = null;
    await _auth.signOut();
  }

  // ------------------------------------------------------------------ firestore
  DocumentReference<Map<String, dynamic>> get _playerDoc =>
      _firestore.collection(StoreSkus.playersCollection).doc(uid!);

  /// Creates players/{uid} on first sign-in with the documented defaults.
  Future<void> ensurePlayerDocument(User user) async {
    final DocumentReference<Map<String, dynamic>> doc =
        _firestore.collection(StoreSkus.playersCollection).doc(user.uid);
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await doc.get();
    if (!snapshot.exists) {
      await doc.set(<String, dynamic>{
        FirestoreFields.coins: 0,
        FirestoreFields.multimediaUnlocked: false,
        FirestoreFields.createdAt: FieldValue.serverTimestamp(),
        FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
        'displayName': user.displayName ?? 'Player',
        'email': user.email,
      }, SetOptions(merge: true));
    }
  }

  /// Live economy + entitlement stream for the Riverpod provider.
  Stream<Map<String, dynamic>?> watchPlayer() {
    if (uid == null) return Stream<Map<String, dynamic>?>.value(null);
    return _playerDoc
        .snapshots()
        .map((DocumentSnapshot<Map<String, dynamic>> snap) => snap.data())
        .handleError((Object error) {
      debugPrint('GameStore.watchPlayer: $error');
      return _localSnapshot();
    });
  }

  Future<Map<String, dynamic>?> fetchPlayer() async {
    if (uid == null) return null;
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap = await _playerDoc.get();
      return snap.data() ?? _localSnapshot();
    } catch (error) {
      debugPrint('GameStore.fetchPlayer: $error');
      return _localSnapshot();
    }
  }

  Map<String, dynamic> _localSnapshot() => <String, dynamic>{
        FirestoreFields.coins: _local.coins,
        FirestoreFields.multimediaUnlocked: _local.multimediaUnlocked,
        if (_local.profile != null) FirestoreFields.profile: _local.profile,
      };

  // ------------------------------------------------------------------- economy
  /// Atomically deducts [cost] coins. Returns false when the balance is short,
  /// which makes the caller open the store sheet instead of unlocking.
  Future<bool> spendCoins(int cost) async {
    final String? userId = uid;
    if (userId == null || cost <= 0) return false;
    final DocumentReference<Map<String, dynamic>> doc =
        _firestore.collection(StoreSkus.playersCollection).doc(userId);

    try {
      return await _firestore.runTransaction<bool>((Transaction tx) async {
        final DocumentSnapshot<Map<String, dynamic>> snap = await tx.get(doc);
        final Map<String, dynamic> data = snap.data() ?? <String, dynamic>{};
        final int coins = (data[FirestoreFields.coins] as num?)?.toInt() ?? 0;
        if (coins < cost) return false;
        tx.set(
          doc,
          <String, dynamic>{
            FirestoreFields.coins: coins - cost,
            FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        return true;
      });
    } catch (error) {
      debugPrint('GameStore.spendCoins failed, using local cache: $error');
      if (_local.coins < cost) return false;
      _local.coins -= cost;
      return true;
    }
  }

  /// Credits a verified purchase. [orderId] makes the grant idempotent.
  Future<void> grantCoins(int amount, {required String sku, String? orderId}) async {
    final String? userId = uid;
    if (userId == null) throw StateError('Not signed in');

    final DocumentReference<Map<String, dynamic>> doc =
        _firestore.collection(StoreSkus.playersCollection).doc(userId);
    final DocumentReference<Map<String, dynamic>> ledger = doc
        .collection('purchases')
        .doc(orderId ?? '${sku}_${DateTime.now().millisecondsSinceEpoch}');

    await _firestore.runTransaction<void>((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> existing = await tx.get(ledger);
      if (existing.exists) return; // idempotent replay
      final DocumentSnapshot<Map<String, dynamic>> snap = await tx.get(doc);
      final int coins =
          (snap.data()?[FirestoreFields.coins] as num?)?.toInt() ?? 0;
      tx.set(
        doc,
        <String, dynamic>{
          FirestoreFields.coins: coins + amount,
          FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      tx.set(ledger, <String, dynamic>{
        'sku': sku,
        'coins': amount,
        'store': storeType.name,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }).catchError((Object error) {
      // Keep the player's coins in the local mirror so the entitlement is not
      // lost, then rethrow: a paid purchase that never reached Firestore must
      // be reported, not silently labelled "saved".
      debugPrint('GameStore.grantCoins failed, using local cache: $error');
      if (_local.purchases.add(orderId ?? 'local_$sku')) {
        _local.coins += amount;
      }
      throw PurchasePersistenceException(error.toString());
    });
  }

  /// Grants the Multimedia Package (permanent, two-way unlock).
  Future<void> grantMultimediaPackage({required String sku, String? orderId}) async {
    _local.multimediaUnlocked = true;
    _local.purchases.add(orderId ?? 'local_$sku');
    final String? userId = uid;
    if (userId == null) return;
    final DocumentReference<Map<String, dynamic>> doc =
        _firestore.collection(StoreSkus.playersCollection).doc(userId);
    try {
      await doc.set(<String, dynamic>{
        FirestoreFields.multimediaUnlocked: true,
        FirestoreFields.unlockedEntitlements: FieldValue.arrayUnion(<String>[sku]),
        FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      // Ledger row: makes RESTORE / support able to prove the order, and lets a
      // replayed transaction be detected instead of granting twice.
      await doc
          .collection('purchases')
          .doc(orderId ?? '${sku}_${DateTime.now().millisecondsSinceEpoch}')
          .set(<String, dynamic>{
        'sku': sku,
        'store': storeType.name,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('GameStore.grantMultimediaPackage: $error');
      throw PurchasePersistenceException(error.toString());
    }
  }

  // ------------------------------------------------------------------ profile
  Future<void> saveProfile(PlayerProfile profile) async {
    _local.profile = profile.toJson();
    final String? userId = uid;
    if (userId == null) return;
    try {
      await _firestore
          .collection(StoreSkus.playersCollection)
          .doc(userId)
          .set(<String, dynamic>{
        FirestoreFields.profile: profile.toJson(),
        FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('GameStore.saveProfile: $error');
    }
  }

  // ---------------------------------------------------------------- purchases
  /// Configure the billing rail for this user. RevenueCat is used for Amazon
  /// and Samsung builds; Xsolla is the fallback rail for installer stores
  /// without a RevenueCat key.
  Future<void> _configurePurchases(String userId) async {
    if (_purchasesConfigured && _configuredUid == userId) return;
    final String? key = _revenueCatKey();
    if (key == null) return;
    try {
      await Purchases.setLogLevel(
        kDebugMode ? LogLevel.debug : LogLevel.error,
      );
      await Purchases.configure(PurchasesConfiguration(key));
      await Purchases.logIn(userId);
      _purchasesConfigured = true;
      _configuredUid = userId;
    } catch (error) {
      debugPrint('GameStore: RevenueCat configure failed: $error');
    }
  }

  String? _revenueCatKey() {
    final String storeKey = StoreSkus.installerKeys[storeType.installerPackage] ?? '';
    if (storeKey.isNotEmpty) return storeKey;
    // The generic key belongs to the Play project. Using it on a Galaxy or
    // Amazon build asks the wrong project about the SKU and produces a
    // misleading "no product" for a product that does exist.
    if (storeType == StoreType.googlePlay &&
        StoreSkus.revenueCatAndroidKey.isNotEmpty) {
      return StoreSkus.revenueCatAndroidKey;
    }
    return null;
  }

  /// True when this rail has no way to charge, so the sheet can say so before
  /// the player taps BUY.
  bool get hasConfiguredRail =>
      _revenueCatKey() != null ||
      storeType == StoreType.xsolla ||
      storeType == StoreType.googlePlay;

  /// Routes a SKU to the right rail and returns the verified result.
  ///
  /// Entitlements are applied by [applyPurchase] only after the rail confirms.
  Future<PurchaseResult> buy(String sku) async {
    if (uid == null) {
      return PurchaseResult.failure(
        'Sign in with Google first — purchases are saved to your account.',
      );
    }

    // Collect the *reason* each rail declined, so the sheet can show a real
    // message instead of a flat "no rail available".
    final List<String> attempts = <String>[];

    // 1) RevenueCat (Amazon / Samsung / Play when a key is configured).
    if (_revenueCatKey() != null) {
      final PurchaseResult? rc = await _buyWithRevenueCat(sku);
      if (rc != null) return rc;
      attempts.add('RevenueCat has no product "$sku"');
    }

    // 2) Xsolla Pay Station through the Kotlin bridge.
    //
    // This runs on *every* build that has the bridge, not just the Play and
    // Xsolla rails. It used to be gated to those two, so an Amazon or Samsung
    // install fell straight through to "no billing rail" and the player never
    // saw the Pay Station — even though the Pay Station can settle any order.
    final PurchaseResult xsolla = await _buyWithXsolla(sku);
    if (xsolla.success || xsolla.cancelled) return xsolla;
    if (xsolla.message != null) attempts.add(xsolla.message!);

    // 3) Nothing opened a payment window. Only debug builds may simulate, and
    //    the result is flagged so the UI can label it honestly.
    if (kDebugMode || _allowSimulatedPurchases) {
      return PurchaseResult(
        success: true,
        sku: sku,
        transactionId: 'SIM_${DateTime.now().millisecondsSinceEpoch}',
        simulated: true,
        message: 'Sandbox grant (no billing rail configured)',
      );
    }

    return PurchaseResult.failure(
      attempts.isEmpty
          ? 'No payment method is available for ${storeType.label} in this build.'
          : attempts.join(' • '),
    );
  }


  static const bool _allowSimulatedPurchases =
      bool.fromEnvironment('NTB_ALLOW_SIMULATED_PURCHASES', defaultValue: false);

  Future<PurchaseResult?> _buyWithRevenueCat(String sku) async {
    try {
      if (!_purchasesConfigured && uid != null) {
        await _configurePurchases(uid!);
      }
      final List<StoreProduct> products = await Purchases.getProducts(
        <String>[sku],
        productCategory: ProductCategory.nonSubscription,
      );
      if (products.isEmpty) {
        // Not an error: this build's RevenueCat project simply does not carry
        // the SKU. Returning null lets the next rail try; it used to end the
        // purchase as a failure named after the wrong provider.
        debugPrint('GameStore: RevenueCat has no product for $sku');
        return null;
      }
      final StoreProduct product = products.first;
      final CustomerInfo info = await Purchases.purchaseStoreProduct(product);
      return PurchaseResult(
        success: true,
        sku: sku,
        transactionId: info.originalAppUserId,
      );
    } on PlatformException catch (error) {
      final PurchasesErrorCode code = PurchasesErrorHelper.getErrorCode(error);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        return PurchaseResult.cancelledByUser();
      }
      // Configuration / store-missing / network errors are not a verdict on
      // the sku: hand over to the Pay Station instead of failing the purchase.
      debugPrint('GameStore: RevenueCat unavailable: ${error.message}');
      return null;
    } catch (error) {
      debugPrint('GameStore: RevenueCat purchase failed: $error');
      return null;
    }
  }

  Future<PurchaseResult> _buyWithXsolla(String sku) async {
    try {
      await _xsollaChannel.invokeMethod<bool>('initXsolla');

      // The Xsolla Mobile SDK reports the Pay Station purchase token back so
      // the order can be reconciled server-side. Older bridges returned a bare
      // bool, which is still accepted here.
      final Object? response = await _xsollaChannel.invokeMethod<Object?>(
        'buySku',
        <String, dynamic>{'sku': sku},
      );
      final bool completed = response == true ||
          (response is Map && (response['purchaseToken'] as String?)?.isNotEmpty == true);
      if (completed) {
        final String? token = response is Map
            ? response['purchaseToken'] as String?
            : null;
        return PurchaseResult(
          success: true,
          sku: sku,
          transactionId: token ?? 'XS_${DateTime.now().millisecondsSinceEpoch}',
        );
      }
      return PurchaseResult.failure('Xsolla order was not completed');
    } on MissingPluginException {
      return PurchaseResult.failure(
        'The Xsolla bridge is not in this build (missing plugin channel). '
        'Rebuild with -PwithXsolla.',
      );
    } on PlatformException catch (error) {
      return PurchaseResult.failure(error.message ?? 'Xsolla purchase failed');
    }
  }

  /// Applies a verified purchase to the Firestore economy ledger.
  /// Writes a paid purchase to `players/{uid}`.
  ///
  /// Returns the document snapshot the grant left behind, or null when the sku
  /// is unknown. Throws `PurchasePersistenceException` when the payment went
  /// through but the cloud write did not — the player has been charged, so the
  /// caller must say so rather than pretend it succeeded.
  Future<Map<String, dynamic>?> applyPurchase(PurchaseResult result) async {
    final String? sku = result.sku;
    if (!result.success || sku == null) return null;
    final int? coins = StoreSkus.coinsForSku(sku);
    try {
      if (coins != null) {
        await grantCoins(coins, sku: sku, orderId: result.transactionId);
      } else if (sku == StoreSkus.multimediaPack) {
        await grantMultimediaPackage(sku: sku, orderId: result.transactionId);
      } else {
        return null;
      }
    } catch (error) {
      throw PurchasePersistenceException(
        'Payment went through, but the cloud write to players/{uid} failed: $error. '
        'The grant is queued locally — sign in with the same account and use RESTORE.',
      );
    }
    return fetchPlayer();
  }

  /// Restores entitlements.
  ///
  /// The authoritative record for *every* rail is the `players/{uid}` document
  /// written by [applyPurchase], so the cloud read comes first — that is what
  /// makes a reinstall or a new device recover the purchase. RevenueCat is only
  /// consulted when it is configured and the cloud document is empty.
  Future<bool> restorePurchases() async {
    final String? userId = uid;
    if (userId == null) return false;

    // 1) Cloud Firestore — the source of truth.
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap = await _firestore
          .collection(StoreSkus.playersCollection)
          .doc(userId)
          .get();
      final Map<String, dynamic> data = snap.data() ?? <String, dynamic>{};
      final int coins = (data[FirestoreFields.coins] as num?)?.toInt() ?? 0;
      final bool pack = data[FirestoreFields.multimediaUnlocked] == true;
      if (pack) _local.multimediaUnlocked = true;
      if (coins > 0) _local.coins = coins;
      if (pack || coins > 0) return true;
    } catch (error) {
      debugPrint('GameStore.restorePurchases (cloud) failed: $error');
    }

    // 2) RevenueCat, when this build has a key.
    //
    // The app reads *non-consumable purchases*, not entitlements: attaching the
    // SKUs to an entitlement in the dashboard is optional, and the old check
    // here looked only at entitlements — so a catalogue that was correct but
    // had nothing attached reported "nothing to restore" after a restore.
    if (_revenueCatKey() == null) return false;
    try {
      if (!_purchasesConfigured) await _configurePurchases(userId);
      final CustomerInfo info = await Purchases.restorePurchases();

      // `allPurchasedProductIdentifiers` covers one-time products, which is all
      // this game sells. Entitlements are checked only as a fallback, since the
      // dashboard does not require attaching them.
      for (final String sku in <String>[
        StoreSkus.multimediaPack,
        StoreSkus.coins100,
        StoreSkus.coins500,
        StoreSkus.coins1500,
      ]) {
        if (info.allPurchasedProductIdentifiers.contains(sku)) {
          await applyPurchase(
            PurchaseResult(
              success: true,
              sku: sku,
              // Deterministic, so restoring twice cannot re-credit the grant.
              transactionId: 'rc_restore_${sku}_$userId',
            ),
          );
          return true;
        }
      }

      final bool entitled =
          info.entitlements.all.values.any((EntitlementInfo e) => e.isActive);
      if (entitled) {
        await grantMultimediaPackage(sku: StoreSkus.multimediaPack);
      }
      return entitled;
    } catch (error) {
      debugPrint('GameStore.restorePurchases failed: $error');
      return false;
    }
  }

}
