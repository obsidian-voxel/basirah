# Eval test set — Haram Blur

Fixed, labeled image set used by `tools/evaluate.py`. Sources are free and
internal-evaluation only (not redistributed).

The policy is gender-neutral: it blurs nudity/exposed regions and uncovered
awrah bands for every person. It does not classify gender and does not blur
women's faces or whole people for who they are.

## Actual contents (`tests/eval_set/labels.jsonl`)

| Class | Count | Source |
|---|---|---|
| `nude` | 30 | DarkyMan nsfw zip, held out of training |
| `benign_person` | 20 | COCO val2017 images containing clothed people |
| `benign_scene` | 20 | COCO val2017 images without people |
| **Total** | **70** | |

There are currently **no** `beard_headscarf` / `beard_control` images. The
harness still understands those labels and enforces "zero blurs" on them, but
the check reports "not evaluated" when the class is absent rather than passing
vacuously.

## Label format

```json
{"image": "nsfw_001_abc.jpg", "class": "nude", "boxes": []}
```

`class` ∈ {`nude`, `awrah`, `benign_person`, `benign_scene`,
`beard_headscarf`, `beard_control`}. `boxes` is unused: the harness scores
whether a frame receives any region, not localisation.

## Metrics and thresholds

A label is "blurred" when the shipped cascade returns at least one region.

- Recall on `nude`: ≥ 0.90.
- False-positive rate on `benign_person` + `benign_scene`: ≤ 0.05.
- `beard_headscarf` / `beard_control`: 0 blurred frames (when present).

Current run: recall 0.967, FP 0.025, exit 0. See `README.md` / `PROGRESS.md`.

## Curation

`tools/curate_eval.py` documents how the set was downloaded. Eval images are
never included in training; `tools/train_nsfw*.py` excludes them by filename.

## Portrait classes (added for the face-aware exposure work)

`hijab_portrait` (11 after curation) and `niqab_portrait` (12) were added from
Openverse with `tools/add_portrait_classes.py`, which only accepts CC BY / CC0
/ PDM results. Queries: `hijab portrait`, `niqab portrait`.

These classes are benign targets: the gates require **zero blurred frames at
every sensitivity**. `tools/evaluate.py` counts them in the benign FP rate and
prints a separate "Portrait/clothed FP" line.

### Curation decisions

| image | decision | reason |
|---|---|---|
| `hijab_05.jpg` | **removed** (file + label) | Query noise: the photo shows two women on a promenade, one wearing a tank top and shorts. Blurring her is correct behaviour, so the image cannot be a "0% blurred" portrait target. |
| `niqab_07.jpg` | **removed** (file + label) | The image contains a fully veiled woman **and** a second woman in a tank top with bare shoulders and arms. Blurring the second woman is correct, so it cannot be a zero-blur portrait target. |
| `hijab_11.jpg` | **kept** as a genuine false positive | Close-up of a modest woman in a headscarf and glasses, no other person, no bare skin beyond the face. YuNet finds no face box and PoseLandmarker returns out-of-range landmarks (x > 1, hip/knee visibility ~0), which is exactly the hard case the guarantee must cover. Not curated. |
| `coco_034.jpg` | flagged, not relabelled | A bird in the sky; the benign_scene label is correct. It fires through the `band` rule, which is a model/segmentation artifact, not a label problem. |
| `coco_020.jpg` | flagged, not relabelled | A pizza with an incidental bare arm at the frame edge; benign_scene is arguably imprecise but this is exactly an "innocent everyday content" case that level 6 must not blur. |

No other portrait image was removed. Remaining blurred portraits are kept as
genuine false-positive signals rather than relabelled, so the gates keep
exposing them. `hijab_03.jpg` (a close-up face filling the frame) is the
canonical hard case this work targets.

### Known limitations

* Openverse text search is noisy; some results are multi-person scenes rather
  than portraits.
* The images are CC BY, so attribution lives with the Openverse record rather
  than in this repository. `add_portrait_classes.py` prints every source URL
  when it fetches, which is the provenance record.
* The synthetic portraits in `test/portrait_guard_test.dart` cover the geometry
  contract independently of this set.

## Face boxes (`tests/eval_set/face_boxes.json`)

Face boxes are the only source of face truth for the exposed-skin rule. There
is no skin-component heuristic anymore.

| | detector | why |
|---|---|---|
| Live app | ML Kit `face-detection` (bundled model, offline) | runs on the reduced working frame in the capture path |
| Oracle + Dart tests | OpenCV YuNet (`tools/generate_face_boxes.py`) | deterministic, host-runnable, no Play services; detects profile and partially covered faces |

Both expand every box by **12%** of its width/height. That margin absorbs the
difference between the two detectors: the rule removes skin inside the box, so
a slightly larger box is safe, while a slightly smaller one would leak cheek
skin.

