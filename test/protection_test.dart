import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haram_blur/services/native_bridge.dart';
import 'package:haram_blur/services/protection_service.dart';
import 'package:haram_blur/ui/protection_screen.dart';
import 'package:haram_blur/ui/theme.dart';

/// The protection dashboard and its model.
///
/// The native bridge is faked at the Dart boundary, so these tests exercise the
/// real parsing, controller and rendering path without claiming any Android
/// device behaviour. Device Owner policy application still needs a disposable
/// provisioned device (see docs/PROTECTION.md).
class _FakeBridge extends NativeBridge {
  _FakeBridge(this.report);

  Map<String, Object?> report;
  final List<String> calls = [];

  @override
  Future<Map<dynamic, dynamic>?> protectionReport() async {
    calls.add('getProtectionReport');
    return report;
  }

  @override
  Future<Map<dynamic, dynamic>?> setProtectionTier(String tier) async {
    calls.add('setProtectionTier:$tier');
    return {'ok': true, 'message': 'Mode saved.', 'report': report};
  }

  @override
  Future<Map<dynamic, dynamic>?> applyHardenedRestrictions() async {
    calls.add('applyHardenedRestrictions');
    return {'ok': true, 'message': 'Restrictions verified.', 'report': report};
  }

  @override
  Future<Map<dynamic, dynamic>?> removeHardenedRestrictions() async {
    calls.add('removeHardenedRestrictions');
    return {'ok': true, 'message': 'Restrictions removed.', 'report': report};
  }

  @override
  Future<Map<dynamic, dynamic>?> restartDevice() async {
    calls.add('restartDevice');
    return {
      'ok': true,
      'route': 'system_power_dialog',
      'message': "Android's power menu is open. Choose Restart there.",
      'report': report,
    };
  }

  @override
  Future<Map<dynamic, dynamic>?> powerOffDevice() async {
    calls.add('powerOffDevice');
    return {
      'ok': true,
      'route': 'system_power_dialog',
      'message': "Android's power menu is open. Choose Power off there.",
      'report': report,
    };
  }
}

