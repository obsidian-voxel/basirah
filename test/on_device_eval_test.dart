import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:haram_blur/src/detection_engine.dart';
import 'package:haram_blur/src/on_device_eval.dart';
import 'package:haram_blur/src/policy.dart';

/// Runs the bundled eval set through the exact runtime path (capture excluded)
/// and checks it against `tools/evaluate.py` at sensitivity 6:
/// recall 0.970, benign 0.027, 0 forbidden.
void main() {
  // rootBundle serves the bundled eval labels/images in this test.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('runtime eval matches tools/evaluate.py within 2 points', () async {
    final engine = DetectionEngine();
    addTearDown(engine.dispose);
    await engine.initialize();

    // The Windows host's LiteRT build fails Invoke for this quantised ViT even
    // with a zeroed input (verified separately), so this integration test is
    // only meaningful on a device/emulator. It still runs there.
    try {
      engine.nsfwScoreOf(img.Image(width: 224, height: 224));
    } catch (error) {
      markTestSkipped(
        'Host LiteRT cannot execute nsfw_int8.tflite: $error. '
        'Run on a device with the hidden Settings action instead.',
      );
      return;
    }

    final report = await OnDeviceEval.run(
      engine: engine,
      config: BlurConfig.forSensitivity(6),
      loadBytes: (name) => File('tests/eval_set/images/$name').readAsBytes(),
    );

    // ignore: avoid_print
    print('on-device eval: ${report.summary}');
    for (final stat in report.classes) {
      // ignore: avoid_print
      print('  ${stat.name}: ${stat.blurred}/${stat.total}');
    }

    expect(report.recall, closeTo(0.970, 0.02));
    expect(report.falsePositiveRate, closeTo(0.027, 0.02));
    expect(report.forbiddenBlurred, 0);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
