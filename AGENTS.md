# AGENTS.md — Basirah

## What this project is

`haram-blur` is a Flutter/Android app that blurs nudity on-device and blocks
apps, sites and keywords. The current work is a **visually similar rebuild of
the BlockP Android app** ("BLock P app") inside this existing project rather
than as a separate codebase.

Visual similarity is the goal, not pixel identity. Layout, spacing and type
may be measured against the reference captures, but exact pixel matching is
not a requirement and must never trade away clarity, Sharia compliance,
accessibility or working features. The reference is a design guide, not a
specification to copy literally.

The reference app and all captured evidence live outside the repo:

- Reference APK + XAPK: `C:\Users\H P\Documents\blockp-reference\blockp.apk`, `blockp.xapk`
- Reference screenshots (24 wide captures + 36 tab captures): `C:\Users\H P\Documents\blockp-reference\shot_*.png`, `st*.png`
- Cropped UI regions for pixel matching: `C:\Users\H P\Documents\blockp-reference\user\*.png`
- Extracted icon vector data: `C:\Users\H P\Documents\blockp-reference\vec\*.txt`
- Decoded APK strings/resources: `C:\Users\H P\Documents\blockp-reference\strings_vals.txt`, `res.txt`, `apk_contents\`
- BlockP app icon: `blockp_icon.png`

This directory is **reference material, read-only**. Never edit it.

## Hard constraints

1. **Islamic Sharia compliance, all UI and assets.** No animal mascots or
   avatars (the BlockP dog mascot must never be reproduced), no human faces or
   figures, no prohibited imagery, no sacred symbols used decoratively. The
   Basirah keeps the reference's layout and behaviour but replaces any
   disallowed artwork with original abstract/geometric equivalents, and says
   so plainly.
2. **Fully offline.** No network calls, no INTERNET permission, no accounts, no
   server, no telemetry. Any copy promising community features must stay
   honest about what is local-only.
3. **No fake behaviour.** Every switch, slider, list row and button must
   persist and actually drive the native enforcement layer. No placeholders,
   no no-op handlers, no `TODO` stubs.
4. **Android target:** `applicationId com.haramblur.haram_blur`, minSdk 30,
   targetSdk 34. Kotlin service layer under
   `android/app/src/main/kotlin/com/haramblur/haram_blur/`.

## Protection rules (permanent)

These are architectural rules, not preferences. Changing them changes what the
app claims about a phone.

1. **One protection service.** `SystemWideBlurService` is the only service that
   observes the screen or enforces blocking. Hardened Protection adds Device
   Owner policy, never a second service.
2. **Standard Protection never needs Device Owner.** It must keep working on an
   ordinary Android 11+ install with only the accessibility grant.
3. **Hardened is a verified claim, not a switch.** `PolicyEvaluator.effectiveTier`
   returns `hardened` only when `DevicePolicyManager.isDeviceOwnerApp` is true.
   The stored request is separate (`hb_protection_tier`) and the UI says when the
   request is not in effect.
4. **Never provision, reset or restrict without a human action.** Basirah must
   not call `set-device-owner`, must not start a factory reset, and must not
   apply a device policy without an explicit in-app confirmation that lists what
   it prevents, what it does not, and how to reverse it.
5. **Do not invent power capabilities.** Restart is
   `GLOBAL_ACTION_POWER_DIALOG` (Standard) or `DevicePolicyManager.reboot()`
   (verified owner only). There is no direct shutdown API; Turn Off always opens
   Android's power menu.
6. **No misleading success state.** Health and per-feature states come from
   `PolicyEvaluator`; unreadable policies are `degraded`, unavailable APIs are
   `unsupported`, and unprovisioned ones are `requires_provisioning`. A green
   indicator is only allowed for state Android confirmed.
7. **Anti-tamper state stays local.** `ProtectionHealth` writes transitions to
   `SecurityAudit` in this app's private preferences. No new permission, no
   network, no account, no telemetry. Do not log page text or list contents.
8. **Device validation is per device.** An emulator result is not a Samsung
   result; `docs/PROTECTION.md` records what was and was not observed.

## Where the clone work lives

| Area | File |
|---|---|
| Shared BlockP design system (palette light/dark, type, cards, switches, nav) | `lib/ui/blockp_theme.dart` |
| Geometric mark + calm-mode landscape (replaces BlockP's dog) | `lib/ui/brand_art.dart` |
| Bottom-nav shell + tab order | `lib/main.dart` |
| Dashboard (Off/Normal/Strict, streak, feature switches) | `lib/ui/home_screen.dart` |
| Block list (apps, sites, keywords, allowlist) | `lib/ui/block_list_screen.dart` |
| Calm mode (sessions, allowed apps, prevent exit) | `lib/ui/calm_screen.dart` |
| Premium (feature listing, no purchase flow) | `lib/ui/premium_screen.dart` |
| Support (privacy note, diagnostic copy, FAQ) | `lib/ui/support_screen.dart` |
| Advanced Settings (all blocking layers, data) | `lib/ui/settings_screen.dart` |
| Permissions setup | `lib/ui/permissions_screen.dart` |
| Accountability partner + local log | `lib/ui/accountability_screen.dart` |
| Protection dashboard, modes and device controls | `lib/ui/protection_screen.dart`, `lib/services/protection_service.dart` |
| Daily affirmations | `lib/ui/affirmations_screen.dart` |
| Engine + native bridge | `lib/services/blur_engine.dart`, `lib/services/native_bridge.dart` |
| Filter/policy state | `lib/services/filter_store.dart`, `lib/src/policy.dart`, `lib/src/block_rules.dart` |

Tab order is fixed: **Dashboard, Block list, Premium, Calm, Support.**
Advanced Settings, Permissions, Accountability and Affirmations are pushed
routes, not tabs. The reference app's dark and light themes are both supported;
the palette is a `ThemeExtension` so nothing hard-codes one of them.

## Build and verify

```bash
# from C:\Users\H P\haram-blur
flutter analyze                       # must report "No issues found!"
flutter test                          # 91 tests (85 unit/widget + 6 renders)
flutter build apk --release --target-platform android-arm,android-arm64
                                      # R8 + resource shrinking, signed; phones only
