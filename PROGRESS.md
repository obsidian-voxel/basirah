# Basirah (بَصِيرَة) — status

## Verified on this machine (Windows, Flutter 3.44.8 / Dart 3.12.2)

| Check | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze` | **No issues found!** |
| Tests | `flutter test` | **88 passed, 1 skipped** |
| Android unit tests | `./gradlew :app:testDebugUnitTest` | **14 passed** (6 new) |
| Release APK | `flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64` | **exit 0** |
| Signing | `apksigner verify --print-certs` | **v3 only** on the 1.0.0 artifact (`v1`/`v2` false at minSdk 30), `CN=Haram Blur` |
| Permissions | `aapt2 dump permissions` | only `RECEIVE_BOOT_COMPLETED`, `POST_NOTIFICATIONS`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` — **no INTERNET** |
| UI renders | `flutter test test/ui_render_test.dart` | 16 PNGs in `build/ui-review/` |

Not verified: behaviour on a physical Android device or emulator. No device is
attached and the emulator package is not installed, so the overlay, the
accessibility flow and the release APK have been compiled and inspected, not
observed running.

## REA audit of the shipped APK

REA's `inspect_apk_signature` read the release APK and reported what
`apksigner` had not: the file declared **v2 only**. A v2-only app can never
rotate its signing key, so the signing config now sets v1 off, v2 and v3 on
explicitly. REA re-read the rebuilt APK and reports v2 and v3 with the same
certificate (`167e27d6…`), `schemes_agree_on_signer: true`, `self_consistent:
true`, strongest scheme v3.

Correction (2026-11-25): the 1.0.0 artifacts verify as **v3 only** —
`apksigner -v` reports v1 false, v2 false, v3 true on the universal APK and
on both per-ABI APKs. At minSdk 30 a v3 signature is all a device needs, and
v3 is the scheme that carries the key-rotation lineage this paragraph was
about, so the flag set above holds in spirit but not literally: apksigner
does not add a v2 block when v3 alone already covers minSdk.

`decode_android_resources` is still unavailable on this machine
(`capability_unavailable`: apktool is not on the selected Windows PATH), so
manifest and resource facts were read with `aapt2 dump badging/xmltree`
instead. That audit found and fixed:

- **targetSdk 34 with compileSdk 36.** Bumped to 36; Android 15+ enforces
  edge-to-edge, so the floating nav bar now clears the gesture inset
  (`16 + inset * 0.5`) instead of assuming a 16 dp margin.
- `android:enableOnBackInvokedCallback` enabled, so the system predictive-back
  animation applies on Android 13+.
- Every arm64 native library was checked for 16 KB page alignment (Android 15
  requirement): all eleven are 16 KB or 64 KB aligned.
- Permissions after the change are unchanged: boot, notifications and battery
  exemption only — still no `INTERNET`.

## Reference parity: features added after the rebuild

| Feature | Where | Enforced by |
|---|---|---|
| Custom block screen title and message | Advanced Settings → Custom Blocking | `BlockPrefs.screenTitle/Message`, drawn by `BlurOverlayView` |
| Cross block screen limit (5 blocks in 2 min → 5 min lock) | Advanced Settings → Blocking | `RepeatBlockGuard` + `setLock` on the overlay |
| In-app browser blocking (off by default) | Advanced Settings → Blocking | `NodeText` WebView detection in the service |
| Per-app allowed hours and daily limit UI | Block list → tap an app row | existing `ScheduleWindow` / limits, now reachable again |
| Long sentence lock is actually enforced | Settings lock panel, block list edits, protection-off | `lib/ui/lock_gate.dart` |
| 15 s countdown before protection can be disabled | Dashboard mode picker, Settings switch | `confirmWithDelay` |
| Morning affirmation gate (app-level) | Daily Affirmations → Morning gate | `needsMorningAffirmations` + `MorningAffirmationsGate` |
| Gambling / violence / drugs keyword packs | Block list → Keyword presets | shipped presets, unchanged |
| Adult URL patterns from the owner's export (`*q=*porn*`, `*.xxx`) | bundled asset, no UI | `adult_url_patterns.txt` → `BlockPrefs.urlPatterns` in the service |
| Full 952k-domain adult list | bundled hash index, no UI | `AdultDomainIndex` + `AdultHash`, built by `tools/build_blocklist_index.py` |
| Optional image/video result blocking | Advanced Settings → Blocking | `blockImageSearch` adds `search_image_patterns.txt` to the pushed patterns |

Not implemented, with the reason stated in `README.md`: VPN (excluded by the
project owner), custom redirect (needs a VPN or browser extension), phone-wide
morning lock (needs device-owner plus recording), partner OTP (needs a server),
and power-menu/reboot blocking (Android exposes no hook).

## What the previous pass did

BlockP's real screens (the 34 captures in `Downloads/BlockP/`) are dark navy
with a slate card, and also ship a light theme. The previous clone had a single
pale-blue layout with different tabs, so the UI layer was rebuilt:

- **New design system** (`lib/ui/blockp_theme.dart`): palette as a
  `ThemeExtension` with light and dark variants, Anek Latin type scale, 28 dp
  cards, 74 dp floating nav, compact 44×26 switch, warning banner, segmented
  pill, dialogs. Light colours come from the reference APK's resource table
  (`#E2EEFF` canvas, `#002954` ink, `#0076F4` primary, `#01BE5F` switch);
  dark colours were sampled from the captures (`#1B2531` canvas, `#253141`
  card).
- **Tabs are Dashboard, Block list, Premium, Calm, Support**, matching the
  captures instead of the previous Focus/Community pair.
- **Screens rebuilt**: dashboard (hero mark, mode, permission banners, streak
  strip, protection rows), block list (Blocklist/Whitelist, empty state, Add
  Items sheet for site/app/keyword), premium (gold ticket, checklist,
  comparison), calm (artwork, duration slider, allowed apps, prevent exit),
  support (privacy note, diagnostic copy, FAQ), advanced settings (blocking,
  general, social media, custom, data), permissions, accountability,
  affirmations.
