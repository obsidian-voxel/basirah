import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:haram_blur/src/detection_data.dart';
import 'package:haram_blur/src/policy.dart';

const size = Size(1000, 1000);

Rect box(double l, double t, double r, double b) => Rect.fromLTRB(l, t, r, b);

FrameResult frame({
  double score = 0,
  List<PersonVerdict> persons = const [],
  List<NudityHit> hits = const [],
  Size imageSize = size,
}) =>
    FrameResult(
      imageSize: imageSize,
      nsfwScore: score,
      persons: persons,
      nudityHits: hits,
    );

void main() {
  test('a high nudity score blocks the whole frame', () {
    final policy = BlurPolicy(const BlurConfig(nsfwFrameGate: 0.7));
    final out = policy.apply(frame(score: 0.9));

    expect(out, hasLength(1));
    expect(out.first.kind, BlurKind.nudity);
  });

  test('a score below the gate produces no whole-frame region', () {
    final policy = BlurPolicy(const BlurConfig(nsfwFrameGate: 0.7));
    final out = policy.apply(frame(score: 0.5));

    expect(out.where((r) => r.kind == BlurKind.nudity), isEmpty);
  });

  test('awrah band fires only when the band is mostly uncovered skin', () {
    final policy = BlurPolicy(const BlurConfig(awrahSkinThreshold: 0.7));
    final out = policy.apply(frame(persons: const [
      PersonVerdict(
          box: Rect.fromLTRB(100, 100, 400, 500),
          awrahSkinFraction: 0.8,
          exposedRatio: 0.0),
      PersonVerdict(
          box: Rect.fromLTRB(500, 100, 800, 500),
          awrahSkinFraction: 0.1,
          exposedRatio: 0.0),
    ]));

    final awrah = out.where((r) => r.kind == BlurKind.awrah).toList();
    expect(awrah, hasLength(1));
    // The band triggers, but the whole person box is blurred, padded by 5% of
    // the box: 100,100..400,500 → 85,80..415,520.
    expect(awrah.first.rect.top, closeTo(80, 1));
    expect(awrah.first.rect.bottom, closeTo(520, 1));
    expect(awrah.first.rect.left, closeTo(85, 1));
    expect(awrah.first.rect.right, closeTo(415, 1));
  });

  test('a band trigger blurs the whole person, never just the band', () {
    final policy = BlurPolicy(const BlurConfig(awrahSkinThreshold: 0.5));
    final out = policy.apply(frame(persons: const [
      PersonVerdict(
          box: Rect.fromLTRB(100, 100, 400, 500),
          awrahSkinFraction: 0.9,
          exposedRatio: 0.0),
    ]));

    final region = out.single;
    expect(region.rect.top, closeTo(80, 1));
    expect(region.rect.bottom, closeTo(520, 1));
  });

  test('exposed skin fires when skin ratio exceeds threshold', () {
    final policy = BlurPolicy(const BlurConfig(skinThreshold: 0.5));
    final out = policy.apply(frame(persons: const [
      PersonVerdict(
          box: Rect.fromLTRB(100, 100, 400, 500),
          awrahSkinFraction: 0.0,
          exposedRatio: 0.7),
      PersonVerdict(
          box: Rect.fromLTRB(500, 100, 800, 500),
          awrahSkinFraction: 0.0,
          exposedRatio: 0.2),
    ]));

    final exposed = out.where((r) => r.kind == BlurKind.awrah).toList();
    expect(exposed, hasLength(1));
    expect(exposed.first.evidence, startsWith('Exposed skin'));
  });

  test('level 10 blocks the whole frame on borderline score plus skin', () {
    final policy = BlurPolicy(BlurConfig.forSensitivity(10));
    final out = policy.apply(frame(score: 0.35, persons: const [
      PersonVerdict(
          box: Rect.fromLTRB(100, 100, 400, 500),
          awrahSkinFraction: 0.0,
          exposedRatio: 0.06),
    ]));

    expect(out, hasLength(1));
    expect(out.single.rule, 'borderline_full');
    expect(out.single.kind, BlurKind.nudity);
    expect(out.single.rect, Rect.fromLTWH(0, 0, 1000, 1000));
  });

  test('a portrait contributes no borderline evidence', () {
    final policy = BlurPolicy(BlurConfig.forSensitivity(10));
    final out = policy.apply(frame(score: 0.25, persons: const [
      PersonVerdict(
          box: Rect.fromLTRB(100, 10, 180, 470),
          awrahSkinFraction: 0.0,
          exposedRatio: 0.10),
    ]));

    expect(out, isEmpty);
  });

  test('the borderline rule stays off at level 9', () {
    final policy = BlurPolicy(BlurConfig.forSensitivity(9));
    final out = policy.apply(frame(score: 0.35, persons: const [
      PersonVerdict(
          box: Rect.fromLTRB(100, 100, 400, 500),
          awrahSkinFraction: 0.0,
          exposedRatio: 0.06),
    ]));

    expect(out, isEmpty);
  });

  test('regions are clamped to the image bounds', () {
    final policy = BlurPolicy(const BlurConfig(awrahSkinThreshold: 0.5));
    final out = policy.apply(frame(persons: const [
      PersonVerdict(
          box: Rect.fromLTRB(-50, -50, 150, 150),
          awrahSkinFraction: 1,
          exposedRatio: 0.0),
    ]));

    expect(out, isNotEmpty);
    for (final region in out) {
      expect(region.rect.left, greaterThanOrEqualTo(0));
      expect(region.rect.top, greaterThanOrEqualTo(0));
      expect(region.rect.right, lessThanOrEqualTo(1000));
      expect(region.rect.bottom, lessThanOrEqualTo(1000));
      expect(region.rect.width, greaterThan(0));
      expect(region.rect.height, greaterThan(0));
      expect(region.rect.isFinite, isTrue);
    }
  });

  test('low-score region hits are suppressed', () {
    final policy = BlurPolicy(const BlurConfig());
    final out = policy.apply(frame(hits: [
      const NudityHit(
        box: Rect.fromLTRB(100, 100, 200, 200),
        label: 'BUTTOCKS_EXPOSED',
        score: 0.2,
      ),
    ]));

    expect(out, isEmpty);
  });

  test('near-duplicate person regions are de-duplicated', () {
    final policy = BlurPolicy(const BlurConfig(awrahSkinThreshold: 0.5));
    final out = policy.apply(frame(persons: const [
      PersonVerdict(
          box: Rect.fromLTRB(100, 100, 400, 500),
          awrahSkinFraction: 0.9,
          exposedRatio: 0.0),
      PersonVerdict(
          box: Rect.fromLTRB(102, 101, 399, 499),
          awrahSkinFraction: 0.9,
          exposedRatio: 0.0),
    ]));

    expect(out.where((r) => r.kind == BlurKind.awrah), hasLength(1));
  });

  test('zero-sized images produce no regions', () {
    final policy = BlurPolicy(const BlurConfig());
    expect(
      policy.apply(frame(score: 0.99, imageSize: Size.zero)),
      isEmpty,
    );
  });

  test('sensitivity maps to monotonically lower thresholds', () {
    final configs = List.generate(10, (i) => BlurConfig.forSensitivity(i + 1));
    for (var i = 0; i < configs.length - 1; i++) {
      expect(configs[i].nsfwFrameGate, greaterThan(configs[i + 1].nsfwFrameGate));
      expect(configs[i].awrahSkinThreshold,
          greaterThan(configs[i + 1].awrahSkinThreshold));
      expect(configs[i].skinThreshold,
          greaterThanOrEqualTo(configs[i + 1].skinThreshold));
    }
  });

  test('awrah bands are null for degenerate boxes', () {
    expect(awrahBand(Rect.fromLTRB(0, 0, 100, 0)), isNull);
    expect(awrahBand(Rect.fromLTRB(0, 0, 0, 100)), isNull);
  });
}
