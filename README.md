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

`-PwithXsolla` adds the Xsolla Mobile SDK Gradle dependency and repo. Without it the Kotlin
bridge compiles and runs fine — it resolves the SDK reflectively and reports a specific,
actionable message if a purchase is attempted (never a bare failure).

| build | what a BUY does |
| --- | --- |
| `NTB_STORE=xsolla` + `-PwithXsolla` | Opens the **Xsolla Pay Station** window, then writes the grant to Firestore |
| `NTB_STORE=xsolla` without the AAR | Says the SDK is not bundled and how to rebuild |
| `NTB_STORE=googleplay` / `amazon` / `samsung` | RevenueCat rail (if a key is configured for the *installed* store), then the Xsolla rail |
| debug, no rail at all | Simulated grant, flagged in the sheet as sandbox |

The release workflow builds both APK targets with `-PwithXsolla` and `NTB_STORE=xsolla`, so the
artifacts people install can actually open the payment window.

The compile-time value is only a **fallback**. At startup the app asks Android for its install
source (`getInstallSourceInfo`, via the `…/store` channel) and picks the matching rail, so one APK
behaves correctly on Play, the Galaxy Store and the Amazon Appstore. RevenueCat's generic key is
used only on a genuine Play install; on any other store the app uses that store's key or falls
through to the Pay Station instead of asking the Play project about a SKU it does not have.

Overridable without editing Gradle:

```bash
-PwithXsolla -PxsollaSdkVersion=3.1.4
-PwithXsolla -PxsollaMavenUrl=https://raw.githubusercontent.com/xsolla/xsolla-sdk-android/main
```

Xsolla retired the `com.xsolla.android:login` / `payments` / `store` `3.1.0` artifacts the
original design named — building with them fails with
`Could not find com.xsolla.android:store:3.1.0`. The current SDK is a single
`com.xsolla.android:mobile` artifact (Google-Play-Billing-shaped API, settles through Xsolla Pay
Station) served from a raw Maven tree on GitHub; that is what the bridge targets. The bridge is
reflective on purpose, so default builds never need the AAR on the classpath.

`.github/workflows/xsolla-rail.yml` builds with `-PwithXsolla` on every `android/**` change, so
the optional rail cannot rot silently again. `build-apk.yml` derives the Gradle flag from the
selected `store_rail`, so the two can no longer disagree.

### RevenueCat: products, not currency

RevenueCat's dashboard offers **in-app currency** alongside products. Do not use it for this
game — it is the wrong feature and its form will not accept the SKUs:

| | in-app currency | what the app needs |
| --- | --- | --- |
| code limit | 10 characters | `coins_100`, `coins_500`, `coins_1500`, `multimedia_pack` |
| what it is | a spendable balance RevenueCat tracks and debits for you | a real store product (`StoreProduct` / one-time `INAPP`) |
| what the SDK calls | currency APIs the app does not call | `Purchases.getProducts` + `purchaseStoreProduct` |

`GameStore._buyWithRevenueCat` looks the SKU up as a product; a currency code is invisible to it,
so it reports `no product` and hands over to the next rail. The coin balance in this game lives in
Firestore (`players/{uid}.coins`), granted by `grantCoins` — never in RevenueCat.

### Xsolla Login must accept device sign-in

`forAutoJWT` signs in by **device ID**, so the server has to be willing to create an account for
it. That is a dashboard switch, off by default:

**Publisher Account → Players → Login → Configure → Login API integration → Login with device ID → ON**

With it off, no account is created, and the next call reports `003-002 User not found` on a *JWT*
request — which looks like a catalogue fault and is not one. `Check Xsolla catalogue` in the store
sheet now recognises this shape and names the toggle, and prints the Login ID in use so it can be
compared with the dashboard.

### Xsolla catalogue: item *types* matter

The store sells in four shapes, and the SDK filters by type. The coin packs are **virtual currency
packages** (a *bundle* in SDK terms) and the Multimedia Package is a **virtual item**; asking for
them as a plain one-time product returns an empty list, which looks exactly like a missing SKU.

The bridge now enables both type bridges on `Config.Common` and retries the query per type:

```kotlin
Config.Common.getDefault()
    .withAllowVirtualCurrencyAsInApp(true)   // coin packs: virtual currency packages
    .withAllowBundlesAsInApp(true)
```

so an "Available" item in the dashboard resolves regardless of how the catalogue classifies it. If a
purchase still cannot be found, the sheet now names the item and tells you which type it expects.

### Purchases are consumed

Coin packs are consumable: the bridge calls `consumeAsync` before reporting success, so the same pack
can be bought again. The Multimedia Package is not consumed. The Firestore grant is keyed on the
purchase token, so consuming can never double-credit.