- **No mascot.** The reference app's dog is replaced everywhere with Basirah's
  mark — a geometric aperture: three concentric circles (lens outline, iris
  ring and centre aperture dot), per the global Sharia rule. The mark carries
  no pointed or star-like geometry, no animate being and no face.
- **Branded as Basirah (بَصِيرَة)** — Latin and Arabic wordmarks on the
  dashboard, the morning gate and the premium ticket; the launcher icon, the
  adaptive icon, the splash, the web manifest and every user-facing string
  carry the new name. Amiri (SIL OFL) is bundled because the Latin faces have
  no Arabic glyphs.
- **No human figures.** The reference's head-and-shoulders profile button and
  Material's person, people, accessibility, handshake, smiley and robot glyphs
  are replaced by original abstract devices (interlocking rings, a viewfinder
  bracket, a droplet-and-bar, a rounded square and a system panel). The prayer
  row uses a plain clock dial: prayer times remain as behaviour and plain text,
  never as religious decoration.
- **Honest content.** No prices, no review logos, no chat/social links: the
  premium tab names what is free, support actions copy locally, and the social
  media section blocks apps rather than claiming to block their internal
  searches.
- **Real state only.** Block-list sites now persist (`FilterStore.customDomains`)
  and push to the service; every switch is wired to the engine.

## Bugs found and fixed in passing

- `currentStreak` returned **365** with an empty event log (it counted back
  from "no events" forever), and `weekEventFree` reported every day clean. Both
  now return zero/empty when there is no history, so a fresh install shows
  "Start your streak".
- The **release manifest carried `INTERNET` and `ACCESS_NETWORK_STATE`**, merged
  in from a library manifest, despite the app promising to be offline. Both are
  now removed with `tools:node="remove"`; the built APK has no network
  permission.
- Release signing pointed at `android/app/app/haram-blur-release.jks`
  (`file()` resolves against the module dir); it now resolves paths from
  `android/`.
- `AdaptiveIcon`/legacy launcher icons, splash background and a
  `monochrome` layer now use the new mark on the app's blue.

## False-positive blocks (18 Nov 2026)

Word detection stayed untouched; only the paths that fired without evidence
were narrowed:

- **Private mode** matched any text *containing* "incognito", so the browser
  three-dot menu ("New Incognito tab") blocked. `NodeText.isPrivateLabel` now
  compares normalised text for equality against state labels only
  ("You've gone incognito", "Incognito", "Private Browsing", "InPrivate"…);
  menu commands cannot match. A view-id hint is ignored inside a clickable
  ancestor, since menu rows carry ids such as `menu_item_incognito`.
- **Lock screen and system panels**: `com.android.systemui` /
  `com.android.keyguard` / `*.systemui` are skipped for hard blocks, node
  scans and captures, and the blur is not left floating over the keyguard.
- **"Installed after protection"**: the baseline only holds launcher apps, so
  system UI, input methods and background services looked new. The rule now
  requires `isLaunchable(pkg)` — a launcher icon. Split screen needs one too.
- **Secure windows** (`FLAG_SECURE`) and blank/dim screens capture as one flat
  shade and were still scored. `FrameHash.isFlat` drops a frame when ≥97% of
  pixels sit within 10 levels of the median luminance, so those frames never
  reach the detector.

Covered by `PrivateModeLabelTest` (menu strings rejected, state labels kept)
and `FrameFlatTest`; `:app:testDebugUnitTest` passes 27 tests.

## Release artefacts

```
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk   161 MB  (recommended)
build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk 149 MB
```

Build split per ABI: the universal APK carried the emulator libraries too and
was 219 MB for no benefit on a phone.

The size is dominated by the validated 88 MB nudity model plus the 16 MB
segmentation model; `MODEL_IO.md` explains why the 12 MB alternative is not
usable (AUC ≈ 0.5). Keys live in `android/key.properties` and
`android/app/haram-blur-release.jks`; both are git-ignored and must be backed
up, or future updates cannot be installed over this build.

## Known gaps

- Visual similarity is the goal, not pixel identity. Screens are compared
  against the captures through `build/ui-review/`, and the palette comes from
  the APK's resources, but exact pixel matching is deliberately not a
  requirement: readability, accessibility, Sharia compliance and working
  features come first.
- In-app blocking of searches *inside* social apps is not possible for a
  third-party Android app; those rows block the app instead.
- System-wide blur runs the whole-frame gate plus centre crops; the full
  segmentation cascade is used by the Image check screen.
- Unused experimental models (≈660 MB) remain in `assets/models/` for
  provenance and are not bundled.

## Blocking-logic follow-ups (18 Nov 2026)

Every item is enforced in `SystemWideBlurService`, not only in the UI.

