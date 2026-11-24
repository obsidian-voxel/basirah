import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:haram_blur/src/segmentation.dart';

/// Builds a [width]×[height] class map and lets the test paint rectangles.
class _MapBuilder {
  _MapBuilder(this.width, this.height) : classes = Uint8List(width * height);

  final int width;
  final int height;
  final Uint8List classes;

  void fill(int x1, int y1, int x2, int y2, int value) {
    for (var y = y1; y < y2; y++) {
      for (var x = x1; x < x2; x++) {
        classes[y * width + x] = value;
      }
    }
  }

  SegmentationMap build() =>
      SegmentationMap(width: width, height: height, classes: classes);
}

void main() {
  test('connected clothes form one person box in image coordinates', () {
    final map = _MapBuilder(10, 10)
      ..fill(2, 1, 6, 9, SegmentationMap.clothes)
      ..build();

    final boxes = map.build().personBoxesIn(const Size(100, 100));
    expect(boxes, hasLength(1));
    expect(boxes.first, const Rect.fromLTRB(20, 10, 60, 90));
  });

  test('background-only maps have no persons', () {
    final map = _MapBuilder(8, 8);
    expect(map.build().personBoxesIn(const Size(64, 64)), isEmpty);
  });

  test('components smaller than the minimum area are ignored', () {
    final map = _MapBuilder(20, 20)
      ..fill(0, 0, 2, 2, SegmentationMap.hair) // 4 of 400 px = 1%
      ..fill(10, 10, 16, 16, SegmentationMap.clothes);

    final boxes =
        map.build().personBoxesIn(const Size(200, 200), minAreaFraction: 0.05);
    expect(boxes, hasLength(1));
    expect(boxes.first.left, closeTo(100, 0.01));
  });

  test('separate people produce separate boxes, largest first', () {
    final map = _MapBuilder(40, 10)
      ..fill(0, 0, 10, 10, SegmentationMap.clothes) // 100 px
      ..fill(20, 0, 38, 10, SegmentationMap.bodySkin); // 180 px

    final boxes = map.build().personBoxesIn(const Size(40, 10));
    expect(boxes, hasLength(2));
    expect(boxes.first.left, closeTo(20, 0.001));
    expect(boxes.last.left, closeTo(0, 0.001));
  });

  test('skinFraction counts body and face skin only', () {
    final map = _MapBuilder(10, 10)
      ..fill(0, 0, 10, 5, SegmentationMap.clothes)
      ..fill(0, 5, 5, 10, SegmentationMap.bodySkin)
      ..fill(5, 5, 10, 10, SegmentationMap.faceSkin);

    final built = map.build();
    // Bottom half is 100% skin.
    expect(
      built.skinFraction(const Rect.fromLTRB(0, 5, 10, 10), const Size(10, 10)),
      closeTo(1.0, 0.001),
    );
    // Whole map is 50% skin.
    expect(
      built.skinFraction(const Rect.fromLTRB(0, 0, 10, 10), const Size(10, 10)),
      closeTo(0.5, 0.001),
    );
    // Out-of-bounds rects are clamped, never throw.
    expect(
      built.skinFraction(const Rect.fromLTRB(-50, -50, 4, 4), const Size(10, 10)),
      closeTo(0.0, 0.001),
    );
  });

  test('arg-max logits are converted to a class map', () {
    final logits = Float32List(4 * 6);
    // Pixel 0 → class 4 (clothes), pixel 1 → class 2 (body skin).
    logits[0 * 6 + 4] = 5;
    logits[1 * 6 + 2] = 7;
    final map = SegmentationMap.fromLogits(
      width: 2,
      height: 2,
      logits: logits,
    );
    expect(map.classes[0], SegmentationMap.clothes);
    expect(map.classes[1], SegmentationMap.bodySkin);
    expect(map.classes[2], SegmentationMap.background);
  });
}
