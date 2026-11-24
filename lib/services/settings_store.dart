import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../src/policy.dart';

/// Local accountability contact. No data leaves the device; the app has no
/// messaging backend by design.
class PartnerContact {
  final String name;
  final String email;
  final String phone;

  const PartnerContact({this.name = '', this.email = '', this.phone = ''});

  bool get isEmpty => name.isEmpty && email.isEmpty && phone.isEmpty;

  String get displayName => name.isEmpty ? 'No partner set' : name;

  Map<String, dynamic> toJson() =>
      {'name': name, 'email': email, 'phone': phone};

  factory PartnerContact.fromJson(Map<String, dynamic> json) => PartnerContact(
        name: (json['name'] as String?) ?? '',
        email: (json['email'] as String?) ?? '',
        phone: (json['phone'] as String?) ?? '',
      );
}

/// Which events should be surfaced to the accountability partner.
class AlertPreferences {
  final bool explicitContent;
  final bool bypassAttempts;
  final bool protectionDisabled;

  const AlertPreferences({
    this.explicitContent = true,
    this.bypassAttempts = true,
    this.protectionDisabled = false,
  });

  AlertPreferences copyWith({
    bool? explicitContent,
    bool? bypassAttempts,
    bool? protectionDisabled,
  }) {
    return AlertPreferences(
      explicitContent: explicitContent ?? this.explicitContent,
      bypassAttempts: bypassAttempts ?? this.bypassAttempts,
      protectionDisabled: protectionDisabled ?? this.protectionDisabled,
    );
  }
}

/// One entry in the on-device accountability log.
class AlertLogEntry {
  final DateTime timestamp;
  final String message;

  const AlertLogEntry({required this.timestamp, required this.message});

  Map<String, dynamic> toJson() =>
      {'timestamp': timestamp.toIso8601String(), 'message': message};

  factory AlertLogEntry.fromJson(Map<String, dynamic> json) => AlertLogEntry(
        timestamp: DateTime.parse(json['timestamp'] as String),
        message: (json['message'] as String?) ?? '',
      );

  String get timeLabel =>
      '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-'
      '${timestamp.day.toString().padLeft(2, '0')} '
      '${timestamp.hour.toString().padLeft(2, '0')}:'
      '${timestamp.minute.toString().padLeft(2, '0')}';
}

/// All user preferences that are not detection events.
class SettingsStore {
  static const _sensitivityKey = 'settings_sensitivity';
  static const _customExclusionsKey = 'settings_custom_exclusions';
  static const _partnerKey = 'settings_partner';
  static const _alertsKey = 'settings_alerts';
  static const _alertLogKey = 'settings_alert_log';
  static const _protectionKey = 'settings_protection_enabled';
  static const _blurStrengthKey = 'settings_blur_strength';
  static const _debugOverlayKey = 'settings_debug_overlay';
  static const _affirmationsKey = 'settings_affirmations';
  static const _affirmationLockKey = 'settings_affirmation_lock_minute';
  static const _affirmationDoneKey = 'settings_affirmation_done_day';
  static const _maxAlertLog = 100;

  /// Apps that are never blurred. Mirrors the defaults in
  /// `SystemWideBlurService.EXCLUSION_LIST`; keep both in sync.
  static const defaultExclusions = <String>[
    'com.android.camera',
    'com.sec.android.app.camera',
    'com.google.android.apps.photos',
    'com.whatsapp',
    'org.thoughtcrime.securesms',
  ];

  final SharedPreferences _prefs;

  SettingsStore(this._prefs);

  int get sensitivity => (_prefs.getInt(_sensitivityKey) ?? 5).clamp(1, 10);

  Future<void> setSensitivity(int value) =>
      _prefs.setInt(_sensitivityKey, value.clamp(1, 10));

