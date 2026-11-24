import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// The one preprocessing implementation used by the app, the tests and the
/// on-device self-eval.
///
/// `tools/evaluate.py` mirrors it with PIL/numpy; `test/preprocessing_parity_test.dart`
/// pins the two together on real images so they can never drift again.
class FramePreprocessor {
  static const int nsfwSize = 224;
  static const int segSize = 256;

  /// Input tensor for `nsfw_int8.tflite`: 224x224 RGB in 0..1.
  static Float32List nsfwInput(img.Image image) =>
      _input(image, nsfwSize, scale: 255.0, offset: 0.0);

  /// Input tensor for `selfie_multiclass_256x256.tflite`: 256x256 RGB in -1..1.
  static Float32List segInput(img.Image image) =>
      _input(image, segSize, scale: 127.5, offset: -1.0);

  static Float32List _input(
    img.Image image,
    int size, {
    required double scale,
    required double offset,
  }) {
    final resized = pilResize(image, size, size);
    final rgba = resized.getBytes(order: img.ChannelOrder.rgba);
    final out = Float32List(size * size * 3);
    for (var dst = 0, src = 0; dst < out.length; dst += 3, src += 4) {
      out[dst] = rgba[src] / scale + offset;
      out[dst + 1] = rgba[src + 1] / scale + offset;
      out[dst + 2] = rgba[src + 2] / scale + offset;
    }
    return out;
  }

  /// Per-channel means of a preprocessed input tensor. Used by the parity
  /// golden test and the live-capture diagnostics.
  static ({double r, double g, double b}) channelMeans(Float32List input) {
    var r = 0.0, g = 0.0, b = 0.0;
    final pixels = input.length ~/ 3;
    for (var i = 0; i < input.length; i += 3) {
      r += input[i];
      g += input[i + 1];
      b += input[i + 2];
    }
    if (pixels == 0) return (r: 0, g: 0, b: 0);
    return (r: r / pixels, g: g / pixels, b: b / pixels);
  }

  /// Largest absolute relative difference between two channel-mean triples.
  static double maxRelativeDiff(
    ({double r, double g, double b}) a,
    ({double r, double g, double b}) b,
  ) {
    double rel(double x, double y) {
      final denom = max(x.abs(), y.abs());
      return denom <= 1e-9 ? 0 : (x - y).abs() / denom;
    }

    return max(rel(a.r, b.r), max(rel(a.g, b.g), rel(a.b, b.b)));
  }
}

/// Resizes an image exactly like PIL's `Image.resize(..., BILINEAR)`.
///
/// PIL does not use plain bilinear sampling when shrinking: it widens the
/// triangle filter by the scale factor (an antialiased prefilter). The
/// `image` package offers box (`average`) or non-antialiased (`linear`)
/// filters, whose output statistics differ from the eval's by around 1% on
/// large photos — enough to move a borderline gate score. Reproducing PIL's
/// coefficient computation keeps the device input identical to the eval input.
img.Image pilResize(img.Image source, int width, int height) {
  if (source.width == width && source.height == height) {
    return source;
  }

  final rgba = source.getBytes(order: img.ChannelOrder.rgba);
  final sourceWidth = source.width;
  final sourceHeight = source.height;

  final horizontal = _coefficients(sourceWidth, width);
  final vertical = _coefficients(sourceHeight, height);

  // Horizontal pass: width × sourceHeight × 3 floats.
  final temp = Float32List(width * sourceHeight * 3);
  for (var y = 0; y < sourceHeight; y++) {
    final row = y * sourceWidth * 4;
    final outRow = y * width * 3;
    for (var x = 0; x < width; x++) {
      final coeff = horizontal[x];
      var r = 0.0, g = 0.0, b = 0.0;
      for (var k = 0; k < coeff.count; k++) {
        final weight = coeff.weights[k];
        final index = row + (coeff.start + k) * 4;
        r += rgba[index] * weight;
        g += rgba[index + 1] * weight;
        b += rgba[index + 2] * weight;
      }
      final out = outRow + x * 3;
      temp[out] = r;
      temp[out + 1] = g;
      temp[out + 2] = b;
    }
  }

  // Vertical pass.
  final out = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    final coeff = vertical[y];
    final outRow = y * width * 4;
    for (var x = 0; x < width; x++) {
      var r = 0.0, g = 0.0, b = 0.0;
      for (var k = 0; k < coeff.count; k++) {
        final weight = coeff.weights[k];
        final index = ((coeff.start + k) * width + x) * 3;
        r += temp[index] * weight;
        g += temp[index + 1] * weight;
        b += temp[index + 2] * weight;
      }
      final index = outRow + x * 4;
      out[index] = r.round().clamp(0, 255);
      out[index + 1] = g.round().clamp(0, 255);
      out[index + 2] = b.round().clamp(0, 255);
      out[index + 3] = 255;
    }
  }

  return img.Image.fromBytes(
    width: width,
    height: height,
    bytes: out.buffer,
    order: img.ChannelOrder.rgba,
  );
}

class _Coefficients {
  final int start;
  final Float32List weights;

  const _Coefficients(this.start, this.weights);

  int get count => weights.length;
}

/// PIL's `precompute_coeffs` for a triangle filter.
List<_Coefficients> _coefficients(int inSize, int outSize) {
  final scale = inSize / outSize;
  final filterScale = max(scale, 1.0);
  final support = filterScale;
  final result = <_Coefficients>[];

  for (var i = 0; i < outSize; i++) {
    final center = (i + 0.5) * scale;
    var min = (center - support + 0.5).floor();
    var maxIndex = (center + support + 0.5).ceil();
    if (min < 0) min = 0;
    if (maxIndex > inSize) maxIndex = inSize;
    if (maxIndex <= min) {
      min = min.clamp(0, inSize - 1);
      maxIndex = min + 1;
    }

    final weights = Float32List(maxIndex - min);
    var total = 0.0;
    for (var x = min; x < maxIndex; x++) {
      final t = (x - center + 0.5).abs() / filterScale;
      final weight = t < 1.0 ? 1.0 - t : 0.0;
      weights[x - min] = weight;
      total += weight;
    }
    if (total != 0) {
      for (var k = 0; k < weights.length; k++) {
        weights[k] /= total;
      }
    } else {
      weights[0] = 1;
    }
    result.add(_Coefficients(min, weights));
  }

  return result;
}
