import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:haram_blur/src/preprocessing.dart';

/// Pins the Dart runtime preprocessing to the Python eval preprocessing.
///
/// `tools/gen_preprocessing_reference.py` writes PIL/numpy means for three eval
/// images; any change to resize filter, channel order or normalisation in
/// either implementation fails this test.
void main() {
  test('runtime preprocessing matches the Python eval within 1%', () {
    final fixture = File('test/fixtures/preprocessing_reference.json');
    expect(
      fixture.existsSync(),
      isTrue,
      reason: 'Run: python tools/gen_preprocessing_reference.py',
    );

    final data = jsonDecode(fixture.readAsStringSync()) as Map<String, dynamic>;
    final entries = data['entries'] as Map<String, dynamic>;
    expect(entries, hasLength(3));

    for (final entry in entries.entries) {
      final reference = entry.value as Map<String, dynamic>;
      final image = img.decodeImage(
        File('tests/eval_set/images/${entry.key}').readAsBytesSync(),
      );
      expect(image, isNotNull, reason: 'Could not decode ${entry.key}');

      final input = FramePreprocessor.nsfwInput(image!);
      expect(input.length, FramePreprocessor.nsfwSize * 224 * 3);

      final means = FramePreprocessor.channelMeans(input);
      final expected = (
        r: (reference['mean_r'] as num).toDouble(),
        g: (reference['mean_g'] as num).toDouble(),
        b: (reference['mean_b'] as num).toDouble(),
      );
      final diff = FramePreprocessor.maxRelativeDiff(means, expected);

      expect(
        diff,
        lessThan(0.01),
        reason: '${entry.key}: dart=$means python=$expected (diff %.4f)'
            .replaceFirst('%.4f', diff.toStringAsFixed(4)),
      );
    }
  });
}