| Change | Why | Where |
|---|---|---|
| "Block newly installed browsers" now read | The switch existed in Flutter and prefs but the service never read `KEY_BLOCK_NEW_BROWSERS` | browser baseline in `BlockPrefs`, check in `checkHardBlocks` |
| Typed addresses blocked before load | A page that has not loaded has no URL node and no pixels to judge | `TYPE_VIEW_TEXT_CHANGED` + 450 ms debounce + `AdultDomainIndex` |
| Trusted-site allowlist | 952k hashes cannot express an exception, so a false positive was unfixable | `filter_allowlisted_domains`, checked before every site list; Trusted website in the Whitelist tab |
| Package caches invalidated | `launchablePackages` / `browserPackages` were cached for the life of the process | `PACKAGE_ADDED/REMOVED/REPLACED` receiver clears both |
| Re-baseline / trust an app | A deliberate install looked like a bypass forever | `rebaselineNewApps`, `trustApp`, Advanced Settings → Re-check installed apps |
| Dismiss now expires | Dismissing a block covered a static page until the app changed | 20 s grace; rule scans keep running; a block in the grace does not count as a repeat strike |
| Private mode remembered for the visit | The label only exists on the incognito new tab, so the first navigation escaped | `privateSessionPackage` for the browser's foreground lifetime |
| Private labels in Arabic, Urdu, Turkish, Indonesian, Malay, German | Exact-match labels were English/French/Spanish only | `PRIVATE_LABELS` |
| Host canonicalisation | `pornhub.com.`, `porn%68ub.com` and Unicode hosts missed the index | `BlockPrefs.normalizeHost` (IDN folded to punycode), mirrored in Dart |
| Settings guard + audit | Settings → App info could stop or uninstall the app, and admin state was never recorded | `guardSettings` backs out of screens naming Basirah with uninstall/force-stop/accessibility/admin rows; `SecurityAudit` logs admin transitions, escapes and installs; Advanced Settings → Security audit |
| Usage and midnight | Blocked time counted toward the daily cap and pending seconds crossed midnight | `accountUsage` skips while the overlay is up; counters reset on day change; the cap includes pending seconds |
| Split screen via `windows` | Root bounds lie when an app draws full-bleed inside a small task | `isSplitScreen` reads `AccessibilityService.windows` first; `flagRetrieveInteractiveWindows` added |
| In-app browsers per app | One help page inside a shopping app forced the whole rule off | `advanced_inapp_browser_apps` scopes the rule; empty means all apps |
| Dart/native drift | Native ignored `wholeWord`; `BlockReason` lacked the reasons the service records | whole-word keyword list + `BlockMatcher(wholeWord)`; all wire reasons added |
| Policy cached per edit | Every window change re-split and lowercased every list | `prefListener` invalidation; `firstMatch` lowercases the page once |
| Notification shade scanned | `systemui` was skipped entirely, so notification previews were never read | keyword-only scan of `TYPE_SYSTEM` windows, no pixels, no app rules |
| Prayer-time blocking | Salah-aware scheduling without a server or location permission | `PrayerTimes` solar calculation from typed coordinates, windows enforced in `checkHardBlocks` |

New tests: `HostNormalizationTest`, `WholeWordTest`, `PrayerTimesTest`, plus
multilingual cases in `PrivateModeLabelTest`.

## Phase 1 test harness (19 Nov 2026)

Repeatable emulator suite under `tools/harness/`: `run_phase1.sh` (orchestrator),
`uiauto.py` (UI-tree helper), `serve.py` + `fixtures/` (loopback fixture pages),
`scenarios.md` (S01–S11 with expected outcomes), `physical-device.md` (what the
emulator cannot prove), `README.md` (how to run, how to read a failure).
`tools/build_x64.bat` no longer points at a hardcoded `C:\hb`.

Decisions worth keeping:

- The harness installs a **debug** x86_64 APK, because preference state is
  injected with `run-as`: force-stop, write the preference XML, then rebind the
  accessibility service so a fresh process loads exactly that state.
- Assertions read the app's own `EventLog` / `SecurityAudit` records, not pixels
  or log wording.
- Each scenario rewrites the whole preference file, so no scenario can inherit
  another's state and every event count starts at zero.

First runs (evidence in `tools/harness/results/`):

| Scenario | Result |
|---|---|
| S01 service configuration | PASS — the bound service requests `TYPE_VIEW_TEXT_CHANGED` |
| S07 Settings guard | PASS — leaves the app-info screen and audits `settings_escape` |
| S06 blocked app | Block confirmed by screenshot (“Blocked: Clock is on your blocklist”), but the `EventLog` assertion timed out at 20 s |
| S02/S03 keyword, S04/S05 typed URL, S08 notification | Not established — each was blocked by a harness or host problem, see below |
| S09/S10/S11 | Not established |

Findings from those runs (each one fixed in the harness, except where noted):

- The APK installed on the AVD was two days older than the source and did not
  request `TYPE_VIEW_TEXT_CHANGED`, so typed-address blocking could never have
  fired. This is exactly why S01 asserts the service configuration directly.
- Git Bash rewrites `/sdcard/...` and hands `/c/...` paths to `adb.exe` and
  `python.exe`; every device and native path is now converted explicitly.
- `settings put secure enabled_accessibility_services ""` is rejected by the
  device shell ("Bad arguments"), so the old “switch accessibility off” step
  silently did nothing; the harness now deletes the key.
- Port 8765 cannot be bound on this machine (`WinError 10013`), so the fixture
  server now binds an OS-chosen port and reports it.
- Chrome's first-run and notification prompts sit over the page and swallow
  `input text`; they are dismissed by node text, and `S04` fails with "the typed
  address never reached the address bar" instead of blaming the blocker.
- `cmd notification post -t "Phase 1 harness" …` loses its quoting through
  `adb shell`, so the body became “1”; it is now one quoted device command, and
  S08 first proves the body rendered in the shade.
- A single “System UI isn't responding” dialog stayed up across scenarios and
  stole input focus. The harness now dismisses it with **Wait** (never “Close
  app”) before each scenario.
- `SystemWideBlurService.scanNodeTree` now logs when it cannot read the active
  window, and what it did read. A silent scanner is indistinguishable from a
  clean page.

## Phase 1 session 2 (2026-11-20): browser page text, and what is still open

### Chrome page text was never scanned (fixed)

The `Node scan:` diagnostics from session 1 resolved this. Chrome hands an
accessibility client only its own browser chrome — 13–38 nodes, ~150 characters,
no page subtree — until **another** accessibility client asks the window for its
children, after which the page appears. `rootInActiveWindow` alone was therefore
structurally unable to see page text, which is why `uiautomator` proved `whine`
was on screen while the scanner saw nothing.

