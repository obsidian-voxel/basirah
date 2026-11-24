import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:haram_blur/src/frame_pixels.dart';

/// Builds a padded frame where every visible pixel has a known colour and the
/// padding bytes are loud garbage. If the converter reads the stride wrong, the
/// row shifts and the assertions fail.
FramePixels paddedFrame() {
  const width = 3;
  const height = 2;
  const stride = 5; // 2 pixels of padding per row
  final pixels = Int32List(stride * height);

  // Fill padding with magenta so a naive tight read is unmistakable.
  for (var i = 0; i < pixels.length; i++) {
    pixels[i] = 0xFFFF00FF.toSigned(32);
  }

  void set(int x, int y, int argb) => pixels[y * stride + x] = argb;

  set(0, 0, 0xFFFF0000); // red
  set(1, 0, 0xFF00FF00); // green
  set(2, 0, 0xFF0000FF); // blue
  set(0, 1, 0xFFFFFFFF); // white
  set(1, 1, 0xFF000000); // black
  set(2, 1, 0x80123456); // translucent

  return FramePixels(width: width, height: height, stride: stride, argb: pixels);
}

void main() {
  test('row padding is reported in pixels and bytes', () {
    final frame = paddedFrame();
    expect(frame.rowPadding, 2);
    expect(frame.rowPaddingBytes, 8);
  });

  test('padded rows are tightened without shearing the image', () {
    final image = paddedFrame().toImage();

    expect(image.width, 3);
    expect(image.height, 2);

    expect(image.getPixel(0, 0).r.toInt(), 255);
    expect(image.getPixel(0, 0).g.toInt(), 0);
    expect(image.getPixel(0, 0).b.toInt(), 0);

    expect(image.getPixel(1, 0).g.toInt(), 255);
    expect(image.getPixel(2, 0).b.toInt(), 255);

    expect(image.getPixel(0, 1).r.toInt(), 255);
    expect(image.getPixel(0, 1).g.toInt(), 255);
    expect(image.getPixel(0, 1).b.toInt(), 255);

    expect(image.getPixel(1, 1).r.toInt(), 0);
    expect(image.getPixel(1, 1).g.toInt(), 0);
    expect(image.getPixel(1, 1).b.toInt(), 0);

    expect(image.getPixel(2, 1).r.toInt(), 0x12);
    expect(image.getPixel(2, 1).g.toInt(), 0x34);
    expect(image.getPixel(2, 1).b.toInt(), 0x56);
    expect(image.getPixel(2, 1).a.toInt(), 0x80);
  });

  test('no magenta padding leaks into the tightened image', () {
    final image = paddedFrame().toImage();
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        final isMagenta = p.r.toInt() == 255 &&
            p.g.toInt() == 0 &&
            p.b.toInt() == 255;
        expect(isMagenta, isFalse, reason: 'padding leaked at ($x,$y)');
      }
    }
  });

  test('a tight frame (stride == width) converts unchanged', () {
    final pixels = Int32List.fromList([0xFF102030, 0xFF405060]);
    final frame = FramePixels(
      width: 2,
      height: 1,
      stride: 2,
      argb: pixels,
    );
    expect(frame.rowPadding, 0);
    final image = frame.toImage();
    expect(image.getPixel(1, 0).r.toInt(), 0x40);
    expect(image.getPixel(1, 0).g.toInt(), 0x50);
    expect(image.getPixel(1, 0).b.toInt(), 0x60);
  });

  test('a short buffer is rejected instead of reading garbage', () {
    expect(
      () => FramePixels(
        width: 4,
        height: 4,
        stride: 4,
        argb: Int32List(4),
      ).toImage(),
      throwsArgumentError,
    );
  });
}
