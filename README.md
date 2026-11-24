# Basirah (بَصِيرَة)

An offline Android app that blocks pornography and blurs exposure on screen.
Basirah's interface is visually similar to the BlockP reference — dashboard,
block list, premium, calm and support tabs, plus advanced settings, permissions
and the accountability partner — rebuilt on top of Basirah's own on-device
detection engine.

Everything runs on the phone. There is no account, no server, no analytics and
no `INTERNET` permission in the release manifest.

## What it does

- **Screen blur** — the accessibility service takes a screenshot when the
  foreground app changes, classifies it with bundled LiteRT models and covers
  explicit frames (or exposed awrah bands) with an unreadable blurred copy. If
  the blur cannot be shown, the app is sent home instead.
- **App blocking** — package-level blocklist, enforced the moment a window
  opens, before any pixels are analysed. Includes the newly-installed-app and
  newly-installed-browser guards.
- **Web and keyword blocking** — 952,260 bundled adult domains, kept as a
  sorted hash index the service searches by host suffix (7.3 MB, no strings to
  parse), plus a bundled adult URL pattern list (search queries such as
  `*q=*porn*` and `.xxx` hosts, URL only), your own sites and keywords. All of
  it is matched against the address bar; keywords also against visible text,
  where `xxx*` wildcards are supported.
- **Image and video results** — optionally blocks the thumbnail grids on the
  major engines (Advanced Settings → Blocking, on by default).
- **Schedules and daily limits** — per app allowed hours and a daily minute cap,
  edited by tapping an app row in the block list.
- **Custom block screen text** — your own title and message on the block
  screen, in place of the shipped wording.
- **Cross block screen limit** — the fifth block of the same target inside two
  minutes keeps the screen up for five minutes with no dismiss button, which
  stops dismiss-and-reopen loops.
- **In-app browser blocking** (off by default) — blocks WebViews inside other
  apps, the usual way a blocked site is still reachable from a social app.
- **Long sentence lock** — with a sentence set, opening Advanced Settings asks
  for it, and switching protection off needs it plus a 15-second wait.
- **Morning affirmation gate** — after the time you choose, the app opens on
  your affirmations and unlocks once every line is read. This gates this app,
  not the whole phone.
- **Calm mode** — lock every app except an allow list for 15 to 180 minutes,
  with an optional "prevent exit" that disables ending the session early.
- **Image check** — run the shipped cascade on a photo you pick, on device.
- **Accountability partner** — a trusted person's details and a local log of
  what the app would report. Nothing is sent: the log is copied by hand.
- **Daily affirmations** — built-in sentences plus your own, stored locally.
- **Uninstall protection** — optional device admin, which requests no wipe,
  lock or password policies and only makes casual removal harder.
- **Two protection modes** — Standard works on any Android 11+ phone with the
  accessibility grant. Hardened is optional and only appears active when the
  phone is provisioned as a fully managed device with Basirah as Device Owner;
  it then adds Safe Mode prevention, an app-management lock, a factory-reset
  restriction and an uninstall block for Basirah itself. See
  [docs/PROTECTION.md](docs/PROTECTION.md) for what each one does not prevent.
- **Protection dashboard** — accessibility, the detection engine, the matcher,
  the last successful scan, reboot recovery and anti-tamper state, each read
  back from Android instead of assumed, plus the current Device Owner state and
  the local security audit.
- **Restart and Turn Off** — with a confirmation, Restart opens Android's power
  menu (or restarts directly on a verified Device Owner), and Turn Off opens the
  same system menu. Android exposes no direct shutdown API, and the app never
  claims either action before the operating system performs it.
- **No VPN.** App, site, keyword and screen filtering all work without one, so
  no VPN service is bundled, requested or implemented.

## What is not included, and why

- **No network features.** The BlockP reference offers sign-in, cloud
  accountability OTPs, a support chat, a community and update checks. All of
  them need a server; this build has no `INTERNET` permission, so every screen
  that would host one shows a local equivalent and says so plainly.