- `SystemWideBlurService.scanNodeTree` now enumerates the active window **plus
every `TYPE_APPLICATION` window owned by the package** (`appWindows(pkg)`) and
merges the results (`mergeScans()`); it also logs `wins=` and the window types,
so the next regression is measurable.
- `accessibility_service_config.xml` gained
`flagIncludeNotImportantViews|flagReportViewIds` (13 → 37 nodes on a Chrome
page), without which the page's text nodes are not reported at all.

After both changes the service logs `nodes=40 chars=353 webview=true`, then
`Keyword match: pkg=com.android.chrome`, then enforcement. S02 and S03 pass.

### Harness defects found and fixed this session

- `EventLog` is stored JSON-escaped (`&quot;`) inside the pref XML, so every
  `EventLog`/`SecurityAudit` assertion silently matched nothing; `read_prefs`
  now decodes the entities. This is what made S06 pass.
- `logcat -t 1500` truncated the buffer *before* tag filtering, so scans from the
  relevant minute were dropped; `-t` is gone.
- Pre-push `ui_dump` used an unbound `SCENARIO_ID` under `set -u`.
- Fixtures must not be named after the term they contain: a URL hit records
  `r=url`, which hides whether page text was scanned. Hence `term-a.html`
  (`cnnam`) and `term-b.html` (`gucci third leg`).
- Fresh Chrome shows a full-screen *Make Chrome your own* sign-in page that
  outlasts a single dismissal attempt; `browser_open_page` now loops, dismissing
  known first-run prompts until the page **or** the block overlay is on screen,
  and reports "the fixture page never rendered" separately from a failed block.
- `acc_wait` 40 → 150 s (a cold Flutter start on this AVD takes 60–90 s),
  `settle_device()` (wake, keyguard, stay awake, 720×1560 @ 320 dpi, 45 s),
  `reset_ui()` per scenario, bounded device calls (`PHASE1_DEV_TIMEOUT`), and
  `ensure_alive()` aborting with exit 2 rather than hanging when the AVD dies.
- `tap_text`/`type_text` drive the browser by node identity (never hardcoded
  coordinates) and type in short bursts, because the omnibox dropped characters
  when the whole string was sent at once.

### Still open (evidence in `tools/harness/results/`)

- **S04** never passed: `input text` still fails to reach Chrome's omnibox
  (`typed_visible` is false), so the pre-load URL block is unproven.
- **S07** was open in session 2 and is resolved in session 3 (below): the guard
  already worked, the harness could not observe it.
- **S10** never passed: the service rebinds after a reboot but does not block the
  keyword page; the reboot frequently wedges the emulator instead.
- **S11** is a documented `SKIP`: `am start --windowingMode` does not produce a
  real split screen on this image.
- **S08** passed once (`20261119T212757Z`) but is not reproducible: the shade
  often fails to expand while System UI is ANRing.
- The emulator ANRs *with the accessibility service unbound* (Chrome alone), and
  dies silently mid-run on a freshly wiped 4 GB / 6-core AVD; it also reaches a
  state where `uiautomator dump` writes 47 bytes and every assertion in that
  scenario degenerates. This is an environment limit, not an app verdict.
- There is no pref that runs the rules without the screenshot/ML pipeline, so
  app-caused and emulator-caused load cannot be separated on this image.

## Phase 1 session 3 (2026-11-21): S07 resolved — the guard worked, the harness could not see it

### Root cause

A manual `am start -a android.settings.APPLICATION_DETAILS_SETTINGS -d
package:com.haramblur.haram_blur` proved, before any code change, that the app
detected the page, recorded `settings_escape` and left it with
`GLOBAL_ACTION_BACK`. Three harness defects hid that:

- **Vacuous escape check.** "Was the page left?" was answered by looking for an
  `InstalledAppDetails` node. Android 16 re-hosts the page as
  `com.android.settings/.spa.SpaActivity`, so the node was never present and the
  check passed from the first second without proving anything.
- **Stale service label.** `acc_bound()` and S01 grepped `dumpsys accessibility`
  for `label=Haram Blur`, a string that no longer exists — the device reports
  `Service[label=Basirah, …]`. The bound check was false with the service running
  perfectly, so scenarios raced a rebind or failed on their first assertion.
- **Audit read too early / wrong window.** The count was taken from state dumped
  before the guard wrote it, and the read relied on `rootInActiveWindow`, which on
  a re-hosted SPA subtree reports only the fragment root.

### Fix (app)

`android/app/src/main/kotlin/com/haramblur/haram_blur/SystemWideBlurService.kt`:

- `SETTINGS_PACKAGES` + `isSettingsPackage()` recognise Settings by package (exact
  and prefix) instead of one activity class, so `.spa.SpaActivity`,
  `SettingsHomepageActivity` and future re-hostings all reach the guard.
- The text gate is unchanged and still does the filtering: the page must show our
  application label next to a destructive word (`protectionSettingsWord()` returns
  the matched word, e.g. `uninstall`). Ordinary Settings screens are therefore
  still not treated as an escape.
- `guardSettings(pkg)` scans the active window plus every `TYPE_APPLICATION`
  window owned by Settings and merges them (`appWindows` / `mergeScans`), the same
  fix that made Chrome's re-hosted page readable.
- Repeat accessibility callbacks for one page no longer multiply the record: a
  screen signature plus a 10 s window (`SETTINGS_AUDIT_MS`) suppresses duplicate
  entries, while a genuine second escape is still recorded.
- `Log.d` names only the matched action word, never page text.

No other detection threshold, rule or permission changed.

### Fix (harness, `tools/harness/run_phase1.sh`)

- `APP_LABEL` is read from `res/values/strings.xml`; `acc_bound()` and S01 match
  `label=$APP_LABEL,`.
- `audit_count()` / `audit_last_detail()` count `SecurityAudit` wire entries in the
  preference file the app itself writes, and each scenario snapshots
  `prefs_<ID>_after.xml`.