  BlurStrength get blurStrength {
    final raw = _prefs.getString(_blurStrengthKey);
    return BlurStrength.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => BlurStrength.strong,
    );
  }

  Future<void> setBlurStrength(BlurStrength strength) =>
      _prefs.setString(_blurStrengthKey, strength.name);

  /// On-screen capture HUD (NSFW score, skin ratio, decision). On by default:
  /// thresholds cannot be tuned without seeing what the engine measures.
  bool get debugOverlayEnabled => _prefs.getBool(_debugOverlayKey) ?? true;

  Future<void> setDebugOverlay(bool value) =>
      _prefs.setBool(_debugOverlayKey, value);

  bool get protectionEnabled => _prefs.getBool(_protectionKey) ?? false;

  Future<void> setProtectionEnabled(bool value) =>
      _prefs.setBool(_protectionKey, value);

  List<String> get customExclusions =>
      List<String>.unmodifiable(_prefs.getStringList(_customExclusionsKey) ?? const []);

  Future<void> setCustomExclusions(List<String> packages) async {
    final cleaned = packages
        .map((p) => p.trim())
        .where((p) => p.contains('.') && p.length > 2)
        .toSet()
        .toList()
      ..sort();
    await _prefs.setStringList(_customExclusionsKey, cleaned);
  }

  PartnerContact get partner {
    final raw = _prefs.getString(_partnerKey);
    if (raw == null) return const PartnerContact();
    try {
      return PartnerContact.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const PartnerContact();
    }
  }

  Future<void> setPartner(PartnerContact contact) =>
      _prefs.setString(_partnerKey, jsonEncode(contact.toJson()));

  AlertPreferences get alerts {
    final raw = _prefs.getString(_alertsKey);
    if (raw == null) return const AlertPreferences();
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return AlertPreferences(
        explicitContent: (json['explicit'] as bool?) ?? true,
        bypassAttempts: (json['bypass'] as bool?) ?? true,
        protectionDisabled: (json['disabled'] as bool?) ?? false,
      );
    } catch (_) {
      return const AlertPreferences();
    }
  }

  Future<void> setAlerts(AlertPreferences alerts) => _prefs.setString(
        _alertsKey,
        jsonEncode({
          'explicit': alerts.explicitContent,
          'bypass': alerts.bypassAttempts,
          'disabled': alerts.protectionDisabled,
        }),
      );

  List<AlertLogEntry> get alertLog {
    final raw = _prefs.getStringList(_alertLogKey) ?? const [];
    final entries = <AlertLogEntry>[];
    for (final line in raw) {
      try {
        entries
            .add(AlertLogEntry.fromJson(jsonDecode(line) as Map<String, dynamic>));
      } catch (_) {
        // Ignore corrupt entries.
      }
    }
    return entries;
  }

  Future<void> addAlert(String message) async {
    final entries = [AlertLogEntry(timestamp: DateTime.now(), message: message)];
    entries.addAll(alertLog.take(_maxAlertLog - 1));
    await _prefs.setStringList(
      _alertLogKey,
      entries.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  /// Affirmations the user wrote themselves. Shown after the built-in ones
  /// and kept on the device only.
  List<String> get customAffirmations =>
      List<String>.unmodifiable(_prefs.getStringList(_affirmationsKey) ?? const []);

  Future<void> addAffirmation(String text) async {
    final value = text.trim();
    if (value.length < 4) return;
    if (customAffirmations.contains(value)) return;
    await _prefs.setStringList(_affirmationsKey, [...customAffirmations, value]);
  }

  Future<void> removeAffirmation(String text) async {
    await _prefs.setStringList(
      _affirmationsKey,
      customAffirmations.where((a) => a != text).toList(),
    );
  }

  /// Minute of the day after which the morning gate appears. Default 06:00.
  int get affirmationLockMinute =>
      (_prefs.getInt(_affirmationLockKey) ?? 6 * 60).clamp(0, 1439);

  Future<void> setAffirmationLockMinute(int minute) =>
      _prefs.setInt(_affirmationLockKey, minute.clamp(0, 1439));

  /// Day key (`2026-11-16`) on which the gate was last passed.
  String get affirmationDoneDay => _prefs.getString(_affirmationDoneKey) ?? '';

  Future<void> markAffirmationsDone(String day) =>
      _prefs.setString(_affirmationDoneKey, day);

  Future<void> clearAlertLog() => _prefs.remove(_alertLogKey);

  /// Clears every preference this store owns, including detection history.
  Future<void> clearAll() async {
    await _prefs.remove(_sensitivityKey);
    await _prefs.remove(_customExclusionsKey);
    await _prefs.remove(_partnerKey);
    await _prefs.remove(_alertsKey);
    await _prefs.remove(_protectionKey);
    await _prefs.remove(_alertLogKey);
    await _prefs.remove(_blurStrengthKey);
    await _prefs.remove(_debugOverlayKey);
    await _prefs.remove(_affirmationsKey);
    await _prefs.remove(_affirmationLockKey);
    await _prefs.remove(_affirmationDoneKey);
  }
}
