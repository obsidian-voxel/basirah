import 'keyword_blocker.dart';

/// Why a screen was blocked. Wire names match the strings the Android service
/// records in the event log (`EventLog.append`), so analytics can group events
/// without a translation table.
enum BlockReason {
  visual('visual', 'Visual AI'),
  app('app', 'Blocked app'),
  keyword('keyword', 'Blocked keyword'),
  url('url', 'Blocked URL'),
  schedule('schedule', 'Outside allowed hours'),
  dailyLimit('dailyLimit', 'Daily limit reached'),
  privateMode('privateMode', 'Private mode'),
  focus('focus', 'Focus session'),
  prayer('prayer', 'Prayer time'),
  splitScreen('splitScreen', 'Split screen'),
  newApp('newApp', 'Installed after setup'),
  newBrowser('newBrowser', 'Browser installed after setup'),
  inAppBrowser('inAppBrowser', 'In-app browser'),
  unsupportedBrowser('unsupportedBrowser', 'Unsupported browser'),
  settingsGuard('settingsGuard', 'Protection settings');

  const BlockReason(this.wire, this.label);

  /// Stable identifier shared with the native service.
  final String wire;

  /// Human-readable label for analytics and the block overlay.
  final String label;

  static BlockReason? fromWire(String? value) {
    if (value == null) return null;
    for (final reason in values) {
      if (reason.wire == value) return reason;
    }
    return null;
  }
}

/// Outcome of the non-visual filters. `reason == null` means "allow".
class BlockDecision {
  final BlockReason? reason;

  /// Extra context: the matched keyword, package name or schedule label.
  final String? detail;

  const BlockDecision.allow()
      : reason = null,
        detail = null;

  const BlockDecision.block(this.reason, {this.detail});

  bool get blocked => reason != null;

  @override
  String toString() =>
      blocked ? 'BlockDecision(${reason!.wire}, $detail)' : 'BlockDecision(allow)';
}

/// A daily allowed window, in minutes since midnight.
///
/// `start == end` means "no restriction". `start > end` wraps midnight, so
/// 22:00–06:00 allows 23:00 and 05:00 but blocks 12:00.
class ScheduleWindow {
  final int startMinute;
  final int endMinute;

  const ScheduleWindow(this.startMinute, this.endMinute);

  bool get isAlwaysAllowed => startMinute == endMinute;

  bool isAllowed(DateTime now) {
    if (isAlwaysAllowed) return true;
    final minute = now.hour * 60 + now.minute;
    if (startMinute < endMinute) {
      return minute >= startMinute && minute < endMinute;
    }
    return minute >= startMinute || minute < endMinute;
  }

  String get label =>
      '${_clock(startMinute)}–${_clock(endMinute)}${isAlwaysAllowed ? ' (always)' : ''}';

  Map<String, int> toJson() => {'start': startMinute, 'end': endMinute};

