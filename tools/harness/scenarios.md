# Phase 1 scenario matrix

The formal milestone definition for Phase 1. Each scenario has a documented
expected outcome and a pass criterion that reads the app's own records
(`EventLog`, `SecurityAudit`, `dumpsys accessibility`), never a screenshot by
eye. `run_phase1.sh` implements these one-to-one; actual results for a given run
live in `results/<timestamp>/summary.md`.

## Executed on the emulator

| ID | Scenario | Preconditions | Steps | Expected outcome | Pass criterion |
|---|---|---|---|---|---|
| S01 | Service configuration | Service bound | `dumpsys accessibility` | Bound `Basirah` service requests `TYPE_WINDOW_STATE_CHANGED`, `TYPE_WINDOW_CONTENT_CHANGED`, `TYPE_VIEW_TEXT_CHANGED` | Dump names all three event types |
| S02 | Keyword in page text | `filter_blocked_keywords=whine` | Load fixture `keyword.html` in Chrome | One `EventLog` entry `p=com.android.chrome r=keyword` | Entry appears within 25 s; screenshot shows the block screen |
| S03 | Custom terms | One term per run: `cnnam`, `gucci third leg` | Load the matching fixture page | One `p=com.android.chrome r=keyword` entry per term | Both terms block, each in its own fresh state |
| S04 | Typed address, pre-load | `filter_blocked_domains=pornhub.com` | Focus omnibox, type `pornhub.com`, Enter | `p=com.android.chrome r=url` **before** a page can load | Entry appears ≤3 s after Enter |
| S05 | Allowlisted site | Same domain also in `filter_allowlisted_domains` | Same typing sequence as S04 | No `r=url` entry; Chrome stays foreground | No event for 10 s and Chrome still foreground |
| S06 | Blocked app | `filter_blocked_apps=com.android.deskclock` | Launch DeskClock | `p=com.android.deskclock r=app` | Entry within 15 s |
| S07 | Settings guard | `advanced_guard_settings=true` | `am start -a android.settings.APPLICATION_DETAILS_SETTINGS -d package:com.haramblur.haram_blur` | Service backs out; `SecurityAudit` records one `settings_escape` naming the app | `am start -W` reports `Status: ok`; an entry naming `Basirah` appears; the app-info page is gone; exactly one entry is added; ordinary `android.settings.SETTINGS` stays foreground |
| S08 | Notification preview | `filter_blocked_keywords=cnnam` | Post notification containing `cnnam`, expand shade | `p=com.android.systemui r=keyword` | Entry within 15 s |
| S09 | Accessibility revoked | Protection running | Clear enabled accessibility services | Service unbinds; nothing claims continued protection | Service unbound **and** observed alert count recorded (0 ⇒ `KNOWN-GAP`, roadmap item 1) |
| S10 | Reboot persistence | Keyword configured, service bound | `adb reboot`, wait for boot, load fixture **without opening Basirah** | Service rebinds, restores preferences, scans the first page, blocks the same keyword | `SERVICE_CONNECTED` + `PREFERENCES_RESTORED` logged after boot; `FIRST_SCAN_COMPLETED`; keyword entry within 30 s; protection preference still true |
| S11 | Split screen | `advanced_block_split_screen=true` | Two apps in split screen | `r=splitScreen` | Entry while split is genuinely active; otherwise `SKIP` |

Notes that matter for interpreting a run:

- Each scenario rewrites the whole preference file, so every `EventLog` count
  starts at zero and one scenario cannot mask another's failure.
- A visible overlay suppresses further blocks, so multi-part scenarios (S03)
  re-apply state between parts instead of chaining pages.
- `S04`/`S05` are a pair. S04 proves the typed-address path fires; S05 proves
  the same path does **not** fire for a trusted site. Neither is meaningful
  alone: S05 passes trivially if typing never works at all.

## Not executed here (manual, see `physical-device.md`)

| Area | Why not on the emulator |
|---|---|
| Pixel/NSFW detection accuracy | Software graphics; the model is not the thing under test and results would not transfer |
| Battery and thermal cost | Not measurable without a real battery |
| OEM Settings layouts, aggressive battery managers | Requires the actual phone |
| Picture-in-picture bypass | No deterministic way to enter PiP with video on this image |
| WebView in-app browser rule | No app on the AVD hosts a WebView it does not own |
| Notification dismissal via `NotificationListenerService` | Not implemented yet (roadmap item 4, stage 2) |
| Accessibility revocation *alerting* | Not implemented yet (roadmap item 1); S09 records the gap |
| Split screen | `am start --windowingMode` does not produce a real split here |

## Phase 1 exit criteria

Phase 1 is complete when, on the current working tree:

1. the full run finishes with zero `FAIL`;
2. every `SKIP` has a documented manual equivalent that has been performed once
   on the physical device;
3. the `S09` gap is either fixed (turning it into `PASS`) or explicitly accepted
   in the roadmap with the run's evidence attached.

Phase 1 does **not** gate on detection accuracy. That is Phase 3 work, and it
needs the physical device to mean anything.

## Emulator behaviour observed while running these scenarios

Recorded so a later run does not relearn it, and so a `FAIL` here is not read as
an app defect without checking which of these happened:

| Symptom | What it means | What the harness does |
|---|---|---|
| `Node scan: … chars≈150 webview=false` on a loaded Chrome page | The page subtree is not exposed yet (Chrome only publishes it once a second client asks for children) | `appWindows()` enumerates the package's application windows and merges them; the scenario fails on "page text is NOT in the window tree" |
| `uiautomator dump` writes ~47 bytes | The image's accessibility/UI stack is wedged (usually an ANR dialog underneath) | every assertion that depends on the dump fails in that scenario; the run continues |
| `System UI isn't responding` / `Chrome isn't responding` | Emulator capacity: Chrome ANRs even with the accessibility service **unbound** | dismissed with **Wait**, never "Close app" |
| `input text` reaches the omnibox partly ("por") | The modal/browser is not focused or the IME dropped input | `type_text` types 3 characters at a time; S04/S05 report an input-focus failure instead of a failed block |
| `adb shell` hangs, `adb emu kill` times out | The AVD has died | kill the `qemu` process only (`Stop-Process -Id`), restart, re-apply `wm size`/`density` |
| A `-wipe-data` boot kept being interrupted | The userdata image is left half-initialised and later boots stall before `sys.boot_completed` | re-run `-wipe-data` and let the first boot finish (~7 min) |
