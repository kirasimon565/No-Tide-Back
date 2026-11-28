import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Minimal Firebase substitutes for widget tests.
///
/// `firebase_core` is not initialised in a unit test (there is no platform
/// channel), so anything that reads `FirebaseAuth.instance` or
/// `FirebaseFirestore.instance` would throw. Production code degrades
/// gracefully when Firebase is missing; these stubs let Riverpod build the
/// providers so the *rest* of each screen still gets exercised.
class StubFirebaseAuth implements FirebaseAuth {
  @override
  User? get currentUser => null;

  @override
  Stream<User?> authStateChanges() => Stream<User?>.value(null);

  @override
  Stream<User?> idTokenChanges() => Stream<User?>.value(null);

  @override
  Stream<User?> userChanges() => Stream<User?>.value(null);

  @override
  Future<void> signOut() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('FirebaseAuth.${invocation.memberName}');
}

/// Never used directly: [GameStore] is overridden in the widget tests, but the
/// type is needed for its constructor.
class StubFirestore implements FirebaseFirestore {
  const StubFirestore();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Firestore.${invocation.memberName}');
}