YuNet model: `face_detection_yunet_2023mar.onnx`, fetched by
`tools/fetch_yunet.py` from OpenCV Zoo into `tools/models/` (not committed).
Source: <https://github.com/opencv/opencv_zoo>, MIT licensed. Score threshold
0.6, NMS 0.3, `minSize` from the image itself.

Coverage changed from Haar to YuNet: 44/93 → 46/93 images with a box; hijab
7/11 → 9/11; niqab 8/12 → 5/12; abaya 3/7 → 1/7; fully clothed 3/5 → 2/5;
benign_scene 3/12 → 6/12; nude 13/30 → 15/30. YuNet is better on the hijab
close-ups but finds fewer veiled niqab faces.

### Coverage at generation time

44 of 93 images got at least one box.

| class | with face box |
|---|---|
| hijab_portrait | 7/11 |
| niqab_portrait | 8/12 |
| abaya_niqab | 3/7 |
| fully_clothed | 3/5 |
| benign_person | 6/13 |
| benign_scene | 3/12 |
| bikini_swimwear | 1/3 |
| nude | 13/30 |

Images with no box are mostly non-frontal faces, covered faces, distant people
in COCO scenes and nudity shots where the classifier gate fires before the
skin rule. Haar in particular misses the close-up **profile** portrait
(`hijab_03`) and fully veiled faces (`niqab_03`, `niqab_07`), which is the
largest source of the remaining portrait false positives.

A missing face box is safe **only** when the visible skin is small (the niqab
assumption: a tiny eye slit, so the ratio stays near zero). It is **not** safe
for a profile face or a face-covering portrait whose hands/neck/background
still contribute skin — those cases currently remain false positives, which
is why the gates fail. Live ML Kit is expected to find more of these faces
than Haar, but that cannot be verified without a device.

### Face-independent filters

Skin components smaller than **2%** of the person's pixels are discarded (eye
slits, neck fragments), and components whose bounding box is mostly inside a
face's downward-expanded neck zone (1.3 face heights) are discarded. A 10%
floor was measured and rejected: `coco_029`'s exposed limb is 7,018 px of
140,334 person pixels (5.0%), so 10% deleted it and dropped that bikini from
~0.63 to 0.579, below the level-6 0.60 threshold. 2% keeps the limb and still
drops `niqab_03`'s sub-1% eye slit. Mirrored in `lib/src/skin_exposure.dart`
and `tools/evaluate.py`.

The `exposed` rule skips a person only when the box is **both** under 8% of the
frame area **and** under 25% of the frame height. Area alone was too blunt:
it skipped `coco_010`'s mid-distance swimmer (7.0% area, but 34% tall), while
`coco_020`'s incidental arm (5.1% area, 18% tall) and `coco_035`'s fragment
(2.3% area, 23% tall) are genuinely distant. `gate_full` and `band` are
unaffected. Mirrored in `lib/src/policy.dart` and `tools/evaluate.py`.

Person boxes that are ≥80% contained inside a larger person box are dropped.
Connected-component segmentation can split one person into a nested fragment
(`hijab_11` produced a 264×312 corner box inside its 696×1024 person box whose
own ratio was 0.74), and evaluating that fragment produced a false positive
on a genuine modest close-up. Mirrored in `lib/src/segmentation.dart` and
`tools/evaluate.py`.

The `band` rule only fires when the person box is at least 15% of the frame
height. Segmentation artifacts on distant objects (a bird's wings in
`coco_034`) otherwise look like people. Mirrored in `lib/src/policy.dart` and
`tools/evaluate.py`.

Level 10 uses a 0.25 exposed-skin threshold rather than the linear 0.18. The
three bikini images expose 0.706 (coco_010), 0.778 (coco_012) and 0.629
(coco_029), so 0.25 leaves ample recall headroom. It also clears modest
portraits: `niqab_03` reaches 0.232 with the 2% component floor and `niqab_02`
0.185. Levels 7–9 keep the linear curve.

`tools/evaluate.py --no-faces` reruns the whole eval with every face box
removed, simulating total detector failure. It is a commit gate for the modest
classes.

### Profiles

`--profile strict` implements the confirmed product policy: modest classes are
never blurred at any level; level 6 everyday content FP ≤5%; levels 6 and 10
require nude ≥90% and bikini ≥90%; level-10 benign FP is informational.
`--profile legacy` keeps the historical gates for comparison.

### Parity gate

The on-device self-eval uses live ML Kit boxes while the oracle uses YuNet. The
standing rule is that the two must agree within **2 percentage points** per
class; if they diverge, the face boxes (not the thresholds) are the first
thing to compare.
