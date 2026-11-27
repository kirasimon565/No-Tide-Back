# No Tide Back

**Episode 1: The Contract** — a dark maritime psychological thriller told entirely through a
simulated phone. Built with Flutter + Riverpod 3, Firebase (Auth + Firestore) for economy and
cloud saves, and a custom `.ntb` script engine that drives every message, choice and haptic.

```
Package / Application ID : com.eyeswatchinggames.no_tide_back
Studio                   : EyesWatching Games
Episode 1 script         : 4 linked parts, 38 scenes, 68 gotos, 700+ messages
Firebase project         : no-tide-back (android/app/google-services.json)
Build verified by CI     : flutter 3.50.x stable · Gradle 9.5.0 · AGP 9.3.1 · JDK 21
```

**Status:** `flutter analyze` clean, `flutter test` green, and the release APK + AAB build
successfully in GitHub Actions on every push to this branch.

---

## 1. Quick start

```bash
flutter pub get
flutter run                             # debug (billing simulated, Firebase live)
flutter build apk --debug               # signed with the debug key
flutter build apk --release             # uses android/key.properties if present
```

Billing rail is a compile-time switch:

```bash
flutter build apk --release --dart-define=NTB_STORE=googleplay   # default
flutter build apk --release --dart-define=NTB_STORE=amazon       # RevenueCat Amazon key
flutter build apk --release --dart-define=NTB_STORE=samsung      # RevenueCat Galaxy key
flutter build apk --release --dart-define=NTB_STORE=xsolla -PwithXsolla
```

`-PwithXsolla` adds the Xsolla Android SDK Gradle dependencies and repo. Without it the Kotlin
bridge compiles and runs fine — it resolves the SDK reflectively and reports
"Xsolla SDK not bundled in this build" if a purchase is attempted.

---

## 2. Assets: where everything lives

Every file referenced by the scripts (`@image`, `@video`, `@audio`, `@sound`, `@music`) is resolved
by `lib/core/constants/asset_catalog.dart` from its bare name, so the `.ntb` scripts stay
untouched.

| Folder | Contents |
| --- | --- |
| `assets/scripts/` | `episode_01_part_1.ntb` … `part_4.ntb` |
| `assets/images/branding/` | `studio_logo.png` (Screen 0), `app_icon.png` (launcher, from `ico.png`) |
| `assets/images/title/` | `bg_title_screen.png` |
| `assets/images/chat/` | `bg_chat_dark.png` |
| `assets/images/hacking/` | `bg_hacking_grid.png` |
| `assets/images/overlays/` | `overlay_red_alert.png`, `overlay_vhs_static.png` |
| `assets/images/characters/` | `avatar_*.png` (8 cast portraits) |
| `assets/images/evidence/` | `img_*.jpg` (in-thread photos + decrypted frame) |
| `assets/images/documents/` | `doc_*.jpg` (contracts, logs, Multimedia Package notes) |
| `assets/video/` | `vid_abigail_corrupted_01.mp4` |
| `assets/audio/bgm/` | `bgm_*.mp3` music beds |
| `assets/audio/sfx/` | chimes, alarms, `hack_success` / `hack_fail` |
| `assets/audio/voice/` | `aud_hallway_scream_01.ogg` |
| `assets/fonts/` | Inter + JetBrains Mono (SIL OFL 1.1, see `OFL.txt`) |

Launcher icons in `android/app/src/main/res/mipmap-*` were generated from `ico.png`
(legacy + adaptive + monochrome). `android/app/src/main/res/values/colors.xml` holds the
red adaptive-icon background.

---

## 3. Screens

| # | Screen | File |
| --- | --- | --- |
| 0 | Studio boot (pure black, logo fade + hold, tap-to-skip) | `ui/screens/studio_intro_screen.dart` |
| 1 | Splash & Google Sign-In (Firestore sync) | `ui/screens/splash_auth_screen.dart` |
| 2 | Home Hub (episodes, resume, coins, pack) | `ui/screens/home_hub_screen.dart` |
| 3 | Player identity (name + pronouns) | `ui/screens/player_setup_screen.dart` |
| 4 | Simulated phone inbox (9 threads) | `ui/screens/phone_inbox_screen.dart` |
| 5 | Chat room (script playback + choices) | `ui/screens/chat_room_screen.dart` |
| 6 | Hacking & decryption tool | `ui/screens/hacking_tool_screen.dart` |
| 7 | Evidence vault & case board | `ui/screens/evidence_vault_screen.dart` |
| 8 | Store & Multimedia Package sheet | `ui/widgets/store_modal_sheet.dart` |
| 9 | Episode end & stinger | `ui/screens/episode_end_screen.dart` |

---

## 4. Script engine

`lib/engine/ntb_parser.dart`

* Concatenates the four parts into one instruction stream and indexes every `:: scene_label`, so
  `@goto` jumps across part boundaries (`@goto ep1_part3_chaos` from the end of part 2 works).