```

Flutter lives at `C:\flutter\bin\flutter.bat`. The release APK lands in
`build\app\outputs\flutter-apk\app-release.apk`; signing keys are in
`android/key.properties` and `android/app/haram-blur-release.jks` (both
.gitignored, both must be backed up).

`test/ui_render_test.dart` renders every screen at 1080x2340 into
`build/ui-review/` so visual changes can be compared with the reference
captures instead of described from memory. It loads AnekLatin from the app's
assets and MaterialIcons from the Flutter SDK cache; without the icon font the
captures show empty boxes.

Install with `C:\Android\Sdk\platform-tools\adb.exe` — note the SDK is split
across `C:\Android\Sdk` (platform-tools, build-tools, platforms, ndk) and
`C:\AndroidSDK` (cmdline-tools only). `JAVA_HOME` must be set to
`C:\Program Files\Eclipse Adoptium\jdk-17.0.20.8-hotspot` for `sdkmanager`.

## Tooling notes

- **REA MCP is already registered** in Freebuff (`configKey: "rea"`), with the
  native-analysis tool allowlist configured. Use it for APK/DEX inspection
  rather than guessing at BlockP's behaviour.
- The Android emulator package is **not installed** and `sdkmanager` downloads
  for it have been stalling. `C:\Users\H P\.android\avd\Pixel_10_Pro_XL.avd`
  exists, so only `emulator` + a `system-images;android-36;google_apis;x86_64`
  package are missing. Rendering comparisons against the reference currently
  rely on the captured screenshots above.

## Style

Boring, boring, boring. Match the existing code: Flutter/Dart with
`flutter_lints`, doc comments on public symbols explaining *why*, no clever
abstractions. One convention per concern — do not introduce a second design
system next to `blockp_theme.dart`.
