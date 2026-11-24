# Phase 1 harness — emulator regression and bypass checks

A repeatable, evidence-producing test suite for the ways protection is *supposed*
to hold, and for the ways it is known not to. It exists because every blocking
claim so far was argued from source code, and the first run of this harness
immediately found that the APK installed on the test device was two days older
than the code: it did not request `TYPE_VIEW_TEXT_CHANGED`, so typed-address
blocking could never have fired. A behaviour test alone would have missed that,
which is why `S01` asserts the service configuration directly.

## What a run does

1. Boots the `BlockP_Test` AVD (or reuses an attached device).
2. Builds an x86_64 **debug** APK from the working tree (`tools/build_x64.bat`).
   The debug build is required for `run-as` preference injection and is never
   shipped.
3. Installs it with runtime permissions granted.
4. For each scenario: writes the exact preference state, restarts the
   accessibility service so it reads that state, drives the device, then reads
   back the app's own `EventLog` / `SecurityAudit` records.
5. Writes `results/<UTC timestamp>/` with screenshots, logcat slices,
   `prefs_*.xml`, and `summary.md` (expected vs actual).

## Run

```bash
bash tools/harness/run_phase1.sh               # full run, ~8 min including reboot
bash tools/harness/run_phase1.sh --no-reboot   # skip the reboot scenario
bash tools/harness/run_phase1.sh --no-build    # reuse the APK already on disk
bash tools/harness/run_phase1.sh --only=S02,S04
```

Requirements: `adb` + `emulator` (default `C:/Android/Sdk/...`, override with
`ADB` / `EMULATOR`), Python 3 (`uiauto.py` and the fixture server), and
`C:\flutter\bin\flutter.bat` for the build step.

Exit status is `0` when nothing failed, `1` when a scenario failed, `2` when the
harness could not set up. `SKIP` and `KNOWN-GAP` are not failures.

## Reading the outcome

| Outcome | Meaning |
|---|---|
| `PASS` | The expected record appeared exactly as documented. |
| `FAIL` | Protection did not behave as documented: a regression. |
| `SKIP` | The emulator could not create the precondition (e.g. real split screen). Needs the manual step in `physical-device.md`. |
| `KNOWN-GAP` | Observed behaviour contradicts a protection claim that is still open on the roadmap. Recorded on purpose, not hidden. |

`S09` is the clearest example of `KNOWN-GAP`: switching accessibility off stops
protection and, today, nothing tells the user. That is roadmap item 1 (protection
heartbeat), and the scenario will keep reporting `KNOWN-GAP` until it is built.

## Why preferences are injected with `run-as`

The service reads its rules from `SharedPreferences` natively, so it keeps
blocking with the Flutter engine dead. There is no Android API to write another
app's preferences, and driving the whole UI by taps would make every scenario
fragile. The harness therefore force-stops the app, writes the preference XML
through `run-as`, and re-enables the accessibility service so a fresh process
loads it from disk. Each scenario's exact XML is saved next to its evidence.

## What this harness does not prove

- **Pixel detection accuracy.** The AVD runs with software graphics; the NSFW
  model path is not exercised here. Those claims need `physical-device.md`.
- **Battery and thermal cost.** Not measurable meaningfully in an emulator.
- **OEM behaviour.** Nothing about Xiaomi/Samsung battery managers, or their
  Settings layouts.
- **Picture-in-picture, WebView in-app browsers, notification *dismissal*.**
  No deterministic driver on this image; listed as manual checks.

## Adding a scenario

1. Add `sNN()` to `run_phase1.sh`: set state with `pref_*`, call `apply_state`,
   act, assert with `wait_event`, and **always `return`** `0`/`1`/`77`/`78` with
   `DETAIL` set.
2. Append `SNN` to `SCENARIOS` and add its title/expectation to
   `scenario_title` / `scenario_expected`.
3. Document the expected outcome in `scenarios.md` in the same commit.
