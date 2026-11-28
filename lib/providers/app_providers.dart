import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/ntb_parser.dart';
import '../models/ntb_ast_node.dart';
import '../services/audio_service.dart';
import '../services/cloud_save_service.dart';
import '../services/game_store.dart';
import '../services/haptics_service.dart';
import '../services/isar_service.dart';

/// Root bootstrap state: Screen 0 holds until this is ready.
enum BootPhase { starting, firebase, database, scripts, ready, failed }

class BootState {
  const BootState({
    this.phase = BootPhase.starting,
    this.status = '> ESTABLISHING SECURE RELAY...',
    this.error,
  });

  final BootPhase phase;
  final String status;
  final String? error;

  bool get isReady => phase == BootPhase.ready;

  BootState copyWith({BootPhase? phase, String? status, String? error}) =>
      BootState(
        phase: phase ?? this.phase,
        status: status ?? this.status,
        error: error ?? this.error,
      );
}

/// Firebase and the local mirror are already open by the time this runs;
/// parsing the four script parts is the only async work left.
class BootController extends AsyncNotifier<BootState> {
  @override
  Future<BootState> build() async {
    try {
      await ref.read(isarServiceProvider.future);
      await ref.read(ntbProgramProvider.future);
      return const BootState(
        phase: BootPhase.ready,
        status: '> RELAY ONLINE',
      );
    } catch (error) {
      return BootState(
        phase: BootPhase.failed,
        status: '> BOOT FAILED',
        error: error.toString(),
      );
    }
  }

  void retry() => ref.invalidateSelf();
}

final bootControllerProvider =
    AsyncNotifierProvider<BootController, BootState>(BootController.new);

final isarServiceProvider =
    FutureProvider<IsarService>((Ref ref) => IsarService.open());

final audioServiceProvider =
    Provider<AudioService>((Ref ref) {
  final AudioService service = AudioService();
  ref.onDispose(service.dispose);
  return service;
});

final hapticsServiceProvider =
    Provider<HapticsService>((Ref ref) => const HapticsService());

final gameStoreProvider =
    Provider<GameStore>((Ref ref) => GameStore());

final cloudSaveServiceProvider =
    FutureProvider<CloudSaveService>((Ref ref) async {
  final IsarService local = await ref.watch(isarServiceProvider.future);
  return CloudSaveService(local: local);
});

/// Auth user exposed as a small immutable value so widgets never touch
/// firebase_auth types directly.
class AuthUserInfo {
  const AuthUserInfo({this.uid, this.email, this.displayName, this.photoUrl});

  final String? uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;

  bool get isSignedIn => uid != null && uid!.isNotEmpty;
  String get shortEmail => email ?? 'offline player';
  String get initial {
    final String source = (displayName ?? email ?? 'P').trim();
    return source.isEmpty ? 'P' : source.substring(0, 1).toUpperCase();
  }

  static AuthUserInfo fromFirebase(User? user) {
    if (user == null) return const AuthUserInfo();
    return AuthUserInfo(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
      photoUrl: user.photoURL,
    );
  }
}

final authUserProvider =
    StreamProvider<AuthUserInfo>((Ref ref) {
  // Firebase is optional at runtime (widget tests, a device without a valid
  // google-services.json). Fall back to a signed-out stream instead of
  // throwing, so the UI degrades to the offline path.
  try {
    return FirebaseAuth.instance
        .authStateChanges()
        .map(AuthUserInfo.fromFirebase);
  } catch (_) {
    return Stream<AuthUserInfo>.value(const AuthUserInfo());
  }
});

/// Parsed Episode 1 programme (all four parts linked into one stream).
class NtbParserResult {
  const NtbParserResult({
    required this.program,
    required this.warnings,
    required this.metadata,
  });

  final NtbProgram program;
  final List<String> warnings;
  final Map<String, String> metadata;

  int get instructionCount => program.length;
  int get sceneCount => program.sceneIndex.length;

  String get title => metadata['title'] ?? 'No Tide Back - Episode 1';
  String get author => metadata['author'] ?? 'EyesWatching Games';
}

final ntbProgramProvider =
    FutureProvider<NtbParserResult>((Ref ref) async {
  final NtbParser parser = NtbParser();
  final NtbProgram program = await parser.parseEpisode();
  return NtbParserResult(
    program: program,
    warnings: parser.warnings,
    metadata: parser.metadata,
  );
});
