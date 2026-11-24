import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../src/detection_engine.dart';
import '../src/policy.dart';
import '../src/screen_gate.dart';

/// Headless entrypoint (`detectorMain` in `main.dart`).
///
/// The accessibility service starts a background FlutterEngine with this
/// function, sends raw screenshot pixels and receives policy regions. There is
/// no second inference implementation: this is the same engine the Image lab,
/// the tests and the on-device eval use.
@pragma('vm:entry-point')
Future<void> runDetectorEngine() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.haramblur.haram_blur/detector');
  final engine = DetectionEngine();

  channel.setMethodCallHandler((call) async {
    if (call.method != 'analyze') return null;
    final arguments = Map<Object?, Object?>.from(call.arguments as Map);
    final width = (arguments['width'] as num).toInt();
    final height = (arguments['height'] as num).toInt();
    final stride = (arguments['stride'] as num?)?.toInt() ?? width;
    final sensitivity = (arguments['sensitivity'] as num?)?.toInt() ?? 5;
    // Excluded apps still get the whole-frame nudity gate; only the
    // segmentation-based awrah stage is switched off for them.
    final allowAwrah = arguments['allowAwrah'] as bool? ?? true;
    final raw = arguments['pixels'];
    final pixels = raw is Int32List
        ? raw
        : Int32List.fromList((raw as List<Object?>).cast<num>().map((n) => n.toInt()).toList());

    final image = frameToImage(
      width: width,
      height: height,
      stride: stride,
      pixels: pixels,
    );

    // Normalised face boxes from ML Kit, converted into working-frame pixels.
    final faces = <Rect>[];
    final rawFaces = arguments['faces'];
    if (rawFaces is List) {
      for (final entry in rawFaces) {
        if (entry is List && entry.length >= 4) {
          faces.add(Rect.fromLTRB(
            (entry[0] as num).toDouble() * width,
            (entry[1] as num).toDouble() * height,
            (entry[2] as num).toDouble() * width,
            (entry[3] as num).toDouble() * height,
          ));
        }
      }
    }

    final config = BlurConfig.forSensitivity(sensitivity);
    final result = await analyzeScreen(
      engine,
      image,
      config,
      allowAwrah: allowAwrah,
      faces: faces,
    );
    final size = Size(width.toDouble(), height.toDouble());
    debugPrint(
      'Basirah: Capture analyzed - NSFW: '
      '${result.score.toStringAsFixed(3)}, Skin: '
      '${result.maxExposed.toStringAsFixed(3)}',
    );

    return <String, Object?>{
      'score': result.score,
      'fullScore': result.fullScore,
      'gate': result.gate,
      'blurred': result.blurred,
      'personCount': result.personCount,
      'maxExposed': result.maxExposed,
      'elapsedMs': result.elapsedMs,
      'coverage': result.coverage(size),
      'regions': [
        for (final region in result.regions)
          <Object?>[
            region.rect.left,
            region.rect.top,
            region.rect.right,
            region.rect.bottom,
            region.confidence,
            region.kind.name,
            region.evidence,
            region.rule,
          ],
      ],
    };
  });

  // Load the models before reporting ready so the first capture is not dropped
  // while the 88 MB classifier initialises.
  await engine.initialize();
  await channel.invokeMethod<void>('ready');
}
