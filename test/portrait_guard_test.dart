import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:haram_blur/src/detection_data.dart';
import 'package:haram_blur/src/policy.dart';
import 'package:haram_blur/src/skin_exposure.dart';

const _skin = [222, 172, 140];
const _cloth = [38, 42, 52];

/// Synthetic face+neck region in the 240x480 figure below.
const _face = Rect.fromLTRB(80, 20, 161, 119);
const _smallFace = Rect.fromLTRB(100, 20, 140, 60);

img.Image personImage({
  required bool bareTorso,
  required bool bareFace,
  bool hands = false,
}) {
  final image = img.Image(width: 240, height: 480);
  img.fill(image, color: img.ColorRgb8(245, 245, 245));

  void rect(int x1, int y1, int x2, int y2, List<int> rgb) {
    img.fillRect(
      image,
      x1: x1,
      y1: y1,
      x2: x2,
      y2: y2,
      color: img.ColorRgb8(rgb[0], rgb[1], rgb[2]),
    );
  }

  rect(50, 110, 190, 460, _cloth);
  if (bareFace) rect(80, 20, 160, 100, _skin);
  if (bareFace) rect(105, 100, 135, 118, _skin);
  if (bareTorso) {
    rect(55, 150, 185, 300, _skin);
    rect(65, 300, 120, 430, _skin);
    rect(125, 300, 180, 430, _skin);
  }
  if (hands) {
    rect(40, 210, 60, 250, _skin);
    rect(180, 210, 200, 250, _skin);
  }
  return image;
}

Rect fullBox(img.Image image) =>
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());

SkinExposure exposureOf(img.Image image, {List<Rect> faces = const []}) =>
    measureSkinExposure(image, fullBox(image), faces: faces);

FrameResult frameWith(img.Image image, double ratio) => FrameResult(
      imageSize: Size(image.width.toDouble(), image.height.toDouble()),
      nsfwScore: 0,
      persons: [
        PersonVerdict(
          box: fullBox(image),
          awrahSkinFraction: 0,
          exposedRatio: ratio,
        ),
      ],
    );