- **No purchase flow.** Premium has no price, no subscription and no restore:
  every feature is included. The tab keeps the reference layout and replaces
  the pricing copy with what is true of this build.
- **No in-app search blocking inside WhatsApp, Telegram, Instagram, etc.** The
  Social Media Blocking section blocks those apps entirely rather than hooking
  their internal search boxes, which Android does not expose to third-party
  apps. The rows say "Blocks the app entirely".
- **No custom redirect.** Sending a blocked page to a page of your choice
  needs the ability to intercept the browser's request, which means a VPN or a
  browser extension — the two things this app does not use. The block screen
  shows custom text instead.
- **No phone-wide morning lock.** The reference locks the whole device until
  affirmations are *spoken*; that needs recording plus device-owner rights.
  This build gates only Basirah and asks for a tap per line, and the screen
  says so.
- **No OTP accountability.** Verifying a partner's email requires a server;
  the partner log is stored locally and copied by hand.
- **No power-menu blocking.** Android does not let an app intercept or veto the
  power menu at any privilege level, so no such switch exists. Basirah can open
  the menu on request (Restart / Turn Off controls) but cannot stop a hardware
  shutdown, and says so.
- **No automatic Device Owner.** Provisioning a fully managed device and
  applying device-wide restrictions are user actions, documented in
  [docs/PROTECTION.md](docs/PROTECTION.md). The app never starts provisioning
  and never factory-resets anything.

## Sharia compliance

This app is built to respect Islamic Sharia in both behaviour and artwork.

- **No depictions of animate beings.** The reference app's dog mascot appears on
  its dashboard, premium ticket and calm-mode artwork. None of it is reproduced.
  Basirah keeps those slots and fills them with an original device — its mark,
  a geometric aperture: three concentric circles (lens outline, iris ring and
  centre aperture dot) with no points and no face — and an abstract mountain
  landscape. The app icon and splash use the same mark.
- **No human faces or figures.** The reference's head-and-shoulders profile
  button, Material's person, people, accessibility, handshake, smiley and robot
  glyphs are all replaced by original abstract devices: interlocking rings, a
  viewfinder bracket, a droplet-and-bar, a rounded square and a system panel.
  The old almond-eye mark was also replaced because it could be read as an eye,
  a facial feature.
- The app blurs exposure for every person equally. It does not classify gender,
  does not blur a woman's face because she is a woman, and has no
  "block women" mode — those rules target a protected class and were not built.
- **No religious symbols used decoratively**, no nudity, no alcohol and no
  gambling imagery. The prayer-time feature is present as behaviour and plain
  text, marked by a plain clock dial rather than a religious symbol.
- Copy avoids pork, alcohol and exploitative framing, and every claim about the
  app is one the code actually keeps.

The rule for this and every other project lives in `C:\Users\H P\.AGENTS.md`.

## Privacy

Read [PRIVACY.md](PRIVACY.md) for the full note. In short: no network
permission, no account, no telemetry, screenshots are classified in memory and
never stored, and the history, block lists and partner details live in this
app's private storage.

## How detection works

There is exactly **one** inference and policy implementation: the Dart engine
in `lib/src/` (`FramePreprocessor` → `DetectionEngine` → `BlurPolicy`). The
Image check screen and every test call it directly.

1. **Whole-frame gate** — `nsfw_int8.tflite`, a quantised ViT, 224×224 float
   input, two logits. Softmax P(nudity) above the threshold blurs the frame.
2. **Awrah band** — `selfie_multiclass_256x256.tflite` gives a per-pixel class
   map; connected components become person boxes and the band is blurred only
   when most of it is uncovered skin. The top of the head is excluded, so
   hijab and niqab portraits are not touched by this stage.

Sensitivity 1..10 maps to a gate of 0.85→0.50 and a band of 0.85→0.55; level 5
is the validated default. For screen protection, Kotlin captures and converts
pixels and draws the regions; a headless Flutter engine scores them, so the
screen layer and the image pipeline cannot drift apart.

## Build

```bash
flutter analyze                  # must print "No issues found!"
flutter test                     # unit, widget and screen-render tests
flutter build apk --release      # R8 + resource shrinking
```