- S07 now proves its preconditions instead of racing them: `am start -W` must
  report `Status: ok` and a `com.android.settings` component; the audit entry must
  appear and must name `Basirah`; enforcement means the page is gone; exactly one
  entry may be added; ordinary `android.settings.SETTINGS` is held open for 8 s as
  a negative control.

### Result

S07 passes: `app-info page detected, backed out and audited once; ordinary Settings
untouched` — with the strict "the entry names Basirah" assertion in
`tools/harness/results/20261121T165351Z/`, and without it in the four runs
`20261120T234439Z`, `20261120T234739Z`, `20261120T235057Z`, `20261120T235628Z`.
In `20261121T165351Z/prefs_S07_after.xml` the post-state holds exactly one
`device_admin` and one `settings_escape` entry, and the device log records
`Settings guard: com.android.settings shows "uninstall" next to our name` followed
by `repeated callback for the same screen, not recorded twice`.

Build: `flutter build apk --debug --target-platform android-x64` → `BUILD_EXIT=0`
(`tools/harness/build_s07.log`). The APK these runs exercised,
`build/app/outputs/flutter-apk/app-debug.apk`, is 396,380,606 bytes and newer than
`SystemWideBlurService.kt`, so the installed code is the fixed code.

### Environment note (cost the most time in this session)

A cold boot now stalls at host-Vulkan initialisation: no adb device appears and
`emulator.log` stops at "Deciding if GLDirectMem/Vulkan should be enabled", so the
harness waited on `adb wait-for-device` forever. `-no-window` was worse: the
framebuffer stayed black, `uiautomator dump` failed and the guard logged
`no window for com.android.settings`, so nothing could be observed. S07 passes
with `-gpu swiftshader` and a window; `results/20261121T163918Z/` is the headless
attempt, kept as evidence of that environment limit rather than an app result.

### Still open (unchanged this session)

- **S10** reboot protection: the service rebinds after a reboot but does not block
  the keyword page. Unexplained, in order: binding present, preferences restored
  before the first scan, detector initialised, window scan returning nodes,
  matcher ready, first screen captured at all. The reboot also frequently wedges
  the emulator, so this needs a restart-tolerant harness step before it can be
  diagnosed.
- **S04** typed-URL pre-load block, **S08** notification shade reproducibility, and
  **S11** split-screen `SKIP` stand exactly as recorded in session 2.

## Phase 1 session 4 (2026-11-23): S10 — protection after a reboot

### Objective and outcome

S10 ("protection restores itself after a reboot, without Basirah being opened")
was investigated stage by stage. The app-side root cause is fixed: after
`adb reboot` the service connects, restores its preferences, adopts the window in
front, reads it and loads the matcher, all with no app opened and within seconds
of the boot. **S10 has not yet passed end to end on this host** — the final block
was never observed, because the emulator dies or its `system_server` ANRs a few
minutes into each attempt, and on the last attempts the window in front was a
system ANR dialog rather than the browser. Everything below separates what the
logs prove from what the environment prevented.

### Root cause (each link has a log line behind it)

1. **The accessibility service arrives late after boot.** It is not
   `directBootAware`, so Android starts it only after the user is unlocked;
   `BootReceiver` and the service therefore run tens of seconds after
   `sys.boot_completed`.
2. **The old start-up blocked the main thread.** `DartDetector.ensureStarted()`
   ran on the service's main thread and took 18–47 s at cold boot (measured:
   `DETECTOR_READY after=14466ms`, `after=41156ms`), and every window callback
   queued behind it.
3. **`onUnbind` cleared `running`.** A rebind (Android re-creating the
   connection) left the service thinking it was off, so an already-matched page
   was skipped.
4. **Rule scans queued behind face detection.** The capture thread spent 10–30 s
   per frame in `FaceBoxes.detect` (`TimeoutException: Timed out waiting for
   Task`), so the keyword pass waited behind it.
5. **The first window read was treated as the last word.** A browser that
   appears before its web content exists is read as an empty/short tree, and no
   later window event follows the page rendering.

Failing lifecycle stage, in the language of the log: **the first usable window
was not scanned**. `FIRST_WINDOW_AVAILABLE` and `FIRST_SCAN_COMPLETED` were
reached, but the scan either read a still-empty tree or the wrong package, so
`PROTECTION_ACTIVE` never followed.

### Fix (app, `SystemWideBlurService.kt`)

- Lifecycle instrumentation (`Log.i`, tag `HaramBlur`, package names and counts
  only, never page text): `SERVICE_CONNECTED`, `PREFERENCES_RESTORED`,
  `PROTECTION_ARMED`, `FIRST_WINDOW_AVAILABLE`, `FIRST_SCAN_COMPLETED`,
  `MATCHER_READY`, `DETECTOR_READY`, `BOOT_RECEIVED`, `SERVICE_UNBOUND`.
- `resumeAfterRebind()`: a rebind reuses the existing worker, capture executor
  and Dart engine instead of building a second of each; `onUnbind` no longer
  disables the service.
- `adoptForegroundWindow()` runs on connect and on every tick while
  `foregroundPackage` is null, so an app already on screen is judged without a
  new window event.
- A dedicated `scanHandler` (`haram-blur-scan`) thread keeps rule scans off the
  capture thread.
- The tick re-reads the foreground app on every beat (`requestScan` +
  `scanInFlight`), so a page that renders after the first read is still judged;
  `scanNodeTree`'s own 1 s throttle bounds the cost.
- Before each retry the tick now asks the window tree which package is really in
  front (`adoptForegroundWindow()` returns it), because window events left
  `foregroundPackage` naming the launcher while the browser held focus.

### Fix (harness, `tools/harness/run_phase1.sh`)

- The reboot gate is the kernel `boot_id`, not `sys.boot_completed` (which still
  reads `1` from the previous boot for seconds — run `20261122T084008Z` asserted
  against the old boot).