void main() {
  test('the top 40% of the box never counts as exposed skin', () {
    // Hijab portrait with a bare face and no ML Kit face box: the head is the
    // only skin in the frame, so the fail-safe must return exactly zero.
    final hijab = personImage(bareTorso: false, bareFace: true);
    final exposure = exposureOf(hijab);

    expect(exposure.ratio, 0);
  });

  test('a bare face above the 40% line is not exposed skin', () {
    final portrait = personImage(bareTorso: false, bareFace: true);
    final withoutFace = exposureOf(portrait);
    final withFace = exposureOf(portrait, faces: const [_face]);

    // The face box is still reported as removed face skin (ML Kit exclusion),
    // and the head contributes nothing either way.
    expect(withFace.facePixels, greaterThan(0));
    expect(withFace.ratio, 0);
    expect(withoutFace.ratio, 0);
  });

  test('face and neck skin below the 40% line is still excluded', () {
    final image = img.Image(width: 240, height: 480);
    img.fill(image, color: img.ColorRgb8(245, 245, 245));
    img.fillRect(
      image,
      x1: 40,
      y1: 192,
      x2: 200,
      y2: 470,
      color: img.ColorRgb8(38, 42, 52),
    );
    // Skin under the expanded face box, below the head cut.
    img.fillRect(
      image,
      x1: 90,
      y1: 200,
      x2: 150,
      y2: 300,
      color: img.ColorRgb8(222, 172, 140),
    );

    final withoutFace = exposureOf(image);
    final withFace = exposureOf(
      image,
      faces: const [Rect.fromLTRB(80, 190, 170, 320)],
    );

    expect(withoutFace.ratio, greaterThan(0));
    expect(withFace.facePixels, greaterThan(0));
    expect(withFace.ratio, lessThan(withoutFace.ratio));
    expect(withFace.ratio, 0);
  });

  test('a portrait box needs more than 25% skin to block at level 10', () {
    final config = BlurConfig.forSensitivity(10);
    const portrait = Rect.fromLTRB(100, 10, 180, 470); // 80 x 460

    List<BlurRegion> regions(double ratio) => BlurPolicy(config).apply(
          FrameResult(
            imageSize: const Size(240, 480),
            nsfwScore: 0,
            persons: [
              PersonVerdict(
                box: portrait,
                awrahSkinFraction: 0,
                exposedRatio: ratio,
              ),
            ],
          ),
        );

    expect(regions(0.10), isEmpty);
    expect(regions(0.24), isEmpty);
    expect(regions(0.30), isNotEmpty);
  });

  test('a wide face box marks a close-up portrait', () {
    final portrait = personImage(bareTorso: false, bareFace: true);
    final exposure = exposureOf(
      portrait,
      faces: const [Rect.fromLTRB(50, 10, 200, 140)],
    );
    expect(exposure.closeUp, isTrue);

    final normal = exposureOf(portrait, faces: const [_smallFace]);
    expect(normal.closeUp, isFalse);
  });

  test('portraits and clothed figures produce zero regions at every level', () {
    final portraits = {
      'hijab_portrait': personImage(bareTorso: false, bareFace: true),
      'niqab_portrait': personImage(bareTorso: false, bareFace: true),
      'abaya_niqab': personImage(bareTorso: false, bareFace: false),
      'fully_clothed': personImage(bareTorso: false, bareFace: false),
      'fully_clothed_hands': personImage(
        bareTorso: false,
        bareFace: true,
        hands: true,
      ),
    };

    for (final entry in portraits.entries) {
      final exposure = exposureOf(entry.value, faces: const [_face]);
      for (var level = 1; level <= 10; level++) {
        final config = BlurConfig.forSensitivity(level);
        final regions =
            BlurPolicy(config).apply(frameWith(entry.value, exposure.ratio));
        expect(
          regions,
          isEmpty,
          reason: '${entry.key} blurred at sensitivity $level '
              '(ratio ${exposure.ratio.toStringAsFixed(3)}, '
              'threshold ${config.skinThreshold})',
        );
      }
    }
  });

  test('bikini skin still fires at sensitivity 10 with a face box', () {
    final bikini = personImage(bareTorso: true, bareFace: true);
    final exposure = exposureOf(bikini, faces: const [_face]);
    final config = BlurConfig.forSensitivity(10);

    expect(exposure.ratio, greaterThan(config.skinThreshold));
    final regions = BlurPolicy(config).apply(frameWith(bikini, exposure.ratio));
    expect(regions, isNotEmpty);
  });

  test('the eval face_boxes.json covers images and is well formed', () {
    final file = File('tests/eval_set/face_boxes.json');
    expect(file.existsSync(), isTrue);
    final boxes = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(boxes, isNotEmpty);

    for (final entry in boxes.entries) {
      for (final box in entry.value as List) {
        expect(box, hasLength(4));
        final values = (box as List).cast<num>();
        expect(values[0], inInclusiveRange(0, 1));
        expect(values[1], inInclusiveRange(0, 1));
        expect(values[2], greaterThan(values[0]));
        expect(values[3], greaterThan(values[1]));
      }
    }

    // A real close-up portrait with a detected face must lose most of its
    // exposed-skin ratio once the face box is applied.
    final name = 'hijab_03.jpg';
    final raw = boxes[name] as List?;
    if (raw != null && raw.isNotEmpty) {
      final image = img.decodeImage(
        File('tests/eval_set/images/$name').readAsBytesSync(),
      )!;
      final faces = [
        for (final box in raw)
          Rect.fromLTRB(
            (box as List)[0] * image.width,
            box[1] * image.height,
            box[2] * image.width,
            box[3] * image.height,
          ),
      ];
      final withFace = measureSkinExposure(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        faces: faces,
      );
      expect(withFace.closeUp || withFace.ratio < 0.18, isTrue);
    }
  });

  test('the all-sensitivity threshold curve is unchanged', () {
    expect(BlurConfig.forSensitivity(10).skinThreshold, closeTo(0.20, 0.001));
    for (var level = 1; level < 10; level++) {
      expect(
        BlurConfig.forSensitivity(level).skinThreshold,
        greaterThanOrEqualTo(
          BlurConfig.forSensitivity(level + 1).skinThreshold,
        ),
      );
    }
  });
}
