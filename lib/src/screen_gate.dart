import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;

import 'detection_data.dart';
import 'detection_engine.dart';
import 'frame_pixels.dart';
import 'policy.dart';

/// One screen-analysis result, in screenshot pixel coordinates.
class ScreenAnalysis {
  /// Highest nudity score seen across the full frame and the content crops.
  final double score;

  /// Score of the untouched full frame, kept for diagnostics: a high crop
  /// score with a low full-frame score is exactly the browser-viewer case.
  final double fullScore;

  final double gate;

  /// True when any scorer reached the gate.
  final bool blurred;

  /// The crop that produced [score], or null for the full frame.
  final Rect? gateRect;

  final List<BlurRegion> regions;
  final int personCount;
  final double maxExposed;
  final int elapsedMs;

  const ScreenAnalysis({
    required this.score,
    required this.fullScore,
    required this.gate,
    required this.blurred,
    required this.regions,
    required this.personCount,
    required this.maxExposed,
    required this.elapsedMs,
    this.gateRect,
  });

  /// Fraction of the frame covered by the blur, for the live-capture card.
  double coverage(Size frame) {
    if (frame.isEmpty) return 0;
    final area = frame.width * frame.height;
    var covered = 0.0;
    for (final region in regions) {
      covered += region.rect.width * region.rect.height;
    }
    return (covered / area).clamp(0.0, 1.0);
  }
}

/// Runs the shipped cascade on a screenshot.
///
/// A phone screenshot is mostly browser chrome and letterboxing; the eval
/// images are cropped to the photo. Scoring only the full frame therefore
/// scored the chrome, not the photo, and nudity inside a viewer was missed.
/// The gate is additionally evaluated on two centre crops (85% and 60%), which
/// is where image viewers put the photo, and the best score wins. The
/// segmentation/policy stage still runs on the untouched frame so awrah boxes
/// keep their real coordinates.
Future<ScreenAnalysis> analyzeScreen(
  DetectionEngine engine,
  img.Image screen,
  BlurConfig config, {
  /// Apps the user excluded from awrah blur still block nudity. When false,
  /// the whole-frame gate and the content crops run exactly as usual; if they
  /// do not fire, the segmentation-based skin stage is skipped entirely.
  bool allowAwrah = true,

  /// Face boxes in full-frame pixels, already expanded by the detector's
  /// margin. Source of face truth for the exposed-skin rule.
  List<Rect> faces = const [],
}) async {
  final started = DateTime.now();
  await engine.initialize();
  final size = Size(screen.width.toDouble(), screen.height.toDouble());

  // One segmentation+policy pass on the untouched frame. Its people count also
  // gates the crop scanner: a skin-toned page or wall must not produce a blur
  // region where no person exists.
  final frame = await engine.analyze(screen, faces: faces);
  final fullScore = frame.nsfwScore;

  if (nsfwBlocks(fullScore, config)) {
    return ScreenAnalysis(
      score: fullScore,
      fullScore: fullScore,
      gate: config.nsfwFrameGate,
      blurred: true,
      regions: [
        BlurRegion(
          rect: Rect.fromLTWH(0, 0, size.width, size.height),
          kind: BlurKind.nudity,
          confidence: fullScore,
          evidence: 'Nudity detected (whole frame)',
          rule: 'gate_full',
        ),
      ],
      personCount: frame.persons.length,
      maxExposed: 0,
      elapsedMs: DateTime.now().difference(started).inMilliseconds,
    );
  }

  // Content crops. Image viewers centre the photo, so these find it without
  // parsing the browser UI. They require a detected person: without one the
  // gallery grid, wallpaper or sand can score high and blur nothing useful.
  for (final fraction in const [0.85, 0.60]) {
    if (frame.persons.isEmpty) break;
    final crop = _centreCrop(screen, fraction);
    final score = engine.nsfwScoreOf(crop);
    if (!nsfwBlocks(score, config)) continue;

    final cropBounds = Rect.fromLTWH(
      ((screen.width - crop.width) / 2).roundToDouble(),
      ((screen.height - crop.height) / 2).roundToDouble(),
      crop.width.toDouble(),
      crop.height.toDouble(),
    );

    // The gate fired on the crop, so the blur region is expressed in crop
    // pixels first and then mapped back into full-frame pixels. Adding the
    // offset here (once) is what keeps the overlay aligned; applying the
    // offset and then scaling again produced floating patches.
    final cropLocal = Rect.fromLTWH(
      0,
      0,
      crop.width.toDouble(),
      crop.height.toDouble(),
    ).inflate(0.10 * crop.width);
    final rect = _clampRect(
      cropRectToFrame(cropLocal, cropBounds: cropBounds),
      size,
    );
    return ScreenAnalysis(
      score: score,
      fullScore: fullScore,
      gate: config.nsfwFrameGate,
      blurred: true,
      gateRect: rect,
      regions: [
        BlurRegion(
          rect: rect,
          kind: BlurKind.nudity,
          confidence: score,
          evidence: 'Nudity detected (content area)',
          rule: 'gate_crop',
        ),
      ],
      personCount: frame.persons.length,
      maxExposed: 0,
      elapsedMs: DateTime.now().difference(started).inMilliseconds,
    );
  }

  if (!allowAwrah) {
    return ScreenAnalysis(
      score: fullScore,
      fullScore: fullScore,
      gate: config.nsfwFrameGate,
      blurred: false,
      regions: const [],
      personCount: frame.persons.length,
      maxExposed: 0,
      elapsedMs: DateTime.now().difference(started).inMilliseconds,
    );
  }

  // No nudity: the normal awrah/exposure cascade decides.
  final regions = BlurPolicy(config).apply(frame);
  final maxExposed = frame.persons.isEmpty
      ? 0.0
      : frame.persons
          .map((p) => p.exposedRatio)
          .reduce((a, b) => a > b ? a : b);

  return ScreenAnalysis(
    score: maxOf(fullScore, frame.nsfwScore),
    fullScore: fullScore,
    gate: config.nsfwFrameGate,
    blurred: regions.isNotEmpty,
    regions: regions,
    personCount: frame.persons.length,
    maxExposed: maxExposed,
    elapsedMs: DateTime.now().difference(started).inMilliseconds,
  );
}

