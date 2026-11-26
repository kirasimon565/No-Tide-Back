import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'services/audio_service.dart';
import 'services/isar_service.dart';

/// Entry point.
///
/// Firebase and the local mirror are opened before the first frame so the
/// studio boot screen can cross-fade straight into authenticated content
/// without a loading flicker.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF070B0E),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  bool firebaseReady = false;
  try {
    await Firebase.initializeApp();
    firebaseReady = true;
  } catch (error) {
    // The game is fully playable offline; cloud save and purchases light up
    // as soon as Firebase is available.
    debugPrint('Firebase.initializeApp failed: $error');
  }

  await IsarService.open();

  runApp(
    ProviderScope(
      child: NoTideBackApp(firebaseReady: firebaseReady),
    ),
  );
}

/// Exposed so tests can pump the app without Firebase.
@visibleForTesting
Future<AudioService> warmUpAudio() async {
  final AudioService service = AudioService();
  await service.init();
  return service;
}
