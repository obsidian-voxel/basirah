import 'package:flutter/foundation.dart';

import 'native_bridge.dart';

/// Which protection mode Basirah is meant to run in.
///
/// Standard works on any Android phone through the accessibility service.
/// Hardened adds Device Owner restrictions and therefore needs a one-time
/// provisioning step the user performs on a managed device. The two are never
/// mixed: [ProtectionReport.tier] is the verified mode, [requestedTier] is only
/// what the user asked for.
enum ProtectionTier {
  standard('standard', 'Standard'),
  hardened('hardened', 'Hardened');

  const ProtectionTier(this.wire, this.label);

  final String wire;
  final String label;

  static ProtectionTier fromWire(Object? value) =>
      values.firstWhere((tier) => tier.wire == value, orElse: () => standard);
}

/// Per-feature state, mirroring `PolicyEvaluator.State` in Kotlin.
///
/// "Needs provisioning" and "needs privileges" are separate from "inactive" so
/// a feature Android cannot grant is never shown as one the user simply left
/// off.
enum ProtectionState {
  active('active', 'Active'),
  inactive('inactive', 'Inactive'),
  degraded('degraded', 'Degraded'),
  temporarilyUnavailable('temporarily_unavailable', 'Unavailable'),
  disabled('disabled', 'Disabled'),
  unsupported('unsupported', 'Unsupported'),
  requiresPrivilege('requires_privilege', 'Needs privileges'),
  requiresProvisioning('requires_provisioning', 'Needs provisioning'),
  unknown('unknown', 'Unknown');

  const ProtectionState(this.wire, this.label);

  final String wire;
  final String label;

  bool get isActive => this == ProtectionState.active;

  /// Unknown wire values become [unknown] instead of a guessed success state.
  static ProtectionState fromWire(Object? value) =>
      values.firstWhere((state) => state.wire == value, orElse: () => unknown);
}

/// One row on the protection dashboard: a stable key, its verified state and a
/// plain-language explanation of what that state means.
@immutable
class ProtectionFeature {
  final String key;
  final ProtectionState state;
  final String detail;

  /// Only set for the power controls: `system_power_dialog`,
  /// `device_owner_reboot` or `unavailable`.
  final String? route;

  const ProtectionFeature({
    required this.key,
    required this.state,
    required this.detail,
    this.route,
  });

  factory ProtectionFeature.fromMap(Map<dynamic, dynamic> map) =>
      ProtectionFeature(
        key: map['key'] as String? ?? 'unknown',
        state: ProtectionState.fromWire(map['state']),
        detail: map['detail'] as String? ?? '',
        route: map['route'] as String?,
      );
}

/// A complete, verified snapshot of protection. Built from the native report;
/// nothing here is inferred on the Dart side.
@immutable
class ProtectionReport {
  final ProtectionTier tier;
  final ProtectionTier requestedTier;
  final bool deviceOwner;
  final bool deviceAdmin;
  final String ownerComponent;
  final ProtectionState health;
  final String healthDetail;
  final List<ProtectionFeature> components;
  final List<ProtectionFeature> restrictions;
  final List<ProtectionFeature> controls;
  final int lastScanAt;
  final int lastConnectAt;
  final int lastBootAt;
  final String? notice;
  final bool samsungValidated;
  final String samsungDetail;

  const ProtectionReport({
    required this.tier,
    required this.requestedTier,
    required this.deviceOwner,
    required this.deviceAdmin,
    required this.ownerComponent,
    required this.health,
    required this.healthDetail,
    required this.components,
    required this.restrictions,
    required this.controls,
    required this.lastScanAt,
    required this.lastConnectAt,
    required this.lastBootAt,
    this.notice,
    this.samsungValidated = false,
    this.samsungDetail = '',
  });

  bool get hardenedActive => tier == ProtectionTier.hardened;

  /// True when the user asked for Hardened but Android has not verified it.
  bool get hardenedPending =>
      requestedTier == ProtectionTier.hardened && !hardenedActive;

  int get appliedRestrictions =>
      restrictions.where((feature) => feature.state.isActive).length;

  ProtectionFeature? component(String key) => _find(components, key);

  ProtectionFeature? restriction(String key) => _find(restrictions, key);

  ProtectionFeature? control(String key) => _find(controls, key);

  static ProtectionFeature? _find(List<ProtectionFeature> list, String key) {
    for (final feature in list) {
      if (feature.key == key) return feature;
    }
    return null;
  }

