import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/blur_event.dart';

/// Snapshot of the native protection state, as reported by MainActivity.
@immutable
class NativeStatus {
  final bool supported;

  /// Whether the user has granted the Accessibility service in Android
  /// settings. Android does not allow an app to grant this itself.
  final bool accessibilityEnabled;

  /// Whether the accessibility service is currently bound and running.
  final bool serviceConnected;

  /// Whether the user switched protection on.
  final bool protectionEnabled;

  final bool deviceAdmin;
  final bool notificationsEnabled;
  final bool batteryOptimizationIgnored;
  final int sensitivity;
  final int todayBlurs;
  final int totalBlurs;
  final List<BlurEvent> recentEvents;

  const NativeStatus({
    required this.supported,
    this.accessibilityEnabled = false,
    this.serviceConnected = false,
    this.protectionEnabled = false,
    this.deviceAdmin = false,
    this.notificationsEnabled = true,
    this.batteryOptimizationIgnored = true,
    this.sensitivity = 5,
    this.todayBlurs = 0,
    this.totalBlurs = 0,
    this.recentEvents = const [],
  });

  /// Protection is only real when the user enabled it *and* Android has the
  /// service bound. The old UI reported "active" from a local bool alone.
  bool get isActive =>
      supported && protectionEnabled && accessibilityEnabled && serviceConnected;

  bool get needsAccessibility => supported && !accessibilityEnabled;

  static const unsupported = NativeStatus(supported: false);

  factory NativeStatus.fromMap(Map<dynamic, dynamic> map) {
    final rawEvents = map['events'];
    return NativeStatus(
      supported: true,
      accessibilityEnabled: map['accessibilityEnabled'] == true,
      serviceConnected: map['serviceConnected'] == true,
      protectionEnabled: map['protectionEnabled'] == true,
      deviceAdmin: map['deviceAdmin'] == true,
      notificationsEnabled: map['notificationsEnabled'] != false,
      batteryOptimizationIgnored: map['batteryOptimizationIgnored'] != false,
      sensitivity: (map['sensitivity'] as num?)?.toInt() ?? 5,
      todayBlurs: (map['todayBlurs'] as num?)?.toInt() ?? 0,
      totalBlurs: (map['totalBlurs'] as num?)?.toInt() ?? 0,
      recentEvents: rawEvents is List
          ? rawEvents
              .whereType<Map>()
              .map(BlurEvent.fromNative)
              .toList(growable: false)
          : const [],
    );
  }
}

/// One screenshot as the service logged it, plus the exact frame the pipeline
/// received (downscaled preview) and the decision that came out of Dart.
@immutable
class LiveCapture {
  final int width;
  final int height;
  final int rowPadding;
  final double gate;
  final double score;
  final double fullScore;
  final double exposed;
  final double coverage;
  final int persons;
  final int regions;
  final int elapsedMs;
  final String decision;
  final String packageName;
  final bool detectorReady;
  final String? detectorError;
  final Uint8List? preview;
  final String log;

  const LiveCapture({
    required this.width,
    required this.height,
    required this.rowPadding,
    required this.gate,
    required this.score,
    required this.fullScore,
    required this.exposed,
    required this.persons,
    required this.regions,
    required this.elapsedMs,
    required this.decision,
    required this.packageName,
    required this.detectorReady,
    required this.log,
    this.coverage = 0,
    this.detectorError,
    this.preview,
  });

  bool get isEmpty => width == 0 && height == 0;

  factory LiveCapture.fromMap(Map<dynamic, dynamic> map) {
    double number(String key) => (map[key] as num?)?.toDouble() ?? 0;
    int integer(String key) => (map[key] as num?)?.toInt() ?? 0;
    return LiveCapture(
      width: integer('w'),
      height: integer('h'),
      rowPadding: integer('rowPadding'),
      gate: number('gate'),
      score: number('score'),
      fullScore: number('fullScore'),
      exposed: number('exposed'),
      coverage: number('coverage'),
      persons: integer('persons'),
      regions: integer('regions'),
      elapsedMs: integer('ms'),
      decision: map['decision'] as String? ?? 'unknown',
      packageName: map['pkg'] as String? ?? '',
      detectorReady: map['detectorReady'] == true,
      detectorError: map['detectorError'] as String?,
      preview: map['preview'] is Uint8List ? map['preview'] as Uint8List : null,
      log: map['log'] as String? ?? '',
    );
  }
}

/// One installed launchable app, for the "choose apps" picker.
@immutable
class InstalledApp {
  final String label;
  final String packageName;

