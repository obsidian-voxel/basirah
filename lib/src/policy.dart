import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'detection_data.dart';

/// How hard the overlay obscures a region.
///
/// standard: downscale long side to 1/60 (min 8 px), no box blur.
/// strong:   1/40 (min 8 px) + one box-blur pass  (default).
/// max:      1/25 (min 8 px) + two box-blur passes.
enum BlurStrength { standard, strong, max }

/// User-tunable detection settings. Applies identically to every person
/// regardless of gender: this app blurs nudity/exposure only, never a person
/// for who they are.
class BlurConfig {
  /// Probability of nudity/sexual content above which the whole frame is
  /// blocked. 0.7 was tuned on `tests/eval_set` (96.7% recall, 0 false
  /// positives on 40 benign images).
  final double nsfwFrameGate;

  /// Fraction of uncovered skin in a person's awrah band above which the band
  /// is blurred. 0.7 keeps benign portraits, beach scenes and headscarves
  /// clean on the evaluation set.
  final double awrahSkinThreshold;

  /// Fraction of exposed skin in a person box above which the person is
  /// blurred. Lower = stricter; curves down as sensitivity increases.
  final double skinThreshold;

  /// Extra padding (fraction of region size) applied to every blur region.
  final double padding;

  /// Minimum score for an optional region detector's hits.
  final double minRegionScore;

  /// Overlay obscuration strength (also mirrored natively).
  final BlurStrength strength;

  /// Sensitivity level (1..10) the config was built for. 0 when constructed
  /// directly, which disables level-scoped rules such as the borderline gate.
  final int sensitivity;

  const BlurConfig({
    this.nsfwFrameGate = 0.70,
    this.awrahSkinThreshold = 0.70,
    this.skinThreshold = 0.60,
    this.padding = 0.05,
    this.minRegionScore = 0.60,
    this.strength = BlurStrength.strong,
    this.sensitivity = 0,
  });

  /// Maps the 1..10 strictness slider onto thresholds.
  ///
  /// Level 1 is lenient (gate 0.85 / band 0.85), level 5 is the validated
  /// default (≈0.69 / ≈0.72) and level 10 is strict (0.50 / 0.55). Higher
  /// strictness means a lower threshold and therefore more blurs.
  static BlurConfig forSensitivity(
    int level, {
    BlurStrength strength = BlurStrength.strong,
  }) {
    final clamped = level.clamp(1, 10);
    final t = (clamped - 1) / 9.0; // 0..1
    // Keep skin threshold at 0.60 for levels 1-6 to avoid false positives
    // on clothed / abaya / niqab images; lower from level 7 onwards. Level 10
    // is 0.20: with keyword/URL/app blocking in place the visual stage no
    // longer has to carry the whole load, so it stays conservative.
    final skin = clamped <= 6
        ? 0.60
        : (clamped == 10 ? 0.20 : 0.60 - 0.42 * (clamped - 6) / 4.0);
    return BlurConfig(
      nsfwFrameGate: _round(0.85 - 0.35 * t),
      awrahSkinThreshold: _round(0.85 - 0.30 * t),
      skinThreshold: _round(skin),
      strength: strength,
      sensitivity: clamped,
    );
  }

  static double _round(double value) => (value * 1000).roundToDouble() / 1000;

  /// Human-readable thresholds, e.g. `gate 69% · band 72%`.
  String get summary =>
      'gate ${(nsfwFrameGate * 100).round()}% · '
      'band ${(awrahSkinThreshold * 100).round()}% · '
      'skin ${(skinThreshold * 100).round()}% · ${strength.name}';

  BlurConfig copyWith({
    double? nsfwFrameGate,
    double? awrahSkinThreshold,
    double? skinThreshold,
    double? padding,
    double? minRegionScore,
    BlurStrength? strength,
    int? sensitivity,
  }) {
    return BlurConfig(
      nsfwFrameGate: nsfwFrameGate ?? this.nsfwFrameGate,
      awrahSkinThreshold: awrahSkinThreshold ?? this.awrahSkinThreshold,
      skinThreshold: skinThreshold ?? this.skinThreshold,
      padding: padding ?? this.padding,
      minRegionScore: minRegionScore ?? this.minRegionScore,
      strength: strength ?? this.strength,
      sensitivity: sensitivity ?? this.sensitivity,
    );
  }
}