  factory ProtectionReport.fromMap(Map<dynamic, dynamic> map) {
    List<ProtectionFeature> features(Object? raw) => raw is List
        ? raw
              .whereType<Map>()
              .map(ProtectionFeature.fromMap)
              .toList(growable: false)
        : const <ProtectionFeature>[];
    final owner = map['deviceOwner'];
    final ownerMap = owner is Map ? owner : const {};
    final samsung = map['samsung'];
    final samsungMap = samsung is Map ? samsung : const {};
    return ProtectionReport(
      tier: ProtectionTier.fromWire(map['tier']),
      requestedTier: ProtectionTier.fromWire(map['tierRequested']),
      deviceOwner: ownerMap['isOwner'] == true,
      deviceAdmin: ownerMap['adminActive'] == true,
      ownerComponent: ownerMap['component'] as String? ?? '',
      health: ProtectionState.fromWire(map['health']),
      healthDetail: map['healthDetail'] as String? ?? '',
      components: features(map['components']),
      restrictions: features(map['restrictions']),
      controls: features(map['controls']),
      lastScanAt: (map['lastScanAt'] as num?)?.toInt() ?? 0,
      lastConnectAt: (map['lastConnectAt'] as num?)?.toInt() ?? 0,
      lastBootAt: (map['lastBootAt'] as num?)?.toInt() ?? 0,
      notice: map['notice'] as String?,
      samsungValidated: samsungMap['validated'] == true,
      samsungDetail: samsungMap['detail'] as String? ?? '',
    );
  }
}

/// The outcome of one policy or power action, with the refreshed report.
@immutable
class ProtectionActionResult {
  final bool ok;
  final String message;

  const ProtectionActionResult({required this.ok, required this.message});

  static const unavailable = ProtectionActionResult(
    ok: false,
    message: 'The native protection channel is unavailable on this platform.',
  );
}

/// Owns the protection report for the dashboard. One instance per screen, so a
/// refresh can never race another screen's copy of the same state.
class ProtectionController extends ChangeNotifier {
  ProtectionController({NativeBridge? bridge})
    : _bridge = bridge ?? nativeBridge;

  /// Used by the screen-render test, which has no Android channel to ask.
  @visibleForTesting
  ProtectionController.withReport(ProtectionReport report)
    : _bridge = null,
      _report = report;

  final NativeBridge? _bridge;
  ProtectionReport? _report;
  bool _loading = false;
  String? _error;

  ProtectionReport? get report => _report;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> refresh() async {
    final bridge = _bridge;
    if (bridge == null) return;
    _loading = true;
    notifyListeners();
    final map = await bridge.protectionReport();
    _loading = false;
    if (map == null) {
      _error =
          'Protection status is read from Android, and is unavailable here.';
      _report = null;
    } else {
      _error = null;
      _report = ProtectionReport.fromMap(map);
    }
    notifyListeners();
  }

  Future<ProtectionActionResult> setTier(ProtectionTier tier) async {
    final bridge = _bridge;
    if (bridge == null) return ProtectionActionResult.unavailable;
    return _apply(await bridge.setProtectionTier(tier.wire));
  }

  Future<ProtectionActionResult> applyRestrictions() async {
    final bridge = _bridge;
    if (bridge == null) return ProtectionActionResult.unavailable;
    return _apply(await bridge.applyHardenedRestrictions());
  }

  Future<ProtectionActionResult> removeRestrictions() async {
    final bridge = _bridge;
    if (bridge == null) return ProtectionActionResult.unavailable;
    return _apply(await bridge.removeHardenedRestrictions());
  }

  Future<ProtectionActionResult> restart() async {
    final bridge = _bridge;
    if (bridge == null) return ProtectionActionResult.unavailable;
    return _apply(await bridge.restartDevice());
  }

  Future<ProtectionActionResult> powerOff() async {
    final bridge = _bridge;
    if (bridge == null) return ProtectionActionResult.unavailable;
    return _apply(await bridge.powerOffDevice());
  }

  /// Every action returns a fresh report; refresh from it so the dashboard
  /// describes what Android confirmed, not what was requested.
  ProtectionActionResult _apply(Map<dynamic, dynamic>? map) {
    if (map == null) {
      _error = 'Android did not answer the request.';
      notifyListeners();
      return ProtectionActionResult.unavailable;
    }
    final nested = map['report'];
    if (nested is Map) _report = ProtectionReport.fromMap(nested);
    _error = null;
    notifyListeners();
    return ProtectionActionResult(
      ok: map['ok'] == true,
      message: map['message'] as String? ?? 'Android reported no detail.',
    );
  }
}