* Indentation becomes a tree: `@choice` owns its `@reply` / `@choice_locked` / `@choice_if`
  options, and each option owns the nested `@set` / `@goto` body.
* `@comment` lines are stripped, `@metadata` is captured for the hub, and every `@goto` target is
  validated (unresolved targets surface as warnings instead of crashing mid-scene).

`lib/engine/ntb_interpreter.dart`

* Async pull-based state machine. `run()` executes until it needs the player, then returns — which
  makes "resume from checkpoint" a matter of `run(startIndex)`.
* Every directive the scripts use is handled: `@set`, `@if/@elseif/@else/@endif`, `@goto`,
  `@character`, `@online/@offline`, `@environment`, `@ui open`, `@notification`, `@typing`,
  `@delay`, `@message`, `@thought`, `@system_message`, `@image/@video/@audio`,
  `@react_message`, `@choice/@reply/@choice_if/@choice_locked`, `@add_evidence`,
  `@custom action="launch_hacking_tool" | "database_lookup"`, `@wait_input`, `@sound`,
  `@music/@stop_music`, `@vibration`, `@camera effect`, `@network`, `@autosave`,
  `@unlock_achievement`, `@fade_in/@fade_out`, `@show_text`, `@end_scene`.
* `{player_name}`, `{they}`, `{them}`, `{their}`, `{bro_sis}` are interpolated before anything is
  rendered or persisted.
* `@if` chains are resolved by indentation, including compound expressions
  (`sister_suspicious == true && home_safe == false`).

`lib/engine/ntb_expression.dart` is a tiny evaluator for those conditions.

---

## 5. Two-way unlock & economy

* `players/{uid}` holds `coins`, `multimediaUnlocked`, `profile`, `activeSave`.
* `players/{uid}/saves/{slotId}` holds full snapshots (`save_slot_1..3`, `ep1_complete`).
* `players/{uid}/achievements/{id}` holds `ach_ep1_clear` etc.
* `players/{uid}/purchases/{orderId}` is the idempotent purchase ledger.

The rule is implemented once, in `EconomyNotifier` + `GameStateNotifier.requestPremiumUnlock`:

```
if multimediaUnlocked == true            → unlock for free (0 coins)
else if coins >= cost                    → Firestore transaction deducts coins
else                                     → open StoreModalSheet over the chat, keep script position
```

The same check powers the Hacking Tool auto-bypass ("FREE WITH MULTIMEDIA PACK" vs "🪙 10 COINS").
Because `@if multimedia_package_owned == true` gates the bonus scenes in the scripts, the runtime
variable is seeded from Firestore on every launch and every save checkpoint.

`firestore.rules` (repo root) contains the security rules — deploy with
`firebase deploy --only firestore:rules`.

---

## 6. Local mirror

`lib/services/local_store.dart` + `lib/services/isar_service.dart` implement the
ChatThread / ChatMessage / EvidenceItem / GameSaveState collections from the design document as
JSON documents in `shared_preferences`: synchronous reads (no spinner before the first frame) and
per-thread batched writes, which is what keeps a 700-message feed instant.

The storage layer is isolated behind `IsarService`, so swapping in Isar later only means
re-implementing that one class.

---

## 7. Android signing via repository secrets

The keystore is **never** committed. Add these secrets
(Settings → Secrets and variables → Actions):

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 upload-keystore.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | store password |
| `ANDROID_KEY_ALIAS` | key alias |
| `ANDROID_KEY_PASSWORD` | key password |
| `REVENUECAT_ANDROID_KEY` | optional, RevenueCat public SDK key |

The workflow decodes the keystore into `android/app/upload-keystore.jks`, writes
`android/key.properties`, builds, uploads the artifacts, and deletes the signing material in an
`always()` step. If the secrets are absent the build still succeeds with the debug signature and
the run summary says so.

For local signed builds, create `android/key.properties` yourself:

```properties
storeFile=upload-keystore.jks
storePassword=…
keyAlias=…
keyPassword=…
```

Both files are git-ignored.

---

## 8. Workflows

| File | Trigger | Output |
| --- | --- | --- |
| `.github/workflows/ci.yml` | push / PR | `flutter analyze`, unit tests, `.ntb` asset + label validation |
| `.github/workflows/build-apk.yml` | push / PR / manual | APK (and optionally AAB), manual inputs for rail + Xsolla SDK |
| `.github/workflows/release.yml` | tag `v*` | split-ABI + universal APK attached to a GitHub Release |

Manual run (Actions → Build Android APK → Run workflow) lets you pick `apk` / `aab` / `both`,
the billing rail, and whether to bundle the Xsolla SDK.

---

## 9. Tests

```bash
flutter test
```

Covers pronoun interpolation, the expression evaluator, parser scene indexing, `@choice` nesting,
`@if` block skipping, and the nine-thread seed.
