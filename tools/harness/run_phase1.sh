#!/usr/bin/env bash
#
# Phase 1 harness: repeatable emulator regression + bypass checks for Haram Blur.
#
# What it does
#   1. boots the BlockP_Test AVD (or reuses an already attached device)
#   2. builds the x86_64 debug APK from the working tree (tools/build_x64.bat)
#   3. installs it, grants runtime permissions, enables the accessibility service
#   4. drives each scenario documented in tools/harness/scenarios.md
#   5. writes one folder of evidence per run: screenshots, logcat, the exact
#      preference state used, and summary.md with expected vs actual outcome
#
# Preferences are injected through `run-as` (the debug APK is debuggable),
# because Android offers no other way to set them from a script. Nothing here
# leaves the machine: the only "network" is a loopback fixture server reached
# through `adb reverse`.
#
# Usage
#   bash tools/harness/run_phase1.sh                  full run
#   bash tools/harness/run_phase1.sh --no-build        reuse the existing APK
#   bash tools/harness/run_phase1.sh --no-reboot       skip S10 (reboot check)
#   bash tools/harness/run_phase1.sh --only=S02,S04    run selected scenarios
#
# Exit status: 0 when no scenario FAILED (SKIP and KNOWN-GAP are not failures),
# 1 when at least one scenario failed, 2 when the harness could not set up.

set -u -o pipefail

HARNESS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HARNESS_DIR/../.." && pwd)

ADB=${ADB:-C:/Android/Sdk/platform-tools/adb.exe}
EMULATOR=${EMULATOR:-C:/Android/Sdk/emulator/emulator.exe}
AVD=${AVD:-BlockP_Test}
PKG=com.haramblur.haram_blur
SERVICE="$PKG/$PKG.SystemWideBlurService"
APK="$ROOT/build/app/outputs/flutter-apk/app-debug.apk"
# The fixture server picks its own port (see serve.py): Windows refuses to bind
# some fixed ports, and a silent bind failure used to make every browser
# scenario fail with a connection-error page.
PORT=""
BOOT_TIMEOUT=${PHASE1_BOOT_TIMEOUT:-360}

# Git Bash rewrites /sdcard/... into a Windows path before adb sees it. Every
# device path here depends on this being off.
export MSYS_NO_PATHCONV=1

BUILD=1
INSTALL=1
DO_REBOOT=1
ONLY=""
for arg in "$@"; do
    case "$arg" in
        --no-build) BUILD=0 ;;
        --no-install) INSTALL=0 ;;
        --no-reboot) DO_REBOOT=0 ;;
        --only=*) ONLY=${arg#--only=} ;;
        -h|--help) sed -n '2,30p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
OUT="$HARNESS_DIR/results/$RUN_ID"
mkdir -p "$OUT"

# adb.exe and python.exe are native Windows programs: they cannot open Git
# Bash's /c/Users/... paths, which is why every path handed to them is
# converted first. Bash-internal redirections keep using the POSIX form.
to_win() { cygpath -w "$1" 2>/dev/null || printf '%s' "$1"; }
ROOT_W=$(to_win "$ROOT")
HARNESS_W=$(to_win "$HARNESS_DIR")
OUT_W=$(to_win "$OUT")
APK_W=$(to_win "$APK")

# The accessibility service declares no label of its own, so Android reports
# the application label in `dumpsys accessibility`. Read it from the resources
# instead of hardcoding one: the app was renamed to "Basirah" and every bind
# assertion silently went false while the service was running perfectly.
APP_LABEL=$(sed -n 's/.*<string name="app_name">\([^<]*\)<\/string>.*/\1/p' \
    "$ROOT/android/app/src/main/res/values/strings.xml" 2>/dev/null | head -1)
[ -n "$APP_LABEL" ] || APP_LABEL="Basirah"

EXPECT_COUNTS_PASS=0
EXPECT_COUNTS_FAIL=0
EXPECT_COUNTS_SKIP=0
EXPECT_COUNTS_GAP=0

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

say() { printf '%s\n' "$*"; }
# Every device call is bounded. A wedged emulator (seen after S10's reboot)
# makes `adb shell` hang forever, and without a timeout the run stops with no
# output at all instead of reporting which step failed.
DEV_TIMEOUT=${PHASE1_DEV_TIMEOUT:-45}
dev() { timeout "$DEV_TIMEOUT" "$ADB" "$@" 2>/dev/null; }
dsh() { timeout "$DEV_TIMEOUT" "$ADB" shell "$@" 2>/dev/null; }

# Bounded wait: `bounded_wait <seconds> <command...>` polls until the command
# succeeds. Avoids fixed sleeps where a condition can be observed.
#
# The deadline is wall-clock, not a poll count: after an S10 reboot a wedged
# guest makes each `adb shell` probe burn its 45 s device timeout, so counting
# iterations turned a 360 s boot timeout into an unbounded wait.
bounded_wait() {
    local timeout=$1 start=$SECONDS
    shift
    while [ $((SECONDS - start)) -lt "$timeout" ]; do
        if "$@"; then
            return 0
        fi
        sleep 0.5
    done
    return 1
}

# ---------------------------------------------------------------------------
# Preference state
#
# Each scenario declares the full state it needs; nothing is inherited from a
# previous scenario. PREF_LINES becomes the SharedPreferences XML the service
# loads on its next start.
# ---------------------------------------------------------------------------

PREF_LINES=()