/// Skin ratio above which a tall, narrow person box blocks on exposure.
///
/// A portrait's face and neck dominate the skin count, and a covered head can
/// still leave chin/neck above the clothing line, so a portrait is held to a
/// deliberately high floor instead of the ordinary [BlurConfig.skinThreshold].
const double portraitSkinThreshold = 0.25;

/// True when [box] is tall and narrow enough to be a portrait (h > 2w).
bool isPortraitBox(Rect box) => box.height > box.width * 2;

/// Level-10 borderline rule: a non-trivial nudity score combined with real
/// exposed skin blocks the whole frame, even when the configured gate is not
/// met. This is what catches bikinis, swimwear and suggestive poses the model
/// calls "benign". Only the strictest level applies it; lower levels keep
/// their wider margin.
bool borderlineBlocks({
  required double nsfwScore,
  required double skinRatio,
  required BlurConfig config,
}) =>
    config.sensitivity >= 10 && nsfwScore > 0.3 && skinRatio > 0.05;

/// Policy engine: unions model evidence into final blur regions per frame.
/// Coordinates are source-image pixels (`[0, width] × [0, height]`).
class BlurPolicy {
  final BlurConfig config;
  const BlurPolicy(this.config);

  /// Human-readable summary shown in the UI.
  String get summary => config.summary;

  List<BlurRegion> apply(FrameResult frame) {
    final size = frame.imageSize;
    if (size.width <= 0 || size.height <= 0) return const [];

    // 1. Whole-frame safeguard: nudity / sexual content is blocked for every
    //    user, before any per-person logic runs.
    if (frame.nsfwScore >= config.nsfwFrameGate) {
      return [
        BlurRegion(
          rect: Rect.fromLTWH(0, 0, size.width, size.height),
          kind: BlurKind.nudity,
          confidence: frame.nsfwScore,
          evidence: 'Nudity detected (whole frame)',
          rule: 'gate_full',
        ),
      ];
    }

    // 1b. Level-10 borderline rule: bikinis, swimwear and tight shorts often
    //     reach the classifier as "benign" (0.3-0.5) while a large part of the
    //     person is bare skin. At the strictest level that combination blocks
    //     the whole frame, so borderline content cannot slip under the gate.
    var frameSkin = 0.0;
    for (final person in frame.persons) {
      // A portrait only contributes evidence above the portrait floor; its
      // face-heavy ratio is not proof of exposed skin.
      if (isPortraitBox(person.box) &&
          person.exposedRatio <= portraitSkinThreshold) {
        continue;
      }
      if (person.exposedRatio > frameSkin) frameSkin = person.exposedRatio;
    }
    if (config.sensitivity >= 10) {
      debugPrint(
        'Basirah: Borderline check - NSFW: '
        '${frame.nsfwScore.toStringAsFixed(3)}, Skin: '
        '${frameSkin.toStringAsFixed(3)}',
      );
    }
    if (borderlineBlocks(
      nsfwScore: frame.nsfwScore,
      skinRatio: frameSkin,
      config: config,
    )) {
      return [
        BlurRegion(
          rect: Rect.fromLTWH(0, 0, size.width, size.height),
          kind: BlurKind.nudity,
          confidence: frame.nsfwScore,
          evidence: 'Borderline nudity with exposed skin',
          rule: 'borderline_full',
        ),
      ];
    }

    final regions = <BlurRegion>[];

    // 2. Exposed intimate regions from an optional region detector.
    for (final hit in frame.nudityHits) {
      if (hit.score < config.minRegionScore) continue;
      final padded = padRegion(hit.box, 0.18, size);
      if (padded != null) {
        regions.add(BlurRegion(
          rect: padded,
          kind: BlurKind.nudity,
          confidence: hit.score,
          evidence: 'Exposed region: ${hit.label}',
          rule: 'exposed',
        ));
      }
    }

    // 3. Awrah band: the band is the trigger, the whole person box is the
    //    blur. Blurring only the 42%-92% strip left heads, shoulders and legs
    //    readable and, on a screenshot, often missed the visible body
    //    entirely. The box is padded by config.padding (5%).
    for (final person in frame.persons) {
      // Segmentation artifacts on distant objects (a bird's wings, a cloud)
      // can look like a person. Real people large enough for the band rule
      // occupy at least 15% of the frame height.
      if (person.box.height < size.height * 0.15) continue;
      if (person.awrahSkinFraction < config.awrahSkinThreshold) continue;
      final padded = padRegion(person.box, config.padding, size);
      if (padded == null) continue;
      regions.add(BlurRegion(
        rect: padded,
        kind: BlurKind.awrah,
        confidence: person.awrahSkinFraction,
        evidence: 'Uncovered awrah band (whole person)',
        rule: 'band',
      ));
    }

    // 3b. Exposed skin: blur person when exposed skin ratio exceeds threshold.
    // Distant/incidental people are skipped: a box under 8% of the frame area
    // AND under 25% of its height. Requiring both keeps a mid-distance
    // swimmer (7% area but 34% tall, coco_010) while dropping an arm at the
    // frame edge (5% area, 18% tall, coco_020) and background fragments.
    final frameArea = size.width * size.height;
    for (final person in frame.persons) {
      final small = person.box.width * person.box.height < 0.08 * frameArea;
      final short = person.box.height < 0.25 * size.height;
      if (small && short) continue;
      // Portrait safeguard: a tall, narrow box is a portrait, where face and
      // neck dominate the skin count. It needs a far higher ratio to block.
      final threshold = isPortraitBox(person.box)
          ? max(config.skinThreshold, portraitSkinThreshold)
          : config.skinThreshold;
      if (person.exposedRatio < threshold) continue;
      final padded = padRegion(person.box, config.padding, size);
      if (padded == null) continue;
      regions.add(BlurRegion(
        rect: padded,
        kind: BlurKind.awrah,
        confidence: person.exposedRatio,
        evidence: 'Exposed skin ${(person.exposedRatio * 100).round()}%',
        rule: 'exposed',
      ));
    }

    return dedupe(regions, size);
  }

