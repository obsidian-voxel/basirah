import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/blur_event.dart';
import '../src/block_rules.dart';
import '../src/policy.dart';
import 'blur_event_store.dart';
import 'filter_store.dart';
import 'native_bridge.dart';
import 'settings_store.dart';

/// Coordinates system-wide protection: persisted settings, the native
/// service state, and the local blur-event history. Screens listen to this
/// object, so every status change comes from one place.
class BlurEngine extends ChangeNotifier {
  BlurEventStore? _store;
  SettingsStore? _settings;
  FilterStore? _filters;
  NativeStatus _status = NativeStatus.unsupported;
  bool _initialized = false;
  String? _initError;
  Timer? _watchdog;
  DateTime? _lastWatchdogNotice;

  bool get isInitialized => _initialized;
  String? get initError => _initError;
  NativeStatus get status => _status;

  SettingsStore get settings {
    final value = _settings;
    if (value == null) {
      throw StateError('BlurEngine not initialised; call init() first');
    }
    return value;
  }

  /// App/keyword blocklists, schedules and daily limits.
  FilterStore get filters {
    final value = _filters;
    if (value == null) {
      throw StateError('BlurEngine not initialised; call init() first');
    }
    return value;
  }

  int get sensitivity => _settings?.sensitivity ?? 5;

  BlurStrength get blurStrength => _settings?.blurStrength ?? BlurStrength.strong;

  /// Effective detection thresholds for the current sensitivity.
  BlurConfig get config =>
      BlurConfig.forSensitivity(sensitivity, strength: blurStrength);

  bool get enabled => _status.protectionEnabled;
  bool get isActive => _status.isActive;
  bool get isSupported => _status.supported;