**Entitlements are optional.** `Attach` is offered next to every product, but this game reads
purchases (`CustomerInfo.allPurchasedProductIdentifiers`), not entitlements, because it sells
fixed packs rather than subscriptions. Leave them unattached, or create one `multimedia` entitlement
and attach only `multimedia_pack` — both work now. Before, restore looked *only* at entitlements, so
a correct catalogue showed "nothing to restore".

Create these as **products** (one-time / non-consumable), with the identifier matching exactly:

| identifier | type | Play Console product id |
| --- | --- | --- |
| `coins_100` | non-consumable | `coins_100` |
| `coins_500` | non-consumable | `coins_500` |
| `coins_1500` | non-consumable | `coins_1500` |
| `multimedia_pack` | non-consumable | `multimedia_pack` |

Coin packs are consumables in spirit, but the grant is idempotent on the order id in Firestore, so
a non-consumable keeps the SKU simple and prevents a re-purchase of the same pack from being
blocked. Grant them once per order and never let the store's own consumption logic decide the
balance.

### Where a purchase is stored

One document is the source of truth for every rail: `players/{uid}`.

```
players/{uid}
  coins: 1500                     # incremented transactionally
  multimediaUnlocked: true        # the permanent package
  unlockedEntitlements: [sku,…]   # appended on every payment
  updatedAt: <serverTimestamp>
  purchases/{orderId}             # ledger row: sku, store, createdAt
```

`applyPurchase` returns the post-write document and raises
`PurchasePersistenceException` if the cloud write fails, so the store sheet can distinguish
"paid and saved" from "paid but not saved" — it never claims the cloud copy exists when it does
not. `RESTORE` reads that document first (that is what recovers a purchase after a reinstall)
and only falls back to RevenueCat.

**Two things only the project owner can do**, and the Pay Station cannot charge without them:

1. Add the catalog in Xsolla Publisher Account → Store for project `322198`, using exactly
   the SKUs the app sends: `coins_100`, `coins_500`, `coins_1500`, `multimedia_pack`.
   A missing SKU is reported in the sheet by name.
2. Deploy the Firestore rules (`firebase deploy --only firestore:rules`) so
   `players/{uid}` is writable by its owner; otherwise the payment succeeds and the sheet says
   `NOT SAVED TO THE CLOUD` instead.

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

## 2b. Design system — "slate terminal"

The UI follows the production language of Dreadmoor (the studio's other
release), not a Material dashboard:

| Token | Value | Used for |
| --- | --- | --- |
| canvas | `#1E252B` slate | every screen background (never pure black) |
| panel | `#2A3239` | cards, rows, plates |
| chrome | `#161C21` | status bar, headers, docks |
| accent | `#00ACC1` cyan | **the only** interactive colour |
| danger | `#B71C1C` crimson | relay lost, redacted, horror beats |
| premium | `#FBC02D` | coins, locked pack |

Rules the code follows:

- **Flat, not floating.** Panels are a fill plus a 0.7px steel border. No drop
  shadows, no elevation, corner radii stay at 0–3px (the old build used 12–18px
  everywhere, which is what made it read as a generic app).
- **Two type voices.** `Michroma` (bundled at `assets/fonts/`) is the console
  voice: labels, headers, buttons, titles, always upper-case and letter-spaced.
  `Inter` is the human voice: chat bodies, prose, form input. No runtime font
  download, so the UI renders on a plane.
- **One accent.** Cyan means "you can touch this". Crimson means danger. Coins
  are the only yellow. Character name tags in group chats carry their own muted
  colour so a 795-message log stays readable.

Shared widgets in `lib/ui/widgets/common_widgets.dart`: `ConsoleHeader`,
`SlatePanel`, `ConsoleButton`, `GhostButton`, `StatusPill`, `RuleLabel`,
`GlassChrome`, `SlateNoise`. `NtbCard` / `NtbTag` / `NtbDivider` are thin
aliases onto these so nothing can drift back to the old look.

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
| 9 | Episode end stinger → Episode 2 waiting hub | `ui/screens/episode_end_screen.dart`, `ui/screens/episode_waiting_screen.dart` |

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

## 4b. Screen 9 — the stinger and the waiting hub

`@end_scene` (part 4, line 606) does not drop the player back to a menu. Screen 9 runs the
authored tail of the script and then parks them on a persistent waiting dashboard:

**Stinger** (`ui/widgets/episode_stinger.dart`) — executes the directives in script order:

