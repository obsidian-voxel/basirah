import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:haram_blur/models/blur_event.dart';
import 'package:haram_blur/services/blur_event_store.dart';
import 'package:haram_blur/services/filter_store.dart';
import 'package:haram_blur/services/settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SettingsStore', () {
    test('defaults are safe and persisted values round-trip', () async {
      final store = SettingsStore(await SharedPreferences.getInstance());

      expect(store.sensitivity, 5);
      expect(store.partner.isEmpty, isTrue);
      expect(store.alerts.explicitContent, isTrue);
      expect(store.customExclusions, isEmpty);

      await store.setSensitivity(9);
      await store.setPartner(
        const PartnerContact(name: 'Aisha', email: 'a@example.com', phone: '1'),
      );
      await store.setAlerts(const AlertPreferences(protectionDisabled: true));

      final reopened = SettingsStore(await SharedPreferences.getInstance());
      expect(reopened.sensitivity, 9);
      expect(reopened.partner.name, 'Aisha');
      expect(reopened.partner.email, 'a@example.com');
      expect(reopened.alerts.protectionDisabled, isTrue);
      expect(reopened.alerts.explicitContent, isTrue);
    });

    test('sensitivity is clamped to 1..10', () async {
      final store = SettingsStore(await SharedPreferences.getInstance());
      await store.setSensitivity(99);
      expect(store.sensitivity, 10);
      await store.setSensitivity(-4);
      expect(store.sensitivity, 1);
    });

    test('custom exclusions are validated, de-duplicated and sorted', () async {
      final store = SettingsStore(await SharedPreferences.getInstance());
      await store.setCustomExclusions([
        ' com.example.b ',
        'com.example.a',
        'com.example.b',
        'not a package',
        'x',
      ]);

      expect(store.customExclusions, ['com.example.a', 'com.example.b']);
    });

    test('alert log keeps newest first and can be cleared', () async {
      final store = SettingsStore(await SharedPreferences.getInstance());
      await store.addAlert('first');
      await store.addAlert('second');

      expect(store.alertLog.first.message, 'second');
      await store.clearAlertLog();
      expect(store.alertLog, isEmpty);
    });
  });

  group('BlockP parity settings', () {
    test('block screen copy round-trips and clears back to default', () async {
      final store = FilterStore(await SharedPreferences.getInstance());
      expect(store.blockScreenTitle, isEmpty);
      expect(store.blockScreenMessage, isEmpty);

      await store.setBlockScreen(
        title: 'Stay strong',
        message: 'This page is not for you.',
      );
      final reopened =
          FilterStore(await SharedPreferences.getInstance());
      expect(reopened.blockScreenTitle, 'Stay strong');
      expect(reopened.blockScreenMessage, 'This page is not for you.');

      await reopened.setBlockScreen(title: '  ', message: '');
      expect(reopened.blockScreenTitle, isEmpty);
      expect(reopened.blockScreenMessage, isEmpty);
    });

    test('new guards have honest defaults and persist', () async {
      final store = FilterStore(await SharedPreferences.getInstance());
      // In-app browser blocking breaks ordinary help pages, so it starts off.
      expect(store.blockInAppBrowsers, isFalse);
      // The repeat-attempt lock is safe to have on.
      expect(store.crossBlockLimit, isTrue);

      await store.setAdvanced(blockInAppBrowsers: true, crossBlockLimit: false);
      final reopened = FilterStore(await SharedPreferences.getInstance());
      expect(reopened.blockInAppBrowsers, isTrue);
      expect(reopened.crossBlockLimit, isFalse);
    });

    test('morning gate time is clamped and the day key round-trips', () async {
      final store = SettingsStore(await SharedPreferences.getInstance());
      expect(store.affirmationLockMinute, 6 * 60);
      expect(store.affirmationDoneDay, isEmpty);

      await store.setAffirmationLockMinute(-30);
      expect(store.affirmationLockMinute, 0);
      await store.setAffirmationLockMinute(5000);
      expect(store.affirmationLockMinute, 1439);

      await store.markAffirmationsDone('2026-11-16');
      final reopened = SettingsStore(await SharedPreferences.getInstance());
      expect(reopened.affirmationDoneDay, '2026-11-16');
    });
  });

  group('BlurEventStore', () {
    Future<BlurEventStore> newStore() async =>
        BlurEventStore(await SharedPreferences.getInstance());

    BlurEvent event(DateTime time, String package) => BlurEvent(
          timestamp: time,
          packageName: package,
          reason: 'nsfw',
          confidence: 0.9,
        );

    test('events merge without double counting', () async {
      final store = await newStore();
      final now = DateTime(2026, 5, 4, 12);
      final a = event(now, 'com.example.a');

      await store.add(a);
      await store.merge([a, event(now.add(const Duration(minutes: 1)), 'com.example.b')]);

      expect(store.total, 2);
      expect(store.events.first.packageName, 'com.example.b');
    });

    test('counts per day and per app are correct', () async {
      final store = await newStore();
      final now = DateTime.now();
      await store.add(event(now, 'com.example.a'));
      await store.add(event(now.add(const Duration(milliseconds: 1)), 'com.example.a'));
      await store.add(event(now.subtract(const Duration(days: 2)), 'com.example.b'));

      expect(store.countToday(now), 2);
      expect(store.countsByApp(), {
        'com.example.a': 2,
        'com.example.b': 1,
      });

      final week = store.countsForLastDays(7, now);
      expect(week.last, 2);
      expect(week[4], 1);
      expect(week.fold<int>(0, (a, b) => a + b), 3);
    });

    test('export is valid JSON and contains the events', () async {
      final store = await newStore();
      await store.add(event(DateTime.now(), 'com.example.a'));

      final json = store.exportJson();
      expect(json, contains('"eventCount": 1'));
      expect(json, contains('com.example.a'));
    });

    test('corrupt cache entries are skipped', () async {
      SharedPreferences.setMockInitialValues({
        'blur_events': ['not json', '{"timestamp": "2026-01-01T00:00:00.000"}'],
      });
      final store = await newStore();
      expect(store.total, 1);
      expect(store.events.first.packageName, 'unknown');
    });
  });
}
