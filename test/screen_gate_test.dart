import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:haram_blur/src/detection_data.dart';
import 'package:haram_blur/src/detection_engine.dart';
import 'package:haram_blur/src/policy.dart';
import 'package:haram_blur/src/screen_gate.dart';

/// Replaces only the models. The whole `analyzeScreen` path — gate, content
/// crops, awrah flag, segmentation result handling and policy — still runs.
class _FakeEngine extends DetectionEngine {
  _FakeEngine({required this.gate, required this.persons});

  final double gate;
  final List<PersonVerdict> persons;

  @override
  Future<void> initialize() async {}

  @override
  double nsfwScoreOf(img.Image image) => gate;

  @override
  Future<FrameResult> analyze(
    img.Image image, {
    List<Rect> faces = const [],
  }) async =>
      FrameResult(
        imageSize: Size(image.width.toDouble(), image.height.toDouble()),
        nsfwScore: gate,
        persons: persons,
      );

  @override
  void dispose() {}
}

void main() {
  // A real bikini image from the eval set, used as the screen/frame input.
  final bikini = img.decodeImage(
    File('tests/eval_set/images/coco_010.jpg').readAsBytesSync(),
  )!;
  final box = Rect.fromLTRB(
    bikini.width * 0.2,
    bikini.height * 0.2,
    bikini.width * 0.8,
    bikini.height * 0.85,
  );
  // Exposed skin above the level-10 threshold; band skin below its trigger.
  final person = PersonVerdict(
    box: box,
    awrahSkinFraction: 0.0,
    exposedRatio: 0.80,
  );

  test('level 10 uses the strict skin threshold and gate', () {
    expect(BlurConfig.forSensitivity(10).skinThreshold, closeTo(0.20, 0.001));
    expect(BlurConfig.forSensitivity(10).nsfwFrameGate, closeTo(0.50, 0.001));
  });

  test('high-confidence nudity blocks at every sensitivity level', () {
    for (var level = 1; level <= 10; level++) {
      final config = BlurConfig.forSensitivity(level);
      // Above the highest configured gate (level 1 is 0.85).
      expect(nsfwBlocks(0.82, config), isTrue, reason: 'level $level');
      expect(nsfwBlocks(0.99, config), isTrue, reason: 'level $level');
    }
  });

  test('0.75 always blocks at every sensitivity level', () {
    for (var level = 1; level <= 10; level++) {
      final config = BlurConfig.forSensitivity(level);
      expect(nsfwBlocks(0.75, config), isTrue, reason: 'level $level');
      expect(nsfwBlocks(0.95, config), isTrue, reason: 'level $level');
      expect(nsfwBlocks(0.45, config), isFalse, reason: 'level $level');
    }
  });

  test('each level gate still decides below 0.75', () {
    // Level 1's gate is 0.85, level 10's is 0.50.
    expect(nsfwBlocks(0.60, BlurConfig.forSensitivity(1)), isFalse);
    expect(nsfwBlocks(0.60, BlurConfig.forSensitivity(10)), isTrue);
  });

  test('level 10 blocks a borderline score that comes with skin', () async {
    final engine = _FakeEngine(gate: 0.35, persons: [
      PersonVerdict(box: box, awrahSkinFraction: 0.0, exposedRatio: 0.06),
    ]);
    final result = await analyzeScreen(
      engine,
      bikini,
      BlurConfig.forSensitivity(10),
      allowAwrah: true,
    );

    expect(result.blurred, isTrue);
    expect(result.regions.single.kind, BlurKind.nudity);
    expect(result.regions.single.rule, 'borderline_full');
  });

  test('the borderline rule does not fire below level 10', () async {
    final engine = _FakeEngine(gate: 0.35, persons: [
      PersonVerdict(box: box, awrahSkinFraction: 0.0, exposedRatio: 0.06),
    ]);
    final result = await analyzeScreen(
      engine,
      bikini,
      BlurConfig.forSensitivity(9),
      allowAwrah: true,
    );

    expect(result.regions, isEmpty);
    expect(result.blurred, isFalse);
  });

  test('level 1 blocks the borderline nudity score it used to miss', () async {
    final engine = _FakeEngine(gate: 0.82, persons: const []);
    final result = await analyzeScreen(
      engine,
      bikini,
      BlurConfig.forSensitivity(1),
      allowAwrah: false,
    );

    expect(result.blurred, isTrue);
    expect(result.regions.single.kind, BlurKind.nudity);
  });

  test('bikini exposure returns a region when awrah is allowed', () async {
    final engine = _FakeEngine(gate: 0.05, persons: [person]);
    final result = await analyzeScreen(
      engine,
      bikini,
      BlurConfig.forSensitivity(10),
      allowAwrah: true,
    );

    expect(result.regions, isNotEmpty);
    expect(result.blurred, isTrue);
    expect(result.regions.first.kind, BlurKind.awrah);
    // The policy blurs the whole person box (padded by 5%), not just the band.
    expect(result.regions.first.rect.contains(box.center), isTrue);
    expect(result.regions.first.rect.width, greaterThan(box.width));
    expect(result.regions.first.rect.height, greaterThan(box.height));
  });

  test('the same evidence returns no region when awrah is disabled', () async {
    final engine = _FakeEngine(gate: 0.05, persons: [person]);
    final result = await analyzeScreen(
      engine,
      bikini,
      BlurConfig.forSensitivity(10),
      allowAwrah: false,
    );

    expect(result.regions, isEmpty);
    expect(result.blurred, isFalse);
    // People are still detected and reported; only the awrah rules are off.
    expect(result.personCount, 1);
  });

  test('nudity still blocks when awrah is disabled', () async {
    final engine = _FakeEngine(gate: 0.99, persons: [person]);
    final result = await analyzeScreen(
      engine,
      bikini,
      BlurConfig.forSensitivity(10),
      allowAwrah: false,
    );

    expect(result.regions, hasLength(1));
    expect(result.regions.first.kind, BlurKind.nudity);
  });
}
