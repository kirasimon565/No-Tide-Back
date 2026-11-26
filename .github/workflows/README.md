# Workflows

| File | Trigger | Result |
| --- | --- | --- |
| `ci.yml` | every push / PR | `flutter analyze`, unit tests, `.ntb` asset + `@goto` validation |
| `build-apk.yml` | every push / PR, or manual | Release APK (optionally AAB), signed from repository secrets |
| `release.yml` | tag `v*` | Split-ABI + universal APK attached to a GitHub Release |

## Required secrets

| Secret | Purpose |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 your-upload-keystore.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_ALIAS` | key alias inside the keystore |
| `ANDROID_KEY_PASSWORD` | key password |
| `REVENUECAT_ANDROID_KEY` | optional; public RevenueCat SDK key |

Without the keystore secrets the build still succeeds, signed with the debug key,
and the run summary shows a warning instead of failing.