Map<String, Object?> buildReport({
  String tier = 'standard',
  String requestedTier = 'standard',
  bool deviceOwner = false,
  String health = 'active',
  String healthDetail =
      'Accessibility, the rule matcher and the visual detector are all running.',
  List<Map<String, Object?>>? components,
  List<Map<String, Object?>>? restrictions,
  List<Map<String, Object?>>? controls,
  String? notice,
}) => {
  'tier': tier,
  'tierRequested': requestedTier,
  'deviceOwner': {
    'isOwner': deviceOwner,
    'adminActive': false,
    'component':
        'com.haramblur.haram_blur/com.haramblur.haram_blur.DeviceAdmin',
    'apiSupported': true,
    'packageName': 'com.haramblur.haram_blur',
  },
  'health': health,
  'healthDetail': healthDetail,
  'components':
      components ??
      [
        {
          'key': 'accessibility',
          'state': 'active',
          'detail': 'Granted and connected to Android.',
        },
        {
          'key': 'detection_engine',
          'state': 'active',
          'detail': 'The on-device model is loaded and scoring frames.',
        },
        {
          'key': 'matcher',
          'state': 'active',
          'detail': 'Block lists are loaded and matching.',
        },
        {
          'key': 'last_scan',
          'state': 'active',
          'detail': 'Last screen scan 2 min ago.',
        },
        {
          'key': 'reboot_recovery',
          'state': 'active',
          'detail': 'The service reconnected after the last restart.',
        },
        {
          'key': 'anti_tamper',
          'state': 'active',
          'detail': 'Recording changes locally.',
        },
      ],
  'restrictions':
      restrictions ??
      [
        {
          'key': 'safe_boot',
          'state': 'requires_provisioning',
          'detail': 'Needs Device Owner (a one-time provisioning step).',
        },
        {
          'key': 'apps_control',
          'state': 'requires_provisioning',
          'detail': 'Needs Device Owner (a one-time provisioning step).',
        },
        {
          'key': 'factory_reset',
          'state': 'requires_provisioning',
          'detail': 'Needs Device Owner (a one-time provisioning step).',
        },
        {
          'key': 'uninstall_blocked',
          'state': 'requires_provisioning',
          'detail': 'Needs Device Owner (a one-time provisioning step).',
        },
      ],
  'controls':
      controls ??
      [
        {
          'key': 'restart',
          'state': 'active',
          'route': 'system_power_dialog',
          'detail':
              "Opens Android's own power menu; you choose the action "
              'there.',
        },
        {
          'key': 'power_off',
          'state': 'active',
          'route': 'system_power_dialog',
          'detail':
              "Opens Android's own power menu; you choose the action "
              'there.',
        },
      ],
  'lastScanAt': 0,
  'lastConnectAt': 0,
  'lastBootAt': 0,
  'notice': notice,
  'samsung': {
    'device': 'Samsung Galaxy A56 (One UI)',
    'validated': false,
    'detail': 'Not validated on a physical Galaxy A56 in this workspace.',
  },
  'audit': <Map<String, Object?>>[],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeBridge bridge;

  setUp(() {
    bridge = _FakeBridge(buildReport());
  });

  /// The dashboard is taller than the test surface, so a control must be
  /// scrolled into view before it can be tapped, exactly as a user would.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: ProtectionScreen(
          controller: ProtectionController(bridge: bridge),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // -------------------------------------------------------------------
  // Model
  // -------------------------------------------------------------------

  group('ProtectionReport', () {
    test('parses a standard-mode report without inventing hardened state', () {
      final parsed = ProtectionReport.fromMap(buildReport());
      expect(parsed.tier, ProtectionTier.standard);
      expect(parsed.hardenedActive, isFalse);
      expect(parsed.hardenedPending, isFalse);
      expect(parsed.deviceOwner, isFalse);
      expect(parsed.health, ProtectionState.active);
      expect(parsed.appliedRestrictions, 0);
      expect(parsed.component('accessibility')?.state, ProtectionState.active);
      expect(
        parsed.restriction('safe_boot')?.state,
        ProtectionState.requiresProvisioning,
      );
    });

    test('a requested hardened mode without a device owner stays pending', () {
      final parsed = ProtectionReport.fromMap(
        buildReport(tier: 'standard', requestedTier: 'hardened'),
      );
      expect(parsed.tier, ProtectionTier.standard);
      expect(parsed.hardenedPending, isTrue);
      expect(parsed.hardenedActive, isFalse);
    });

    test('verified hardened mode needs the owner and the policies', () {
      final parsed = ProtectionReport.fromMap(
        buildReport(
          tier: 'hardened',
          requestedTier: 'hardened',
          deviceOwner: true,
          restrictions: [
            {'key': 'safe_boot', 'state': 'active', 'detail': 'Set.'},
            {'key': 'apps_control', 'state': 'active', 'detail': 'Set.'},
            {
              'key': 'factory_reset',
              'state': 'unsupported',
              'detail': 'No API.',
            },
            {'key': 'uninstall_blocked', 'state': 'active', 'detail': 'Set.'},
          ],
        ),
      );
      expect(parsed.hardenedActive, isTrue);
      expect(parsed.deviceOwner, isTrue);
      expect(parsed.appliedRestrictions, 3);
      expect(
        parsed.restriction('factory_reset')?.state,
        ProtectionState.unsupported,
      );
    });

    test('unknown states never become active', () {
      expect(
        ProtectionState.fromWire('something_new'),
        ProtectionState.unknown,
      );
      expect(ProtectionState.fromWire(null), ProtectionState.unknown);
      expect(ProtectionTier.fromWire('rooted'), ProtectionTier.standard);
      expect(ProtectionState.fromWire('active'), ProtectionState.active);
    });
  });

  // -------------------------------------------------------------------
  // Interface
  // -------------------------------------------------------------------

  group('ProtectionScreen', () {
    testWidgets('shows the verified health, restrictions and both controls', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text('Protection active'), findsOneWidget);
      expect(find.text('Accessibility service'), findsOneWidget);
      expect(find.text('Safe Mode prevention'), findsOneWidget);
      // Four restrictions all waiting for provisioning.
      expect(find.text('Needs provisioning'), findsWidgets);
      expect(find.text('Restart now'), findsOneWidget);
      expect(find.text('Turn off now'), findsOneWidget);
      expect(
        find.textContaining("hold the phone's side button"),
        findsOneWidget,
      );
    });

    testWidgets('never shows a disabled feature as active', (tester) async {
      bridge.report = buildReport(
        health: 'temporarily_unavailable',
        healthDetail:
            'Android has accessibility off, so Basirah cannot see the screen.',
        components: [
          {
            'key': 'accessibility',
            'state': 'temporarily_unavailable',
            'detail': 'Not granted.',
          },
        ],
        controls: [
          {
            'key': 'restart',
            'state': 'inactive',
            'route': 'unavailable',
            'detail': 'Needs the accessibility service.',
          },
          {
            'key': 'power_off',
            'state': 'inactive',
            'route': 'unavailable',
            'detail': 'Needs the accessibility service.',
          },
        ],
      );
      await pumpScreen(tester);

      expect(find.text('Protection temporarily unavailable'), findsOneWidget);
      expect(find.text('Unavailable'), findsWidgets);
      expect(find.text('Protection active'), findsNothing);
      expect(find.text('Needs the accessibility service.'), findsNWidgets(2));
      expect(
        find.textContaining("hold the phone's side button"),
        findsOneWidget,
      );
    });

    testWidgets(
      'choosing hardened without an owner explains provisioning only',
      (tester) async {
        await pumpScreen(tester);

        await tapVisible(tester, find.text('Hardened'));

        expect(find.text('Provisioning hardened protection'), findsOneWidget);
        expect(
          find.textContaining('adb shell dpm set-device-owner'),
          findsOneWidget,
        );
        // Nothing was applied and no mode was stored: the dialog is the whole
        // action until the device is genuinely provisioned.
        expect(bridge.calls, isNot(contains('applyHardenedRestrictions')));
        expect(
          bridge.calls.where((call) => call.startsWith('setProtectionTier')),
          isEmpty,
        );

        await tapVisible(tester, find.text('Close'));
      },
    );

    testWidgets('restart asks first and does nothing when cancelled', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tapVisible(tester, find.text('Restart now'));
      expect(find.text('Restart this phone?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(bridge.calls, isNot(contains('restartDevice')));
    });

    testWidgets('turn off asks first and never claims a shutdown', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tapVisible(tester, find.text('Turn off now'));
      expect(find.text('Turn off this phone?'), findsOneWidget);
      expect(
        find.textContaining('never switches the device off'),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(bridge.calls, isNot(contains('powerOffDevice')));
    });

    testWidgets('a requested-but-unverified mode is called out in words', (
      tester,
    ) async {
      bridge.report = buildReport(
        tier: 'standard',
        requestedTier: 'hardened',
        notice: 'This device has no verified Device Owner.',
      );
      await pumpScreen(tester);

      expect(
        find.textContaining('Standard protection is what is actually running'),
        findsOneWidget,
      );
      expect(
        find.text('This device has no verified Device Owner.'),
        findsOneWidget,
      );
    });

    testWidgets('a provisioned owner is offered the restriction action', (
      tester,
    ) async {
      bridge.report = buildReport(deviceOwner: true);
      await pumpScreen(tester);

      expect(find.text('Enable hardened restrictions'), findsOneWidget);
      expect(find.text('Needs Device Owner provisioning'), findsNothing);
    });
  });
}
