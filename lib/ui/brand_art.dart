import 'package:flutter/material.dart';

import 'blockp_theme.dart';

/// Basirah's mark: an abstract aperture of insight.
///
/// The mark is three concentric circles - a lens outline, an iris ring and a
/// centre aperture dot - on the Basirah field. It carries no pointed or
/// star-like geometry, no animate being, no face and no religious symbol.
class BasirahMark extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const BasirahMark({
    super.key,
    required this.size,
    this.color,
    this.strokeWidth = 4,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _MarkPainter(
        color: color ?? context.bp.ink,
        strokeWidth: strokeWidth,
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  _MarkPainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    // The lens outline.
    canvas.drawCircle(center, radius * 0.44, stroke);

    // The iris ring.
    canvas.drawCircle(center, radius * 0.28, stroke);

    // The centre aperture dot.
    canvas.drawCircle(
      center,
      radius * 0.14,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}

/// The calm-mode scene: abstract night mountains, a moon disc and a tent.
///
/// The reference draws a cartoon campsite with its dog mascot. The composition
/// is kept (sky, peaks, tent, foreground slope) but every element is a plain
/// geometric shape and the mascot is gone.
class CalmScene extends StatelessWidget {
  const CalmScene({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CalmPainter(isDark: Theme.of(context).brightness == Brightness.dark),
      child: const SizedBox.expand(),
    );
  }
}

class _CalmPainter extends CustomPainter {
  final bool isDark;

  _CalmPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final sky = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? const [Color(0xFF1E3048), Color(0xFF2B4664), Color(0xFF35536F)]
            : const [Color(0xFFCFE4FA), Color(0xFFE4F0FB), Color(0xFFF3EFE2)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), sky);

    // Moon / sun disc, high and small so it stays decorative.
    final disc = Paint()
      ..color = isDark
          ? const Color(0xFFE9EFF6).withValues(alpha: 0.85)
          : const Color(0xFFFFFFFF).withValues(alpha: 0.9);
    canvas.drawCircle(Offset(w * 0.78, h * 0.20), w * 0.10, disc);

    // Three mountain ridges, back to front. Each is one polyline through
    // peaks and valleys, so the silhouettes read as ranges rather than
    // isolated triangles.
    _ridge(
      canvas,
      w,
      h,
      const [
        (0.16, 0.34), (0.28, 0.46), (0.44, 0.24), (0.58, 0.44),
        (0.74, 0.30), (0.90, 0.44),
      ],
      0.62,
      isDark ? const Color(0xFF33506F) : const Color(0xFFA9C6E4),
    );
    _ridge(
      canvas,
      w,
      h,
      const [
        (0.08, 0.56), (0.24, 0.68), (0.40, 0.44), (0.54, 0.64),
        (0.70, 0.50), (0.86, 0.66),
      ],
      0.78,
      isDark ? const Color(0xFF2A435F) : const Color(0xFF8FB3D8),
    );
    _ridge(
      canvas,
      w,
      h,
      const [
        (0.04, 0.80), (0.20, 0.66), (0.34, 0.82), (0.50, 0.70),
        (0.64, 0.84), (0.80, 0.72), (0.94, 0.82),
      ],
      0.90,
      isDark ? const Color(0xFF22374E) : const Color(0xFF7599BF),
    );

    // Snow caps: two white wedges on the nearest peak.
    final snow = Paint()..color = const Color(0xFFF7FBFF).withValues(alpha: 0.92);
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.40, h * 0.44)
        ..lineTo(w * 0.465, h * 0.56)
        ..lineTo(w * 0.433, h * 0.535)
        ..lineTo(w * 0.40, h * 0.575)
        ..lineTo(w * 0.372, h * 0.535)
        ..lineTo(w * 0.338, h * 0.56)
        ..close(),
      snow,
    );

    // Tent: a triangle with a door slit, on the right third.
    final tent = Paint()..color = isDark ? const Color(0xFFB8763F) : const Color(0xFFE0955A);
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.74, h * 0.42)
        ..lineTo(w * 0.96, h * 0.80)
        ..lineTo(w * 0.52, h * 0.80)
        ..close(),
      tent,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.74, h * 0.50)
        ..lineTo(w * 0.83, h * 0.80)
        ..lineTo(w * 0.65, h * 0.80)
        ..close(),
      Paint()..color = isDark ? const Color(0xFF8F5A2F) : const Color(0xFFC97A44),
    );

    // Foreground slope.
    canvas.drawPath(
      Path()
        ..moveTo(0, h * 0.80)
        ..quadraticBezierTo(w * 0.3, h * 0.74, w * 0.62, h * 0.82)
        ..quadraticBezierTo(w * 0.84, h * 0.87, w, h * 0.81)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close(),
      Paint()..color = isDark ? const Color(0xFF1B2B3C) : const Color(0xFFF5F9FF),
    );
  }

  void _ridge(
    Canvas canvas,
    double w,
    double h,
    List<(double, double)> points,
    double base,
    Color color,
  ) {
    final path = Path()..moveTo(-w * 0.05, h * base);
    for (final point in points) {
      path.lineTo(w * point.$1, h * point.$2);
    }
    path
      ..lineTo(w * 1.05, h * base)
      ..lineTo(w * 1.05, h)
      ..lineTo(-w * 0.05, h)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_CalmPainter oldDelegate) => oldDelegate.isDark != isDark;
}