xml_escape() {
    printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

pref_bool() { PREF_LINES+=("    <boolean name=\"$1\" value=\"$2\" />"); }
pref_int() { PREF_LINES+=("    <int name=\"$1\" value=\"$2\" />"); }
pref_long() { PREF_LINES+=("    <long name=\"$1\" value=\"$2\" />"); }
pref_float() { PREF_LINES+=("    <float name=\"$1\" value=\"$2\" />"); }
pref_str() { PREF_LINES+=("    <string name=\"$1\">$(xml_escape "$2")</string>"); }

# A StringSet, one value per remaining argument.
pref_set() {
    local name=$1 value out=""
    shift
    for value in "$@"; do
        out+="<string>$(xml_escape "$value")</string>"
    done
    PREF_LINES+=("    <set name=\"$name\">$out</set>")
}

state_reset() {
    PREF_LINES=()
    # Protection on, developer HUD off: the scenarios assert real enforcement.
    pref_bool system_wide_enabled true
    pref_bool debug_overlay_enabled false
    pref_bool advanced_guard_settings true
}

push_prefs() {
    local file="$OUT/prefs_${SCENARIO_ID:-default}.xml"
    {
        echo "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>"
        echo '<map>'
        printf '%s\n' "${PREF_LINES[@]}"
        echo '</map>'
    } > "$file"
    dev push "$(to_win "$file")" /data/local/tmp/phase1_prefs.xml >/dev/null || return 1
    dsh run-as "$PKG" mkdir -p shared_prefs || return 1
    dsh "run-as $PKG sh -c 'cat /data/local/tmp/phase1_prefs.xml > shared_prefs/${PKG}_preferences.xml'" || return 1
    read_prefs | grep -q 'name="system_wide_enabled"' || return 1
}

# The preference XML escapes JSON inside a <string> value (" becomes &quot; on
# some platform versions), so entity-decode before matching an EventLog entry.
# Without this, a block that really happened reads as "no event".
read_prefs() {
    "$ADB" exec-out run-as "$PKG" cat "shared_prefs/${PKG}_preferences.xml" 2>/dev/null \
        | sed -e 's/&quot;/\"/g' -e 's/&apos;/'"'"'/g' -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&amp;/\&/g'
}

# `settings put ... ""` is rejected by the device shell ("Bad arguments"),
# which silently left protection on and made S09/S10 meaningless. Deleting the
# key is the reliable way to switch the service off.
acc_off() {
    dsh settings delete secure enabled_accessibility_services
    dsh settings put secure accessibility_enabled 0
}

acc_on() {
    dsh settings put secure enabled_accessibility_services "$SERVICE"
    dsh settings put secure accessibility_enabled 1
}

# Only the "Bound services" line proves the service is running: the dump also
# lists enabled/installed services, and matching those made a stopped service
# look alive.
acc_bound() {
    dsh dumpsys accessibility | grep "Bound services" | grep -q "label=$APP_LABEL,"
}

# A cold start of the Flutter engine on this image takes 60-90 s (the log
# shows dex verification of the whole engine before onServiceConnected), so a
# 40 s wait reported "service did not bind" for a service that was starting.
acc_wait() { bounded_wait "${PHASE1_ACC_WAIT:-150}" acc_bound; }

# Kill the process, replace the preference file, then let Android rebind the
# service so it reads exactly that state from disk.
apply_state() {
    dsh am force-stop "$PKG"
    # A force-stop that has not taken effect leaves the old process running
    # with its cached keyword list, so the next scenario was judged with the
    # PREVIOUS scenario's rules. Wait for the process to be gone.
    _process_gone() { [ -z "$(dsh pidof "$PKG" | tr -d '\r')" ]; }
    bounded_wait 10 _process_gone || say "   (warning: $PKG is still running after force-stop)"
    acc_off
    sleep 0.5
    push_prefs || return 1
    acc_on
    acc_wait
}

# ---------------------------------------------------------------------------
# Reading what the service did
#
# EventLog appends {"t":..,"p":<package>,"r":<reason>,"c":..} entries into the
# same SharedPreferences file, so the harness reads the same record the app
# shows in its history instead of guessing from pixels.
# ---------------------------------------------------------------------------

event_count() {
    { read_prefs | grep -o "\"p\":\"$1\",\"r\":\"$2\"" || true; } | wc -l | tr -d ' '
}

# SecurityAudit appends {"t":..,"e":<event>,"d":..} entries to the same
# preference file. Count the wire names, never the page text in "d".
audit_count() {
    { read_prefs | grep -o "\"e\":\"$1\"" || true; } | wc -l | tr -d ' '
}

# The newest settings_escape entry's detail, i.e. the page the guard saw.
audit_last_detail() {
    { read_prefs | grep -o '"e":"settings_escape","d":"[^"]*"' || true; } \
        | tail -1 | sed -e 's/.*"d":"//' -e 's/"$//'
}

wait_event() {
    local pkg=$1 reason=$2 before=$3 timeout=${4:-15}
    _event_ready() { [ "$(event_count "$pkg" "$reason")" -gt "$before" ]; }
    bounded_wait "$timeout" _event_ready
}

screenshot() {
    timeout 30 "$ADB" exec-out screencap -p > "$OUT/${SCENARIO_ID}-${1:-shot}.png" 2>/dev/null
}

# No -t: with -t the buffer is truncated BEFORE the tag filter, so a burst of
# System UI ANR spam pushed the app's own lines out and the log looked empty.
capture_logcat() {
    dsh logcat -d -s HaramBlur:* AdultDomainIndex:* > "$OUT/${SCENARIO_ID}.log"
}

# ---------------------------------------------------------------------------
# Device / browser driving
# ---------------------------------------------------------------------------

top_activity() {
    dsh dumpsys activity activities | grep -m1 -i topResumedActivity
}

# A tab left over from an earlier scenario stayed on screen and was scanned
# instead of the fixture page, so every navigation starts from a stopped
# browser: the URL intent then opens exactly the requested page.
open_url() {
    dsh am force-stop com.android.chrome
    sleep 1
    dsh am start -W -a android.intent.action.VIEW -d "$1" \
        -n com.android.chrome/com.google.android.apps.chrome.Main >/dev/null 2>&1
}

launch_package() {
    dsh monkey -p "$1" -c android.intent.category.LAUNCHER 1
}

UI_XML=""

ui_dump() {
    # The pre-run Chrome warm-up happens before any scenario, so the id needs a
    # default; `set -u` used to abort the whole run here.
    UI_XML="$OUT/ui_${SCENARIO_ID:-baseline}.xml"
    dsh rm -f /sdcard/phase1_ui.xml
    local i=0
    while [ "$i" -lt 3 ]; do
        dsh uiautomator dump /sdcard/phase1_ui.xml >/dev/null && break
        sleep 1
        i=$((i + 1))
    done
    "$ADB" exec-out cat /sdcard/phase1_ui.xml > "$UI_XML" 2>/dev/null
    [ -s "$UI_XML" ]
}

tap_text() {
    local coords
    coords=$(python "$HARNESS_W/uiauto.py" center "$(to_win "$UI_XML")" "$1") || return 1
    # shellcheck disable=SC2086
    dsh input tap $coords
}

# Chrome interrupts with first-run, sign-in and notification-permission
# prompts, and a modal one swallows `input text` completely. Dismiss any prompt
# by node text, repeatedly, until the browser is actually usable.
# An ANR dialog ("System UI isn't responding") steals the input focus and stays
# up for the rest of the run, which silently breaks every later typing step.
# Never choose "Close app": "Wait" leaves the system intact.
dismiss_system_dialogs() {
    local i=0
    while [ "$i" -lt 3 ]; do
        ui_dump || return 0
        if python "$HARNESS_W/uiauto.py" has "$(to_win "$UI_XML")" "isn't responding|is not responding"; then
            say "   (dismissing a system ANR dialog with Wait)"
            tap_text "^wait$" || dsh input keyevent 4
            sleep 2
            i=$((i + 1))
            continue
        fi
        return 0
    done
}

chrome_ready() {
    local i=0
    # Three passes: every pass costs a uiautomator dump, which is slow on a
    # software-rendered image, and the dialogs are at most two deep.
    while [ "$i" -lt 3 ]; do
        top_activity | grep -q "com.android.chrome" || return 0
        dismiss_system_dialogs
        ui_dump || return 1
        if tap_text "use without an account"; then :
        elif tap_text "^no thanks$"; then :
        elif tap_text "not now"; then :
        elif tap_text "got it"; then :
        else
            return 0
        fi
        sleep 2
        i=$((i + 1))
    done
    return 0
}

# Focus the address bar. The resource id is the stable handle; the placeholder
# text and the top-bar coordinate are fallbacks for a Chrome build that renames
# or hides it.
focus_omnibox() {
    ui_dump || return 1
    python "$HARNESS_W/uiauto.py" center-id "$(to_win "$UI_XML")" "url_bar" > /tmp/phase1_coords 2>/dev/null \
        && { # shellcheck disable=SC2046
             dsh input tap $(cat /tmp/phase1_coords); return 0; }
    if tap_text "search google or type|type a url|search or type"; then
        return 0
    fi
    # Fallback: the omnibox is the top-centre field. Derive the point from the
    # real display size instead of the 1080-wide coordinate, which missed the
    # bar entirely once the harness shrank the framebuffer.
    say "   (address bar not found by id or text; tapping the top-centre field)"
    local size w h
    size=$(dsh wm size | tr -d '\r' | awk -F'[:x] ' '/Override|Physical/ {print $NF}' | tail -1)
    w=${size%x*}
    h=${size#*x}
    [ -n "$w" ] && [ -n "$h" ] || { w=720; h=1560; }
    dsh input tap $((w / 2)) $((h * 6 / 100))
}

# `input text` races Chrome's omnibox: a single burst arrived as "por"
# instead of "pornhub.com", so the URL never formed and both S04 and S05 were
# meaningless. Three characters at a time is slow enough for the field and
# still takes under two seconds.
type_text() {
    local text=$1 chunk i=0
    while [ "$i" -lt "${#text}" ]; do
        chunk=${text:$i:3}
        dsh input text "$chunk"
        sleep 0.25
        i=$((i + 3))
    done
}

# True when the typed string is visible in the address bar, i.e. the typing
# actually reached the field. Without this, "not blocked" cannot be told apart
# from "never typed".
typed_visible() {
    ui_dump || return 1
    python "$HARNESS_W/uiauto.py" has "$(to_win "$UI_XML")" "$1"
}

# Opens [url] and waits until the page (a node matching [want]) or the block
# overlay ("Blocked:") is on screen, dismissing Chrome's first-run prompts as
# they appear. A fresh install shows a full-screen "Make Chrome your own" sign-in
# page that outlasts a single check, which made every browser scenario fail
# before the fixture was ever read.
browser_open_page() {
    local url=$1 want=$2 timeout=${3:-60} i=0
    open_url "$url"
    while [ "$i" -lt "$timeout" ]; do
        if ui_dump; then
            if python "$HARNESS_W/uiauto.py" has "$(to_win "$UI_XML")" "$want|blocked:"; then
                return 0
            fi
            if tap_text "use without an account"; then
                sleep 2
                i=$((i + 3))
                continue
            fi
            if tap_text "^no thanks$"; then
                sleep 2
                i=$((i + 3))
                continue
            fi
            if tap_text "not now"; then
                sleep 2
                i=$((i + 3))
                continue
            fi
        fi
        sleep 3
        i=$((i + 3))
    done
    return 1
}

start_fixtures() {
    ( exec python "$HARNESS_W/serve.py" ) > "$OUT/fixture_port.txt" 2> "$OUT/fixtures_http.log" &
    FIXTURES_PID=$!
    local i=0
    while [ "$i" -lt 60 ]; do
        PORT=$(head -1 "$OUT/fixture_port.txt" 2>/dev/null | tr -d '\r\n')
        [ -n "$PORT" ] && break
        sleep 0.25
        i=$((i + 1))
    done
    if [ -z "$PORT" ]; then
        say "fixture server did not report a port; see fixtures_http.log"
        return 1
    fi
    dev reverse "tcp:$PORT" "tcp:$PORT" >/dev/null
}

stop_fixtures() {
    dev reverse --remove "tcp:$PORT" >/dev/null
    if [ -n "${FIXTURES_PID:-}" ]; then
        kill "$FIXTURES_PID" 2>/dev/null
        wait "$FIXTURES_PID" 2>/dev/null
    fi
}

# ---------------------------------------------------------------------------
# Scenarios
#
# Contract: each scenario sets DETAIL and returns
#   0 pass · 1 fail · 77 skip · 78 known gap
# so a scenario can never fall through into a later verdict.
# ---------------------------------------------------------------------------

# S01 The bound service must advertise the event types the blocking code needs.
#      A stale APK is invisible to every behavioural test, so assert it directly.
s01() {
    # Precondition: S01 is about what the BOUND service advertises. If Android
    # has not rebound it yet, rebind and wait instead of failing on a race.
    if ! acc_bound; then
        acc_on
        acc_wait || {
            DETAIL="service never bound, so its configuration could not be read"
            return 1
        }
    fi
    local dump
    dump=$(dsh dumpsys accessibility)
    echo "$dump" > "$OUT/accessibility_dump_$SCENARIO_ID.txt"
    if ! echo "$dump" | grep -q "label=$APP_LABEL,"; then
        DETAIL="no bound accessibility service labelled $APP_LABEL"
        return 1
    fi
    if ! echo "$dump" | grep -q "TYPE_VIEW_TEXT_CHANGED"; then
        DETAIL="service bound but does not request TYPE_VIEW_TEXT_CHANGED (stale APK or config not applied)"
        return 1
    fi
    DETAIL="bound with TYPE_WINDOW_STATE_CHANGED, TYPE_WINDOW_CONTENT_CHANGED, TYPE_VIEW_TEXT_CHANGED"
    return 0
}

# S02 A blocked word in a page's visible text blocks the browser.
s02() {
    state_reset
    pref_str filter_blocked_keywords "whine"
    if ! apply_state; then
        DETAIL="service did not bind after applying preferences"
        return 1
    fi
    if ! chrome_ready; then
        DETAIL="Chrome first-run flow could not be dismissed"
        return 1
    fi
    local before
    before=$(event_count com.android.chrome keyword)
    if ! browser_open_page "http://localhost:$PORT/keyword.html" "whine" 60; then
        screenshot no-page
        DETAIL="the fixture page never rendered in Chrome, so the keyword scan was never exercised"
        return 1
    fi
    # The block follows the window/content change that rendering causes.
    if wait_event com.android.chrome keyword "$before" 20; then
        screenshot blocked
        DETAIL="com.android.chrome keyword event raised after loading the page"
        return 0
    fi
    # Distinguish "the page never rendered" from "the page rendered and the
    # scanner missed it": the dump proves the word was on screen at decision
    # time, independently of the app's own logs.
    screenshot no-block
    local seen="no ui dump"
    if ui_dump; then
        if python "$HARNESS_W/uiauto.py" has "$(to_win "$UI_XML")" "whine"; then
            seen="page text 'whine' is visible in the window tree"
        else
            seen="page text 'whine' is NOT in the window tree"
        fi
    fi
    DETAIL="no keyword event within 25s; $seen"
    return 1
}

    # S03 The custom terms the user requires, including the multi-word one. Each
# term gets a fresh state because a visible overlay suppresses new blocks.
# The fixture NAMES deliberately avoid the terms: a URL containing the term is
# blocked as r=url (correctly), which would hide whether page text is scanned.
s03() {
    local term page before total=0 checked=0 missing=""
    for spec in "cnnam:term-a.html" "gucci third leg:term-b.html"; do
        term=${spec%%:*}
        page=${spec#*:}
        checked=$((checked + 1))
        state_reset
        pref_str filter_blocked_keywords "$term"
        if ! apply_state; then
            missing+="$term(bind) "
            continue
        fi
        if ! chrome_ready; then
            missing+="$term(chrome) "
            continue
        fi
        before=$(event_count com.android.chrome keyword)
        if ! browser_open_page "http://localhost:$PORT/$page" "$term" 60; then
            missing+="$term(page) "
            continue
        fi
        if wait_event com.android.chrome keyword "$before" 20; then
            total=$((total + 1))
        else
            missing+="$term "
        fi
    done
    screenshot last-block
    if [ "$total" -eq "$checked" ]; then
        DETAIL="both custom terms blocked (cnnam, gucci third leg)"
        return 0
    fi
    DETAIL="blocked $total of $checked; missing: ${missing:-none}"
    return 1
}

# S04 A typed address is blocked before the page loads. This path needs
#      TYPE_VIEW_TEXT_CHANGED, i.e. exactly what a stale APK cannot do.
s04() {
    state_reset
    pref_str filter_blocked_domains "pornhub.com"
    if ! apply_state; then
        DETAIL="service did not bind after applying preferences"
        return 1
    fi
    if ! chrome_ready; then
        DETAIL="Chrome first-run flow could not be dismissed"
        return 1
    fi
    open_url "about:blank"
    sleep 3
    focus_omnibox
    sleep 1
    local before started elapsed
    type_text "pornhub.com"
    sleep 1
    if ! typed_visible "pornhub.com"; then
        screenshot not-typed
        DETAIL="the typed address never reached the address bar (input focus problem)"
        return 1
    fi
    before=$(event_count com.android.chrome url)
    started=$(date +%s)
    dsh input keyevent 66
    if wait_event com.android.chrome url "$before" 8; then
        elapsed=$(( $(date +%s) - started ))
        screenshot blocked
        if [ "$elapsed" -le 3 ]; then
            DETAIL="url block ${elapsed}s after Enter, i.e. before the page could load"
            return 0
        fi
        DETAIL="url block only after ${elapsed}s; cannot prove it happened pre-load"
        return 1
    fi
    screenshot no-block
    DETAIL="typed address was not blocked within 8s"
    return 1
}

# S05 A trusted site is not blocked: the false-positive guarantee. Paired with
#      S04: same address, same typing path, and now it must get through.
s05() {
    state_reset
    pref_str filter_blocked_domains "pornhub.com"
    pref_str filter_allowlisted_domains "pornhub.com"
    if ! apply_state; then
        DETAIL="service did not bind after applying preferences"
        return 1
    fi
    if ! chrome_ready; then
        DETAIL="Chrome first-run flow could not be dismissed"
        return 1
    fi
    open_url "about:blank"
    sleep 3
    focus_omnibox
    sleep 1
    local before
    type_text "pornhub.com"
    sleep 1
    if ! typed_visible "pornhub.com"; then
        DETAIL="the typed address never reached the address bar; the negative result is not meaningful"
        return 1
    fi
    before=$(event_count com.android.chrome url)
    dsh input keyevent 66
    sleep 10
    screenshot result
    if [ "$(event_count com.android.chrome url)" -gt "$before" ]; then
        DETAIL="allowlisted site still raised a url block (false positive)"
        return 1
    fi
    if ! top_activity | grep -q "com.android.chrome"; then
        DETAIL="Chrome left the foreground; the negative result is not meaningful"
        return 1
    fi
    DETAIL="allowlisted address produced no url block in 10s while Chrome stayed foreground"
    return 0
}

# S06 A package on the blocklist is covered as soon as it is opened.
s06() {
    state_reset
    # Google's Clock on this image. It is inert, launchable and never needs
    # to be opened by any other scenario.
    pref_set filter_blocked_apps "com.google.android.deskclock"
    if ! apply_state; then
        DETAIL="service did not bind after applying preferences"
        return 1
    fi
    local before
    before=$(event_count com.google.android.deskclock app)
    launch_package com.google.android.deskclock
    # A cold start has to spin up the Dart engine first (measured 19 s on this
    # AVD), so 20 s was racing the engine start, not the block.
    if wait_event com.google.android.deskclock app "$before" 35; then
        screenshot blocked
        DETAIL="com.google.android.deskclock blocked by the app rule"
        return 0
    fi
    screenshot no-block
    DETAIL="no app block for com.google.android.deskclock within 35s"
    return 1
}

# S07 Opening Haram Blur's own app-info page is backed out of, and recorded.
s07() {
    state_reset
    if ! apply_state; then
        DETAIL="service did not bind after applying preferences"
        return 1
    fi
    local before
    before=$(audit_count settings_escape)
    # Precondition: prove the protected page was launched. Reading it out of a
    # dump races the guard, which backs out within a second or two - and on
    # Android 16 the page is `.spa.SpaActivity`, so "is InstalledAppDetails
    # gone?" was true from the first second and used to pass vacuously.
    local launch
    # One quoted argument: the device shell must receive `package:<pkg>` intact,
    # and passing the arguments separately left the URI as a bare "package:".
    launch=$(dsh "am start -W -a android.settings.APPLICATION_DETAILS_SETTINGS -d package:$PKG")
    printf '%s\n' "$launch" > "$OUT/s07_launch.txt"
    if ! echo "$launch" | grep -q "Status: ok"; then
        screenshot no-app-info
        DETAIL="the app-info intent did not launch: $(echo "$launch" | tail -1)"
        return 1
    fi
    if ! echo "$launch" | grep -q "com.android.settings"; then
        screenshot no-app-info
        DETAIL="the app-info intent resolved outside Settings: $(echo "$launch" | grep -m1 Activity)"
        return 1
    fi
    # Best effort: if the page is still up, keep its tree as evidence.
    ui_dump >/dev/null 2>&1 || true
    screenshot before-escape
    _recorded() { [ "$(audit_count settings_escape)" -gt "$before" ]; }
    if ! bounded_wait 20 _recorded; then
        screenshot no-audit
        DETAIL="app-info page was open for 20s and no settings_escape entry was recorded"
        return 1
    fi
    # The entry must be about OUR page: Settings keeps the last-viewed fragment
    # when it is re-hosted, so an entry that does not name the app would mean
    # the guard saw a leftover page.
    if ! printf '%s' "$(audit_last_detail)" | grep -qi "$APP_LABEL"; then
        DETAIL="the settings_escape entry does not name $APP_LABEL: $(audit_last_detail | cut -c1-60)"
        return 1
    fi
    # Enforcement, not just logging: the page must actually be left.
    _left_app_info() {
        if ui_dump; then
            ! python "$HARNESS_W/uiauto.py" has "$(to_win "$UI_XML")" "force stop"
        else
            ! top_activity | grep -q "com.android.settings"
        fi
    }
    if ! bounded_wait 20 _left_app_info; then
        screenshot still-open
        DETAIL="settings_escape was recorded but the app-info page stayed open"
        return 1
    fi
    screenshot after-escape
    # One page, one entry: several accessibility callbacks must not multiply it.
    local recorded
    recorded=$(audit_count settings_escape)
    if [ "$recorded" -gt "$((before + 1))" ]; then
        DETAIL="one escape wrote $((recorded - before)) audit entries (duplicates)"
        return 1
    fi
    # Negative control: ordinary Settings navigation stays usable and unrecorded.
    dsh am start -a android.settings.SETTINGS >/dev/null
    sleep 8
    screenshot plain-settings
    if [ "$(audit_count settings_escape)" -ne "$recorded" ]; then
        DETAIL="ordinary Settings navigation was recorded as an escape (false positive)"
        return 1
    fi
    if ! top_activity | grep -q "com.android.settings"; then
        DETAIL="ordinary Settings was backed out of (false positive)"
        return 1
    fi
    DETAIL="app-info page detected, backed out and audited once; ordinary Settings untouched"
    return 0
}

# S08 A blocked word in a notification preview is caught in the shade.
s08() {
    state_reset
    pref_str filter_blocked_keywords "cnnam"
    if ! apply_state; then
        DETAIL="service did not bind after applying preferences"
        return 1
    fi
    local before
    before=$(event_count com.android.systemui keyword)
    # One quoted string, or the device shell splits the title and the body
    # message into separate arguments and the word never reaches the shade.
    dsh "cmd notification post -S bigtext -t 'Phase 1 harness' phase1 'cnnam in the shade'"
    sleep 1
    # System UI ANRs (the emulator runs out of RAM) leave the shade closed, so
    # "the body never rendered" was blamed on the notification. Dismiss the
    # dialog and retry the expansion once before drawing that conclusion.
    local opened=0 attempt=0
    while [ "$attempt" -lt 2 ]; do
        dsh cmd statusbar expand-notifications
        sleep 3
        if ui_dump && python "$HARNESS_W/uiauto.py" has "$(to_win "$UI_XML")" "cnnam"; then
            opened=1
            break
        fi
        dismiss_system_dialogs
        attempt=$((attempt + 1))
    done
    if [ "$opened" -eq 0 ] && ui_dump && ! python "$HARNESS_W/uiauto.py" has "$(to_win "$UI_XML")" "cnnam"; then
        screenshot shade
        dsh cmd statusbar collapse
        DETAIL="the notification body never rendered in the shade; the scan was never given a chance"
        return 1
    fi
    if wait_event com.android.systemui keyword "$before" 15; then
        screenshot blocked
        dsh cmd statusbar collapse
        DETAIL="notification preview keyword blocked in com.android.systemui"
        return 0
    fi
    screenshot no-block
    dsh cmd statusbar collapse
    DETAIL="no systemui keyword event within 15s"
    return 1
}

# S09 Revoking accessibility stops protection. This characterises the gap the
#      roadmap calls item 1 instead of pretending it passes.
s09() {
    state_reset
    if ! apply_state; then
        DETAIL="service did not bind after applying preferences"
        return 1
    fi
    acc_off
    sleep 3
    if acc_bound; then
        DETAIL="service still reported as bound after accessibility was switched off"
        return 1
    fi
    local notified
    notified=$( { dsh dumpsys notification --noredact | grep -c "protection is off" || true; } )
    screenshot revoked
    # Leave protection enabled again so the next scenario starts from the same
    # place a user would be in.
    acc_on
    DETAIL="accessibility off -> service unbound; watchdog notifications found: $notified (0 means no alert is raised: roadmap item 1)"
    return 78
}

# S10 Protection survives a reboot without the app being opened.
#
# This records the whole boot timeline, not just "is it bound": the service
# logs its lifecycle milestones (BOOT_RECEIVED, SERVICE_CONNECTED,
# PREFERENCES_RESTORED, FIRST_WINDOW_AVAILABLE, FIRST_SCAN_COMPLETED,
# PROTECTION_ACTIVE), so a failure names the stage that did not happen instead
# of only saying "not blocked". Basirah is never launched here: the only user
# action is opening Chrome.
s10() {
    state_reset
    pref_str filter_blocked_keywords "whine"
    if ! apply_state; then
        DETAIL="service did not bind after applying preferences"
        return 1
    fi
    # The pushed state is the "before" side of the before/after comparison.
    cp "$OUT/prefs_S10.xml" "$OUT/prefs_S10_before_reboot.xml" 2>/dev/null || true
    # Chrome on a reset profile answers a VIEW intent with its first-run card
    # ("Make Chrome your own") instead of the page, so the post-reboot step
    # never requests the fixture (results/20261122T211150Z: empty
    # fixtures_http.log, screenshot on the card). Finishing it once here is the
    # only place it can be done by node: after the reboot every uiautomator
    # dump would unbind the connection under test. The page used here is
    # benign, and the browser is stopped again before the reboot.
    open_url "http://localhost:$PORT/term-a.html"
    chrome_ready
    dsh am force-stop com.android.chrome >/dev/null 2>&1
    dsh input keyevent 3 >/dev/null 2>&1
    sleep 2

    say "   (rebooting; the fixture page is opened again once the device is up)"
    # `sys.boot_completed` still reads 1 from the previous boot for several
    # seconds after `adb reboot`, and adb reconnects while the guest is still
    # restarting. Waiting only for that property let the whole scenario run
    # against the old boot (run 20261122T083015Z asserted at 09:37 on a device
    # whose real boot happened at 09:38), so the kernel boot id — which cannot
    # be stale — is the gate.
    local boot_id
    boot_id=$(dsh cat /proc/sys/kernel/random/boot_id | tr -d '\r')
    dsh reboot >/dev/null 2>&1
    sleep 5
    _device_present() { [ "$(dev get-state | tr -d '\r')" = "device" ]; }
    _rebooted() {
        local now
        now=$(dsh cat /proc/sys/kernel/random/boot_id | tr -d '\r')
        [ -n "$now" ] && [ "$now" != "$boot_id" ]
    }
    if ! bounded_wait 240 _rebooted; then
        DETAIL="the device never restarted (kernel boot id unchanged) after the reboot command (environment, not the app)"
        return 1
    fi
    if ! bounded_wait 180 _device_present; then
        DETAIL="the device did not come back on adb after the reboot (environment, not the app)"
        return 1
    fi
    _booted() { [ "$(dsh getprop sys.boot_completed | tr -d '\r')" = "1" ]; }
    if ! bounded_wait "$BOOT_TIMEOUT" _booted; then
        DETAIL="the device did not finish booting within ${BOOT_TIMEOUT}s (environment, not the app)"
        return 1
    fi
    # Early timeline: what the receiver and service logged before any harness
    # step touched the device. The post-bind capture below supersedes it.
    dsh logcat -d -s HaramBlur:* > "$OUT/S10_boot_early.log" 2>/dev/null || true
    read_prefs > "$OUT/prefs_S10_after_reboot.xml" 2>/dev/null || true
    if ! grep -q 'name="system_wide_enabled" value="true"' "$OUT/prefs_S10_after_reboot.xml"; then
        DETAIL="the protection preference was not readable as true after the reboot"
        return 1
    fi

    # Emulator housekeeping only: the reverse mapping, the framebuffer size and
    # the keyguard are device state a reboot resets. None of it enables
    # protection or launches Basirah.
    dev reverse "tcp:$PORT" "tcp:$PORT" >/dev/null 2>&1
    # No uiautomator after the reboot: it is what unbinds the service here.
    settle_device 1

    # The app's own connect line is the authority, not `dumpsys accessibility`:
    # that list can still show the pre-reboot binding while the guest restarts.
    _service_connected() { dsh logcat -d -s HaramBlur:* | grep -q "Lifecycle: SERVICE_CONNECTED"; }
    if ! bounded_wait 150 _service_connected; then
        screenshot not-connected
        DETAIL="onServiceConnected never logged within 150s of the boot (see S10_boot.log)"
        return 1
    fi
    # `dumpsys accessibility` can lag the connect by a few seconds while the
    # system is busy dismissing boot-time ANR dialogs (run 20261122T095458Z saw
    # the connect log with the dump still empty), so give it a bounded moment
    # rather than failing on a single read.
    if ! bounded_wait 60 acc_bound; then
        screenshot not-bound
        DETAIL="the service logged a connect but Android does not list it as bound"
        return 1
    fi
    # The log buffer was cleared by the reboot, so this holds the full timeline
    # from boot to the bind even though the bind can take 60-90 s.
    dsh logcat -d -s HaramBlur:* > "$OUT/S10_boot.log" 2>/dev/null || true
    if ! grep -q "Lifecycle: SERVICE_CONNECTED" "$OUT/S10_boot.log"; then
        screenshot not-connected
        DETAIL="Android lists the service as bound but onServiceConnected never logged"
        return 1
    fi
    if grep -q "Lifecycle: PROTECTION_IDLE" "$OUT/S10_boot.log"; then
        screenshot idle
        DETAIL="service connected but stayed idle: system_wide_enabled read as false after boot"
        return 1
    fi
    if ! grep -q "Lifecycle: PREFERENCES_RESTORED" "$OUT/S10_boot.log"; then
        DETAIL="service connected without logging the restored preference counts"
        return 1
    fi
    if top_activity | grep -q "$PKG/"; then
        DETAIL="Basirah itself was in the foreground, so this would not prove automatic protection"
        return 1
    fi
    local before
    before=$(event_count com.android.chrome keyword)
    # No uiautomator in this scenario, on purpose: on this image every
    # UiAutomation session (`uiautomator dump`) tears down and re-creates
    # third-party accessibility connections — the system log shows
    # "Registering UiTestAutomationService" immediately before each
    # SERVICE_UNBOUND — so polling the UI here would measure the harness, not
    # the app. The VIEW intent loads the fixture and the app's own scan line
    # (url=...keyword.html) plus the EventLog entry prove what was read.
    #
    # Chrome on this reset profile answers a VIEW intent with its first-run
    # card ("Make Chrome your own") instead of the page, and a boot-time
    # system ANR can sit above it; either one leaves the fixture unrequested
    # (results/20261122T211150Z: empty fixtures_http.log, screenshot on the
    # card). Both are cleared with fixed taps on the 720x1560 layout, because
    # the uiautomator path that normally taps them would unbind the
    # connection this scenario is measuring.
    open_url "http://localhost:$PORT/keyword.html"
    sleep 3
    dsh input tap 228 893 >/dev/null 2>&1
    sleep 2
    dsh input tap 360 1246 >/dev/null 2>&1
    sleep 2
    open_url "http://localhost:$PORT/keyword.html"
    if wait_event com.android.chrome keyword "$before" 60; then
        screenshot blocked
        dsh logcat -d -s HaramBlur:* > "$OUT/S10_enforced.log" 2>/dev/null || true
        if grep -q "Lifecycle: FIRST_SCAN_COMPLETED pkg=com.android.chrome" "$OUT/S10_enforced.log"; then
            DETAIL="no app opened after boot; first page scanned and the keyword page blocked"
        else
            DETAIL="keyword blocked after reboot, but no first-scan milestone was logged"
        fi
        return 0
    fi
    screenshot no-block
    local last
    last=$( { dsh logcat -d -s HaramBlur:* | grep -o "Lifecycle: [A-Z_]*" | tail -1; } )
    DETAIL="service rebound but did not block the keyword page after reboot; last milestone: ${last:-none logged}"
    return 1
}

# S11 Split screen. `am start --windowingMode` does not reliably produce a real
#      split on this image, so an unproven setup is reported as SKIP.
s11() {
    state_reset
    pref_bool advanced_block_split_screen true
    pref_str filter_blocked_keywords "whine"
    if ! apply_state; then
        DETAIL="service did not bind after applying preferences"
        return 1
    fi
    dsh am start --windowingMode 3 -n com.android.deskclock/com.android.deskclock.DeskClock
    sleep 2
    dsh am start --windowingMode 4 -n com.android.chrome/com.google.android.apps.chrome.Main
    sleep 4
    screenshot split
    if ! dsh dumpsys activity activities | grep -q "WindowingMode=3"; then
        DETAIL="emulator did not enter split screen via am --windowingMode; needs the manual step in physical-device.md"
        return 77
    fi
    local before
    before=$(event_count com.android.chrome splitScreen)
    open_url "http://localhost:$PORT/keyword.html"
    if wait_event com.android.chrome splitScreen "$before" 20; then
        DETAIL="split screen detected and blocked"
        return 0
    fi
    DETAIL="split screen was active but no splitScreen block was raised"
    return 1
}

SCENARIOS="S01 S02 S03 S04 S05 S06 S07 S08 S09 S10 S11"

scenario_title() {
    case "$1" in
        S01) echo "Bound service advertises the required event types" ;;
        S02) echo "Blocked word in page text blocks the browser" ;;
        S03) echo "Custom terms (cnnam, gucci third leg) block" ;;
        S04) echo "Typed address blocked before load" ;;
        S05) echo "Trusted/allowlisted site is not blocked" ;;
        S06) echo "Blocklisted app is covered on open" ;;
        S07) echo "Settings app-info screen backs out and is audited" ;;
        S08) echo "Blocked word in a notification preview" ;;
        S09) echo "Accessibility revoked: protection stops (known gap)" ;;
        S10) echo "Protection survives reboot" ;;
        S11) echo "Split screen is detected and blocked" ;;
        *) echo "unknown" ;;
    esac
}

