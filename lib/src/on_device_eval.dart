import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;

import 'detection_engine.dart';
import 'policy.dart';

/// Per-class result of running the bundled eval set through the real runtime.
class EvalClassStats {
  final String name;
  int total = 0;
  int blurred = 0;

  EvalClassStats(this.name);

  double get rate => total == 0 ? 0 : blurred / total;
}

class OnDeviceEvalReport {
  final List<EvalClassStats> classes;
  final Map<String, int> perClassTotal;
  final Map<String, int> perClassBlurred;
  final int elapsedMs;
  final String? error;

  const OnDeviceEvalReport({
    required this.classes,
    required this.perClassTotal,
    required this.perClassBlurred,
    required this.elapsedMs,
    this.error,
  });

  double get recall => _rate(const ['nude', 'bikini_swimwear']);
  double get falsePositiveRate =>
      _rate(const ['benign_person', 'benign_scene', 'fully_clothed', 'abaya_niqab']);
  int get forbiddenBlurred => perClassBlurred['beard_headscarf'] ?? 0;

  double _rate(List<String> names) {
    var total = 0;
    var blurred = 0;
    for (final name in names) {
      total += perClassTotal[name] ?? 0;
      blurred += perClassBlurred[name] ?? 0;
    }
    return total == 0 ? 0 : blurred / total;
  }

  String get summary => 'recall ${(recall * 100).toStringAsFixed(1)}% · '
      'FP ${(falsePositiveRate * 100).toStringAsFixed(1)}% · '
      '${elapsedMs}ms';
}

/// Runs `tests/eval_set` through [FramePreprocessor] + [DetectionEngine] +
/// [BlurPolicy] — the exact runtime path, capture excluded.
///
/// If this does not match `tools/evaluate.py` within two points, the runtime
/// and the eval oracle have diverged again.
class OnDeviceEval {
  static const String labelsAsset = 'tests/eval_set/labels.jsonl';
  static const String _images = 'tests/eval_set/images';

  /// [loadBytes] lets tests read from disk; the app uses bundled assets.
  static Future<OnDeviceEvalReport> run({
    required DetectionEngine engine,
    required BlurConfig config,
    Future<Uint8List> Function(String name)? loadBytes,
    void Function(int done, int total)? onProgress,
    /// Live ML Kit boxes (normalised to the source image). Android only; null
    /// in tests and on the host.
    Future<List<Rect>> Function(Uint8List bytes)? detectFaces,
  }) async {
    final started = DateTime.now();
    final labels = await _loadLabels();
    final names = labels.keys.toList()..sort();
    final total = names.length;

    final stats = <String, EvalClassStats>{};
    final totals = <String, int>{};
    final blurredByClass = <String, int>{};

    for (var i = 0; i < total; i++) {
      final name = names[i];
      final cls = labels[name] as String;
      final bytes = loadBytes == null
          ? (await rootBundle.load('$_images/$name')).buffer.asUint8List()
          : await loadBytes(name);

      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        onProgress?.call(i + 1, total);
        continue;
      }
      final oriented = img.bakeOrientation(decoded);
      final normalisedFaces = detectFaces == null
          ? const <Rect>[]
          : await detectFaces(bytes);
      final faces = [
        for (final face in normalisedFaces)
          Rect.fromLTRB(
            face.left * oriented.width,
            face.top * oriented.height,
            face.right * oriented.width,
            face.bottom * oriented.height,
          ),
      ];
      final frame = await engine.analyze(oriented, faces: faces);
      final regions = BlurPolicy(config).apply(frame);

      totals[cls] = (totals[cls] ?? 0) + 1;
      if (regions.isNotEmpty) {
        blurredByClass[cls] = (blurredByClass[cls] ?? 0) + 1;
      }
      stats.putIfAbsent(cls, () => EvalClassStats(cls))
        ..total += 1
        ..blurred += regions.isEmpty ? 0 : 1;
      onProgress?.call(i + 1, total);
    }

    return OnDeviceEvalReport(
      classes: stats.values.toList()..sort((a, b) => a.name.compareTo(b.name)),
      perClassTotal: totals,
      perClassBlurred: blurredByClass,
      elapsedMs: DateTime.now().difference(started).inMilliseconds,
    );
  }

  static Future<Map<String, String>> _loadLabels() async {
    final raw = await rootBundle.loadString(labelsAsset);
    final labels = <String, String>{};
    for (final line in const LineSplitter().convert(raw)) {
      if (line.trim().isEmpty) continue;
      final entry = jsonDecode(line) as Map<String, dynamic>;
      labels[entry['image'] as String] = entry['class'] as String;
    }
    return labels;
  }
}