- Post-reboot `acc_bound` is a bounded wait, not an instantaneous read.
- **No `uiautomator` after the reboot**: every `UiAutomation` session tears down
  third-party accessibility connections on this image (system log:
  `Registering UiTestAutomationService` immediately before each
  `SERVICE_UNBOUND`). Run `20261122T102121Z` proved this: the service was bound
  and healthy, the harness's own dump unbound it, and Chrome then opened with no
  service attached. `settle_device 1` skips the dialog pass instead.
- Chrome's first-run card is finished **before** the reboot (`chrome_ready` on a
  benign page), because after the reset a `VIEW` intent opens "Make Chrome your
  own" instead of the page, so the fixture was never requested
  (`results/20261122T211150Z`).
- Fixed taps clear a boot-time ANR dialog and the first-run card post-reboot,
  where `uiautomator` cannot be used.

### Evidence

| Run | What it proves |
| --- | --- |
| `results/20261122T083015Z`, `…095458Z` | post-reboot `SERVICE_CONNECTED` → `PREFERENCES_RESTORED` → `PROTECTION_ARMED` → `FIRST_WINDOW_AVAILABLE` → `FIRST_SCAN_COMPLETED` → `MATCHER_READY` in ~3 s |
| `results/20261122T102121Z` | service bound and healthy, then unbound by the harness's own `uiautomator` dump |
| `results/20261122T205044Z` | full lifecycle after reboot; Chrome never opened (wedged guest), so no block |
| `results/20261122T211150Z` | screenshot: Chrome's first-run card with "Process system isn't responding" above it |
| `results/20261123T084827Z` | Chrome scanned after boot, 264 chars, no URL: the offline/first-run page |
| `results/20261123T091057Z` | fixture requested after reboot (`GET /keyword.html 200`), but the foreground window was the system ANR dialog (`pkg=android`), never the page |
| `results/20261123T094754Z` | page visibly rendered with "whine" (`S02-no-block.png`) while the app's single early scan had read only the toolbar |
| `results/20261123_manual_chrome.png` | post-reboot Chrome on its first-run card, `FirstRunActivity` focused |

Builds: `tools/harness/build_s10g.log` (`BUILD_EXIT=0`, stale-foreground fix),
`tools/harness/build_s10h.log` (`BUILD_EXIT=0`, per-tick rescan).

### Regressions (run `results/20261123T095928Z`)

- **S07 PASS** — app-info page detected, backed out, audited once; ordinary
  Settings untouched.
- **S02 FAIL** — "the fixture page never rendered in Chrome" (the page did not
  render within 60 s on this boot).
- **S03 FAIL** — "blocked 0 of 2": the app's own log shows it scanning
  `com.google.android.apps.nexuslauncher` every 2 s while Chrome was in front,
  i.e. the accessibility foreground was wrong, not the term rules.
Earlier session results for S01/S05/S06/S07/S09 are unchanged in
`tools/harness/results/`.

### Environment limits (what actually blocked this session)

- The emulator process exits on its own 5–20 minutes after boot (no crash line;
  `qemu-system` simply disappears). Windowed `-gpu host`/`angle_indirect` hang at
  SwiftShader/Vulkan init once the host driver has been exercised; deleting
  stale `%TEMP%\AndroidEmulator` state restores a windowed `-gpu swiftshader`
  boot (~150–190 s).
- After `adb reboot` the guest frequently wedges: `adb` lists the device but the
  shell does not answer, or `system_server` ANRs and its dialog owns the
  foreground window (`pkg=android`).
- Chrome on the reset profile needs its first-run flow completed once; a
  reboot-shaped test cannot do that after the reboot without `uiautomator`.

### Still unverified / next task

- End-to-end S10 (keyword page blocked in Chrome after a reboot, with
  `PROTECTION_ACTIVE` recorded) is **not** verified. The remaining gap is
  environmental: a boot whose `system_server` is healthy and whose browser is
  the foreground window.
- The per-tick rescan added in this session is compiled and exercised
  (`results/20261123T095928Z` shows it scanning every 2 s) but not yet proven to
  block after a reboot.
- **Next task:** rerun S10 on a device/emulator that survives a reboot (a
  physical device, or a fresh AVD on a host whose GPU driver has not wedged),
  and confirm `PROTECTION_ACTIVE pkg=com.android.chrome reason=keyword` plus a
  `keyword` row in the app's event log. Then re-run S02/S03/S07 on the same boot.

## Protection modes, Device Owner and device controls (2026-11-23)

Two protection tiers now exist: **Standard** (no Device Owner required) and
**Hardened** (Device Owner). The rule throughout is that the app never shows a
green state it has not read back from Android.

### Architecture

| Layer | File | Responsibility |
|---|---|---|
| Pure policy logic | `PolicyEvaluator.kt` | tiers, health states, restriction set, power actions, transitions; no Android imports, JVM-testable |
| Device Owner wrapper | `DeviceOwner.kt` | `DevicePolicyManager` only: `safe_boot`, `apps_control`, `factory_reset`, `uninstall_blocked`; snapshot/apply/clear/read-back |
| Health + audit | `ProtectionHealth.kt` | prefs keys (`hb_protection_tier`, `hb_last_scan_at`, `hb_last_service_connect_at`, `hb_last_boot_at`, `hb_boot_recovered_at`, `hb_matcher_ready`, `hb_last_health`, `hb_policy_signature`, `hb_accessibility_granted`, `hb_device_owner`, `hb_detector_error`, `hb_last_service_interrupt_at`), transition audit, `samsungNote()` |
| Power controls | `PowerControls.kt` | restart / turn off; `GLOBAL_ACTION_POWER_DIALOG` unless a verified Device Owner restart can use `reboot()`; audits `device_control` |
| Channel | `MainActivity.kt` | `getProtectionReport`, `setProtectionTier`, `applyHardenedRestrictions`, `removeHardenedRestrictions`, `restartDevice`, `powerOffDevice`, `changePolicies`, `powerResult` |
| Service hooks | `SystemWideBlurService.kt` | `onServiceConnected`, `onServiceUnbound`, `markScan`, `onDetectorState`, `detectorError()`, `openPowerDialog()` |
| Boot | `BootReceiver.kt` | `ProtectionHealth.onBoot`, shared accessibility check |
| Flutter | `lib/services/protection_service.dart`, `lib/ui/protection_screen.dart` | report/state model, controller, dashboard, provisioning dialog, confirmations |
| Docs | `docs/PROTECTION.md` | modes, restrictions, provisioning, recovery |

