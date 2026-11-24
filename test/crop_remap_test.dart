import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:haram_blur/src/detection_data.dart';
import 'package:haram_blur/src/detection_engine.dart';
import 'package:haram_blur/src/policy.dart';
import 'package:haram_blur/src/screen_gate.dart';

/// Scores only the requested crop size, so the test controls which gate fires.
class _CropOnlyEngine extends DetectionEngine {
  _CropOnlyEngine(this.triggerWidth);

  final int triggerWidth;

  @override
  Future<void> initialize() async {}

  @override
  double nsfwScoreOf(img.Image image) => image.width == triggerWidth ? 0.99 : 0.0;

  @override
  Future<FrameResult> analyze(
    img.Image image, {
    List<Rect> faces = const [],
  }) async {
    final size = Size(image.width.toDouble(), image.height.toDouble());
    // The crop gate requires a detected person; this frame has one.
    return FrameResult(
      imageSize: size,
      nsfwScore: 0,
      persons: [
        PersonVerdict(
          box: Rect.fromLTWH(0, 0, size.width, size.height),
          awrahSkinFraction: 0,
          exposedRatio: 0,
        ),
      ],
    );
  }

  @override
  void dispose() {}
}

void main() {
  final frame = img.Image(width: 1000, height: 2000);

  test('crop-local rect is translated into frame coordinates', () {
    final mapped = cropRectToFrame(
      const Rect.fromLTWH(100, 50, 100, 100),
      cropBounds: const Rect.fromLTWH(200, 400, 600, 1200),
    );

    expect(mapped, const Rect.fromLTRB(300, 450, 400, 550));
  });

  test('a gate hit on the 60% crop maps to the full-frame content area', () async {
    // 60% of 1000x2000 = 600x1200, centred at (200,400).
    final engine = _CropOnlyEngine(600);
    final result = await analyzeScreen(
      engine,
      frame,
      BlurConfig.forSensitivity(6),
    );

    expect(result.regions, hasLength(1));
    final rect = result.regions.single.rect;

    // Crop bounds inflated by 10% of the crop width (60 px), clamped to frame.
    expect(rect.left, closeTo(140, 1));
    expect(rect.top, closeTo(340, 1));
    expect(rect.right, closeTo(860, 1));
    expect(rect.bottom, closeTo(1660, 1));

    // The crop centre must land at the frame centre.
    expect(rect.contains(const Offset(500, 1000)), isTrue);
  });

  test('a gate hit on the 85% crop still maps inside the frame', () async {
    // 85% of 1000x2000 = 850x1700, centred at (75,150).
    final engine = _CropOnlyEngine(850);
    final result = await analyzeScreen(
      engine,
      frame,
      BlurConfig.forSensitivity(6),
    );

    final rect = result.regions.single.rect;
    expect(rect.left, closeTo(0, 1)); // 75 - 85 = -10, clamped
    expect(rect.top, closeTo(65, 1)); // 150 - 85 = 65
    expect(rect.right, closeTo(1000, 1)); // 925 + 85 = 1010, clamped
    expect(rect.bottom, closeTo(1935, 1)); // 1935 is inside the frame
    expect(rect.contains(const Offset(500, 1000)), isTrue);
  });
}
