# Workflows

| File | Trigger | Result |
| --- | --- | --- |
| `ci.yml` | every push / PR | `flutter analyze`, unit tests, `.ntb` asset + `@goto` validation |
| `build-apk.yml` | every push / PR, or manual | Release APK (optionally AAB), signed from repository secrets |
| `release.yml` | tag `v*`, or manual with a tag | Split-ABI + universal APK + AAB attached to a GitHub Release |

## Required secrets

| Secret | Purpose |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 your-upload-keystore.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_ALIAS` | key alias inside the keystore |
| `ANDROID_KEY_PASSWORD` | key password |
| `REVENUECAT_ANDROID_KEY` | optional; public RevenueCat SDK key |

Without the keystore secrets `build-apk.yml` still succeeds, signed with the debug
key, and the run summary says so. `release.yml` requires the keystore because a
debug-signed build cannot be uploaded to Play.

## Toolchain (pinned by `pubspec.yaml` + `android/`)

| Component | Version | Why |
| --- | --- | --- |
| Flutter | stable channel (built with 3.50.x) | Riverpod 3 needs Dart ≥ 3.7, the Android build needs Gradle ≥ 9.3.1 |
| Dart SDK constraint | `>=3.7.0 <4.0.0` | set in `pubspec.yaml` |
| Gradle | 9.5.0 | Flutter 3.50 template default |
| Android Gradle Plugin | 9.3.1 | Flutter 3.50 template default |
| Kotlin Gradle Plugin | 2.4.20 | Flutter 3.50 minimum is 2.4.10 |
| JDK | 21 | required by Gradle 9 / AGP 9 lint; app bytecode still targets 17 |
| compileSdk / targetSdk / minSdk | 36 / 36 / 24 | current plugin AARs require API 36 |

The Gradle wrapper distribution is downloaded by `android/gradlew` (a small POSIX
launcher) rather than a committed wrapper JAR — see the comment at the top of that
file.

## Reproducing a build locally

```bash
flutter pub get
flutter build apk --release --dart-define=NTB_STORE=googleplay
flutter build appbundle --release          # Play deliverable
```

Reference sizes from CI (downscaled media, obfuscated release build):

| Artifact | Size |
| --- | --- |
| Universal APK (all ABIs) | ~133 MB |
| arm64-v8a APK | ~56 MB |
| AAB (Play) | ~65 MB |

`assets/images` was downscaled to keep the bundle Play-friendly — avatars 640×640,
documents ≤1400 px, evidence ≤1280 px, backgrounds ≤1200 px.
