import 'package:flutter/material.dart';

/// The five bottom-navigation glyphs, redrawn as vector painters.
///
/// The reference app ships its navigation icons as bitmap assets, so the
/// Material icon set is a poor match: its `grid_view_rounded` is a filled
/// nine-cell grid, `workspace_premium` is a medal rather than a crown, and
/// `filter_hdr` is a landscape photo. Each glyph below is drawn from the
/// reference screenshots instead (see
/// `Documents/blockp-reference/nav_icons_sheet.png`):
///
/// * Dashboard - four rounded squares in a 2x2 arrangement
/// * Block list - a rounded square holding two bullets and two dashes
/// * Premium - a three-pointed crown over a baseline
/// * Calm - a timer dial, the same ring the calm screen counts down in
/// * Support - a headphone band with two ear pads
///
/// Every painter strokes with a round cap and a round join, matching the
/// reference's soft, hand-drawn-looking outlines.
enum BpNavIcon { dashboard, blockList, premium, calm, support }

/// Paints one of the reference's bottom-navigation glyphs.
class BpNavGlyph extends StatelessWidget {
  final BpNavIcon glyph;
  final Color color;
  final double size;
  final double strokeWidth;

  const BpNavGlyph({
    super.key,
    required this.glyph,
    required this.color,
    this.size = 26,
    this.strokeWidth = 2.4,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _NavGlyphPainter(
        glyph: glyph,
        color: color,
        strokeWidth: strokeWidth,
      ),
    );
  }
}

class _NavGlyphPainter extends CustomPainter {
  final BpNavIcon glyph;
  final Color color;
  final double strokeWidth;

  _NavGlyphPainter({
    required this.glyph,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    switch (glyph) {
      case BpNavIcon.dashboard:
        _dashboard(canvas, stroke, w, h);
      case BpNavIcon.blockList:
        _blockList(canvas, stroke, fill, w, h);
      case BpNavIcon.premium:
        _premium(canvas, stroke, fill, w, h);
      case BpNavIcon.calm:
        _calm(canvas, stroke, fill, w, h);
      case BpNavIcon.support:
        _support(canvas, stroke, w, h);
    }
  }

  /// Four rounded squares: tall on the left column, square on the right.
  void _dashboard(Canvas canvas, Paint stroke, double w, double h) {
    final r = w * 0.16;

    // Top-left: a tall rounded rectangle.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.13, h * 0.10, w * 0.21, h * 0.34),
        Radius.circular(r * 0.7),
      ),
      stroke,
    );

    // Top-right: a square.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.44, h * 0.10, w * 0.21, h * 0.21),
        Radius.circular(r * 0.7),
      ),
      stroke,
    );

    // Bottom-left: a square.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.13, h * 0.54, w * 0.21, h * 0.21),
        Radius.circular(r * 0.7),
      ),
      stroke,
    );

    // Bottom-right: a tall rounded rectangle.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.44, h * 0.54, w * 0.21, h * 0.34),
        Radius.circular(r * 0.7),
      ),
      stroke,
    );
  }

  /// A rounded square frame holding two filled bullets and two dashes.
  void _blockList(Canvas canvas, Paint stroke, Paint fill, double w, double h) {
    final frame = Rect.fromLTWH(w * 0.10, h * 0.06, w * 0.80, h * 0.88);
    canvas.drawRRect(
      RRect.fromRectAndRadius(frame, Radius.circular(w * 0.13)),
      stroke,
    );

    const bulletX = 0.30;
    const dashX = 0.50;

    for (final cy in [0.31, 0.62]) {
      canvas.drawCircle(
        Offset(w * bulletX, h * cy),
        w * 0.055,
        fill,
      );
      canvas.drawLine(
        Offset(w * dashX, h * cy),
        Offset(w * 0.76, h * cy),
        stroke,
      );
    }
  }

  /// A three-pointed crown over a detached baseline.
  void _premium(Canvas canvas, Paint stroke, Paint fill, double w, double h) {
    final path = Path()
      ..moveTo(w * 0.10, h * 0.32)
      ..lineTo(w * 0.26, h * 0.52)
      ..lineTo(w * 0.50, h * 0.20)
      ..lineTo(w * 0.74, h * 0.52)
      ..lineTo(w * 0.90, h * 0.32)
      ..lineTo(w * 0.82, h * 0.80)
      ..lineTo(w * 0.18, h * 0.80)
      ..close();
    canvas.drawPath(path, stroke);

    // The three crown tips carry small filled dots.
    for (final p in [
      Offset(w * 0.10, h * 0.30),
      Offset(w * 0.50, h * 0.17),
      Offset(w * 0.90, h * 0.30),
    ]) {
      canvas.drawCircle(p, w * 0.055, fill);
    }

    canvas.drawLine(
      Offset(w * 0.14, h * 0.93),
      Offset(w * 0.86, h * 0.93),
      stroke,
    );
  }

  /// A timer dial: one ring, a hand to twelve and a hand to three.
  ///
  /// The old glyph was a mountain with a flag, copied from the reference
  /// screenshots; at 22 dp the two slopes read as a pair of legs, which is
  /// exactly the figurative shape this app avoids. A dial says "a session
  /// with a clock on it" without drawing anything alive.
  void _calm(Canvas canvas, Paint stroke, Paint fill, double w, double h) {
    final centre = Offset(w * 0.5, h * 0.52);
    canvas.drawCircle(centre, w * 0.38, stroke);
    canvas.drawLine(centre, Offset(w * 0.5, h * 0.24), stroke);
    canvas.drawLine(centre, Offset(w * 0.70, h * 0.52), stroke);
    canvas.drawCircle(centre, w * 0.07, fill);
  }

  /// A headphone band with two ear pads.
  void _support(Canvas canvas, Paint stroke, double w, double h) {
    final band = Path()
      ..moveTo(w * 0.12, h * 0.60)
      ..cubicTo(w * 0.12, h * 0.10, w * 0.88, h * 0.10, w * 0.88, h * 0.60);
    canvas.drawPath(band, stroke);

    // Left ear pad.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.07, h * 0.55, w * 0.17, h * 0.30),
        Radius.circular(w * 0.07),
      ),
      stroke,
    );

    // Right ear pad.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.76, h * 0.55, w * 0.17, h * 0.30),
        Radius.circular(w * 0.07),
      ),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_NavGlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}
