import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:haram_blur/src/block_rules.dart';
import 'package:haram_blur/src/keyword_blocker.dart';

void main() {
  group('KeywordBlocker', () {
    test('matches case-insensitively inside text', () {
      final blocker = KeywordBlocker(['porn']);
      expect(blocker.match('Free PORN videos')?.keyword, 'porn');
      expect(blocker.match('a normal page'), isNull);
    });

    test('supports the xxx* wildcard', () {
      final blocker = KeywordBlocker(['xxx*']);
      expect(blocker.match('xxxtube')?.evidence, 'xxxtube');
      expect(blocker.match('x-rated'), isNull);
      expect(blocker.match('nothing here'), isNull);
    });

    test('whole-word mode does not match inside a longer word', () {
      expect(KeywordBlocker(['porn']).match('pornography'), isNotNull);
      expect(
        KeywordBlocker(['porn'], wholeWord: true).match('pornography'),
        isNull,
      );
      expect(
        KeywordBlocker(['porn'], wholeWord: true).match('free porn now'),
        isNotNull,
      );
    });

    test('normalisation trims, lowercases and drops duplicates', () {
      expect(
        KeywordBlocker.normalizeAll([' Porn ', 'porn', '', '*', 'x']),
        ['porn'],
      );
    });

    test('the default pack blocks a typical explicit URL', () {
      final hit = KeywordBlocker(DefaultBlocklists.keywords)
          .match('https://example.com/porn/hub');
      expect(hit, isNotNull);
      expect(hit!.keyword, anyOf('porn', 'porn*'));
    });

    test('modest-dress vocabulary never matches', () {
      const text = 'Hijab niqab abaya modest clothing tutorial';
      expect(KeywordBlocker(DefaultBlocklists.keywords).match(text), isNull);
    });
  });

  group('ScheduleWindow', () {
    test('allows only inside the window', () {
      const window = ScheduleWindow(18 * 60, 20 * 60);
      expect(window.isAllowed(DateTime(2026, 1, 1, 18, 0)), isTrue);
      expect(window.isAllowed(DateTime(2026, 1, 1, 19, 59)), isTrue);
      expect(window.isAllowed(DateTime(2026, 1, 1, 20, 0)), isFalse);
      expect(window.isAllowed(DateTime(2026, 1, 1, 12, 0)), isFalse);
    });

    test('windows can wrap midnight', () {
      const window = ScheduleWindow(22 * 60, 6 * 60);
      expect(window.isAllowed(DateTime(2026, 1, 1, 23, 30)), isTrue);
      expect(window.isAllowed(DateTime(2026, 1, 1, 5, 0)), isTrue);
      expect(window.isAllowed(DateTime(2026, 1, 1, 12, 0)), isFalse);
    });

    test('equal endpoints mean unrestricted', () {
      expect(
        const ScheduleWindow(600, 600).isAllowed(DateTime(2026, 1, 1, 3, 0)),
        isTrue,
      );
    });

    test('JSON round-trips', () {
      final window =
          ScheduleWindow.fromJson(const ScheduleWindow(600, 1200).toJson())!;
      expect(window.startMinute, 600);
      expect(window.endMinute, 1200);
      expect(window.label, '10:00–20:00');
    });
  });

  group('UsageCounter', () {
    test('accumulates seconds per package', () {
      final usage =
          UsageCounter.empty.copyAt(DateTime(2026, 3, 4)).add('com.a', 90);
      expect(usage.secondsFor('com.a'), 90);
      expect(usage.secondsFor('com.b'), 0);
    });

    test('a cap is reached only at the limit', () {
      final usage = UsageCounter.empty
          .copyAt(DateTime(2026, 3, 4))
          .add('com.a', 30 * 60 - 1);
      expect(usage.isExhausted('com.a', 30), isFalse);
      expect(usage.add('com.a', 1).isExhausted('com.a', 30), isTrue);
      expect(usage.isExhausted('com.a', 0), isFalse);
    });

    test('counters reset on a new day', () {
      final yesterday =
          UsageCounter.empty.copyAt(DateTime(2026, 3, 4)).add('com.a', 999);

      final sameDay = yesterday.rollOver(DateTime(2026, 3, 4, 23, 59));
      expect(sameDay.secondsFor('com.a'), 999);

      final nextDay = yesterday.rollOver(DateTime(2026, 3, 5, 0, 1));
      expect(nextDay.dateKey, UsageCounter.dayKeyOf(DateTime(2026, 3, 5)));
      expect(nextDay.secondsFor('com.a'), 0);
    });
  });

  group('evaluateBlock', () {
    test('blocks an app from the default blocklist', () {
      final decision = evaluateBlock(
        packageName: 'com.pornhub.android',
        blockedApps: DefaultBlocklists.apps,
        keywords: const [],
      );
      expect(decision.blocked, isTrue);
      expect(decision.reason, BlockReason.app);
    });

    test('blocks outside the allowed hours and allows inside', () {
      const schedules = {
        'com.instagram.android': ScheduleWindow(18 * 60, 20 * 60),
      };
      expect(
        evaluateBlock(
          packageName: 'com.instagram.android',
          blockedApps: const [],
          keywords: const [],
          schedules: schedules,
          now: DateTime(2026, 1, 1, 19),
        ).reason,
        isNull,
      );
      expect(
        evaluateBlock(
          packageName: 'com.instagram.android',
          blockedApps: const [],
          keywords: const [],
          schedules: schedules,
          now: DateTime(2026, 1, 1, 12),
        ).reason,
        BlockReason.schedule,
      );
    });

    test('blocks once the daily limit is used up', () {
      final used = UsageCounter.empty
          .copyAt(DateTime(2026, 1, 1))
          .add('com.a', 30 * 60);
      expect(
        evaluateBlock(
          packageName: 'com.a',
          blockedApps: const [],
          keywords: const [],
          dailyLimitsMinutes: const {'com.a': 30},
          usage: used,
          now: DateTime(2026, 1, 1, 15),
        ).reason,
        BlockReason.dailyLimit,
      );

      final under = UsageCounter.empty
          .copyAt(DateTime(2026, 1, 1))
          .add('com.a', 60);
      expect(
        evaluateBlock(
          packageName: 'com.a',
          blockedApps: const [],
          keywords: const [],
          dailyLimitsMinutes: const {'com.a': 30},
          usage: under,
          now: DateTime(2026, 1, 1, 15),
        ).blocked,
        isFalse,
      );
    });

    test('distinguishes a URL hit from a text hit', () {
      final url = evaluateBlock(
        packageName: 'com.android.chrome',
        blockedApps: const [],
        keywords: const ['porn'],
        url: 'https://example.test/porn',
      );
      expect(url.reason, BlockReason.url);
      expect(url.detail, 'porn');

      final text = evaluateBlock(
        packageName: 'com.android.chrome',
        blockedApps: const [],
        keywords: const ['porn'],
        text: 'watch porn now',
      );
      expect(text.reason, BlockReason.keyword);
    });

    test('the app block outranks keywords', () {
      final decision = evaluateBlock(
        packageName: 'com.pornhub.android',
        blockedApps: DefaultBlocklists.apps,
        keywords: const ['porn'],
        text: 'porn',
      );
      expect(decision.reason, BlockReason.app);
    });

    test('private mode blocks when flagged', () {
      expect(
        evaluateBlock(
          packageName: 'com.android.chrome',
          blockedApps: const [],
          keywords: const [],
          privateMode: true,
        ).reason,
        BlockReason.privateMode,
      );
    });

    test('URL patterns catch search queries and the .xxx TLD', () {
      const patterns = ['*q=*porn*', '*.xxx'];
      expect(
        evaluateBlock(
          packageName: 'com.android.chrome',
          blockedApps: const [],
          keywords: const [],
          blockedUrlPatterns: patterns,
          url: 'https://www.bing.com/search?q=free+porn',
        ).reason,
        BlockReason.url,
      );
      expect(
        evaluateBlock(
          packageName: 'com.android.chrome',
          blockedApps: const [],
          keywords: const [],
          blockedUrlPatterns: patterns,
          url: 'https://example.xxx/watch',
        ).reason,
        BlockReason.url,
      );
      expect(
        evaluateBlock(
          packageName: 'com.android.chrome',
          blockedApps: const [],
          keywords: const [],
          blockedUrlPatterns: patterns,
          url: 'https://www.bing.com/search?q=hijab+tutorial',
        ).blocked,
        isFalse,
      );
    });

    test('URL patterns never inspect page text', () {
      expect(
        evaluateBlock(
          packageName: 'com.android.chrome',
          blockedApps: const [],
          keywords: const [],
          blockedUrlPatterns: const ['*porn*'],
          url: 'https://news.example/health',
          text: 'a report about porn addiction',
        ).blocked,
        isFalse,
      );
    });

    test('ordinary pages pass every filter', () {
      final decision = evaluateBlock(
        packageName: 'com.android.chrome',
        blockedApps: DefaultBlocklists.apps,
        keywords: DefaultBlocklists.keywords,
        url: 'https://news.example/',
        text: 'Hijab fashion guide',
      );
      expect(decision.blocked, isFalse);
    });
  });

  test('the bundled lists ship with entries', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Sorted 64-bit hashes, one per bundled domain.
    final index = await rootBundle.load('assets/blocklists/adult_domains.idx');
    expect(index.lengthInBytes % 8, 0);
    expect(index.lengthInBytes ~/ 8, greaterThan(900000));

    final patterns = await rootBundle
        .loadString('assets/blocklists/adult_url_patterns.txt');
    final parsedPatterns = patterns
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .toList();
    expect(parsedPatterns, contains('*.xxx'));
    expect(parsedPatterns, contains('*porn*'));

    final imagePatterns = await rootBundle
        .loadString('assets/blocklists/search_image_patterns.txt');
    expect(imagePatterns, contains('*tbm=isch*'));
  });

  test('the default blocklists are populated and well formed', () {
    expect(DefaultBlocklists.apps, isNotEmpty);
    expect(DefaultBlocklists.apps, contains('com.pornhub.android'));
    expect(DefaultBlocklists.keywords, isNotEmpty);
    expect(DefaultBlocklists.keywords, contains('onlyfans'));
    expect(
      DefaultBlocklists.presets.map((preset) => preset.name),
      containsAll(<String>['Porn', 'Gambling', 'Violence', 'Drugs']),
    );
    for (final package in DefaultBlocklists.apps) {
      expect(package.contains('.'), isTrue, reason: package);
    }
  });
}
