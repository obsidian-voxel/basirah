import 'dart:ui';

/// One axis-aligned blur region produced by the policy engine.
class BlurRegion {
  final Rect rect;
  final BlurKind kind;
  final double confidence;
  final String evidence; // human-readable reason, e.g. "Nudity (whole frame)"

  /// Which rule produced this region: `gate_full`, `gate_crop`, `exposed` or
  /// `band`. Logged natively and printed by the eval so a false positive can
  /// be attributed without re-running anything.
  final String rule;

  const BlurRegion({
    required this.rect,
    required this.kind,
    required this.confidence,
    required this.evidence,
    this.rule = 'band',
  });

  BlurRegion copyWith({
    Rect? rect,
    BlurKind? kind,
    double? confidence,
    String? evidence,
    String? rule,
  }) {
    return BlurRegion(
      rect: rect ?? this.rect,
      kind: kind ?? this.kind,
      confidence: confidence ?? this.confidence,
      evidence: evidence ?? this.evidence,
      rule: rule ?? this.rule,
    );
  }
}

/// What a blur region is protecting. No gender-specific kinds exist: the app
/// blurs nudity/exposure for every person equally.
enum BlurKind {
  nudity, // exposed intimate parts / sexual content
  awrah, // uncovered body band that modesty rules require covered
}

/// Evidence about one detected person. Deliberately contains no gender or
/// identity classification.
class PersonVerdict {
  /// Person bounding box in source-image pixels.
  final Rect box;

  /// Fraction of pixels in the person's awrah band classified as bare skin.
  final double awrahSkinFraction;
  /// Fraction of exposed skin in the whole person box (excluding head).
  final double exposedRatio;
  const PersonVerdict({
    required this.box,
    required this.awrahSkinFraction,
    required this.exposedRatio,
  });
}

/// Exposed-region evidence box from a region detector. The shipped model is a
/// whole-frame classifier, so this list is normally empty; the type stays so
/// that a region detector can be plugged in without changing the policy API.
class NudityHit {
  final Rect box;
  final String label;
  final double score;

  const NudityHit({required this.box, required this.label, required this.score});
}

/// All model evidence for a single frame, in source-image coordinates.
class FrameResult {
  final Size imageSize;
  final double nsfwScore; // 0..1 probability of nudity/sexual content
  final List<PersonVerdict> persons;
  final List<NudityHit> nudityHits;

  const FrameResult({
    required this.imageSize,
    required this.nsfwScore,
    this.persons = const [],
    this.nudityHits = const [],
  });

  bool get hasPerson => persons.isNotEmpty;
}

/// Awrah band of a person box: navel→knee, approximated as 42%–92% of the
/// person's height. Shared by the detector, the policy and the tests so the
/// three can never drift apart.
Rect? awrahBand(Rect box) {
  if (box.height <= 0 || box.width <= 0) return null;
  final top = box.top + box.height * 0.42;
  final bottom = box.top + box.height * 0.92;
  if (bottom <= top) return null;
  return Rect.fromLTRB(box.left, top, box.right, bottom);
}