scenario_expected() {
    case "$1" in
        S01) echo "Bound service requests windowStateChanged, windowContentChanged and viewTextChanged" ;;
        S02) echo "EventLog: com.android.chrome / keyword within 25s" ;;
        S03) echo "One keyword event per term; both terms matched" ;;
        S04) echo "EventLog: com.android.chrome / url within 3s of Enter" ;;
        S05) echo "No url event for 10s; Chrome still foreground" ;;
        S06) echo "EventLog: com.android.deskclock / app within 15s" ;;
        S07) echo "App-info page left; one settings_escape naming the app; plain Settings untouched" ;;
        S08) echo "EventLog: com.android.systemui / keyword within 15s" ;;
        S09) echo "Service unbound; no false claim of continued protection" ;;
        S10) echo "Service rebound after reboot; keyword still blocked" ;;
        S11) echo "splitScreen block while two apps share the screen" ;;
        *) echo "" ;;
    esac
}

record() {
    local id=$1 mark=$2 detail=$3
    case "$mark" in
        PASS) EXPECT_COUNTS_PASS=$((EXPECT_COUNTS_PASS + 1)) ;;
        FAIL) EXPECT_COUNTS_FAIL=$((EXPECT_COUNTS_FAIL + 1)) ;;
        SKIP) EXPECT_COUNTS_SKIP=$((EXPECT_COUNTS_SKIP + 1)) ;;
        KNOWN-GAP) EXPECT_COUNTS_GAP=$((EXPECT_COUNTS_GAP + 1)) ;;
    esac
    printf '%s\t%s\t%s\t%s\n' "$id" "$(scenario_title "$id")" "$mark" "$detail" >> "$OUT/results.tsv"
}

