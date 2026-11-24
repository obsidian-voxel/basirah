import 'dart:math';
import 'dart:ui' show Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter_litert/flutter_litert.dart';
import 'package:image/image.dart' as img;

import 'detection_data.dart';
import 'frame_pixels.dart';
import 'preprocessing.dart';
import 'segmentation.dart';
import 'skin_exposure.dart';

/// On-device detection cascade (TFLite, no network):
///
///   nsfw_int8.tflite            → whole-frame nudity / sexual-content score
///   selfie_multiclass_256x256   → per-pixel person + skin segmentation
///
/// Person boxes are derived from the segmentation map with connected
/// components. The previous implementation decoded BlazePose anchor tensors
/// incorrectly (sigmoid on already-decoded coordinates plus a fixed-size box),
/// which produced meaningless regions; segmentation is both simpler and more
/// accurate for the awrah band this app needs.
class DetectionEngine {
  static const String nsfwAsset = 'assets/models/nsfw_int8.tflite';
  static const String segmentationAsset =
      'assets/models/selfie_multiclass_256x256.tflite';

  static const int _nsfwSize = 224;
  static const int _segSize = 256;
  static const int _segClasses = 6;

  Interpreter? _nsfw;
  Interpreter? _segmentation;
  Future<void>? _loading;
  String? _error;

  /// True when the nudity classifier is loaded. Segmentation is optional: if
  /// it fails, whole-frame detection still works and awrah bands are skipped.
  bool get isReady => _nsfw != null;

  bool get hasSegmentation => _segmentation != null;

  /// Last initialisation error, if any (shown in the UI instead of failing
  /// silently).
  String? get error => _error;

  Future<void> initialize() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final options = InterpreterOptions()..threads = 4;
      _nsfw = await Interpreter.fromAsset(nsfwAsset, options: options);
      // The exported classifier declares a placeholder dynamic shape
      // ([1, 1, 1, 3]); pin it to the real input size.
      _nsfw!.resizeInputTensor(0, [1, _nsfwSize, _nsfwSize, 3]);
      _nsfw!.allocateTensors();
      debugPrint('Basirah: NSFW Model loaded successfully');
    } catch (e) {
      _error = 'Nudity model failed to load: $e';
      _nsfw = null;
      debugPrint('Basirah: NSFW model failed to load - $_error');
    }
    try {
      final options = InterpreterOptions()..threads = 2;
      _segmentation =
          await Interpreter.fromAsset(segmentationAsset, options: options);
    } catch (e) {
      _segmentation = null;
    }
  }

  /// Runs the cascade on raw ARGB pixels captured by Android.
  ///
  /// Padded rows (hardware-buffer stride) are tightened first; every later
  /// stage operates on the tightened image, so a padded screenshot cannot
  /// shear into a different picture than the one being scored.
  Future<FrameResult> analyzePixels(
    FramePixels frame, {
    List<Rect> faces = const [],
  }) async {
    await initialize();
    return analyze(frame.toImage(), faces: faces);
  }

  /// Whole-frame nudity probability for an arbitrary image (a crop, in the
  /// screen gate). Uses the single shared preprocessing path.
  double nsfwScoreOf(img.Image image) {
    final interp = _nsfw;
    if (interp == null) {
      throw StateError(_error ?? 'Detection engine is not available');
    }
    final input = FramePreprocessor.nsfwInput(image);
    final output = Float32List(2);
    interp.run(input, output);
    final maxLogit = max(output[0], output[1]);
    final e0 = exp(output[0] - maxLogit);
    final e1 = exp(output[1] - maxLogit);
    final sum = e0 + e1;
    if (sum <= 0 || sum.isNaN) {
      return 0;
    }
    return (e1 / sum).clamp(0.0, 1.0);
  }

  /// Runs the cascade on one decoded image.
  Future<FrameResult> analyze(
    img.Image image, {
    List<Rect> faces = const [],
  }) async {
    await initialize();
    final classifier = _nsfw;
    if (classifier == null) {
      throw StateError(_error ?? 'Detection engine is not available');
    }
    if (image.width == 0 || image.height == 0) {
      throw ArgumentError('Image has no pixels');
    }

    final size = Size(image.width.toDouble(), image.height.toDouble());
    final score = _nsfwScore(image, classifier);

    var persons = const <PersonVerdict>[];
    final segmenter = _segmentation;
    if (segmenter != null) {
      final map = _segment(image, segmenter);
      final mask = map.personMask(size);
      final maskWidth = size.width.round();
      final maskHeight = size.height.round();
      persons = [
        for (final box in map.personBoxesIn(size))
          _verdict(image, map, box, size, faces, mask, maskWidth, maskHeight),
      ];
    }

    return FrameResult(
      imageSize: size,
      nsfwScore: score,
      persons: persons,
    );
  }

  double _skinInBand(SegmentationMap map, Rect box, Size size) {
    final band = awrahBand(box);
    if (band == null) return 0;
    return map.skinFraction(band, size);
  }

  /// One person's exposure evidence.
  ///
  /// The ratio counts skin only over segmented person pixels and removes every
  /// skin pixel inside a face box. When a face box is at least 60% as wide as
  /// the person box, the person is a close-up portrait: its 42–92% "band" is
  /// the face/neck, so the band rule is suppressed for that person entirely.
  PersonVerdict _verdict(
    img.Image image,
    SegmentationMap map,
    Rect box,
    Size size,
    List<Rect> faces,
    Uint8List mask,
    int maskWidth,
    int maskHeight,
  ) {
    final exposure = measureSkinExposure(
      image,
      box,
      faces: faces,
      personMask: mask,
      maskWidth: maskWidth,
      maskHeight: maskHeight,
    );
    return PersonVerdict(
      box: box,
      awrahSkinFraction: exposure.closeUp ? 0 : _skinInBand(map, box, size),
      exposedRatio: exposure.ratio,
    );
  }

  /// Whole-frame nudity/sexual-content probability.
  ///
  /// The model emits two logits (`[benign, nudity]`); softmax turns them into
  /// a probability. The old code read `output[1]` of a two-element buffer and
  /// treated a raw logit as a probability.
  double _nsfwScore(img.Image image, Interpreter interp) {
    return nsfwScoreOf(image);
  }

  SegmentationMap _segment(img.Image image, Interpreter interp) {
    final input = FramePreprocessor.segInput(image);
    final output = Float32List(_segSize * _segSize * _segClasses);
    interp.run(input, output);
    return SegmentationMap.fromLogits(
      width: _segSize,
      height: _segSize,
      logits: output,
      classCount: _segClasses,
    );
  }

  void dispose() {
    _nsfw?.close();
    _segmentation?.close();
    _nsfw = null;
    _segmentation = null;
    _loading = null;
  }
}
