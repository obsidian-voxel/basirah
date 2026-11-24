import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../src/block_rules.dart';
import 'native_bridge.dart';

/// Persists the non-visual blocklists (apps, keywords, schedules, daily
/// limits) and pushes them to the accessibility service.
///
/// The service is the enforcer — it must keep blocking even when this Flutter
/// engine is gone — so every mutation here ends with a channel push. Defaults
/// are seeded on first launch so a fresh install is already protected.
class FilterStore {
  static const _appsKey = 'filter_blocked_apps';
  static const _keywordsKey = 'filter_blocked_keywords';
  static const _domainsKey = 'filter_blocked_domains';
  static const _urlPatternsKey = 'filter_blocked_url_patterns';
  static const _imageSearchPatternsKey = 'filter_image_search_patterns';
  static const _blockImageSearchKey = 'advanced_block_image_search';
  static const _customDomainsKey = 'filter_custom_domains';
  static const _schedulesKey = 'filter_schedules';
  static const _limitsKey = 'filter_daily_limits';
  static const _blockNewAppsKey = 'advanced_block_new_apps';
  static const _blockNewBrowsersKey = 'advanced_block_new_browsers';
  static const _blockUnsupportedBrowsersKey = 'advanced_block_unsupported_browsers';
  static const _dailyAffirmationsKey = 'advanced_daily_affirmations';
  static const _whitelistKey = 'filter_whitelisted_apps';
  static const _focusUntilKey = 'focus_active_until';
  static const _focusAllowedKey = 'focus_allowed_apps';
  static const _focusPreventExitKey = 'focus_prevent_exit';
  static const _blockSplitScreenKey = 'advanced_block_split_screen';
  static const _blockIncognitoKey = 'advanced_block_incognito';
  static const _blockInAppBrowsersKey = 'advanced_block_inapp_browsers';
  static const _crossBlockLimitKey = 'advanced_cross_block_limit';
  static const _blockScreenTitleKey = 'block_screen_title';
  static const _blockScreenMessageKey = 'block_screen_message';
  static const _passwordKey = 'advanced_long_sentence_password';
  static const _allowlistedDomainsKey = 'filter_allowlisted_domains';
  static const _wholeWordKeywordsKey = 'filter_blocked_keywords_wholeword';
  static const _inAppBrowserAppsKey = 'advanced_inapp_browser_apps';
  static const _guardSettingsKey = 'advanced_guard_settings';
  static const _prayerEnabledKey = 'advanced_prayer_blocking';
  static const _prayerLatitudeKey = 'prayer_latitude';
  static const _prayerLongitudeKey = 'prayer_longitude';
  static const _prayerMinutesKey = 'prayer_minutes_after';
  static const _prayerMethodKey = 'prayer_method';

  /// The full bundled adult-domain list: a sorted hash index read by the
  /// native service (`AdultDomainIndex`), never loaded into Dart.
  static const domainsAsset = 'assets/blocklists/adult_domains.idx';

  /// Bundled adult URL patterns (`*` wildcards).
  static const urlPatternsAsset = 'assets/blocklists/adult_url_patterns.txt';

  /// Image and video search result pages, used only while [blockImageSearch].
  static const imageSearchAsset = 'assets/blocklists/search_image_patterns.txt';

  final SharedPreferences _prefs;

  FilterStore(this._prefs);

  /// Blocked packages: the seeded defaults until the user edits them.
  List<String> get blockedApps =>
      List<String>.unmodifiable(_prefs.getStringList(_appsKey) ?? DefaultBlocklists.apps);

  /// Blocked keywords: the seeded porn pack until the user edits them.
  List<String> get keywords =>
      List<String>.unmodifiable(_prefs.getStringList(_keywordsKey) ?? DefaultBlocklists.keywords);