# A previous scenario (or a manual probe) can leave the notification shade,
# an ANR dialog or another app in front. Without this, a scenario reported its
# own failure while the screen was actually showing something else.
reset_ui() {
    dsh cmd statusbar collapse >/dev/null 2>&1
    dsh input keyevent 3 >/dev/null 2>&1
    sleep 0.5
    dismiss_system_dialogs
}

# A crashed emulator used to look like a pile of application failures (no
# bound service, no window, address bar missing). Losing the device is an
# environment failure: say so and stop instead of blaming the app.
ensure_alive() {
    if dev devices | tr -d '\r' | grep -qE "[[:space:]]device$"; then
        return 0
    fi
    say "environment failure: the emulator is gone (no adb device); aborting"
    record "$1" FAIL "ENVIRONMENT: emulator disappeared before this scenario"
    write_summary
    exit 2
}

run_scenario() {
    local id=$1 code mark
    SCENARIO_ID=$id
    DETAIL=""
    ensure_alive "$id"
    say ""
    say "── $id · $(scenario_title "$id")"
    dsh logcat -c
    reset_ui
    "s${id#S}"
    code=$?
    # prefs_<ID>.xml is the state pushed in; the file at the end of the scenario
    # is the app's own record of what it did (EventLog and SecurityAudit both
    # live in it), so keep both in the artifacts.
    read_prefs > "$OUT/prefs_${id}_after.xml" 2>/dev/null || true
    case "$code" in
        0) mark=PASS ;;
        77) mark=SKIP ;;
        78) mark=KNOWN-GAP ;;
        *) mark=FAIL ;;
    esac
    say "   -> $mark: ${DETAIL:-no detail}"
    record "$id" "$mark" "${DETAIL:-no detail}"
    capture_logcat
}

# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

ensure_device() {
    local i=0
    if dev devices | tr -d '\r' | grep -qE "[[:space:]]device$"; then
        say "reusing the attached device"
        return 0
    fi
    say "starting AVD $AVD (this takes a minute)"
    # 1.5 GB (the AVD default) is not enough for Chrome plus the detector: the
    # system UI starts ANR-ing and uiautomator dumps time out.
    # shellcheck disable=SC2086
    ("$EMULATOR" -avd "$AVD" -memory 3072 -no-snapshot-save -no-boot-anim -no-audio \
        > "$OUT/emulator.log" 2>&1 &)
    "$ADB" wait-for-device >/dev/null 2>&1
    while [ "$i" -lt "$BOOT_TIMEOUT" ]; do
        [ "$(dsh getprop sys.boot_completed | tr -d '\r')" = "1" ] && return 0
        sleep 2
        i=$((i + 2))
    done
    return 1
}

# Right after boot this image spends a minute starting system services and
# logs "failed to complete startup" ANRs for com.android.phone and the Google
# keyboard. The dialog that follows owns the foreground and swallows taps and
# the notification shade, which made S07 and S08 fail for the wrong reason.
# Keep the screen awake and give the system a moment to settle.
settle_device() {
    # At 1080x2400 with software rendering this image wedges System UI (the
    # shell stops answering adb). A 720x1560 framebuffer keeps it responsive;
    # taps are node-based, so the layout change does not affect the scenarios.
    #
    # `settle_device 1` skips the dialog pass: every `uiautomator dump` is a
    # UiAutomation session, and on this image that tears down third-party
    # accessibility connections (the system log shows "Registering
    # UiTestAutomationService" immediately before each SERVICE_UNBOUND). The
    # reboot scenario measures that connection, so it must not use uiautomator.
    local skip_ui=${1:-0}
    dsh wm size 720x1560 >/dev/null 2>&1
    dsh wm density 320 >/dev/null 2>&1
    dsh input keyevent 224 >/dev/null 2>&1
    dsh wm dismiss-keyguard >/dev/null 2>&1
    dsh svc power stayon true >/dev/null 2>&1
    dsh settings put system screen_off_timeout 1800000 >/dev/null 2>&1
    sleep "${PHASE1_SETTLE_SECONDS:-45}"
    dsh cmd statusbar collapse >/dev/null 2>&1
    dsh input keyevent 3 >/dev/null 2>&1
    if [ "$skip_ui" -eq 0 ]; then
        dismiss_system_dialogs
        dismiss_system_dialogs
    fi
}