  /// Pads [r] by [frac] of its own size and clamps it to the image. Returns
  /// null when nothing visible would remain.
  Rect? padRegion(Rect r, double frac, Size size) {
    if (r.width <= 0 || r.height <= 0) return null;
    final dx = r.width * frac;
    final dy = r.height * frac;
    final padded = Rect.fromLTRB(
      (r.left - dx).clamp(0.0, size.width),
      (r.top - dy).clamp(0.0, size.height),
      (r.right + dx).clamp(0.0, size.width),
      (r.bottom + dy).clamp(0.0, size.height),
    );
    if (padded.width < 1 || padded.height < 1) return null;
    return padded;
  }

  /// Removes tiny regions and near-duplicates (IoU > 0.85), and collapses to
  /// the whole-frame region when one is present.
  List<BlurRegion> dedupe(List<BlurRegion> regions, Size size) {
    final frameArea = size.width * size.height;
    final out = <BlurRegion>[];
    for (final region in regions) {
      final area = region.rect.width * region.rect.height;
      if (area < 1 || area > frameArea * 1.001) continue;
      if (out.any((o) => iou(o.rect, region.rect) > 0.85)) continue;
      out.add(region);
    }
    return out;
  }

  /// Intersection-over-union of two rects, in `[0, 1]`.
  double iou(Rect a, Rect b) {
    final interLeft = max(a.left, b.left);
    final interTop = max(a.top, b.top);
    final interRight = min(a.right, b.right);
    final interBottom = min(a.bottom, b.bottom);
    if (interRight <= interLeft || interBottom <= interTop) return 0;
    final inter = (interRight - interLeft) * (interBottom - interTop);
    final union = a.width * a.height + b.width * b.height - inter;
    return union <= 0 ? 0 : inter / union;
  }
}