### Decisions worth keeping

- **One protection service.** `SystemWideBlurService` remains the single
  accessibility service; nothing was added beside it.
- **Requested tier is stored separately from the effective tier.**
  `effectiveTier(requested, isDeviceOwner)` returns `hardened` only when
  `DevicePolicyManager.isDeviceOwnerApp` independently agrees, so a device that
  lost Device Owner drops back to Standard instead of claiming Hardened.
- **No invented shutdown API.** Android exposes no app-callable power-off, so
  both controls open `GLOBAL_ACTION_POWER_DIALOG`; only a verified Device Owner
  restart uses `DevicePolicyManager.reboot()`.
- **`clearDeviceOwnerApp` is not used.** It is deprecated and testing-only, so
  the recovery documentation states the truth: removing Device Owner needs a
  factory reset on a production build.
- **Unsupported is reported as unsupported.** Every restriction row shows
  *Active* only after reading the policy back; otherwise it says needs
  provisioning, refused, or unknown.
- Dart tests inject a `ProtectionController` with a fake `NativeBridge` rather
  than overriding the test platform, which tripped a `flutter_test` invariant.

### Verification

| Check | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze` | **No issues found!** |
| Dart tests | `flutter test` | **102 passed, 1 skipped** |
| Android JVM tests | `./gradlew :app:testDebugUnitTest` | **BUILD SUCCESSFUL**, 68 tests |
| UI renders | `test/ui_render_test.dart` | `protection_light.png`, `protection_dark.png` |
| Debug APK | `flutter build apk --debug` | **FAILED** (third attempt) — `:app:mergeDebugNativeLibs`: `There is not enough space on the disk`. Host `C:` was at 3.0 GB free of 238 GB (99% used), so the APK never linked |

The APK failure is a **host disk** failure, not a compile error: Gradle needs
several GB to merge the bundled native libraries and the model assets, and 3 GB
was not enough. The debug build must be re-run after space is freed before this
work can be called compiled.

### Not verified

- No physical device or emulator was available, so overlay, accessibility
  rebinding, the provisioning flow and both power controls are compiled and
  unit-tested, not observed.
- Device Owner itself was never provisioned: the JVM tests cannot be an owner
  and nothing in this repository acts as one. A disposable device or AVD is
  required, per `docs/PROTECTION.md`.
- Samsung One UI behaviour (power menu, background kills, Device Owner policy
  interaction) is documented as a note, not as a validated result. No claim is
  made about the Galaxy A56.

### Next task

Free disk space on the host, re-run `flutter build apk --debug` to green, then
run the Device Owner procedure on a disposable AVD: provision, apply the
restrictions, read each row back as *Active*, reboot, confirm Safe Mode is
refused, remove the restrictions and confirm an uninstall works.

## UI audit and redesign (2026-11-25)

The previous pass copied BlockP pixel for pixel. On a real screen that read as
someone else's app with the name filed off, and several of the copied
measurements were actively broken:

| What the replica did | Why it failed on screen | What replaced it |
|---|---|---|
| Arch cut out of a saturated blue gradient | The arch framed a 294 dp mascot slot this app has no artwork for, so the top third of every tab was empty chrome | One calm tinted canvas (`#F3F6FC` light, `#0C1521` dark), no arch, content starts at the top |
| Fractional type sizes (18.2, 22.4, 15.2…) | Sizes copied from another device's density bucket; headings did not line up across tabs | One scale: 11 / 12.5 / 13.5 / 15 / 20 / 26 / 30 / 32 in AnekLatin |
| Gold "Full Access" ticket with stars and perforation on Premium | Looked like a lottery ticket for an app that sells nothing; the text under it said everything is free | "Everything included" header, a plain hero with three facts, feature rows, "Total to pay — Nothing" |
| Clip-art mountains, tent and sun on Calm | Decoration the app never earned, and a landscape that says nothing about a session timer | Navy-to-blue hero with the countdown dial (ring + remaining time) as the subject |
| Floating nav stadium with a 62.5 dp circle that overflowed its own top edge | It covered the last card on **every** tab; `extendBody: true` let content slide under it | Docked bar, 62 dp, `extendBody: false`, scaffold reserves its height; the selected tab is a tinted chip |
| Mountain-with-flag icon for Calm | At 22 dp the two slopes read as a pair of legs, i.e. a human figure, which the project's Sharia rules forbid | A timer dial: ring, two hands, centre dot |
| Three stacked warnings for one missing permission on the dashboard | The same problem, said three times, in three colours | One setup banner with a count and an arrow; the status card states the truth once and never claims enforcement while the service is off |
| "Please provide permissions (3) Essential permissions are required…" on Block list | Two sentences jammed together with no separator | "3 essential permissions are off" |

Every screen is now built from the same pieces in `lib/ui/blockp_theme.dart`:
`BpCanvas`, `BpPage`, `BpHeader`, `BpSectionLabel`, `BpCard`, `BpRow`,
`BpSwitch`, `BpButton`, `BpOutlineButton`, `BpSegmented`, `BpEmpty`,
`BpWarningBanner`, `BpBottomBar`. The public API of that file was kept, so the
other screens and the test suite compile unchanged.

### Verification