double maxOf(double a, double b) => a > b ? a : b;

/// Whether an NSFW score blocks the screen under [config].
///
/// A score at or above 0.75 is treated as nudity at every sensitivity level,
/// so the slider can never let clear cases through. Below that, each level's
/// configured gate decides.
bool nsfwBlocks(double score, BlurConfig config) {
  if (score >= 0.75) return true;
  return score >= config.nsfwFrameGate;
}

/// Maps a rectangle expressed in crop pixels into full-frame pixels.
///
/// The crop is a 1:1 window of the frame, so the mapping is a pure translation:
/// frame = crop-local + crop origin. [scale] is exposed for callers that hold
/// normalised crop coordinates (0..1) instead of pixels; the gate passes 1.
Rect cropRectToFrame(
  Rect cropLocal, {
  required Rect cropBounds,
  double scale = 1.0,
}) {
  // Translation only (plus an optional unit→pixel scale). The caller clamps to
  // the frame; intersecting with the crop here would cut off the 10% margin.
  return Rect.fromLTRB(
    cropBounds.left + cropLocal.left * scale,
    cropBounds.top + cropLocal.top * scale,
    cropBounds.left + cropLocal.right * scale,
    cropBounds.top + cropLocal.bottom * scale,
  );
}

img.Image _centreCrop(img.Image image, double fraction) {
  final width = (image.width * fraction).round().clamp(1, image.width);
  final height = (image.height * fraction).round().clamp(1, image.height);
  return img.copyCrop(
    image,
    x: (image.width - width) ~/ 2,
    y: (image.height - height) ~/ 2,
    width: width,
    height: height,
  );
}

Rect _clampRect(Rect rect, Size size) {
  final left = rect.left.clamp(0.0, size.width);
  final top = rect.top.clamp(0.0, size.height);
  final right = rect.right.clamp(left, size.width);
  final bottom = rect.bottom.clamp(top, size.height);
  return Rect.fromLTRB(left, top, right, bottom);
}

/// Decodes a padded ARGB frame from Android into an [img.Image].
img.Image frameToImage({
  required int width,
  required int height,
  required int stride,
  required Int32List pixels,
}) {
  final frame = FramePixels(
    width: width,
    height: height,
    stride: stride,
    argb: pixels,
  );
  return frame.toImage();
}