| Directive | What the screen does |
| --- | --- |
| `@autosave slot="ep1_complete"` | commits the checkpoint, shows the cloud tick in the toast |
| `@unlock_achievement ach_ep1_clear` | achievement banner slides down over the fading scene |
| `@fade_out duration="3"` | 3 s fade to pure `#000000` with drifting ocean mist |
| `@stop_music fade_out="2"` → `@music bgm_to_be_continued.mp3` | crossfade |
| `@fade_in` + `@show_text` × 4 | NO TIDE BACK → EPISODE 2: SIDE EFFECTS → IN DEVELOPMENT → *hang in there until the next episode.* (italic, `#94A3B8`, faint `#22D3EE` glow) |
| `@fade_out duration="2"` | hands off to the waiting hub |

The cards come from the interpreter: `@show_text` is captured as an ordered `ShowTextLine`
list per run, so the stinger replays exactly what the script emitted (with
`defaultStingerCards` as the fallback when arriving from a finished save).

**Waiting hub** (`ui/screens/episode_waiting_screen.dart`):

* Crimson `⚠ SECTOR FOUR RELAY: OFFLINE — AWAITING SIGNAL RESTORATION` pill over a pulsing
  sonar sweep, last known coordinates `50 MILES OFFSHORE`.
* Episode badge: `EPISODE 1 COMPLETED • 100%` next to `EPISODE 2: SIDE EFFECTS — IN DEVELOPMENT`.
* Horizontally swipeable last-known-status cards for every character at `01:03 AM`
  (Suite A-2 signal lost, Jessica severed, Kathy unreachable, Kai standing by, Mom & Chloe
  unaware) — each card opens that thread in **read-only archive mode**.
* While You Wait: Review Chat Logs, Open Evidence Vault (`n/5 COLLECTED`), Replay Episode 1
  (re-asserts the Firestore economy first, so coins and the Multimedia Package survive),
  Follow EyesWatching Games (copies the studio link), plus the Multimedia Package upsell when
  it is not owned.

`ChatRoomScreen(readOnly: true)` suppresses the composer, the choice drawer and the puzzle
push, so re-reading history can never advance the script or spend coins.

Home Hub's RESUME RELAY detects a completed save and becomes `WAITING FOR SIGNAL` →
`ENTER WAITING HUB`, so a finished player always lands here until Episode 2 ships.

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
| `.github/workflows/xsolla-rail.yml` | `android/**` changes / manual | release APK built with `-PwithXsolla` (keeps the Xsolla rail resolving + compiling) |
| `.github/workflows/release.yml` | tag `v*` | split-ABI + universal APK attached to a GitHub Release |

Manual run (Actions → Build Android APK → Run workflow) lets you pick `apk` / `aab` / `both`,
the billing rail, and whether to bundle the Xsolla SDK.

---

## 9. Tests

```bash
flutter test          # 25 tests, ~7 s
```

| File | What it covers |
| --- | --- |
| `test/ntb_engine_test.dart` | pronoun interpolation, the expression evaluator, scene indexing, `@choice` nesting, `@if` block skipping, the nine-thread seed |
| `test/episode_playthrough_test.dart` | drives the **real** four-part script from `:: ep1_start` to `END OF EPISODE 1: THE CONTRACT` with a scripted player: verifies all 68 `@goto` targets resolve, every scene is reachable, no `{token}` leaks into a message, and that the Multimedia-Package path takes the premium branches |
| `test/widget_smoke_test.dart` | mounts every screen plus `MessageBubble`, **drives `BEGIN DEVICE` to the phone** (the boot-freeze regression), checks the asset tree, the declared fonts, and the four script files |

The playthrough is the interesting one — CI publishes its summary as a check notice:

```
PLAYTHROUGH messages=795 choices=29 scenes=34 evidence=17 pings=14 sounds=23
            ended=true endTitle=END OF EPISODE 1: THE CONTRACT
```

That run also caught real control-flow issues during development (choice loops that a
"always pick the last option" player never escapes), which is why the scripted player
dismisses the drawer once a scene repeats.

---

## 10. Verified build status

| Check | Result |
| --- | --- |
| `flutter analyze` | clean (no errors or warnings in `lib/` or `test/`) |
| `flutter test` | 25 passed |
| `.ntb` validation | 47 media references resolve, all `@goto` labels exist |
| Release APK (universal) | built, ~62 MB |
| Release APK (arm64-v8a) | built, ~56 MB |
| Release AAB (Play) | built, ~65 MB |
| Keystore signing | verified with a throwaway keystore (`apksigner verify` passes) |

Bundle size is dominated by art, music and the one MP4 — that is expected for a
fully-offline narrative game. The AAB is what Play ingests; Play then ships per-ABI
splits, so installs are much smaller.