build_apk() {
    if [ "$BUILD" -eq 0 ]; then
        [ -f "$APK" ] && return 0
        say "no APK at $APK and --no-build was given"
        return 1
    fi
    say "building the x86_64 debug APK from the working tree"
    # MSYS_NO_PATHCONV is exported above, so the double-slash form `cmd //c`
    # reaches cmd literally and it starts an interactive shell instead of
    # running the batch file (the run then hangs with only a cmd banner in
    # build.log). With conversion off, `/c` is already the right argument.
    ( cd "$ROOT" && cmd /c 'tools\build_x64.bat' ) > "$OUT/build.log" 2>&1
    grep -q "BUILD_EXIT=0" "$OUT/build.log"
}

install_apk() {
    # Called directly, not through dev(), so adb's failure reason is kept.
    "$ADB" install -r -g "$APK_W" > "$OUT/install.log" 2>&1
    grep -q "Success" "$OUT/install.log"
}

main() {
    say "Phase 1 harness · run $RUN_ID"
    say "artifacts: $OUT"

    command -v python >/dev/null || { say "python is required (uiauto.py, fixture probe)"; exit 2; }
    [ -x "$ADB" ] || [ -x "$ADB.exe" ] || { say "adb not found: $ADB"; exit 2; }

    ensure_device || { say "no usable emulator"; exit 2; }

    dsh getprop ro.build.fingerprint > "$OUT/device.txt"
    say "AVD=$AVD  model=$(dsh getprop ro.product.model | tr -d '\r')  api=$(dsh getprop ro.build.version.sdk | tr -d '\r')" \
        | tee -a "$OUT/device.txt"

    build_apk || { say "build failed, see $OUT/build.log"; exit 2; }
    if [ "$INSTALL" -eq 1 ]; then
        install_apk || { say "install failed, see $OUT/install.log"; exit 2; }
        say "installed $(stat -c %s "$APK" 2>/dev/null || echo '?') bytes"
    else
        # Iterating on the harness against an already-installed build.
        say "reusing the APK already installed (--no-install)"
    fi

    # Animation frames make uiautomator dumps time out and slow every check on
    # a software-rendered emulator. Standard automation setting, device-local.
    dsh settings put global window_animation_scale 0
    dsh settings put global transition_animation_scale 0
    dsh settings put global animator_duration_scale 0

    # `pm clear` was worse than the problem: it brings back Chrome's first-run
    # flow, which outlasts a scenario. Leftover tabs are handled per navigation
    # in open_url instead.
    if [ "${PHASE1_RESET_BROWSER:-0}" -eq 1 ]; then
        dsh pm clear com.android.chrome >/dev/null 2>&1
    fi

    settle_device

    if ! start_fixtures; then
        say "local fixture server did not start"
        stop_fixtures
        exit 2
    fi
    say "fixtures on http://localhost:$PORT (adb reverse)"
    trap stop_fixtures EXIT

    # Bind the service once so S01 has an honest baseline, and so a fresh AVD
    # does not fail every scenario for the same reason.
    state_reset
    apply_state || say "warning: service did not bind with default state"
    chrome_ready || say "warning: Chrome first-run flow not dismissed; browser scenarios will fail"

    for id in $SCENARIOS; do
        if [ -n "$ONLY" ]; then
            case ",$ONLY," in
                *",$id,"*) : ;;
                *) continue ;;
            esac
        fi
        if [ "$id" = "S10" ] && [ "$DO_REBOOT" -eq 0 ]; then
            say ""
            say "── S10 skipped (--no-reboot)"
            record S10 SKIP "--no-reboot"
            continue
        fi
        run_scenario "$id"
    done

    write_summary

    say ""
    say "PASS $EXPECT_COUNTS_PASS · KNOWN-GAP $EXPECT_COUNTS_GAP · SKIP $EXPECT_COUNTS_SKIP · FAIL $EXPECT_COUNTS_FAIL"
    say "summary: $OUT/summary.md"

    [ "$EXPECT_COUNTS_FAIL" -gt 0 ] && exit 1
    exit 0
}