  static ScheduleWindow? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final start = raw['start'];
    final end = raw['end'];
    if (start is! num || end is! num) return null;
    return ScheduleWindow(
      start.toInt().clamp(0, 1439),
      end.toInt().clamp(0, 1439),
    );
  }

  static String _clock(int minute) {
    final h = (minute ~/ 60).toString().padLeft(2, '0');
    final m = (minute % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// Per-day foreground usage. The date key makes the reset automatic: a counter
/// written yesterday is discarded instead of accumulating forever.
class UsageCounter {
  final String dateKey;
  final Map<String, int> secondsByPackage;

  const UsageCounter({required this.dateKey, required this.secondsByPackage});

  static const empty = UsageCounter(dateKey: '', secondsByPackage: {});

  int secondsFor(String packageName) => secondsByPackage[packageName] ?? 0;

  bool isExhausted(String packageName, int limitMinutes) {
    if (limitMinutes <= 0) return false;
    return secondsFor(packageName) >= limitMinutes * 60;
  }

  UsageCounter add(String packageName, int seconds) => UsageCounter(
        dateKey: dateKey,
        secondsByPackage: {
          ...secondsByPackage,
          packageName: secondsFor(packageName) + seconds,
        },
      );

  /// Returns an empty counter when [now] is a different day than [dateKey].
  UsageCounter rollOver(DateTime now) =>
      dateKey == dayKeyOf(now) ? this : UsageCounter.empty.copyAt(now);

  UsageCounter copyAt(DateTime now) =>
      UsageCounter(dateKey: dayKeyOf(now), secondsByPackage: {});

  static String dayKeyOf(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}

/// Unified non-visual decision, in priority order:
/// app blocklist → schedule → daily limit → private mode → URL → keyword.
///
/// The accessibility service applies the same order natively. This function is
/// the tested reference and what Settings previews, so the two can be compared
/// without a device.
/// Host of [url], or '' when it has none. Mirrors `BlockPrefs.hostOf`.
String hostOf(String url) {
  var value = url.trim().toLowerCase();
  final scheme = value.indexOf('://');
  if (scheme >= 0) value = value.substring(scheme + 3);
  value = value.split('/').first.split('?').first.split('#').first;
  final at = value.lastIndexOf('@');
  if (at >= 0) value = value.substring(at + 1);
  final colon = value.lastIndexOf(':');
  if (colon >= 0) value = value.substring(0, colon);
  return normalizeHost(value);
}

/// Canonical host form, mirroring `BlockPrefs.normalizeHost` in Kotlin.
///
/// A trailing dot is a legal absolute name (`example.com.`), and percent
/// escapes reach the server as plain bytes (`porn%68ub.com`), so neither may
/// change the host a rule sees. Punycode folding happens natively, where the
/// 952k-domain index lives.
String normalizeHost(String raw) {
  var value = raw.trim().toLowerCase();
  value = value.replaceFirst(RegExp(r'^\.+'), '');
  value = value.replaceFirst(RegExp(r'\.+$'), '');
  if (value.isEmpty || !value.contains('%')) return value;
  try {
    return Uri.decodeComponent(value.replaceAll('+', '%2B'));
  } catch (_) {
    return value;
  }
}

/// The configured domain that owns [url]'s host, or null. Suffix matching
/// covers every subdomain of a listed domain.
String? matchingDomain(Iterable<String> domains, String url) {
  if (url.isEmpty) return null;
  final host = hostOf(url);
  if (host.isEmpty) return null;
  for (final domain in domains) {
    if (host == domain || host.endsWith('.$domain')) return domain;
  }
  return null;
}

BlockDecision evaluateBlock({
  required String packageName,
  required Iterable<String> blockedApps,
  required Iterable<String> keywords,
  Iterable<String> blockedDomains = const [],
  Iterable<String> allowlistedDomains = const [],
  Iterable<String> blockedUrlPatterns = const [],
  String url = '',
  String text = '',
  Map<String, ScheduleWindow> schedules = const {},
  Map<String, int> dailyLimitsMinutes = const {},
  UsageCounter usage = UsageCounter.empty,
  bool privateMode = false,
  bool wholeWord = false,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();

  // 1. App blocklist: the most reliable rule, no content inspection needed.
  if (blockedApps.contains(packageName)) {
    return BlockDecision.block(BlockReason.app, detail: packageName);
  }

  // 2. Schedule: an app with a window is only usable inside it.
  final window = schedules[packageName];
  if (window != null && !window.isAllowed(at)) {
    return BlockDecision.block(BlockReason.schedule, detail: window.label);
  }

  // 3. Daily limit: counts foreground seconds since midnight.
  final limit = dailyLimitsMinutes[packageName] ?? 0;
  if (usage.isExhausted(packageName, limit)) {
    return BlockDecision.block(BlockReason.dailyLimit, detail: '$limit min');
  }

  // 4. Private browsing: conservative, only when the caller is confident.
  if (privateMode) {
    return const BlockDecision.block(BlockReason.privateMode);
  }

  // 5. A trusted site wins over every site list: the bundled hash index has
  //    no way to express an exception.
  final allowlisted = matchingDomain(allowlistedDomains, url) != null;

  // 6. Bundled adult domains and URL patterns, then URL keywords, then visible
  //    text, so analytics can tell the three apart.
  if (!allowlisted) {
    final domainHit = matchingDomain(blockedDomains, url);
    if (domainHit != null) {
      return BlockDecision.block(BlockReason.url, detail: domainHit);
    }
    // Patterns carry query strings and TLDs a host suffix cannot express
    // (`*q=*porn*`, `*.xxx`), so they are matched against the whole URL and
    // never against page text.
    final patternHit = KeywordBlocker(blockedUrlPatterns).match(url);
    if (patternHit != null) {
      return BlockDecision.block(BlockReason.url, detail: patternHit.keyword);
    }
    final urlHit = KeywordBlocker(keywords, wholeWord: wholeWord).match(url);
    if (urlHit != null) {
      return BlockDecision.block(BlockReason.url, detail: urlHit.keyword);
    }
  }
  final textHit = KeywordBlocker(keywords, wholeWord: wholeWord).match(text);
  if (textHit != null) {
    return BlockDecision.block(BlockReason.keyword, detail: textHit.keyword);
  }

  return const BlockDecision.allow();
}

/// Keyword pack shipped with Settings.
class KeywordPreset {
  final String name;
  final List<String> keywords;
  const KeywordPreset(this.name, this.keywords);
}

/// Defaults so a fresh install is protected before the user configures
/// anything. "Blocked apps" and "Blocked keywords" are seeded from these on
/// first launch and can then be edited or trimmed.
abstract final class DefaultBlocklists {
  /// Known adult/dating plus the high-traffic feeds that host unmoderated
  /// explicit content. Kept deliberately short; the user can add more.
  static const apps = <String>[
    'com.pornhub.android',
    'com.tinder',
    'com.bumble',
    'com.onlyfans',
    'com.grindr',
    'com.twitter.android',
    'com.reddit.frontpage',
  ];

  /// High-risk terms that appear in the URL, title or visible text of explicit
  /// pages. Wildcards are supported (`xxx*`).
  static const porn = <String>[
    'porn',
    'xxx*',
    'nude',
    'nudes',
    'onlyfans',
    'nsfw',
    'hentai',
    'camgirl',
    'sex video',
    'incognito',
    'private mode',
  ];

  static const gambling = <String>[
    'casino',
    'sportsbook',
    'betting',
    'poker',
    'roulette',
    'jackpot',
    'gambling',
  ];

  static const violence = <String>[
    'gore',
    'beheading',
    'snuff',
    'massacre',
    'execution video',
    'brutal death',
  ];

  static const drugs = <String>[
    'buy cocaine',
    'buy heroin',
    'buy weed',
    'buy mdma',
    'darknet market',
    'drug market',
  ];

  static const presets = <KeywordPreset>[
    KeywordPreset('Porn', porn),
    KeywordPreset('Gambling', gambling),
    KeywordPreset('Violence', violence),
    KeywordPreset('Drugs', drugs),
  ];

  static const keywords = porn;
}