  const InstalledApp({required this.label, required this.packageName});

  factory InstalledApp.fromMap(Map<dynamic, dynamic> map) => InstalledApp(
        label: map['label'] as String? ?? '',
        packageName: map['package'] as String? ?? '',
      );

  /// Only used for validation and display when the label is missing.
  bool get isUsable => packageName.contains('.') && packageName.length > 3;
}

/// What the Activate intent resolves to, for the Settings self-test.
@immutable
class DeviceAdminCheck {
  final String action;
  final String component;
  final String? resolved;
  final String? exception;
  final bool active;

  const DeviceAdminCheck({
    required this.action,
    required this.component,
    required this.resolved,
    required this.exception,
    required this.active,
  });

  factory DeviceAdminCheck.fromMap(Map<dynamic, dynamic> map) =>
      DeviceAdminCheck(
        action: map['action'] as String? ?? '',
        component: map['component'] as String? ?? '',
        resolved: map['resolved'] as String?,
        exception: map['exception'] as String?,
        active: map['active'] == true,
      );
}

/// One line of the on-device security audit (device admin, Settings escapes,
/// installs and re-baselines).
@immutable
class SecurityAuditEntry {
  final int timestamp;
  final String event;
  final String detail;

  const SecurityAuditEntry({
    required this.timestamp,
    required this.event,
    required this.detail,
  });

  DateTime get at => DateTime.fromMillisecondsSinceEpoch(timestamp);

  factory SecurityAuditEntry.fromMap(Map<dynamic, dynamic> map) =>
      SecurityAuditEntry(
        timestamp: (map['t'] as num?)?.toInt() ?? 0,
        event: map['event'] as String? ?? 'unknown',
        detail: map['detail'] as String? ?? '',
      );
}

/// One prayer block window, in minutes since midnight.
@immutable
class PrayerWindow {
  final String name;
  final int startMinute;
  final int endMinute;

  const PrayerWindow({
    required this.name,
    required this.startMinute,
    required this.endMinute,
  });

  factory PrayerWindow.fromMap(Map<dynamic, dynamic> map) => PrayerWindow(
        name: map['name'] as String? ?? 'Prayer',
        startMinute: (map['start'] as num?)?.toInt() ?? 0,
        endMinute: (map['end'] as num?)?.toInt() ?? 0,
      );

  String get label => '${_clock(startMinute)}–${_clock(endMinute)}';

  static String _clock(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:'
      '${(minute % 60).toString().padLeft(2, '0')}';
}

/// Bridge to the Android control channel. Every method degrades to
/// [NativeStatus.unsupported] off Android and on plugin errors, so the UI can
/// always render instead of crashing with an unhandled platform exception.
class NativeBridge {
  static const MethodChannel channel =
      MethodChannel('com.haramblur.haram_blur/control');

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<NativeStatus> status() async {
    final map = await _invokeMap('getStatus');
    return map == null ? NativeStatus.unsupported : NativeStatus.fromMap(map);
  }

  Future<NativeStatus> setEnabled(bool enabled) async {
    final map = await _invokeMap('setEnabled', {'enabled': enabled});
    return map == null ? NativeStatus.unsupported : NativeStatus.fromMap(map);
  }

  /// Path to the app's documents directory, via a platform channel so the
  /// app can avoid the `path_provider` dependency (which pulls in native
  /// assets hooks that break on space-containing paths).
  Future<String> appDocumentsDirectory() async {
    if (!isSupported) return Directory.systemTemp.path;
    try {
      return await channel.invokeMethod<String>('appDocumentsDirectory') ??
          Directory.systemTemp.path;
    } on MissingPluginException {
      return Directory.systemTemp.path;
    } on PlatformException {
      return Directory.systemTemp.path;
    }
  }

  Future<void> setSensitivity(int level) =>
      _invoke('setSensitivity', {'level': level.clamp(1, 10)});