| Check | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze` / `dart analyze lib` | **No issues found!** |
| Tests | `flutter test` | **102 passed, 1 skipped** |
| UI renders | `flutter test test/ui_render_test.dart` | 20 PNGs in `build/ui-review/`, light and dark |
| Debug APK | `flutter build apk --debug` | **exit 0**, installed on `emulator-5554` |
| On device | `adb install -r` + `adb exec-out screencap` | Setup, dashboard, Block list, Premium, Calm and Support observed rendering on an android-36 x86_64 AVD; captures in `build/device/` |

### What the emulator pass changed

Running the app on a real Android surface found things the widget renders did
not: the run-together permission banner, the repeated "No hours or daily limit"
line on every app row, the calm glyph reading as a figure, and the Calm
gradient's visible banding. The first three are fixed; the banding is a
software-GPU artefact of the headless emulator and has not been seen on real
hardware, so it is left as is rather than "fixed" blind.

### Not verified

- Still no physical device: overlay drawing, accessibility rebinding, the
  Device Owner flow and the models under real camera/browser traffic remain
  compiled-and-unit-tested, not observed.
- The headless emulator's SystemUI ANRs under load (`-gpu swiftshader_indirect`).
  That is the emulator, not the app: screenshots were taken after
  `settings put global hide_error_dialogs 1` and `svc power stayon true`.
- Committed and tagged as `v1.0.0`; see the release section at the end of this
  file for the artifact and device evidence.

## Release build and tag (2026-11-25)

### Disk

| Step | Free on `C:` |
|---|---|
| Start of session (host 99% full) | **4.6 GB** |
| After deleting regenerable build output | **9.5 GB** |

`build/` was 4.8 GB, of which `build/app` was 4.3 GB. Deleted only regenerable
output: `build/app`, `build/flutter_litert`, `build/unit_test_assets`,
`build/test_cache`, `build/jni`, `build/shared_preferences_android`,
`.dart_tool`. Kept: source, `assets/models/nsfw_int8.tflite`, the release
keystore and signing config, and the `build/device` / `build/ui-review`
captures. No per-ABI split, native-merge change or off-volume build directory
was needed: one cleanup pass made every build below run to completion.

### Artifacts (signed, release)

| File | Size (bytes) | versionCode | Role |
|---|---|---|---|
| `build/app/outputs/flutter-apk/app-release.apk` | 229,346,630 | 1 | universal (arm64-v8a, armeabi-v7a, x86_64) — the F-Droid artifact |
| `build/app/outputs/bundle/release/app-release.aab` | 202,480,205 | 1 | Play upload; `flutter build appbundle --release` **exit 0** |
| `app-arm64-v8a-release.apk` | 163,726,831 | 2001 | per-ABI split |
| `app-x86_64-release.apk` | 169,887,553 | 4001 | per-ABI split, used for the emulator pass |

All four read `versionName='1.0.0'`, `targetSdk 36`, package
`com.haramblur.haram_blur`, matching `pubspec.yaml` (`version: 1.0.0+1`) and
`docs/fdroid/com.haramblur.haram_blur.yml` (`versionName`, `versionCode: 1`,
`commit: v1.0.0`). The universal APK keeps versionCode 1 because Flutter's
per-ABI builds override it with 2001/4001.

Signing: `apksigner verify` → **Verifies**, v3 true (v1 and v2 false, which is
what minSdk 30 plus a v3 signature produces), `CN=Haram Blur, OU=Release,
O=Haram Blur`. `jarsigner -verify` → **jar verified** for the AAB.

Inside the universal APK: `assets/flutter_assets/assets/models/nsfw_int8.tflite`
87,774,224 B, `assets/blocklists/adult_domains.idx` 7,618,080 B,
`adult_url_patterns.txt`, the Amiri and AnekLatin fonts, and
`lib/{arm64-v8a,armeabi-v7a,x86_64}/libapp.so`. The AAB carries the same assets
plus `BUNDLE-METADATA/…debugsymbols/*.so.sym` for all three ABIs.

### The release variant on a device

First ever run of the minified build — R8, the ProGuard keeps for the Flutter
plugins and the 84 MB tflite asset were all unproven in release. On
`emulator-5554` (android-36, x86_64):

- `adb install` → `Success`; `dumpsys package` reads back
  `versionCode=1 versionName=1.0.0 minSdk=30 targetSdk=36`;
- launch opens the setup page ("Finish setting up", three permission rows,
  "Do this later") — the redesign, its icon fonts and its bundled assets all
  survived minification;
- "Do this later" lands on the dashboard: status card, "3 permissions left to
  finish setup", the streak week with today marked, the bypass rows, and the
  docked five-tab bar;
- no `FATAL` / `AndroidRuntime` line in `logcat`, and the process stays alive
  across both screens.

Run twice: once with `app-x86_64-release.apk` and once with the universal
`app-release.apk` (the artifact the recipe will download). Captures:
`build/device/rel-01.png`, `rel-02.png`, `rel-03-universal.png`,
`rel-04-universal-dashboard.png`.

### Environment defect found and fixed

`flutter build appbundle --release` first failed with "Release app bundle failed
to strip debug symbols from native libraries" even though Gradle had reported
`BUILD SUCCESSFUL` and the AAB was complete. `--verbose` showed the real cause:
Flutter's post-build check shells out to
`cmdline-tools/latest/bin/apkanalyzer.bat`, whose unquoted classpath splits on
the space in `C:\Users\H P\Android\sdk` and dies with
`ClassNotFoundException: P\Android\sdk\...`. A junction at `C:\dev\android-sdk`
plus `flutter config --android-sdk C:\dev\android-sdk` gives the check a
space-free path, and the bundle now finishes **exit 0**. That is a Windows
path-with-space bug in the Android SDK helper script, not in Basirah.

### Still open

- No physical device: overlay drawing, accessibility rebinding and the Device
  Owner flow are still compiled-and-tested rather than observed.
- BlazeFace has still never been validated on a device.
- F-Droid still needs a maintainer conversation about Flutter `srclibs` and
  shipping an 84 MB model; the recipe itself now resolves, because the tag
  exists.
