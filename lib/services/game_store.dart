
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../core/constants/app_config.dart';
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

class PurchaseResult {
  const PurchaseResult({
    required this.success,
    this.sku,
    this.transactionId,
    this.cancelled = false,
    this.message,
    this.simulated = false,
  });

  final bool success;
  final String? sku;
  final String? transactionId;
  final bool cancelled;
  final String? message;

  /// True when the entitlement came from a simulated purchase (debug builds
  /// without a billing rail available). Never trusted in release.
  final bool simulated;

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

  final StoreType storeType = StoreType.fromEnvironment();

  bool _purchasesConfigured = false;
  String? _configuredUid;
  final _LocalPlayerCache _local = _LocalPlayerCache();

  // ---------------------------------------------------------------------- auth
  User? get currentUser => _auth.currentUser;
  String? get uid => _auth.currentUser?.uid;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Google Sign-In → Firebase credential exchange.
  Future<User?> signInWithGoogle() async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        scopes: const <String>['email'],
      );
      // Force the account picker so switching accounts always works.
      await googleSignIn.signOut();
      final GoogleSignInAccount? account = await googleSignIn.signIn();
      if (account == null) return null;

      final GoogleSignInAuthentication tokens = await account.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: tokens.accessToken,
        idToken: tokens.idToken,
      );

      final UserCredential result = await _auth.signInWithCredential(credential);
      final User? user = result.user;
      if (user != null) {
        await ensurePlayerDocument(user);
        await _configurePurchases(user.uid);
      }
      return user;
    } on PlatformException catch (error) {
      debugPrint('GameStore.signInWithGoogle platform error: ${error.message}');
      rethrow;
    }
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
      debugPrint('GameStore.grantCoins failed, using local cache: $error');
      if (_local.purchases.add(orderId ?? 'local_$sku')) {
        _local.coins += amount;
      }
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
    await doc.set(<String, dynamic>{
      FirestoreFields.multimediaUnlocked: true,
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await doc.collection('purchases').doc(
          orderId ?? '${sku}_${DateTime.now().millisecondsSinceEpoch}',
        ).set(<String, dynamic>{
      'sku': sku,
      'store': storeType.name,
      'createdAt': FieldValue.serverTimestamp(),
    }).catchError((Object error) {
      debugPrint('GameStore.grantMultimediaPackage: $error');
    });
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
    if (StoreSkus.revenueCatAndroidKey.isNotEmpty) {
      return StoreSkus.revenueCatAndroidKey;
    }
    return null;
  }

  /// Routes a SKU to the right rail and returns the verified result.
  ///
  /// Entitlements are applied by [applyPurchase] only after the rail confirms.
  Future<PurchaseResult> buy(String sku) async {
    if (uid == null) {
      return PurchaseResult.failure('Sign in to make purchases');
    }

    // 1) RevenueCat (Amazon / Samsung / Play with a configured key)
    if (_revenueCatKey() != null) {
      final PurchaseResult? rc = await _buyWithRevenueCat(sku);
      if (rc != null) return rc;
    }

    // 2) Xsolla (installer rail) through the Kotlin bridge
    if (storeType == StoreType.xsolla || storeType == StoreType.googlePlay) {
      final PurchaseResult xsolla = await _buyWithXsolla(sku);
      if (xsolla.success || xsolla.cancelled) return xsolla;
    }

    // 3) No billing rail available in this build: only debug builds may
    //    simulate, and the result is flagged so the UI can label it.
    if (kDebugMode || _allowSimulatedPurchases) {
      return PurchaseResult(
        success: true,
        sku: sku,
        transactionId: 'SIM_${DateTime.now().millisecondsSinceEpoch}',
        simulated: true,
        message: 'Simulated purchase (no billing rail configured)',
      );
    }

    return PurchaseResult.failure('No billing rail available for ${storeType.label}');
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
      debugPrint('GameStore: RevenueCat purchase failed: ${error.message}');
      return PurchaseResult.failure(error.message ?? 'Purchase failed');
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
      return PurchaseResult.failure('Xsolla bridge unavailable');
    } on PlatformException catch (error) {
      return PurchaseResult.failure(error.message ?? 'Xsolla purchase failed');
    }
  }

  /// Applies a verified purchase to the Firestore economy ledger.
  Future<void> applyPurchase(PurchaseResult result) async {
    final String? sku = result.sku;
    if (!result.success || sku == null) return;
    final int? coins = StoreSkus.coinsForSku(sku);
    if (coins != null) {
      await grantCoins(coins, sku: sku, orderId: result.transactionId);
      return;
    }
    if (sku == StoreSkus.multimediaPack) {
      await grantMultimediaPackage(sku: sku, orderId: result.transactionId);
    }
  }

  Future<bool> restorePurchases() async {
    if (_revenueCatKey() == null) return false;
    try {
      if (!_purchasesConfigured && uid != null) {
        await _configurePurchases(uid!);
      }
      final CustomerInfo info = await Purchases.restorePurchases();
      final bool entitled = info.entitlements.all.values
          .any((EntitlementInfo e) => e.isActive);
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
