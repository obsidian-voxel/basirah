import 'dart:convert';

import 'package:haram_blur/models/blur_event.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists blur events locally (shared_preferences) for analytics and
/// accountability dashboards. All data stays on-device.
class BlurEventStore {
  static const _key = 'blur_events';
  static const _maxEvents = 500;

  final SharedPreferences _prefs;

  BlurEventStore(this._prefs);

  /// Newest first.
  List<BlurEvent> get events {
    final raw = _prefs.getStringList(_key) ?? <String>[];
    final out = <BlurEvent>[];
    for (final encoded in raw) {
      try {
        out.add(BlurEvent.fromJson(jsonDecode(encoded) as Map<String, dynamic>));
      } catch (_) {
        // Skip corrupt entries instead of losing the whole history.
      }
    }
    out.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return out;
  }

  Future<void> add(BlurEvent event) async {
    final merged = <String, BlurEvent>{
      for (final e in events) e.key: e,
      event.key: event,
    }.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    await _write(merged);
  }

  /// Merges a batch of events (e.g. pulled from the Android service) into the
  /// cache, de-duplicating by [BlurEvent.key].
  Future<void> merge(Iterable<BlurEvent> incoming) async {
    if (incoming.isEmpty) return;
    final merged = <String, BlurEvent>{
      for (final e in events) e.key: e,
      for (final e in incoming) e.key: e,
    }.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    await _write(merged);
  }

  Future<void> clear() async => _prefs.remove(_key);

  Future<void> _write(List<BlurEvent> events) async {
    final capped = events.take(_maxEvents).toList();
    await _prefs.setStringList(
      _key,
      capped.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  int countToday(DateTime today) {
    final key = dayKeyOf(today);
    return events.where((e) => e.dayKey == key).length;
  }

  int get total => events.length;

  Map<String, int> countsByApp() {
    final counts = <String, int>{};
    for (final event in events) {
      counts[event.packageName] = (counts[event.packageName] ?? 0) + 1;
    }
    return counts;
  }

  /// Count per day key for the last [days] days (oldest first).
  List<int> countsForLastDays(int days, DateTime now) {
    final events = this.events;
    return List.generate(days, (i) {
      final day = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: days - 1 - i));
      final key = dayKeyOf(day);
      return events.where((e) => e.dayKey == key).length;
    });
  }

  String exportJson() {
    final payload = {
      'exportedAt': DateTime.now().toIso8601String(),
      'eventCount': events.length,
      'events': events.map((e) => e.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  static String dayKeyOf(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}
