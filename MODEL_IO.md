# Model I/O contracts

The contracts below are what the Dart `DetectionEngine`, the Android
`MLProcessor` and `tools/evaluate.py` all use. Only the first two files are
listed in `pubspec.yaml`, so they are the only models bundled in the app.

## `nsfw_int8.tflite` — whole-frame nudity gate (SHIPPED)

- Source: ViT nudity classifier fine-tuned on the DarkyMan set (POSITIVE) vs
  COCO val2017 (NEGATIVE); eval images are disjoint by filename.
- Quantisation: dynamic int8 weights, fp32 activations, produced with
  `ai-edge-quantizer` (`recipe.dynamic_wi8_afp32()`). 84 MB instead of 328 MB
  with identical decisions on the eval set (96.7% recall, 0 FP before the
  awrah stage).
- Input: `[1, 224, 224, 3]` float32, `pixel / 255` → `[0, 1]`.
- Output: `[1, 2]` float32 logits, `[benign, nudity]`.
- Decision: `softmax(logits)[1] >= gate`.
- Runtime quirk: the exported graph advertises `[1, 1, 1, 3]`, so both the
  Dart and Kotlin loaders must resize the input explicitly and reallocate:

  ```dart
  interp.resizeInputTensor(0, [1, 224, 224, 3]);
  interp.allocateTensors();
  ```

  ```kotlin
  interp.resizeInput(0, intArrayOf(1, 224, 224, 3)); // LiteRT 1.4 renamed it
  interp.allocateTensors();
  ```

  (`resizeInputTensor` does not exist in `com.google.ai.edge.litert` 1.4.x;
  using it fails compilation, which is how the native side was fixed.)

## `selfie_multiclass_256x256.tflite` — pixel classes (SHIPPED)

- MediaPipe Selfie Multiclass, Apache-2.0.
- Input: `[1, 256, 256, 3]` float32, `pixel / 127.5 - 1` → `[-1, 1]`.
- Output: `[1, 256, 256, 6]` float32 logits. Classes: 0 background, 1 hair,
  2 body-skin, 3 face-skin, 4 clothes, 5 accessories.
- Used for: person boxes (4-connected components over classes 1..5, minimum
  1% of the map, largest 6, mapped back to image pixels) and skin fraction
  inside a person's awrah band (classes 2 and 3).

## Awrah band geometry

- Band = person box from 42% to 92% of its height, full width.
- Blurred when `skinFraction(band) >= awrahSkinThreshold`.
- Painted region = band padded by 5% of its own size, clamped to the image.

## Retired / not shipped

| File | Why it is not used |
|---|---|
| `nsfw.tflite` (328 MB) | fp32 original; int8 matches it on eval |
| `nsfw_float16.tflite` (164 MB) | larger than int8, no accuracy gain |
| `nsfw_int4.tflite` (114 MB) | larger than int8 export; int8 chosen |
| `nsfw_classifier.tflite` (12 MB) | byte-identical to the broken NudeNet export, AUC ≈ 0.5, saturated logits |
| `nudennet_320n.onnx/.tflite` | NudeNet v3.4 heads saturate on every image (AGPL-3.0) |
| `pose_detection.tflite`, `pose_landmarks_detector.tflite` | anchor decoding was wrong and unnecessary now that segmentation provides person boxes |
| `blaze_face_short_range.tflite` | face blurring is out of scope |
| `gender.tflite`, `beard.tflite` | gender classification is intentionally not part of the design |

These files still exist on disk (≈660 MB) for provenance. Deleting them does not
affect the app, but there is no git history here, so keep a copy first.

## Region kinds (`BlurKind`)

`nudity` (whole frame or a padded region hit) and `awrah` (uncovered band).
There are no gender-specific kinds: the app blurs nudity/exposure for every
person equally.

## Probe / eval tools

- `tools/probe_models.py` prints input/output shapes with `ai_edge_litert`.
- `tools/evaluate.py` re-implements the shipped cascade in Python (same models,
  same preprocessing, same thresholds) and fails when recall or FP targets are
  missed.
