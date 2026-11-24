import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:image/image.dart' as img;

/// Result of measuring exposed skin in a person box.
class SkinExposure {
  /// Skin pixels inside a face box, removed from the numerator.
  final int facePixels;

  /// Skin pixels counted as exposed.
  final int skinPixels;

  /// Segmented person pixels considered.
  final int personPixels;

  /// True when any face box is at least 60% as wide as the person box; the
  /// caller suppresses the awrah-band rule for this person.
  final bool closeUp;

  const SkinExposure({
    required this.facePixels,
    required this.skinPixels,
    required this.personPixels,
    this.closeUp = false,
  });

  double get ratio => personPixels == 0 ? 0 : skinPixels / personPixels;
}

/// True when [r],[g],[b] look like bare skin (YCbCr + HSV rules).
bool isSkinPixel(int r, int g, int b) {
  final cb = 128 + (-0.1687 * r - 0.3313 * g + 0.5 * b);
  final cr = 128 + (0.5 * r - 0.4187 * g - 0.0813 * b);
  if (cr < 133 || cr > 173 || cb < 77 || cb > 121) return false;

  final mx = max(max(r, g), b).toDouble();
  final mn = min(min(r, g), b).toDouble();
  final delta = mx - mn;
  double h = 0;
  final s = mx == 0 ? 0.0 : delta / mx;
  if (delta > 0) {
    if (mx == r) {
      h = ((g - b) / delta) % 6;
    } else if (mx == g) {
      h = (b - r) / delta + 2;
    } else {
      h = (r - g) / delta + 4;
    }
    h *= 60;
    if (h < 0) h += 360;
  }
  if (s < 0.15 || s > 0.9) return false;
  return h <= 50 || h >= 340;
}

/// Exposed-skin ratio for one person box using explicit face boxes.
///
/// Skin pixels are counted only where [personMask] marks a segmented person
/// pixel, so skin-toned background cannot inflate the ratio. Every skin pixel
/// inside any [faces] rectangle is removed from the numerator: face boxes are
/// the single source of face truth, with no component heuristic. [faces] are
/// in image pixels and already expanded by the detector's margin.
SkinExposure measureSkinExposure(
  img.Image image,
  Rect box, {
  required List<Rect> faces,
  Uint8List? personMask,
  int maskWidth = 0,
  int maskHeight = 0,
}) {
  if (box.width <= 0 || box.height <= 0) {
    return const SkinExposure(
      facePixels: 0,
      skinPixels: 0,
      personPixels: 0,
    );
  }

  final left = box.left.floor().clamp(0, image.width - 1);
  final right = box.right.ceil().clamp(left + 1, image.width);
  final top = box.top.floor().clamp(0, image.height - 1);
  final bottom = box.bottom.ceil().clamp(top + 1, image.height);
  final width = right - left;
  final height = bottom - top;
  if (width <= 0 || height <= 0) {
    return const SkinExposure(
      facePixels: 0,
      skinPixels: 0,
      personPixels: 0,
    );
  }

  final usableMask =
      personMask != null && maskWidth > 0 && maskHeight > 0 ? personMask : null;
  bool isPerson(int x, int y) {
    if (usableMask == null) return true;
    final mx = (x * maskWidth ~/ image.width).clamp(0, maskWidth - 1);
    final my = (y * maskHeight ~/ image.height).clamp(0, maskHeight - 1);
    return usableMask[my * maskWidth + mx] != 0;
  }

  var closeUp = false;
  final neckZones = <Rect>[];
  for (final face in faces) {
    if (face.width >= box.width * 0.60) {
      closeUp = true;
    }
    neckZones.add(Rect.fromLTRB(
      face.left,
      face.top,
      face.right,
      face.bottom + 1.3 * face.height,
    ));
  }

  // The head, hair and neck occupy the top of a person box, and a bare face is
  // 100% skin pixels. Counting that made hijab/niqab portraits read as exposed
  // skin, and ML Kit frequently finds no face on a covered head at all. The top
  // 40% is therefore excluded from the ratio entirely: numerator and
  // denominator both start at [headLine], so nothing above it can ever fire a
  // block. This is the fail-safe when no face box exists.
  final headLine = top + height * 0.40;

  final skinMask = List<bool>.filled(width * height, false);
  var personPixels = 0;
  var facePixels = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final imageX = left + x;
      final imageY = top + y;
      if (!isPerson(imageX, imageY)) continue;

      final pixel = image.getPixel(imageX, imageY);
      final skinPixel = isSkinPixel(
        pixel.r.toInt(),
        pixel.g.toInt(),
        pixel.b.toInt(),
      );

      // Face boxes stay the single source of face truth (they are already
      // expanded to cover the chin and neck). Counted before the head cut so
      // facePixels still reports how much face skin was removed.
      if (skinPixel) {
        var inFace = false;
        for (final face in faces) {
          if (imageX >= face.left &&
              imageX < face.right &&
              imageY >= face.top &&
              imageY < face.bottom) {
            inFace = true;
            break;
          }
        }
        if (inFace) {
          facePixels++;
          continue;
        }
      }

      if (imageY < headLine) continue;

      personPixels++;
      if (skinPixel) skinMask[y * width + x] = true;
    }
  }

  // Face-independent filtering: drop skin components smaller than 2% of the
  // person (eye slits, neck fragments) and any that overlap a face's
  // downward-expanded neck zone. A limb is ~5% of a person box, so the floor
  // must stay well below it; 10% deleted legitimate exposed limbs.
  final minArea = (0.02 * personPixels).floor().clamp(1, personPixels + 1);
  final labels = List<int>.filled(width * height, -1);
  final stack = <int>[];
  var nextLabel = 0;
  var skinPixels = 0;

  for (var start = 0; start < skinMask.length; start++) {
    if (!skinMask[start] || labels[start] != -1) continue;
    final label = nextLabel++;
    labels[start] = label;
    stack
      ..clear()
      ..add(start);

    final indices = <int>[];
    var minX = width;
    var maxX = -1;
    var minY = height;
    var maxY = -1;

    while (stack.isNotEmpty) {
      final index = stack.removeLast();
      indices.add(index);
      final x = index % width;
      final y = index ~/ width;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;

      void visit(int nx, int ny) {
        final n = ny * width + nx;
        if (skinMask[n] && labels[n] == -1) {
          labels[n] = label;
          stack.add(n);
        }
      }

      if (x > 0) visit(x - 1, y);
      if (x + 1 < width) visit(x + 1, y);
      if (y > 0) visit(x, y - 1);
      if (y + 1 < height) visit(x, y + 1);
    }

    final area = indices.length;
    if (area < minArea) continue;

    final componentBox = Rect.fromLTRB(
      left + minX.toDouble(),
      top + minY.toDouble(),
      left + maxX + 1.0,
      top + maxY + 1.0,
    );
    // Only a component mostly inside the neck zone (a neck/chin fragment) is
    // dropped; a bare torso that merely touches the zone stays.
    final componentArea = componentBox.width * componentBox.height;
    var inNeck = false;
    for (final zone in neckZones) {
      final overlap = componentBox.intersect(zone);
      if (overlap.width <= 0 || overlap.height <= 0) continue;
      if (overlap.width * overlap.height >= 0.5 * componentArea) {
        inNeck = true;
        break;
      }
    }
    if (inNeck) continue;
    skinPixels += area;
  }

  return SkinExposure(
    facePixels: facePixels,
    skinPixels: skinPixels,
    personPixels: personPixels,
    closeUp: closeUp,
  );
}
