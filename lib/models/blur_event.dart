/// One recorded blur event produced by the system-wide detection pipeline.
class BlurEvent {
  final DateTime timestamp;

  /// Package of the app in the foreground when the blur triggered.
  final String packageName;

  /// "nsfw" (whole-frame nudity gate), "closed_app" (nudity detected but the
  /// screen could not be covered, so the app was closed) or "exposure".
  final String reason;

  final double confidence; // 0..1

  /// Secondary measurement, e.g. the exposed-skin ratio for a borderline
  /// event that did not reach the block threshold.
  final double? metric;

  const BlurEvent({
    required this.timestamp,
    required this.packageName,
    required this.reason,
    required this.confidence,
    this.metric,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'packageName': packageName,
        'reason': reason,
        'confidence': confidence,
        'metric': metric,
      };

  factory BlurEvent.fromJson(Map<String, dynamic> json) => BlurEvent(
        timestamp: DateTime.parse(json['timestamp'] as String),
        packageName: (json['packageName'] as String?) ?? 'unknown',
        reason: (json['reason'] as String?) ?? 'nsfw',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
        metric: (json['metric'] as num?)?.toDouble(),
      );

  /// Parses an event reported by the Android service (`{"t","p","r","c"}`),
  /// which uses epoch milliseconds to stay cheap to serialize.
  factory BlurEvent.fromNative(Map<dynamic, dynamic> json) => BlurEvent(
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          (json['t'] as num?)?.toInt() ?? 0,
        ),
        packageName: (json['p'] as String?) ?? 'unknown',
        reason: (json['r'] as String?) ?? 'nsfw',
        confidence: ((json['c'] as num?)?.toDouble() ?? 0)
            .clamp(0.0, 1.0)
            .toDouble(),
        metric: (json['m'] as num?)?.toDouble(),
      );

  /// Stable identity used to merge events pulled from the service with the
  /// local cache without double counting.
  String get key => '${timestamp.millisecondsSinceEpoch}|$packageName';

  String get dayKey =>
      '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';

  /// `HH:mm` for compact lists.
  String get timeLabel =>
      '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';

  String get reasonLabel => switch (reason) {
        'exposure' => 'Exposed skin',
        'exposed skin' => 'Exposed skin',
        'nsfw' => 'Nudity detected',
        'closed_app' => 'App closed (blur unavailable)',
        'app' => 'Blocked app',
        'keyword' => 'Blocked keyword',
        'url' => 'Blocked URL',
        'schedule' => 'Outside allowed hours',
        'dailyLimit' => 'Daily limit reached',
        'privateMode' => 'Private mode',
        'panic' => 'Asked for support',
        _ => reason,
      };

  @override
  String toString() =>
      'BlurEvent(${timestamp.toIso8601String()}, $packageName, $reason, $confidence)';
}
