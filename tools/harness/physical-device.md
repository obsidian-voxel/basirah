# Physical-device validation criteria

The emulator proves the plumbing. It cannot prove protection, because protection
depends on the detector, the battery manager and the OEM's own settings app. A
run of `run_phase1.sh` with zero failures is a prerequisite, not the milestone.

Target device: the Galaxy A56 the app was actually used on. Record the build
fingerprint, One UI version and battery state at the start of the session.

## 1. Reproduce the emulator scenarios

Run the same eleven scenarios by hand (they are listed in `scenarios.md`) and
require the same expected records. Where the harness injects preferences with
`run-as`, set them through the real UI instead: that is also the only way to
verify the Flutter/native bridge writes what the service reads.

Report per scenario: expected record, actual record, screenshot, `logcat -s
HaramBlur`.

**Pass:** the same eleven outcomes, obtained through the UI.

## 2. Detection accuracy (the part the emulator cannot touch)

| Check | Method | Pass criterion |
|---|---|---|
| True positives | 20 pages/apps the user actually wants blocked, opened normally | ≥18 blocked, every miss captured with a screenshot |
| False positives | 30 benign pages (news, shopping, medical, education, social) | 0 blocked; any block is a defect with the matched rule recorded |
| Explicit imagery | 10 images/galleries that contain no blocked words | Blocked by the pixel path, not by text |
| Flat/uniform frames | Video call, white document, dark reading mode | No block (the `isFlat` guard holds) |
| `FLAG_SECURE` apps | Banking app, password manager | No block, no crash, no screenshot attempt |

Record the sensitivity level for every row; a claim without one is not
reproducible.

## 3. Bypass attempts, in the order a determined user would try

1. Type a blocked address and press Enter quickly (S04 path, real keyboard).
2. Open the same address from a link inside another app (in-app browser).
3. Switch to incognito/private **before** navigating, then navigate again.
4. Install a second browser, then open it.
5. Open the same site in split screen.
6. Start a video, then push it to picture-in-picture.
7. Open the notification shade with a matching notification present.
8. Lock the screen with the page open, unlock, return.
9. Rotate, then use the app-switcher preview (recents thumbnail).
10. Force-stop the app, then reopen the site.
11. Revoke accessibility, then reopen the site.
12. Reboot, then open the site without launching Haram Blur first.

For each: does the block still happen, does it happen late, or does it not happen
at all? "Late" is the interesting answer and must be timed, not described.

## 4. Battery and thermal

- 60 min idle, screen on, protection on: record `dumpsys batterystats` delta and
  the biggest wakelock holders.
- 30 min of scrolling a text-heavy site: record battery delta and device
  temperature before/after.
- Compare against protection off for the same 30 min.

**Pass criterion for Phase 1:** no thermal throttling reported and no wakelock
that keeps the CPU awake while the screen is off. Absolute numbers are recorded,
not targeted, until the sampling strategy in roadmap item 5 changes.

## 5. OEM survival

- Enable protection, then let the phone sit untouched for 12 h on battery.
- Confirm the service is still bound afterwards.
- Repeat once with "Remove permissions if app is unused" left at default.
- Check that One UI's "Sleeping apps" list has not put Haram Blur to sleep.

## 6. Manual steps the emulator cannot do

- [ ] Real split screen (two apps, dragged from recents).
- [ ] Picture-in-picture with video playing.
- [ ] WebView inside a social/shopping app, with
      `advanced_block_inapp_browsers` on and scoped to that app.
- [ ] Notification dismissal, once a `NotificationListenerService` exists.
- [ ] Accessibility revoked while the app is backgrounded: is any alert shown?

## Sign-off

Phase 1 is done when: the emulator run has zero failures, sections 1 and 3 have
been performed once with evidence attached, section 2 has been run at the
sensitivity level the user actually uses, and every miss is either fixed or
logged against the roadmap with its evidence.