  /// Runs ML Kit face detection on arbitrary image bytes (Image lab and the
  /// on-device self-eval use the same native path as live capture).
  Future<List<Rect>> detectFaces(Uint8List bytes) async {
    if (!isSupported) return const [];
    try {
      final raw = await channel.invokeMethod<List<Object?>>(
        'detectFaces',
        {'bytes': bytes},
      );
      if (raw == null) return const [];
      final out = <Rect>[];
      for (final entry in raw) {
        if (entry is List && entry.length >= 4) {
          out.add(Rect.fromLTRB(
            (entry[0] as num).toDouble(),
            (entry[1] as num).toDouble(),
            (entry[2] as num).toDouble(),
            (entry[3] as num).toDouble(),
          ));
        }
      }
      return out;
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  /// Shows or hides the live capture HUD (NSFW score, skin ratio, decision).
  Future<void> setDebugOverlay(bool enabled) =>
      _invoke('setDebugOverlay', {'enabled': enabled});

  /// Pushes the overlay obscuration strength (`standard`, `strong`, `max`).
  Future<void> setBlurStrength(String strength) =>
      _invoke('setBlurStrength', {'strength': strength});

  /// Sends the full effective exclusion list (defaults + user additions) so
  /// the native service never has to guess what the UI shows.
  Future<void> setExclusions(List<String> packages) =>
      _invoke('setExclusions', {'packages': packages});

  /// Packages the service blocks on sight, without any detection.
  Future<void> setBlockedApps(List<String> packages) =>
      _invoke('setBlockedApps', {'packages': packages});

  /// Keywords matched against the active window's text and URL.
  Future<void> setKeywordBlocklist(List<String> keywords) =>
      _invoke('setKeywordBlocklist', {'keywords': keywords});

  /// Per-app allowed windows as `package -> [startMinute, endMinute]`.
  Future<void> setAppSchedules(Map<String, List<int>> schedules) =>
      _invoke('setAppSchedules', {'schedules': schedules});

  /// Per-app daily caps in minutes (absent key = no cap).
  Future<void> setDailyLimits(Map<String, int> minutes) =>
      _invoke('setDailyLimits', {'limits': minutes});

  /// Launcher apps installed on this device, for the blocked-apps picker.
  Future<List<InstalledApp>> listApps() async {
    if (!isSupported) return const [];
    try {
      final raw = await channel.invokeMethod<List<Object?>>('listApps');
      if (raw == null) return const [];
      return raw
          .whereType<Map>()
          .map(InstalledApp.fromMap)
          .where((app) => app.isUsable)
          .toList(growable: false);
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  /// Posts the "protection is off" notification. Called by the watchdog when
  /// the accessibility service is no longer connected.
  Future<void> notifyProtectionOff() => _invoke('notifyProtectionOff');

  /// Bundled adult-domain list, matched against the active window URL.
  Future<void> setBlockedDomains(List<String> domains) =>
      _invoke('setBlockedDomains', {'domains': domains});

  /// Bundled adult URL patterns, matched against the page URL only.
  Future<void> setBlockedUrlPatterns(List<String> patterns) =>
      _invoke('setBlockedUrlPatterns', {'patterns': patterns});

  /// Sites that must never be blocked, checked before every site list.
  Future<void> setAllowlistedDomains(List<String> domains) =>
      _invoke('setAllowlistedDomains', {'domains': domains});

  /// Keywords matched only as whole words.
  Future<void> setWholeWordKeywords(List<String> keywords) =>
      _invoke('setWholeWordKeywords', {'keywords': keywords});

  /// Apps where in-app browsers are blocked; empty means all of them.
  Future<void> setInAppBrowserApps(List<String> packages) =>
      _invoke('setInAppBrowserApps', {'packages': packages});

  /// Prayer windows are computed natively from these coordinates, so they
  /// keep working with the Flutter engine dead.
  Future<void> setPrayerPolicy({
    required bool enabled,
    required double? latitude,
    required double? longitude,
    required int minutesAfter,
    required String method,
  }) =>
      _invoke('setPrayerPolicy', {
        'enabled': enabled,
        'latitude': latitude,
        'longitude': longitude,
        'minutesAfter': minutesAfter,
        'method': method,
      });

  /// Today's five windows, computed on device; empty without coordinates.
  Future<List<PrayerWindow>> prayerTimes() async {
    if (!isSupported) return const [];
    try {
      final raw = await channel.invokeMethod<List<Object?>>('getPrayerTimes');
      if (raw == null) return const [];
      return raw
          .whereType<Map>()
          .map(PrayerWindow.fromMap)
          .toList(growable: false);
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  /// Snapshots the apps and browsers installed now as the trusted baseline.
  Future<NativeStatus> rebaselineNewApps() async {
    final map = await _invokeMap('rebaselineNewApps');
    return map == null ? NativeStatus.unsupported : NativeStatus.fromMap(map);
  }

  /// Vouches for one app so the “installed after setup” rule stops flagging it.
  Future<NativeStatus> trustApp(String package) async {
    final map = await _invokeMap('trustApp', {'package': package});
    return map == null ? NativeStatus.unsupported : NativeStatus.fromMap(map);
  }

  /// The on-device audit trail, newest last.
  Future<List<SecurityAuditEntry>> securityAudit() async {
    if (!isSupported) return const [];
    try {
      final raw = await channel.invokeMethod<List<Object?>>('getSecurityAudit');
      if (raw == null) return const [];
      return raw
          .whereType<Map>()
          .map(SecurityAuditEntry.fromMap)
          .toList(growable: false);
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  /// Switches for the bypass-prevention toggles on the dashboard.
  Future<void> setAdvancedPolicy({
    required bool blockNewApps,
    required bool blockNewBrowsers,
    required bool blockUnsupportedBrowsers,
    required bool dailyAffirmations,
    required bool blockSplitScreen,
    required bool blockIncognito,
    required bool blockInAppBrowsers,
    required bool crossBlockLimit,
  }) =>
      _invoke('setAdvancedPolicy', {
        'blockNewApps': blockNewApps,
        'blockNewBrowsers': blockNewBrowsers,
        'blockUnsupportedBrowsers': blockUnsupportedBrowsers,
        'dailyAffirmations': dailyAffirmations,
        'blockSplitScreen': blockSplitScreen,
        'blockIncognito': blockIncognito,
        'blockInAppBrowsers': blockInAppBrowsers,
        'crossBlockLimit': crossBlockLimit,
      });

  /// Custom title and body drawn on the native block screen. Empty strings
  /// restore the shipped wording.
  Future<void> setBlockScreen({required String title, required String message}) =>
      _invoke('setBlockScreen', {'title': title, 'message': message});

  /// Apps the user allows even though they are on the blocklist.
  Future<void> setWhitelistedApps(List<String> packages) =>
      _invoke('setWhitelistedApps', {'packages': packages});

  /// Focus (calm mode) state: until when it runs, which apps stay reachable
  /// and whether the session may be ended early.
  Future<void> setFocusState({
    required int activeUntil,
    required List<String> allowedApps,
    required bool preventExit,
  }) =>
      _invoke('setFocusState', {
        'activeUntil': activeUntil,
        'allowedApps': allowedApps,
        'preventExit': preventExit,
      });

  /// Asks for POST_NOTIFICATIONS (Android 13+). No-op elsewhere.
  Future<void> requestNotificationPermission() =>
      _invoke('requestNotificationPermission');

  /// Asks Android to exempt the app from battery optimization.
  Future<void> requestIgnoreBatteryOptimizations() =>
      _invoke('requestIgnoreBatteryOptimizations');

  Future<void> openAccessibilitySettings() =>
      _invoke('openAccessibilitySettings');

  Future<void> openNotificationSettings() =>
      _invoke('openNotificationSettings');

  /// Opens Android's device-admin screen. Returns null on success, or a
  /// message for the UI. Unlike the generic [_invoke], the error is not
  /// swallowed: a dead Activate button must say why.
  Future<String?> openDeviceAdmin() async {
    if (!isSupported) return 'Device admin is available on Android only.';
    try {
      final map = await channel.invokeMethod<Map<dynamic, dynamic>>(
        'openDeviceAdmin',
      );
      if (map?['deviceAdminFallback'] == true) {
        return 'No device-admin screen on this device; opened Security '
            'settings instead.';
      }
      return null;
    } on MissingPluginException {
      return 'The native control channel is unavailable.';
    } on PlatformException catch (error) {
      return error.message ?? 'Could not open device admin settings.';
    }
  }

  /// Opens the system document picker and returns the chosen image bytes, or
  /// null when the user cancels. Android only; other platforms use
  /// image_picker, which is why the plugin is still a dependency.
  Future<Uint8List?> pickImage() => _readPickedImage('pickImage');

  /// Opens the system camera app and returns the captured image bytes, or null
  /// when the user cancels.
  Future<Uint8List?> takePhoto() => _readPickedImage('takePhoto');

  /// The native side writes the image to a cache file and returns its path; the
  /// bytes are read here and the file removed so nothing lingers on disk.
  Future<Uint8List?> _readPickedImage(String method) async {
    if (!isSupported) return null;
    final path = await channel.invokeMethod<String>(method);
    if (path == null) return null;
    final file = File(path);
    try {
      return await file.readAsBytes();
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // A cache file the OS already cleaned up is not an error.
      }
    }
  }

  /// Last screenshot the protection service analysed, including the frame it
  /// received and the Dart decision. Android only.
  Future<LiveCapture?> lastCapture() async {
    if (!isSupported) return null;
    try {
      final map = await channel.invokeMethod<Map<dynamic, dynamic>>('getLastCapture');
      if (map == null) return null;
      final capture = LiveCapture.fromMap(map);
      return capture.isEmpty ? null : capture;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<String> captureLog() async {
    if (!isSupported) return '';
    try {
      return await channel.invokeMethod<String>('getCaptureLog') ?? '';
    } on MissingPluginException {
      return '';
    } on PlatformException {
      return '';
    }
  }

  Future<void> clearCaptureLog() async {
    if (!isSupported) return;
    try {
      await channel.invokeMethod<void>('clearCaptureLog');
    } on MissingPluginException {
      // Non-Android: nothing to clear.
    } on PlatformException {
      // Nothing to clear.
    }
  }

  /// Builds the same device-admin intent the Activate buttons use and reports
  /// its resolution, so the developer row can prove where it fails.
  Future<DeviceAdminCheck?> testDeviceAdminIntent() async {
    if (!isSupported) return null;
    try {
      final map = await channel
          .invokeMethod<Map<dynamic, dynamic>>('testDeviceAdminIntent');
      return map == null ? null : DeviceAdminCheck.fromMap(map);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  // ---------------------------------------------------------------------
  // Protection modes, Device Owner policies and device controls
  // ---------------------------------------------------------------------

  /// The full protection report: mode, health, components, restrictions and
  /// power controls, every value read back from Android.
  Future<Map<dynamic, dynamic>?> protectionReport() =>
      _invokeMap('getProtectionReport');

  /// Stores the requested tier. Hardened is only effective when Android reports
  /// a verified Device Owner; the returned report says which one is running.
  Future<Map<dynamic, dynamic>?> setProtectionTier(String tier) =>
      _invokeMap('setProtectionTier', {'tier': tier});

  /// Applies every Hardened Device Owner restriction and returns the verified
  /// state. Requires a provisioned Device Owner; never provisioning itself.
  Future<Map<dynamic, dynamic>?> applyHardenedRestrictions() =>
      _invokeMap('applyHardenedRestrictions');

  /// Removes every Hardened restriction. This is the in-app recovery path and
  /// does not remove the Device Owner itself.
  Future<Map<dynamic, dynamic>?> removeHardenedRestrictions() =>
      _invokeMap('removeHardenedRestrictions');

  /// Opens Android's power menu, or restarts directly on a verified Device
  /// Owner in Hardened mode. Returns what Android actually accepted.
  Future<Map<dynamic, dynamic>?> restartDevice() =>
      _invokeMap('restartDevice');

  /// Always the system power dialog: Android exposes no direct shutdown API.
  Future<Map<dynamic, dynamic>?> powerOffDevice() =>
      _invokeMap('powerOffDevice');

  /// Copies the capture log plus the last five frames into Downloads and
  /// returns the path, or a readable failure.
  Future<String> exportCaptureLog() async {
    if (!isSupported) return 'Export is available on Android only.';
    try {
      final path = await channel.invokeMethod<String>('exportCaptureLog');
      return path ?? 'Export finished, but the path was not reported.';
    } on MissingPluginException {
      return 'Export failed: the native channel is unavailable.';
    } on PlatformException catch (error) {
      return 'Export failed: ${error.message ?? error.code}';
    }
  }

  /// Human-readable text for a failed image request. Platform errors carry
  /// codes such as `no_camera` or `read_failed` from MainActivity.
  static String describeImageError(Object error) {
    if (error is PlatformException) {
      return switch (error.code) {
        'no_camera' => 'No camera app is available on this device.',
        'read_failed' =>
          'That image could not be read. Try a different one.',
        'unavailable' => 'The system image picker could not be opened.',
        'busy' => 'Another image is still being opened.',
        _ => error.message ?? 'Could not open an image.',
      };
    }
    return '$error';
  }

  Future<Map<dynamic, dynamic>?> _invokeMap(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    if (!isSupported) return null;
    try {
      return await channel.invokeMethod<Map<dynamic, dynamic>>(
        method,
        arguments,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> _invoke(String method, [Map<String, dynamic>? arguments]) async {
    if (!isSupported) return;
    try {
      await channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Non-Android platform: system-wide protection is unavailable by design.
    } on PlatformException {
      // The settings screen will re-read status and surface the problem.
    }
  }
}

final nativeBridge = NativeBridge();