/// The "Finish setting up your app" strip's leading glyph.
///
/// The reference's `blocker_set_up_icon` is a 33 x 33 vector: a wrench inside
/// a thin ring. The path data below is reproduced verbatim from the APK so the
/// strip reads identically; the glyph itself shows no animate being.
class BpSetupIcon extends StatelessWidget {
  final double size;
  final Color color;

  const BpSetupIcon({super.key, this.size = 26, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _SetupIconPainter(color: color)),
    );
  }
}

class _SetupIconPainter extends CustomPainter {
  final Color color;

  _SetupIconPainter({required this.color});

  /// The APK's vector path, split into its three subpaths: the wrench, the
  /// outer edge of the ring and the ring's inner edge.
  static const _wrench =
      'M21.921,23.396L23.211,22.106C23.331,21.988 23.391,21.85 23.391,21.692'
      'C23.391,21.534 23.331,21.395 23.211,21.275L17.981,16.037'
      'C18.125,15.768 18.234,15.476 18.306,15.162C18.378,14.848 18.414,14.504 '
      '18.414,14.131C18.414,12.919 17.981,11.883 17.115,11.022'
      'C16.249,10.161 15.207,9.731 13.988,9.731C13.786,9.731 13.593,9.742 '
      '13.409,9.765C13.226,9.788 13.043,9.828 12.86,9.884'
      'C12.695,9.941 12.594,10.057 12.557,10.233C12.52,10.409 12.564,10.56 '
      '12.689,10.686L15.022,13.044L12.885,15.181L10.5,12.822'
      'C10.375,12.697 10.224,12.653 10.048,12.689C9.872,12.727 9.752,12.83 '
      '9.689,13C9.641,13.188 9.605,13.377 9.581,13.565C9.558,13.754 9.546,'
      '13.948 9.546,14.147C9.546,15.366 9.979,16.408 10.845,17.274'
      'C11.711,18.14 12.753,18.573 13.972,18.573C14.321,18.573 14.65,18.533 '
      '14.958,18.451C15.267,18.37 15.574,18.266 15.878,18.139L21.117,23.37'
      'C21.237,23.49 21.371,23.554 21.519,23.563C21.667,23.572 21.801,23.516 '
      '21.921,23.396Z';

  static const _ringOuter =
      'M16.504,28.875C14.793,28.875 13.184,28.55 11.678,27.901'
      'C10.172,27.251 8.861,26.37 7.747,25.257C6.632,24.143 5.75,22.834 '
      '5.1,21.329C4.45,19.824 4.125,18.216 4.125,16.504C4.125,14.793 4.45,'
      '13.184 5.099,11.678C5.749,10.172 6.63,8.861 7.743,7.747'
      'C8.857,6.632 10.166,5.75 11.671,5.1C13.176,4.45 14.784,4.125 '
      '16.496,4.125C18.207,4.125 19.816,4.45 21.322,5.099'
      'C22.828,5.749 24.139,6.63 25.253,7.743C26.368,8.857 27.25,10.166 '
      '27.9,11.671C28.55,13.176 28.875,14.784 28.875,16.496'
      'C28.875,18.207 28.55,19.816 27.901,21.322C27.251,22.828 26.37,24.139 '
      '25.257,25.253C24.143,26.368 22.834,27.25 21.329,27.9'
      'C19.824,28.55 18.216,28.875 16.504,28.875Z';

  static const _ringInner =
      'M16.5,27.5C19.571,27.5 22.172,26.434 24.303,24.303'
      'C26.434,22.172 27.5,19.571 27.5,16.5C27.5,13.429 26.434,10.828 '
      '24.303,8.697C22.172,6.566 19.571,5.5 16.5,5.5C13.429,5.5 10.828,6.566 '
      '8.697,8.697C6.566,10.828 5.5,13.429 5.5,16.5C5.5,19.571 6.566,22.172 '
      '8.697,24.303C10.828,26.434 13.429,27.5 16.5,27.5Z';

  static final Path _wrenchPath = _parse(_wrench);
  static final Path _ringOuterPath = _parse(_ringOuter);
  static final Path _ringInnerPath = _parse(_ringInner);

  /// Parses the APK's path data. Only the commands the icon uses are
  /// supported: M, L, C and Z.
  static Path _parse(String data) {
    final path = Path();
    final tokens = data.split(RegExp(r'([MLCZ])'));
    var i = 1;
    while (i < tokens.length) {
      final command = tokens[i];
      final values = tokens[i + 1]
          .split(RegExp(r'[ ,]+'))
          .where((s) => s.isNotEmpty)
          .map(double.parse)
          .toList();
      switch (command) {
        case 'M':
          path.moveTo(values[0], values[1]);
        case 'L':
          path.lineTo(values[0], values[1]);
        case 'C':
          path.cubicTo(
            values[0],
            values[1],
            values[2],
            values[3],
            values[4],
            values[5],
          );
        case 'Z':
          path.close();
      }
      i += 2;
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 33;
    canvas.save();
    canvas.scale(scale);
    final paint = Paint()..color = color;
    // The ring is the difference between the outer and inner circles, so it is
    // drawn with the difference operator to leave the middle hollow.
    final ring = Path.combine(
      PathOperation.difference,
      _ringOuterPath,
      _ringInnerPath,
    );
    canvas.drawPath(ring, paint);
    canvas.drawPath(_wrenchPath, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SetupIconPainter oldDelegate) => oldDelegate.color != color;
}
