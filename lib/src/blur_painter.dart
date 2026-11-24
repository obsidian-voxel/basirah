import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'detection_data.dart';

/// Paints a source image with the given regions blurred.
///
/// The whole image is drawn once, then each region is clipped and the whole
/// image is drawn again through a Gaussian blur filter. Drawing the *whole*
/// image (rather than just the region's own pixels) keeps the blur free of
/// transparent seams at the clip edges.
class BlurPainter extends CustomPainter {
  final ui.Image source;
  final List<BlurRegion> regions;

  const BlurPainter({required this.source, required this.regions});

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final srcRect = Rect.fromLTWH(
      0,
      0,
      source.width.toDouble(),
      source.height.toDouble(),
    );
    final dstRect = Offset.zero & size;

    canvas.drawImageRect(
      source,
      srcRect,
      dstRect,
      Paint()..filterQuality = FilterQuality.medium,
    );

    for (final region in regions) {
      final regionRect = region.rect.intersect(Offset.zero & size);
      if (regionRect.width < 1 || regionRect.height < 1) continue;

      // Scale the blur radius with the region so a small band is still
      // unreadable without smearing the whole frame.
      final sigma = max(6.0, min(regionRect.width, regionRect.height) * 0.12);

      canvas.save();
      canvas.clipRect(regionRect);
      canvas.drawImageRect(
        source,
        srcRect,
        dstRect,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant BlurPainter old) {
    if (old.source != source) return true;
    if (old.regions.length != regions.length) return true;
    for (var i = 0; i < regions.length; i++) {
      final a = old.regions[i];
      final b = regions[i];
      if (a.rect != b.rect || a.kind != b.kind) return true;
    }
    return false;
  }
}
