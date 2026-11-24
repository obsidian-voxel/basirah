import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

/// Per-pixel class map produced by MediaPipe `selfie_multiclass_256x256.tflite`.
///
/// Classes: 0 background, 1 hair, 2 body-skin, 3 face-skin, 4 clothes,
/// 5 accessories. The model has no notion of gender or identity: it only
/// labels pixels, which is exactly the evidence the policy needs.
class SegmentationMap {
  static const int background = 0;
  static const int hair = 1;
  static const int bodySkin = 2;
  static const int faceSkin = 3;
  static const int clothes = 4;
  static const int accessories = 5;

  final int width;
  final int height;
  final Uint8List classes;

  const SegmentationMap({
    required this.width,
    required this.height,
    required this.classes,
  });

  /// Builds a class map from the raw model output `[1, h, w, classes]`
  /// (already flattened) by taking the arg-max class per pixel.
  factory SegmentationMap.fromLogits({
    required int width,
    required int height,
    required Float32List logits,
    int classCount = 6,
  }) {
    final out = Uint8List(width * height);
    for (var i = 0; i < out.length; i++) {
      var best = 0;
      var bestValue = logits[i * classCount];
      for (var c = 1; c < classCount; c++) {
        final value = logits[i * classCount + c];
        if (value > bestValue) {
          bestValue = value;
          best = c;
        }
      }
      out[i] = best;
    }
    return SegmentationMap(width: width, height: height, classes: out);
  }

  static bool isPersonClass(int value) => value >= hair && value <= accessories;

  static bool isSkinClass(int value) => value == bodySkin || value == faceSkin;

  /// Person bounding boxes (in [imageSize] pixels) found by 4-connected
  /// flood fill over every non-background class.
  ///
  /// Deriving boxes from the segmentation avoids depending on BlazePose's
  /// anchor decoding, which is fragile and was previously decoded incorrectly.
  List<Rect> personBoxesIn(
    Size imageSize, {
    double minAreaFraction = 0.01,
    int maxPersons = 6,
  }) {
    if (imageSize.isEmpty) return const [];
    final visited = Uint8List(width * height);
    final minArea = (width * height * minAreaFraction).round().clamp(1, width * height);
    final boxes = <Rect>[];
    final stack = <int>[];

    for (var start = 0; start < classes.length; start++) {
      if (visited[start] != 0 || !isPersonClass(classes[start])) continue;

      stack
        ..clear()
        ..add(start);
      visited[start] = 1;

      var minX = width;
      var maxX = -1;
      var minY = height;
      var maxY = -1;
      var area = 0;

      while (stack.isNotEmpty) {
        final index = stack.removeLast();
        final x = index % width;
        final y = index ~/ width;
        area++;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;

        if (x > 0) {
          final n = index - 1;
          if (visited[n] == 0 && isPersonClass(classes[n])) {
            visited[n] = 1;
            stack.add(n);
          }
        }
        if (x + 1 < width) {
          final n = index + 1;
          if (visited[n] == 0 && isPersonClass(classes[n])) {
            visited[n] = 1;
            stack.add(n);
          }
        }
        if (y > 0) {
          final n = index - width;
          if (visited[n] == 0 && isPersonClass(classes[n])) {
            visited[n] = 1;
            stack.add(n);
          }
        }
        if (y + 1 < height) {
          final n = index + width;
          if (visited[n] == 0 && isPersonClass(classes[n])) {
            visited[n] = 1;
            stack.add(n);
          }
        }
      }

      if (area >= minArea) {
        final scaleX = imageSize.width / width;
        final scaleY = imageSize.height / height;
        boxes.add(Rect.fromLTRB(
          minX * scaleX,
          minY * scaleY,
          (maxX + 1) * scaleX,
          (maxY + 1) * scaleY,
        ));
      }
    }

    boxes.sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));

    // Drop boxes that are ≥80% contained inside a larger box. Connected-
    // component segmentation can split one person into a nested fragment
    // (hijab_11 produced a 264×312 corner box inside the 696×1024 person),
    // and that fragment's own skin ratio then fires a false positive.
    final kept = <Rect>[];
    for (final box in boxes) {
      final area = box.width * box.height;
      final nested = kept.any((outer) {
        final overlap = box.intersect(outer);
        if (overlap.width <= 0 || overlap.height <= 0) return false;
        return overlap.width * overlap.height >= 0.80 * area;
      });
      if (nested) continue;
      kept.add(box);
      if (kept.length == maxPersons) break;
    }
    return kept;
  }

  /// Person mask at image resolution, one byte per pixel (1 = person class).
  ///
  /// The exposed-skin ratio uses this so skin-toned background outside the
  /// segmented person can never count as exposed skin.
  Uint8List personMask(Size imageSize) {
    final outWidth = imageSize.width.round().clamp(1, 100000);
    final outHeight = imageSize.height.round().clamp(1, 100000);
    final out = Uint8List(outWidth * outHeight);
    for (var y = 0; y < outHeight; y++) {
      final sy = (y * height ~/ outHeight).clamp(0, height - 1);
      final row = sy * width;
      for (var x = 0; x < outWidth; x++) {
        final sx = (x * width ~/ outWidth).clamp(0, width - 1);
        out[y * outWidth + x] = isPersonClass(classes[row + sx]) ? 1 : 0;
      }
    }
    return out;
  }

  /// Fraction of pixels inside [rect] (in [imageSize] pixels) classified as
  /// bare skin (body or face). Returns 0 when the rect falls outside the map.
  double skinFraction(Rect rect, Size imageSize) {
    if (imageSize.isEmpty) return 0;
    final sx = width / imageSize.width;
    final sy = height / imageSize.height;

    final left = (rect.left * sx).floor().clamp(0, width - 1);
    final right = (rect.right * sx).ceil().clamp(1, width);
    final top = (rect.top * sy).floor().clamp(0, height - 1);
    final bottom = (rect.bottom * sy).ceil().clamp(1, height);
    if (right <= left || bottom <= top) return 0;

    var total = 0;
    var skin = 0;
    for (var y = top; y < bottom; y++) {
      final row = y * width;
      for (var x = left; x < right; x++) {
        total++;
        if (isSkinClass(classes[row + x])) skin++;
      }
    }
    return total == 0 ? 0 : skin / total;
  }
}
