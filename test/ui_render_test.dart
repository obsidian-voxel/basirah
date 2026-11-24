import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:haram_blur/main.dart';
import 'package:haram_blur/services/blur_engine.dart';
import 'package:haram_blur/services/protection_service.dart';
import 'package:haram_blur/ui/accountability_screen.dart';
import 'package:haram_blur/ui/affirmations_screen.dart';
import 'package:haram_blur/ui/permissions_screen.dart';
import 'package:haram_blur/ui/protection_screen.dart';
import 'package:haram_blur/ui/settings_screen.dart';
import 'package:haram_blur/ui/theme.dart';

/// Renders each screen at the reference capture size and writes PNGs to
/// `build/ui-review/`, so changes can be compared against the BlockP
/// screenshots instead of being described from memory.
///
///   flutter test test/ui_render_test.dart
class _Boundary {
  static final key = GlobalKey();
}

Future<void> _loadFonts() async {
  final loader = FontLoader('AnekLatin');
  for (final weight in [300, 400, 500, 600, 700]) {
    loader.addFont(rootBundle.load('assets/fonts/AnekLatin-$weight.ttf'));
  }
  await loader.load();

  // The Arabic wordmark uses Amiri; without it the Arabic renders as boxes.
  final arabic = FontLoader('Amiri')
    ..addFont(rootBundle.load('assets/fonts/Amiri-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Amiri-Bold.ttf'));
  await arabic.load();

  // Material's icon font lives in the Flutter SDK cache, not in the app's
  // assets; without it every icon renders as an empty box in the captures.
  final iconFont = File(
    'C:/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
  );
  if (iconFont.existsSync()) {
    final bytes = await iconFont.readAsBytes();
    final icons = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await icons.load();
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
    find.byKey(_Boundary.key),
  );
  // Rasterising needs the real async loop; without runAsync the future never
  // completes inside the fake-async test zone.
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2.625);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/ui-review/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Widget _wrap(Widget child, Brightness brightness) {
  return RepaintBoundary(
    key: _Boundary.key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: brightness == Brightness.dark
          ? buildDarkTheme()
          : buildLightTheme(),
      home: child,
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget widget,
  Brightness brightness,
) async {
  tester.view.physicalSize = const Size(1080, 2340);
  // The reference screenshots were taken on a 1080 x 2340 device at 420 dpi,
  // i.e. 2.625 physical pixels per dp. Rendering at a different ratio would
  // scale every dp-based measurement and make the captures incomparable.
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  // BasirahApp follows the system theme, so drive that rather than wrapping
  // it in a second MaterialApp (which the inner app would ignore).
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  await tester.pumpWidget(_wrap(widget, brightness));
  // The calm screen runs a one-second ticker, so pumpAndSettle would never
  // settle; a few frames are enough to lay the screen out.
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 300));
}

/// A verified Standard-mode report, used only to lay the dashboard out.
Map<String, Object?> _protectionReport() => {
  'tier': 'standard',
  'tierRequested': 'standard',
  'deviceOwner': {
    'isOwner': false,
    'adminActive': true,
    'component':
        'com.haramblur.haram_blur/com.haramblur.haram_blur.DeviceAdmin',
    'apiSupported': true,
    'packageName': 'com.haramblur.haram_blur',
  },
  'health': 'active',
  'healthDetail':
      'Accessibility, the rule matcher and the visual detector '
      'are all running.',
  'components': [
    {
      'key': 'preferences',
      'state': 'active',
      'detail': 'Protection is switched on and stored on this device.',
    },
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
      'detail': 'Last screen scan just now.',
    },
    {
      'key': 'reboot_recovery',
      'state': 'active',
      'detail': 'The service reconnected after the last restart.',
    },
    {
      'key': 'anti_tamper',
      'state': 'active',
      'detail':
          'Recording accessibility, policy and Settings changes in '
          'this app\'s private audit log.',
    },
  ],
  'restrictions': [
    {
      'key': 'safe_boot',
      'state': 'requires_provisioning',
      'detail':
          'Safe Mode would let every third-party service start '
          'without Basirah, so this is the bypass it closes.',
    },
    {
      'key': 'apps_control',
      'state': 'requires_provisioning',
      'detail':
          'This covers app management in Settings. It does not stop '
          'ADB, root or an OEM tool from removing apps.',
    },
    {
      'key': 'factory_reset',
      'state': 'requires_provisioning',
      'detail':
          'Recovery-mode wipes, firmware reflashes and Find My Mobile '
          'erasure are outside what any app can block.',
    },
    {
      'key': 'uninstall_blocked',
      'state': 'requires_provisioning',
      'detail': 'Basirah can still be uninstalled the usual way.',
    },
  ],
  'controls': [
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
  'samsung': {
    'device': 'Samsung Galaxy A56 (One UI)',
    'validated': false,
    'detail':
        'Android enterprise Device Owner policy is documented by '
        'Google and used by managed-device products, but Basirah has not '
        'been run on a physical Galaxy A56 in this workspace.',
  },
  'audit': <Map<String, Object?>>[],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFonts();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await blurEngine.init();
  });

  for (final brightness in [Brightness.light, Brightness.dark]) {
    final suffix = brightness == Brightness.dark ? 'dark' : 'light';

    testWidgets('dashboard $suffix', (tester) async {
      await _pump(tester, const BasirahApp(), brightness);
      await _capture(tester, 'dashboard_$suffix');
    });

    testWidgets('tabs $suffix', (tester) async {
      await _pump(tester, const BasirahApp(), brightness);
      for (final entry in {
        'blocklist': 'Block list',
        'premium': 'Premium',
        'calm': 'Calm',
        'support': 'Support',
      }.entries) {
        await tester.tap(find.text(entry.value));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 300));
        await _capture(tester, '${entry.key}_$suffix');
      }
    });

    testWidgets('pushed screens $suffix', (tester) async {
      await _pump(tester, const SettingsScreen(), brightness);
      await _capture(tester, 'settings_$suffix');

      await _pump(tester, const PermissionsScreen(), brightness);
      await _capture(tester, 'permissions_$suffix');

      await _pump(tester, const AccountabilityScreen(), brightness);
      await _capture(tester, 'accountability_$suffix');

      await _pump(tester, const AffirmationsScreen(), brightness);
      await _capture(tester, 'affirmations_$suffix');

      // The protection dashboard has no Android channel in a render test, so
      // it is given one fixed, already-verified report to lay out.
      await _pump(
        tester,
        ProtectionScreen(
          controller: ProtectionController.withReport(
            ProtectionReport.fromMap(_protectionReport()),
          ),
        ),
        brightness,
      );
      await _capture(tester, 'protection_$suffix');
    });
  }
}