write_summary() {
    {
        echo "# Phase 1 emulator run — $RUN_ID"
        echo
        echo "AVD \`$AVD\` · APK $(ls -l "$APK" 2>/dev/null | awk '{print $5" bytes"}') · $(head -2 "$OUT/device.txt" 2>/dev/null | tr '\n' ' ')"
        echo
        echo "PASS **$EXPECT_COUNTS_PASS** · KNOWN-GAP $EXPECT_COUNTS_GAP · SKIP $EXPECT_COUNTS_SKIP · FAIL **$EXPECT_COUNTS_FAIL**"
        echo
        echo "| ID | Scenario | Expected | Actual | Outcome |"
        echo "|---|---|---|---|---|"
        local id title mark detail expected
        while IFS=$'\t' read -r id title mark detail; do
            expected=$(scenario_expected "$id")
            echo "| $id | $title | $expected | ${detail//|/\\|} | $mark |"
        done < "$OUT/results.tsv"
        echo
        echo "## Artifacts"
        echo
        echo "- \`prefs_*.xml\` — the exact preference state each scenario ran with"
        echo "- \`S*-*.png\` — device screenshot at the decisive moment"
        echo "- \`S*.log\` — logcat slice for that scenario (tag \`HaramBlur\`)"
        echo "- \`build.log\`, \`install.log\`, \`fixtures_http.log\`, \`emulator.log\`"
        echo
        echo "This run exercises the debug APK on an emulator with software"
        echo "graphics. It proves the rule-based plumbing, not the accuracy of the"
        echo "pixel detector, and says nothing about OEM behaviour or battery use."
        echo "See \`tools/harness/physical-device.md\` for what still has to be"
        echo "checked on a real phone."
    } > "$OUT/summary.md"
}

main