  Map<String, ScheduleWindow> get schedules {
    final raw = _prefs.getString(_schedulesKey);
    if (raw == null) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final out = <String, ScheduleWindow>{};
      decoded.forEach((key, value) {
        final window = ScheduleWindow.fromJson(value);
        if (window != null && key is String) out[key] = window;
      });
      return out;
    } catch (_) {
      return const {};
    }
  }

  Map<String, int> get dailyLimits {
    final raw = _prefs.getString(_limitsKey);
    if (raw == null) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is num)
            entry.key as String: (entry.value as num).toInt(),
      };
    } catch (_) {
      return const {};
    }
  }

  /// Bundled adult URL patterns, matched against the URL only: search
  /// queries (`*q=*porn*`) and hosts a suffix list cannot cover (`*.xxx`).
  List<String> get urlPatterns =>
      List<String>.unmodifiable(_prefs.getStringList(_urlPatternsKey) ?? const []);

  /// Image and video search result grids are blocked only while this is on
  /// (Advanced Settings → Blocking). On by default: explicit thumbnails are
  /// exactly what a search for a term turns up.
  bool get blockImageSearch => _prefs.getBool(_blockImageSearchKey) ?? true;

  /// Bundled image/video search patterns, matched against the URL only.
  List<String> get imageSearchPatterns => List<String>.unmodifiable(
      _prefs.getStringList(_imageSearchPatternsKey) ?? const [],
    );

  /// Sites the user added themselves. Matched against the URL as a host
  /// suffix, so `de.pornhub.com` is covered by `pornhub.com`.
  List<String> get customDomains =>
      List<String>.unmodifiable(_prefs.getStringList(_customDomainsKey) ?? const []);

  Future<void> addDomain(String domain) async {
    final value = domain.trim().toLowerCase();
    if (!value.contains('.')) return;
    if (customDomains.contains(value)) return;
    await _prefs.setStringList(_customDomainsKey, [...customDomains, value]);
  }

  Future<void> removeDomain(String domain) async {
    await _prefs.setStringList(
      _customDomainsKey,
      customDomains.where((d) => d != domain).toList(),
    );
  }

  /// Sites the user trusts. Checked before the bundled 952k-domain index and
  /// before the URL patterns, because neither can express an exception.
  List<String> get allowlistedDomains =>
      List<String>.unmodifiable(_prefs.getStringList(_allowlistedDomainsKey) ?? const []);

  Future<void> addAllowlistedDomain(String domain) async {
    final value = HostNormalization.canonical(domain);
    if (value == null || allowlistedDomains.contains(value)) return;
    await _prefs.setStringList(
      _allowlistedDomainsKey,
      [...allowlistedDomains, value],
    );
  }

  Future<void> removeAllowlistedDomain(String domain) async {
    await _prefs.setStringList(
      _allowlistedDomainsKey,
      allowlistedDomains.where((d) => d != domain).toList(),
    );
  }

  /// Keywords matched only as whole words. `porn` here does not match
  /// `pornhub`; a wildcard entry keeps substring semantics.
  List<String> get wholeWordKeywords =>
      List<String>.unmodifiable(_prefs.getStringList(_wholeWordKeywordsKey) ?? const []);

  Future<void> addWholeWordKeyword(String keyword) async {
    final value = keyword.trim().toLowerCase();
    if (!KeywordValidation.isValid(value) || wholeWordKeywords.contains(value)) {
      return;
    }
    await _prefs.setStringList(_wholeWordKeywordsKey, [...wholeWordKeywords, value]);
  }

  Future<void> removeWholeWordKeyword(String keyword) async {
    await _prefs.setStringList(
      _wholeWordKeywordsKey,
      wholeWordKeywords.where((k) => k != keyword).toList(),
    );
  }

  /// Apps where the in-app browser rule applies; empty means every app.
  List<String> get inAppBrowserApps =>
      List<String>.unmodifiable(_prefs.getStringList(_inAppBrowserAppsKey) ?? const []);

  Future<void> setInAppBrowserApps(List<String> packages) =>
      _prefs.setStringList(_inAppBrowserAppsKey, packages);

  /// Leave Android Settings screens that could switch protection off.
  bool get guardSettings => _prefs.getBool(_guardSettingsKey) ?? true;

  bool get prayerBlocking => _prefs.getBool(_prayerEnabledKey) ?? false;

  double? get prayerLatitude => _prefs.getDouble(_prayerLatitudeKey);

  double? get prayerLongitude => _prefs.getDouble(_prayerLongitudeKey);

  int get prayerMinutesAfter => _prefs.getInt(_prayerMinutesKey) ?? 15;

  String get prayerMethod => _prefs.getString(_prayerMethodKey) ?? 'MuslimWorldLeague';

  bool get blockNewApps => _prefs.getBool(_blockNewAppsKey) ?? true;

  bool get blockNewBrowsers => _prefs.getBool(_blockNewBrowsersKey) ?? false;

  bool get blockUnsupportedBrowsers =>
      _prefs.getBool(_blockUnsupportedBrowsersKey) ?? true;

  bool get dailyAffirmations => _prefs.getBool(_dailyAffirmationsKey) ?? false;

  /// Apps the user explicitly allows even while a focus session runs.
  List<String> get whitelistedApps =>
      List<String>.unmodifiable(_prefs.getStringList(_whitelistKey) ?? const []);

  /// Epoch milliseconds until which focus mode is active, 0 when idle.
  int get focusActiveUntil => _prefs.getInt(_focusUntilKey) ?? 0;

  /// Apps that stay reachable during a focus session.
  List<String> get focusAllowedApps =>
      List<String>.unmodifiable(_prefs.getStringList(_focusAllowedKey) ?? const []);

  /// When on, a focus session cannot be ended early.
  bool get focusPreventExit => _prefs.getBool(_focusPreventExitKey) ?? false;

  /// Block the app when the device enters split screen.
  bool get blockSplitScreen => _prefs.getBool(_blockSplitScreenKey) ?? false;

  /// Block browsers that are in a private/incognito window.
  bool get blockIncognito => _prefs.getBool(_blockIncognitoKey) ?? false;

  /// Block embedded (in-app) browsers, which bypass the app blocklist's URL
  /// checks by opening pages inside social apps.
  bool get blockInAppBrowsers =>
      _prefs.getBool(_blockInAppBrowsersKey) ?? false;

  /// Keep the block screen up for five minutes after five attempts at the
  /// same target inside two minutes.
  bool get crossBlockLimit => _prefs.getBool(_crossBlockLimitKey) ?? true;

  /// User copy shown on the native block screen; empty means the default.
  String get blockScreenTitle => _prefs.getString(_blockScreenTitleKey) ?? '';
  String get blockScreenMessage =>
      _prefs.getString(_blockScreenMessageKey) ?? '';

  Future<void> setBlockScreen({String? title, String? message}) async {
    if (title != null) {
      if (title.trim().isEmpty) {
        await _prefs.remove(_blockScreenTitleKey);
      } else {
        await _prefs.setString(_blockScreenTitleKey, title.trim());
      }
    }
    if (message != null) {
      if (message.trim().isEmpty) {
        await _prefs.remove(_blockScreenMessageKey);
      } else {
        await _prefs.setString(_blockScreenMessageKey, message.trim());
      }
    }
  }

  /// The long sentence the user must type before a guard can be turned off.
  String get longSentencePassword =>
      _prefs.getString(_passwordKey) ?? '';

  bool get hasLongSentencePassword => longSentencePassword.isNotEmpty;

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
    if (blockNewApps != null) {
      await _prefs.setBool(_blockNewAppsKey, blockNewApps);
    }
    if (blockNewBrowsers != null) {
      await _prefs.setBool(_blockNewBrowsersKey, blockNewBrowsers);
    }
    if (blockUnsupportedBrowsers != null) {
      await _prefs.setBool(_blockUnsupportedBrowsersKey, blockUnsupportedBrowsers);
    }
    if (dailyAffirmations != null) {
      await _prefs.setBool(_dailyAffirmationsKey, dailyAffirmations);
    }
    if (blockSplitScreen != null) {
      await _prefs.setBool(_blockSplitScreenKey, blockSplitScreen);
    }
    if (blockIncognito != null) {
      await _prefs.setBool(_blockIncognitoKey, blockIncognito);
    }
    if (blockInAppBrowsers != null) {
      await _prefs.setBool(_blockInAppBrowsersKey, blockInAppBrowsers);
    }
    if (crossBlockLimit != null) {
      await _prefs.setBool(_crossBlockLimitKey, crossBlockLimit);
    }
    if (blockImageSearch != null) {
      await _prefs.setBool(_blockImageSearchKey, blockImageSearch);
    }
    if (guardSettings != null) {
      await _prefs.setBool(_guardSettingsKey, guardSettings);
    }
  }

  Future<void> setPrayerPolicy({
    required bool enabled,
    required double? latitude,
    required double? longitude,
    required int minutesAfter,
    required String method,
  }) async {
    await _prefs.setBool(_prayerEnabledKey, enabled);
    if (latitude != null) await _prefs.setDouble(_prayerLatitudeKey, latitude);
    if (longitude != null) {
      await _prefs.setDouble(_prayerLongitudeKey, longitude);
    }
    await _prefs.setInt(_prayerMinutesKey, minutesAfter.clamp(1, 120));
    await _prefs.setString(_prayerMethodKey, method);
  }

  Future<void> setWhitelist(List<String> packages) =>
      _prefs.setStringList(_whitelistKey, packages);

  Future<void> addWhitelisted(String package) async {
    if (whitelistedApps.contains(package)) return;
    await setWhitelist([...whitelistedApps, package]);
  }

  Future<void> removeWhitelisted(String package) async {
    await setWhitelist(
      whitelistedApps.where((p) => p != package).toList(),
    );
  }

  /// Starts a focus session that runs until [until] (epoch milliseconds).
  Future<void> startFocus({
    required int until,
    required List<String> allowedApps,
  }) async {
    await _prefs.setInt(_focusUntilKey, until);
    await _prefs.setStringList(_focusAllowedKey, allowedApps);
  }

  Future<void> stopFocus() async {
    await _prefs.setInt(_focusUntilKey, 0);
    await _prefs.setStringList(_focusAllowedKey, const []);
  }

  Future<void> setFocusAllowedApps(List<String> packages) =>
      _prefs.setStringList(_focusAllowedKey, packages);

  Future<void> setFocusPreventExit(bool value) =>
      _prefs.setBool(_focusPreventExitKey, value);

  Future<void> setLongSentencePassword(String value) async {
    if (value.isEmpty) {
      await _prefs.remove(_passwordKey);
    } else {
      await _prefs.setString(_passwordKey, value);
    }
  }

  bool get hasSchedules => schedules.isNotEmpty;

  bool get hasLimits => dailyLimits.isNotEmpty;

  Future<void> ensureSeeded() async {
    if (_prefs.getStringList(_appsKey) == null) {
      await _prefs.setStringList(_appsKey, List.of(DefaultBlocklists.apps));
    }
    if (_prefs.getStringList(_keywordsKey) == null) {
      await _prefs.setStringList(_keywordsKey, List.of(DefaultBlocklists.keywords));
    }
    await _syncBundledList(urlPatternsAsset, _urlPatternsKey);
    await _syncBundledList(imageSearchAsset, _imageSearchPatternsKey);
    // Earlier builds pushed a 4k-domain sample through preferences; the full
    // list is the native index now, so the stale copy is dropped.
    await _prefs.remove(_domainsKey);
  }

  /// Reads a bundled list into [key] when the bundle holds entries the stored
  /// copy does not, so a first launch and an update that ships a longer list
  /// both end up protected. Failure is non-fatal: keyword blocking still works.
  Future<void> _syncBundledList(String asset, String key) async {
    try {
      final raw = await rootBundle.loadString(asset);
      final entries = raw
          .split('\n')
          .map((line) => line.trim().toLowerCase())
          .where((line) => line.isNotEmpty && !line.startsWith('#'))
          .toSet()
          .toList();
      if (entries.isEmpty) return;
      final stored = _prefs.getStringList(key);
      if (stored != null && stored.length >= entries.length) return;
      await _prefs.setStringList(key, entries);
    } catch (_) {
      // Assets unavailable (e.g. a stripped build): keep the app running.
    }
  }

  Future<void> addApp(String package) =>
      _setApps([...blockedApps, package]);

  Future<void> removeApp(String package) =>
      _setApps(blockedApps.where((p) => p != package).toList());

  Future<void> _setApps(List<String> packages) async {
    final cleaned = packages
        .map((p) => p.trim())
        .where((p) => p.contains('.') && p.length > 3)
        .toSet()
        .toList()
      ..sort();
    await _prefs.setStringList(_appsKey, cleaned);
  }

  Future<void> addKeyword(String keyword) async {
    if (!KeywordValidation.isValid(keyword)) return;
    await _setKeywords([...keywords, keyword]);
  }

  Future<void> removeKeyword(String keyword) async {
    final lower = keyword.toLowerCase();
    await _setKeywords(
      keywords.where((k) => k.toLowerCase() != lower).toList(),
    );
  }

  Future<void> addPreset(KeywordPreset preset) =>
      _setKeywords([...keywords, ...preset.keywords]);

  Future<void> _setKeywords(List<String> keywords) async {
    // Keep the user's order but drop blanks/duplicates case-insensitively.
    final seen = <String>{};
    final out = <String>[];
    for (final raw in keywords) {
      final keyword = raw.trim().toLowerCase();
      if (!KeywordValidation.isValid(keyword)) continue;
      if (!seen.add(keyword)) continue;
      out.add(keyword);
    }
    await _prefs.setStringList(_keywordsKey, out);
  }

  Future<void> setSchedule(String package, ScheduleWindow? window) async {
    final next = {...schedules};
    if (window == null) {
      next.remove(package);
    } else {
      next[package] = window;
    }
    await _writeSchedules(next);
  }

  Future<void> setDailyLimit(String package, int minutes) async {
    final next = {...dailyLimits};
    if (minutes <= 0) {
      next.remove(package);
    } else {
      next[package] = minutes;
    }
    await _writeLimits(next);
  }

  Future<void> _writeSchedules(Map<String, ScheduleWindow> value) =>
      _prefs.setString(
        _schedulesKey,
        jsonEncode({
          for (final entry in value.entries) entry.key: entry.value.toJson(),
        }),
      );

  Future<void> _writeLimits(Map<String, int> value) =>
      _prefs.setString(_limitsKey, jsonEncode(value));

  /// Sends the whole effective configuration to Android. Called at startup and
  /// after every edit; the service never guesses what the UI shows.
  Future<void> pushToNative() async {
    await nativeBridge.setBlockedApps(blockedApps);
    // The bundled domain list is the native index; only your own sites travel
    // through the channel.
    await nativeBridge.setBlockedDomains(customDomains);
    await nativeBridge.setAllowlistedDomains(allowlistedDomains);
    await nativeBridge.setBlockedUrlPatterns([
      ...urlPatterns,
      if (blockImageSearch) ...imageSearchPatterns,
    ]);
    await nativeBridge.setKeywordBlocklist(keywords);
    await nativeBridge.setWholeWordKeywords(wholeWordKeywords);
    await nativeBridge.setInAppBrowserApps(inAppBrowserApps);
    await nativeBridge.setPrayerPolicy(
      enabled: prayerBlocking,
      latitude: prayerLatitude,
      longitude: prayerLongitude,
      minutesAfter: prayerMinutesAfter,
      method: prayerMethod,
    );
    await nativeBridge.setAdvancedPolicy(
      blockNewApps: blockNewApps,
      blockNewBrowsers: blockNewBrowsers,
      blockUnsupportedBrowsers: blockUnsupportedBrowsers,
      dailyAffirmations: dailyAffirmations,
      blockSplitScreen: blockSplitScreen,
      blockIncognito: blockIncognito,
      blockInAppBrowsers: blockInAppBrowsers,
      crossBlockLimit: crossBlockLimit,
    );
    await nativeBridge.setBlockScreen(
      title: blockScreenTitle,
      message: blockScreenMessage,
    );
    await nativeBridge.setAppSchedules({
      for (final entry in schedules.entries)
        entry.key: [entry.value.startMinute, entry.value.endMinute],
    });
    await nativeBridge.setDailyLimits(dailyLimits);
    await nativeBridge.setWhitelistedApps(whitelistedApps);
    await nativeBridge.setFocusState(
      activeUntil: focusActiveUntil,
      allowedApps: focusAllowedApps,
      preventExit: focusPreventExit,
    );
  }

  Future<void> clearAll() async {
    await _prefs.remove(_appsKey);
    await _prefs.remove(_keywordsKey);
    await _prefs.remove(_schedulesKey);
    await _prefs.remove(_limitsKey);
    await _prefs.remove(_domainsKey);
    await _prefs.remove(_urlPatternsKey);
    await _prefs.remove(_imageSearchPatternsKey);
    await _prefs.remove(_blockImageSearchKey);
    await _prefs.remove(_customDomainsKey);
    await _prefs.remove(_blockNewAppsKey);
    await _prefs.remove(_blockNewBrowsersKey);
    await _prefs.remove(_blockUnsupportedBrowsersKey);
    await _prefs.remove(_dailyAffirmationsKey);
    await _prefs.remove(_whitelistKey);
    await _prefs.remove(_focusUntilKey);
    await _prefs.remove(_focusAllowedKey);
    await _prefs.remove(_focusPreventExitKey);
    await _prefs.remove(_blockSplitScreenKey);
    await _prefs.remove(_blockIncognitoKey);
    await _prefs.remove(_blockInAppBrowsersKey);
    await _prefs.remove(_crossBlockLimitKey);
    await _prefs.remove(_blockScreenTitleKey);
    await _prefs.remove(_blockScreenMessageKey);
    await _prefs.remove(_passwordKey);
    await _prefs.remove(_allowlistedDomainsKey);
    await _prefs.remove(_wholeWordKeywordsKey);
    await _prefs.remove(_inAppBrowserAppsKey);
    await _prefs.remove(_guardSettingsKey);
    await _prefs.remove(_prayerEnabledKey);
    await _prefs.remove(_prayerLatitudeKey);
    await _prefs.remove(_prayerLongitudeKey);
    await _prefs.remove(_prayerMinutesKey);
    await _prefs.remove(_prayerMethodKey);
  }
}

/// Keyword validation shared by the store and the Settings form.
abstract final class KeywordValidation {
  static bool isValid(String keyword) {
    final trimmed = keyword.trim();
    if (trimmed.length < 2) return false;
    return RegExp(r'[a-z0-9]', caseSensitive: false).hasMatch(trimmed);
  }
}

/// Domain input cleaning for both block and allow lists.
abstract final class HostNormalization {
  /// `https://www.Example.com/path` → `example.com`; null when not a host.
  static String? canonical(String raw) {
    var value = normalizeHost(raw);
    value = value.replaceFirst(RegExp(r'^https?://'), '');
    value = value.split('/').first.split('?').first.split('#').first;
    if (value.startsWith('www.')) value = value.substring(4);
    if (!value.contains('.') || value.length < 4) return null;
    if (!RegExp(r'^[a-z0-9.-]+$').hasMatch(value)) return null;
    return value;
  }
}