The release APK lands in `build/app/outputs/flutter-apk/app-release.apk`.
Signing is read from `android/key.properties` (git-ignored, together with
`android/app/haram-blur-release.jks`). Keep both backed up: Android will not
accept an update signed with a different key. Without `key.properties` the
build falls back to the debug key so `flutter build apk` still works.

Minimum Android 11 (API 30), target API 34, application id
`com.haramblur.haram_blur`.

### Enabling protection

1. Open Basirah. The permissions screen lists accessibility, notifications
   and the battery exemption.
2. Enable **Basirah** in Android's accessibility settings, then come back.
3. The dashboard shows *Active* only when the service is genuinely bound.
4. *Protection & device controls* on the dashboard opens the protection
   dashboard: the mode, every verified component, the Device Owner state, the
   optional restrictions and the Restart / Turn Off controls. Hardened
   Protection is explained there and requires provisioning done by hand.

## Design direction

Basirah's UI is visually similar to the reference app — the same layout ideas,
palette, card shapes and navigation model — without chasing pixel identity.
Exact pixel matching is deliberately not a goal: it would trade away
readability, accessibility, Sharia compliance and working features for no
user-visible benefit.

Colours, radii and type steps were measured from the reference captures with
`tools/shot_metrics.py`. `test/ui_render_test.dart` renders every screen at
1080×2340 into `build/ui-review/`, so the screens can be compared against the
screenshots instead of being described from memory.

Deliberate differences: the Basirah branding and artwork (see Sharia
compliance), the honest copy where the reference markets network features, and
the Support tab's local actions in place of chat and social links.

## Layout

```
lib/main.dart                  app shell, five tabs, permission gate
lib/ui/blockp_theme.dart       design system (palette, type, cards, rows, switch, nav)
lib/ui/brand_art.dart          geometric mark and calm-mode landscape
lib/ui/home_screen.dart        dashboard
lib/ui/block_list_screen.dart  block list / allowlist
lib/ui/premium_screen.dart     feature overview
lib/ui/calm_screen.dart        calm sessions
lib/ui/support_screen.dart     help, privacy note, FAQ
lib/ui/settings_screen.dart    advanced settings
lib/ui/permissions_screen.dart permission setup
lib/ui/accountability_screen.dart  partner and local log
lib/ui/affirmations_screen.dart    affirmations and morning-gate settings
lib/ui/affirmation_gate.dart       the gate shown after the chosen time
lib/ui/lock_gate.dart              sentence password and countdown guards
lib/ui/protection_screen.dart      protection modes, restrictions, device controls
lib/services/protection_service.dart  verified protection report and datatypes
docs/PROTECTION.md                 modes, Device Owner provisioning and recovery
lib/src/                       detection engine, policy, segmentation, block rules
lib/services/                  engine, stores, native bridge, export
android/                       MainActivity, accessibility service, overlay, receivers
test/                          unit, widget and screen-render tests
tools/                         evaluation and screenshot-measurement scripts
```

## Known limitations

- The visual layer on the system screen runs the whole-frame gate plus centre
  crops; the full segmentation pass is used by the Image check screen.
- Secure windows (banking, DRM) refuse screenshots, so protection stays idle
  there.
- Android allows revoking accessibility or deactivating device admin; the app
  can only notice and ask again.
- Device Owner policies stop Settings-based bypasses, not ADB, root, recovery
  mode or a firmware reflash. Removing a Device Owner requires a factory reset,
  which is why Basirah never provisions a phone itself.
- Keyword matching only sees text Android exposes to accessibility services.
- No video-file decoding; video apps are covered by the screen service.
- iOS builds need macOS and only include the image pipeline.

## Release signing and SDK levels

The release APK is signed with the project keystore using APK Signature Scheme
v2 **and v3** (v1 is off, since `minSdk` is 30). v3 is what carries a key
rotation lineage, so keep signing with v3 enabled if the key ever has to
change. `targetSdk` is 36: Android 15+ therefore draws the app edge to edge,
which the layout accounts for through its safe-area padding.
