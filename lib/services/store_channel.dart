import 'package:flutter/services.dart';

import 'game_store.dart';

/// Which store this APK was installed from.
///
/// The rail used to be decided *only* at compile time (`--dart-define=NTB_STORE`),
/// with [StoreType.installerPackage] describing a package the app never asked
/// about. That meant a build labelled `googleplay` — which is what the release
/// workflow produces — reported itself as Google Play even on a Galaxy or
/// Amazon device, and RevenueCat was handed the wrong API key.
///
/// The install source is authoritative, so it wins. The compile-time value stays
/// as the fallback for sideloaded builds, which have no installer at all.
abstract final class StoreChannel {
  static const MethodChannel _channel =
      MethodChannel('com.eyeswatchinggames.no_tide_back/store');

  /// Map of installer package → rail. Unknown stores fall back to [fallback].
  static StoreType resolve(String? installerPackage, StoreType fallback) {
    if (installerPackage == null || installerPackage.isEmpty) return fallback;
    return switch (installerPackage) {
      'com.android.vending' => StoreType.googlePlay,
      'com.amazon.venezia' => StoreType.amazon,
      'com.sec.android.app.samsungapps' => StoreType.samsung,
      // Sideloads (a file manager, a browser download, an APK from a release
      // page) report no installer; keep whatever the build was compiled for.
      _ => fallback,
    };
  }

  /// Asks Android for `getInstallerPackageName`.
  ///
  /// Returns null when the bridge is missing, so the caller keeps its build
  /// default. This never throws: a purchase should not fail because the
  /// installer name could not be read.
  static Future<String?> installerPackage() async {
    try {
      return await _channel.invokeMethod<String>('installerPackage');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
