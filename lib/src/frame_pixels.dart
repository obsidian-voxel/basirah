import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A raw ARGB_8888 frame as Android hands it over, possibly with row padding.
///
/// `Bitmap.wrapHardwareBuffer` can expose a stride (rowPadding) larger than
/// `width * 4`: the hardware buffer is aligned to 16/32/64 bytes. Reading such
/// a buffer as if it were tight shifts every row and shears the image, which
/// silently destroys detections. This class is the only place that conversion
/// is allowed to happen, and it is unit-tested with synthetic padding.
class FramePixels {
  final int width;
  final int height;

  /// Pixels per row in [argb], including padding. `stride >= width`.
  final int stride;

  /// ARGB_8888 pixels, `stride * height` entries.
  final Int32List argb;

  const FramePixels({
    required this.width,
    required this.height,
    required this.stride,
    required this.argb,
  });

  /// Row padding in pixels (`0` when the buffer was already tight).
  int get rowPadding => stride - width;

  int get rowPaddingBytes => rowPadding * 4;

  /// Copies padded rows into a tight RGBA buffer (row by row, so a padded
  /// stride can never shear the frame) and returns it as an image.
  img.Image toImage() {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Frame has no pixels');
    }
    if (stride < width || argb.length < stride * height) {
      throw ArgumentError(
        'Frame buffer is too small: stride=$stride, size=${argb.length}, '
        'expected ${stride * height}',
      );
    }

    final rgba = Uint8List(width * height * 4);
    var dst = 0;
    for (var y = 0; y < height; y++) {
      final row = y * stride;
      for (var x = 0; x < width; x++) {
        final value = argb[row + x] & 0xFFFFFFFF;
        rgba[dst++] = (value >> 16) & 0xFF; // R
        rgba[dst++] = (value >> 8) & 0xFF; // G
        rgba[dst++] = value & 0xFF; // B
        rgba[dst++] = (value >> 24) & 0xFF; // A
      }
    }

    return img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgba.buffer,
      order: img.ChannelOrder.rgba,
    );
  }

  /// Reads one ARGB pixel from a padded buffer. Tests use it to prove the row
  /// stride is honoured without relying on [toImage].
  int pixelAt(int x, int y) {
    RangeError.checkValidIndex(x, List.filled(width, 0), 'x');
    RangeError.checkValidIndex(y, List.filled(height, 0), 'y');
    return argb[y * stride + x] & 0xFFFFFFFF;
  }
}