  /// The complete exclusion list shown in settings and sent to Android.
  List<String> get exclusions => [
        ...SettingsStore.defaultExclusions,
        ...(_settings?.customExclusions ?? const <String>[]),
      ];

  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _store = BlurEventStore(prefs);
      _settings = SettingsStore(prefs);
      _filters = FilterStore(prefs);
      _initialized = true;
      await _syncExclusions();
      await nativeBridge.setDebugOverlay(debugOverlayEnabled);
      // Seed the shipped blocklists on first launch, then hand the whole
      // configuration to the service: it must block without this engine.
      await _filters!.ensureSeeded();
      await _filters!.pushToNative();
      await refreshStatus();
    } catch (error) {
      _initError = error.toString();
      debugPrint('BlurEngine init failed: $error');
    }
  }

  /// Re-reads native state and imports any events the service recorded.
  Future<void> refreshStatus() async {
    final status = await nativeBridge.status();
    _status = status;
    if (status.supported && status.recentEvents.isNotEmpty) {
      await _store?.merge(status.recentEvents);
    }
    notifyListeners();
  }

  /// Turns protection on/off. Returns the resulting native status so the UI
  /// can prompt for the Accessibility permission when it is missing.
  Future<NativeStatus> setEnabled(bool value) async {
    await _settings?.setProtectionEnabled(value);
    final status = await nativeBridge.setEnabled(value);
    if (status.supported) {
      _status = status;
      if (status.recentEvents.isNotEmpty) {
        await _store?.merge(status.recentEvents);
      }
    }
    notifyListeners();
    return _status;
  }

  /// Whether the live capture HUD is drawn over the screen.
  bool get debugOverlayEnabled => _settings?.debugOverlayEnabled ?? true;

  Future<void> setDebugOverlay(bool value) async {
    await _settings?.setDebugOverlay(value);
    await nativeBridge.setDebugOverlay(value);
    notifyListeners();
  }

  Future<void> setBlurStrength(BlurStrength strength) async {
    await _settings?.setBlurStrength(strength);
    await nativeBridge.setBlurStrength(strength.name);
    notifyListeners();
  }

  Future<void> setSensitivity(int level) async {
    final clamped = level.clamp(1, 10);
    await _settings?.setSensitivity(clamped);
    await nativeBridge.setSensitivity(clamped);
    await refreshStatus();
  }

  /// Persists a user-added exclusion and pushes the effective list to Android.
  Future<void> addExclusion(String package) async {
    final store = _settings;
    if (store == null) return;
    final next = [...store.customExclusions, package];
    await store.setCustomExclusions(next);
    await _syncExclusions();
    notifyListeners();
  }

  Future<void> removeExclusion(String package) async {
    final store = _settings;
    if (store == null) return;
    final next = store.customExclusions.where((p) => p != package).toList();
    await store.setCustomExclusions(next);
    await _syncExclusions();
    notifyListeners();
  }

  Future<void> _syncExclusions() async {
    await nativeBridge.setExclusions(exclusions);
  }

  // ---------------------------------------------------------------------
  // Filters & blocklists
  // ---------------------------------------------------------------------

  Future<void> addBlockedApp(String package) async {
    await _filters?.addApp(package);
    await _filters?.pushToNative();
    notifyListeners();
  }

  Future<void> removeBlockedApp(String package) async {
    await _filters?.removeApp(package);
    await _filters?.pushToNative();
    notifyListeners();
  }

  /// Adds a website the user typed in the Block list. Pushed immediately so
  /// the accessibility service blocks it without waiting for a restart.
  Future<void> addBlockedDomain(String domain) async {    await _filters?.addDomain(domain);
    await _filters?.pushToNative();
    notifyListeners();
  }

  Future<void> removeBlockedDomain(String domain) async {
    await _filters?.removeDomain(domain);
    await _filters?.pushToNative();
    notifyListeners();
  }

  Future<void> addBlockedKeyword(String keyword) async {
    await _filters?.addKeyword(keyword);
    await _filters?.pushToNative();
    notifyListeners();
  }

  Future<void> removeBlockedKeyword(String keyword) async {
    await _filters?.removeKeyword(keyword);
    await _filters?.pushToNative();
    notifyListeners();
  }

  Future<void> addKeywordPreset(KeywordPreset preset) async {
    await _filters?.addPreset(preset);
    await _filters?.pushToNative();
    notifyListeners();
  }

  Future<void> setAppSchedule(String package, ScheduleWindow? window) async {
    await _filters?.setSchedule(package, window);
    await _filters?.pushToNative();
    notifyListeners();
  }

  Future<void> setDailyLimit(String package, int minutes) async {
    await _filters?.setDailyLimit(package, minutes);
    await _filters?.pushToNative();
    notifyListeners();
  }

  bool get blockNewApps => _filters?.blockNewApps ?? true;

  bool get blockNewBrowsers => _filters?.blockNewBrowsers ?? false;

  bool get blockUnsupportedBrowsers =>
      _filters?.blockUnsupportedBrowsers ?? true;

  bool get dailyAffirmations => _filters?.dailyAffirmations ?? false;

  /// Apps the user allows even though they are on the blocklist.
  List<String> get whitelistedApps => _filters?.whitelistedApps ?? const [];

  /// Block the app when the device enters split screen.
  bool get blockSplitScreen => _filters?.blockSplitScreen ?? false;

  /// Block browsers that are in a private/incognito window.
  bool get blockIncognito => _filters?.blockIncognito ?? true;

  /// Block embedded browsers inside other apps.
  bool get blockInAppBrowsers => _filters?.blockInAppBrowsers ?? false;

  /// Sites that are never blocked, checked ahead of every site list.
  List<String> get allowlistedDomains =>
      _filters?.allowlistedDomains ?? const [];

  Future<void> addAllowlistedDomain(String domain) async {
    await _filters?.addAllowlistedDomain(domain);
    await _filters?.pushToNative();
    notifyListeners();
  }

  Future<void> removeAllowlistedDomain(String domain) async {
    await _filters?.removeAllowlistedDomain(domain);
    await _filters?.pushToNative();
    notifyListeners();
  }

  /// Keywords that only match as whole words.
  List<String> get wholeWordKeywords => _filters?.wholeWordKeywords ?? const [];

  Future<void> addWholeWordKeyword(String keyword) async {
    await _filters?.addWholeWordKeyword(keyword);
    await _filters?.pushToNative();
    notifyListeners();
  }

  Future<void> removeWholeWordKeyword(String keyword) async {
    await _filters?.removeWholeWordKeyword(keyword);
    await _filters?.pushToNative();
    notifyListeners();
  }

  /// Apps where the in-app browser rule applies; empty means every app.
  List<String> get inAppBrowserApps => _filters?.inAppBrowserApps ?? const [];

  Future<void> setInAppBrowserApps(List<String> packages) async {
    await _filters?.setInAppBrowserApps(packages);
    await _filters?.pushToNative();
    notifyListeners();
  }

  /// Leave Android Settings screens that could switch protection off.
  bool get guardSettings => _filters?.guardSettings ?? true;

  bool get prayerBlocking => _filters?.prayerBlocking ?? false;

  double? get prayerLatitude => _filters?.prayerLatitude;

  double? get prayerLongitude => _filters?.prayerLongitude;

  int get prayerMinutesAfter => _filters?.prayerMinutesAfter ?? 15;

  String get prayerMethod => _filters?.prayerMethod ?? 'MuslimWorldLeague';

  Future<void> setPrayerPolicy({
    required bool enabled,
    double? latitude,
    double? longitude,
    int? minutesAfter,
    String? method,
  }) async {
    await _filters?.setPrayerPolicy(
      enabled: enabled,
      latitude: latitude ?? prayerLatitude,
      longitude: longitude ?? prayerLongitude,
      minutesAfter: minutesAfter ?? prayerMinutesAfter,
      method: method ?? prayerMethod,
    );
    await _filters?.pushToNative();
    notifyListeners();
  }

  /// Today's prayer windows as the native calculator computed them.
  Future<List<PrayerWindow>> prayerTimes() => nativeBridge.prayerTimes();

  /// Re-snapshots installed apps and browsers after an install the user made
  /// on purpose, so the “installed after setup” rule does not flag it.
  Future<void> rebaselineNewApps() async {
    _status = await nativeBridge.rebaselineNewApps();
    notifyListeners();
  }

  /// Vouches for one app: the future-install rules stop flagging it.
  Future<void> trustApp(String package) async {
    _status = await nativeBridge.trustApp(package);
    notifyListeners();
  }

  /// The on-device security audit, newest last.
  Future<List<SecurityAuditEntry>> securityAudit() =>
      nativeBridge.securityAudit();

  /// Lock the block screen for five minutes after repeated attempts.
  bool get crossBlockLimit => _filters?.crossBlockLimit ?? true;

  /// Custom block screen copy; empty means the shipped wording.
  String get blockScreenTitle => _filters?.blockScreenTitle ?? '';
  String get blockScreenMessage => _filters?.blockScreenMessage ?? '';

  Future<void> setBlockScreen({String? title, String? message}) async {
    await _filters?.setBlockScreen(title: title, message: message);
    await _filters?.pushToNative();
    notifyListeners();
  }

  /// The long sentence the user must type before a guard can be turned off.
  String get longSentencePassword => _filters?.longSentencePassword ?? '';

  bool get hasLongSentencePassword => _filters?.hasLongSentencePassword ?? false;

  /// Epoch milliseconds until which focus mode runs; 0 when idle.
  int get focusActiveUntil => _filters?.focusActiveUntil ?? 0;

  /// Apps that stay reachable during a focus session.
  List<String> get focusAllowedApps => _filters?.focusAllowedApps ?? const [];

  /// When on, a focus session cannot be ended early.
  bool get focusPreventExit => _filters?.focusPreventExit ?? false;

  /// True while a focus session is running.
  bool get focusActive =>
      focusActiveUntil > DateTime.now().millisecondsSinceEpoch;

  /// Minutes left in the running focus session, 0 when idle.
  int get focusMinutesLeft {
    final remaining = focusActiveUntil - DateTime.now().millisecondsSinceEpoch;
    if (remaining <= 0) return 0;
    return (remaining / 60000).ceil();
  }

  Future<void> addWhitelistedApp(String package) async {
    await _filters?.addWhitelisted(package);
    await _filters?.pushToNative();
    notifyListeners();
  }

  Future<void> removeWhitelistedApp(String package) async {
    await _filters?.removeWhitelisted(package);
    await _filters?.pushToNative();
    notifyListeners();
  }

  /// Starts a focus session that locks every app that is not allowed.
  Future<void> startFocusSession({
    required Duration duration,
    List<String> allowedApps = const [],
  }) async {
    final until = DateTime.now().add(duration).millisecondsSinceEpoch;
    await _filters?.startFocus(until: until, allowedApps: allowedApps);
    await _filters?.pushToNative();
  }

  Future<void> stopFocusSession() async {
    await _filters?.stopFocus();
    await _filters?.pushToNative();
    notifyListeners();
  }

  Future<void> setFocusAllowedApps(List<String> packages) async {
    await _filters?.setFocusAllowedApps(packages);
    await _filters?.pushToNative();
    notifyListeners();
  }

  Future<void> setFocusPreventExit(bool value) async {
    await _filters?.setFocusPreventExit(value);
    await _filters?.pushToNative();
    notifyListeners();
  }

  /// Stores the long sentence that guards the destructive switches.
  Future<void> setLongSentencePassword(String value) async {
    await _filters?.setLongSentencePassword(value.trim());
    await _filters?.pushToNative();
    notifyListeners();
  }

  /// Image and video search result pages are blocked only while this is on.
  bool get blockImageSearch => _filters?.blockImageSearch ?? true;

  Future<void> setAdvanced({
    bool? blockNewApps,
    bool? blockNewBrowsers,
    bool? blockUnsupportedBrowsers,
    bool? dailyAffirmations,
    bool? blockSplitScreen,
    bool? blockIncognito,
    bool? blockInAppBrowsers,
    bool? crossBlockLimit,
    bool? blockImageSearch,
    bool? guardSettings,
  }) async {
    await _filters?.setAdvanced(
      blockNewApps: blockNewApps,
      blockNewBrowsers: blockNewBrowsers,
      blockUnsupportedBrowsers: blockUnsupportedBrowsers,
      dailyAffirmations: dailyAffirmations,
      blockSplitScreen: blockSplitScreen,
      blockIncognito: blockIncognito,
      blockInAppBrowsers: blockInAppBrowsers,
      crossBlockLimit: crossBlockLimit,
      blockImageSearch: blockImageSearch,
      guardSettings: guardSettings,
    );
    await _filters?.pushToNative();
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Dashboard state
  // ---------------------------------------------------------------------

  /// Damage-free days in a row, counting back from today. A block today means
  /// the streak starts at zero, which is the honest reading.
  int get currentStreak {
    final events = recentEvents;
    // No history at all means no streak yet; counting back from an empty log
    // would claim a 365-day streak on the first launch.
    if (events.isEmpty) return 0;
    var streak = 0;
    for (var offset = 0; offset < 365; offset++) {
      final key = BlurEventStore.dayKeyOf(
        DateTime.now().subtract(Duration(days: offset)),
      );
      if (events.any((event) => event.dayKey == key)) break;
      streak++;
    }
    return streak;
  }

  /// Seven booleans, oldest first: true when that day recorded no block.
  List<bool> get weekEventFree {
    final events = recentEvents;
    // No history yet: no day can claim to be clean.
    if (events.isEmpty) return List<bool>.filled(7, false);
    return List<bool>.generate(7, (index) {
      final day = DateTime.now().subtract(Duration(days: 6 - index));
      final key = BlurEventStore.dayKeyOf(day);
      return !events.any((event) => event.dayKey == key);
    });
  }

  /// Off / Normal / Strict, the three modes the dashboard exposes.
  ProtectionMode get mode {
    if (!enabled) return ProtectionMode.off;
    return sensitivity >= 9 ? ProtectionMode.strict : ProtectionMode.normal;
  }

  Future<void> setMode(ProtectionMode mode) async {
    switch (mode) {
      case ProtectionMode.off:
        await setEnabled(false);
      case ProtectionMode.normal:
        await setSensitivity(5);
        if (!enabled) await setEnabled(true);
      case ProtectionMode.strict:
        await setSensitivity(10);
        if (!enabled) await setEnabled(true);
    }
  }

  // ---------------------------------------------------------------------
  // Bypass watchdog
  // ---------------------------------------------------------------------

  /// Starts the periodic "is protection still real?" check.
  ///
  /// Called from `main()` only, so widget tests never leave a pending timer.
  /// It can only *notice* and re-prompt: Android gives no app the ability to
  /// prevent a force-stop, safe-mode boot or notification-permission denial.
  void startWatchdog({Duration interval = const Duration(seconds: 60)}) {
    if (!nativeBridge.isSupported) return;
    _watchdog?.cancel();
    _watchdog = Timer.periodic(interval, (_) => _checkProtectionStillOn());
  }

  void stopWatchdog() {
    _watchdog?.cancel();
    _watchdog = null;
  }

  Future<void> _checkProtectionStillOn() async {
    final settings = _settings;
    if (settings == null) return;
    final status = await nativeBridge.status();
    if (!status.supported) return;
    _status = status;
    notifyListeners();
    if (!status.protectionEnabled) {
      _lastWatchdogNotice = null;
      return;
    }
    if (status.accessibilityEnabled && status.serviceConnected) {
      _lastWatchdogNotice = null;
      return;
    }
    final now = DateTime.now();
    final last = _lastWatchdogNotice;
    if (last != null && now.difference(last) < const Duration(minutes: 10)) {
      return;
    }
    _lastWatchdogNotice = now;
    await nativeBridge.notifyProtectionOff();
    await settings.addAlert(
      status.accessibilityEnabled
          ? 'Protection is on but the service is not connected'
          : 'Accessibility permission was turned off',
    );
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Accountability settings
  // ---------------------------------------------------------------------

  Future<void> setPartner(PartnerContact partner) async {
    await _settings?.setPartner(partner);
    await _settings?.addAlert(
      partner.isEmpty
          ? 'Accountability partner cleared'
          : 'Accountability partner set to ${partner.displayName}',
    );
    notifyListeners();
  }

  Future<void> setAlerts(AlertPreferences alerts) async {
    await _settings?.setAlerts(alerts);
    notifyListeners();
  }

  Future<void> addAlert(String message) async {
    await _settings?.addAlert(message);
    notifyListeners();
  }

  Future<void> clearAlertLog() async {
    await _settings?.clearAlertLog();
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // History
  // ---------------------------------------------------------------------

  List<BlurEvent> get recentEvents => _store?.events ?? const [];

  int get todayCount => _store?.countToday(DateTime.now()) ?? 0;

  int get totalCount => _store?.total ?? 0;

  Map<String, int> get countsByApp => _store?.countsByApp() ?? const {};

  List<int> countsForLastDays(int days) =>
      _store?.countsForLastDays(days, DateTime.now()) ?? List.filled(days, 0);

  /// Records a blur produced by in-app analysis (the system-wide service
  /// records its own events natively).
  Future<void> recordBlur({
    required String packageName,
    required String reason,
    required double confidence,
  }) async {
    await _store?.add(BlurEvent(
      timestamp: DateTime.now(),
      packageName: packageName,
      reason: reason,
      confidence: confidence,
    ));
    notifyListeners();
  }

  String exportJson() => _store?.exportJson() ?? '{"events": []}';

  Future<void> clearHistory() async {
    await _store?.clear();
    notifyListeners();
  }

  /// Re-seeds the shipped blocklists and drops the user's own sites,
  /// keywords and schedules, then hands the result to the service.
  Future<void> resetFilters() async {
    await _filters?.clearAll();
    await _filters?.ensureSeeded();
    await _filters?.pushToNative();
    notifyListeners();
  }

  /// The user's own affirmations, stored on this device.
  List<String> get customAffirmations =>
      _settings?.customAffirmations ?? const [];

  Future<void> addAffirmation(String text) async {
    await _settings?.addAffirmation(text);
    notifyListeners();
  }

  Future<void> removeAffirmation(String text) async {
    await _settings?.removeAffirmation(text);
    notifyListeners();
  }

  /// Minute of day after which Basirah opens on its affirmations.
  int get affirmationLockMinute => _settings?.affirmationLockMinute ?? 360;

  Future<void> setAffirmationLockMinute(int minute) async {
    await _settings?.setAffirmationLockMinute(minute);
    notifyListeners();
  }

  /// True when the morning gate is on, its time has passed today and it has
  /// not been passed yet. Only this app is gated: a third-party app cannot
  /// lock the whole phone without device-owner privileges.
  bool get needsMorningAffirmations {
    if (!dailyAffirmations) return false;
    final now = DateTime.now();
    if (now.hour * 60 + now.minute < affirmationLockMinute) return false;
    return (_settings?.affirmationDoneDay ?? '') != _dayKey(now);
  }

  /// Marks today's gate as passed; it appears again tomorrow.
  Future<void> completeMorningAffirmations() async {
    await _settings?.markAffirmationsDone(_dayKey(DateTime.now()));
    notifyListeners();
  }

  static String _dayKey(DateTime time) =>
      '${time.year}-${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')}';

  /// Clears history plus every stored preference.
  Future<void> clearEverything() async {
    await _store?.clear();
    await _settings?.clearAll();
    await _filters?.clearAll();
    await _filters?.pushToNative();
    await nativeBridge.setEnabled(false);
    notifyListeners();
  }
}

/// Three-state protection level shown on the dashboard.
enum ProtectionMode {
  off('Off'),
  normal('Normal'),
  strict('Strict');

  const ProtectionMode(this.label);
  final String label;
}

final blurEngine = BlurEngine();
