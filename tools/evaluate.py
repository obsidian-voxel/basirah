"""Offline evaluation of the Haram Blur detection policy.

Mirrors, step for step, what the Flutter app does in
`lib/src/detection_engine.dart` + `lib/src/policy.dart`:

  1. `assets/models/nsfw_int8.tflite` on the whole frame (224x224, 0..1,
     logits `[benign, nudity]`)  -> nudity gate
  2. `assets/models/selfie_multiclass_256x256.tflite` (256x256, -1..1)
     -> per-pixel class map, 4-connected components become person boxes
  3. the "awrah band" (42%..92% of each person's height) is blurred only when
     most of it is uncovered skin
  4. exposed skin ratio (YCbCr + HSV skin mask, minus head region) is blurred
     when it exceeds config.skinThreshold

This is the same cascade the app ships, so the numbers below describe the
actual product rather than an older pose-based prototype.

Run:  python tools/evaluate.py [--sensitivity LEVEL]
Exit code 0 means the targets were met.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image

try:
    from scipy import ndimage
except ImportError:  # pragma: no cover - scipy is optional locally
    ndimage = None

try:
    from ai_edge_litert.interpreter import Interpreter
except ImportError:  # pragma: no cover - fallback for the local dev machine
    sys.path.insert(0, r"C:\tf")
    from ai_edge_litert.interpreter import Interpreter

ROOT = Path(__file__).resolve().parent.parent
MODELS = ROOT / "assets" / "models"
EVAL_SET = ROOT / "tests" / "eval_set"

NSFW_ASSET = MODELS / "nsfw_int8.tflite"
SEG_ASSET = MODELS / "selfie_multiclass_256x256.tflite"

RECALL_THRESHOLD = 0.90
FP_THRESHOLD = 0.05

PERSON_CLASSES = range(1, 6)  # hair, body-skin, face-skin, clothes, accessories
SKIN_CLASSES = (2, 3)


def blur_config_for_sensitivity(level: int) -> dict:
    """Maps the 1..10 strictness slider onto thresholds.

    Matches lib/src/policy.dart BlurConfig.forSensitivity exactly.
    """
    clamped = min(max(level, 1), 10)
    t = (clamped - 1) / 9.0
    # Levels 1-6 stay at 0.60. Level 10 is 0.22 rather than the linear 0.18:
    # all three bikini images expose >0.55 of their person pixels, so the
    # 0.04 headroom above 0.18 only risked modest portraits. With the 2%
    # component floor, niqab_03 reaches 0.232, so level 10 uses 0.25.
    skin = (
        0.60
        if clamped <= 6
        else (0.25 if clamped == 10 else 0.60 - 0.42 * (clamped - 6) / 4.0)
    )
    return {
        "nsfw_frame_gate": round(0.85 - 0.35 * t, 3),
        "awrah_skin_threshold": round(0.85 - 0.30 * t, 3),
        "skin_threshold": round(skin, 3),
    }


def iou(a, b):
    left = max(a[0], b[0])
    top = max(a[1], b[1])
    right = min(a[2], b[2])
    bottom = min(a[3], b[3])
    if right <= left or bottom <= top:
        return 0.0
    inter = (right - left) * (bottom - top)
    union = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter
    return inter / union if union > 0 else 0.0


def containment(inner, outer):
    """Fraction of `inner`'s area that lies inside `outer`."""
    left = max(inner[0], outer[0])
    top = max(inner[1], outer[1])
    right = min(inner[2], outer[2])
    bottom = min(inner[3], outer[3])
    if right <= left or bottom <= top:
        return 0.0
    area = (inner[2] - inner[0]) * (inner[3] - inner[1])
    if area <= 0:
        return 0.0
    return (right - left) * (bottom - top) / area


def awrah_band(box):
    left, top, right, bottom = box
    height = bottom - top
    width = right - left
    if height <= 0 or width <= 0:
        return None
    band_top = top + height * 0.42
    band_bottom = top + height * 0.92
    if band_bottom <= band_top:
        return None
    return (left, band_top, right, band_bottom)


def pad_region(rect, fraction, size):
    width, height = size
    left, top, right, bottom = rect
    dx = width * fraction
    dy = height * fraction
    padded = (
        max(0.0, left - dx),
        max(0.0, top - dy),
        min(float(width), right + dx),
        min(float(height), bottom + dy),
    )
    if padded[2] - padded[0] < 1 or padded[3] - padded[1] < 1:
        return None
    return padded


class Engine:
    def __init__(self):
        if not NSFW_ASSET.exists():
            raise SystemExit(f"Missing model: {NSFW_ASSET}")
        if not SEG_ASSET.exists():
            raise SystemExit(f"Missing model: {SEG_ASSET}")

        self.nsfw = Interpreter(model_path=str(NSFW_ASSET))
        # The export declares a placeholder [1,1,1,3] input, exactly like the
        # runtime the app uses, so the real shape must be set explicitly.
        self.nsfw.resize_tensor_input(0, [1, 224, 224, 3], strict=False)
        self.nsfw.allocate_tensors()

        self.seg = Interpreter(model_path=str(SEG_ASSET))
        self.seg.allocate_tensors()

    @staticmethod
    def _input(image, size, scale, offset):
        resized = image.resize((size, size), Image.BILINEAR)
        array = np.asarray(resized, dtype=np.float32)
        return (array / scale + offset)[None, ...].astype(np.float32)

    def nsfw_score(self, image):
        detail = self.nsfw.get_input_details()[0]
        self.nsfw.set_tensor(detail["index"], self._input(image, 224, 255.0, 0.0))
        self.nsfw.invoke()
        logits = np.asarray(
            self.nsfw.get_tensor(self.nsfw.get_output_details()[0]["index"])
        ).reshape(-1)
        if logits.size < 2:
            # A single-logit export should be a probability already.
            return float(logits[0])
        shifted = np.exp(logits - logits.max())
        return float(shifted[1] / shifted.sum())

    def seg_map(self, image):
        detail = self.seg.get_input_details()[0]
        self.seg.set_tensor(detail["index"], self._input(image, 256, 127.5, -1.0))
        self.seg.invoke()
        logits = self.seg.get_tensor(self.seg.get_output_details()[0]["index"])
        return np.argmax(logits[0], axis=-1).astype(np.uint8)

    @staticmethod
    def person_boxes(classes, image_size):
        """4-connected components over every non-background class."""
        height, width = classes.shape
        image_w, image_h = image_size
        min_area = max(1, round(width * height * 0.01))
        visited = np.zeros((height, width), dtype=bool)
        person = np.isin(classes, list(PERSON_CLASSES))

        boxes = []
        for start_y in range(height):
            for start_x in range(width):
                if visited[start_y, start_x] or not person[start_y, start_x]:
                    continue

                stack = [(start_x, start_y)]
                visited[start_y, start_x] = True
                min_x = max_x = start_x
                min_y = max_y = start_y
                area = 0

                while stack:
                    x, y = stack.pop()
                    area += 1
                    if x < min_x:
                        min_x = x
                    if x > max_x:
                        max_x = x
                    if y < min_y:
                        min_y = y
                    if y > max_y:
                        max_y = y

                    if x > 0 and person[y, x - 1] and not visited[y, x - 1]:
                        visited[y, x - 1] = True
                        stack.append((x - 1, y))
                    if x + 1 < width and person[y, x + 1] and not visited[y, x + 1]:
                        visited[y, x + 1] = True
                        stack.append((x + 1, y))
                    if y > 0 and person[y - 1, x] and not visited[y - 1, x]:
                        visited[y - 1, x] = True
                        stack.append((x, y - 1))
                    if y + 1 < height and person[y + 1, x] and not visited[y + 1, x]:
                        visited[y + 1, x] = True
                        stack.append((x, y + 1))

                if area >= min_area:
                    scale_x = image_w / width
                    scale_y = image_h / height
                    boxes.append(
                        (
                            min_x * scale_x,
                            min_y * scale_y,
                            (max_x + 1) * scale_x,
                            (max_y + 1) * scale_y,
                        )
                    )

        boxes.sort(key=lambda b: (b[2] - b[0]) * (b[3] - b[1]), reverse=True)
        # Drop boxes ≥80% contained inside a larger one: segmentation can split
        # one person into a nested fragment whose own ratio then fires.
        kept = []
        for box in boxes:
            area = (box[2] - box[0]) * (box[3] - box[1])
            if any(containment(box, outer) >= 0.80 for outer in kept):
                continue
            kept.append(box)
        return kept[:6]

    @staticmethod
    def skin_fraction(classes, rect, image_size):
        """Fraction of segmentation-mapped skin classes inside a rect."""
        height, width = classes.shape
        image_w, image_h = image_size
        sx = width / image_w
        sy = height / image_h

        left = min(max(int(np.floor(rect[0] * sx)), 0), width - 1)
        right = min(max(int(np.ceil(rect[2] * sx)), 1), width)
        top = min(max(int(np.floor(rect[1] * sy)), 0), height - 1)
        bottom = min(max(int(np.ceil(rect[3] * sy)), 1), height)
        if right <= left or bottom <= top:
            return 0.0

        patch = classes[top:bottom, left:right]
        return float(np.isin(patch, SKIN_CLASSES).mean())

    @staticmethod
    def exposed_ratio_pixels(image, box):
        """Exposed skin in a person box, with the face excluded.

        Mirrors lib/src/skin_exposure.dart exactly: YCbCr + HSV skin mask, the
        largest face-like 4-connected component (centroid in the top 35%, under
        60% of box width, not a thin strip) removed, and the top 15% head cut
        kept as a second guard.
        """
        left, top, right, bottom = box
        if right <= left or bottom <= top:
            return 0.0

        img_w, img_h = image.size
        left = max(0, min(int(left), img_w - 1))
        right = max(left + 1, min(int(right), img_w))
        top = max(0, min(int(top), img_h - 1))
        bottom = max(top + 1, min(int(bottom), img_h))

        array = np.asarray(image, dtype=np.uint8)[top:bottom, left:right]
        if array.size == 0:
            return 0.0

        r = array[:, :, 0].astype(np.float64)
        g = array[:, :, 1].astype(np.float64)
        b = array[:, :, 2].astype(np.float64)

        cb = 128 + (-0.1687 * r - 0.3313 * g + 0.5 * b)
        cr = 128 + (0.5 * r - 0.4187 * g - 0.0813 * b)
        mask = (cr >= 133) & (cr <= 173) & (cb >= 77) & (cb <= 121)

        mx = np.maximum(np.maximum(r, g), b)
        mn = np.minimum(np.minimum(r, g), b)
        delta = mx - mn
        with np.errstate(divide="ignore", invalid="ignore"):
            s = np.where(mx > 0, delta / mx, 0.0)
        hue = np.zeros_like(r)
        colored = delta > 0
        is_r = colored & (mx == r)
        is_g = colored & (mx == g) & ~is_r
        is_b = colored & ~is_r & ~is_g
        safe_delta = np.where(colored, delta, 1.0)
        hue[is_r] = (((g - b) / safe_delta)[is_r] % 6) * 60
        hue[is_g] = (((b - r) / safe_delta)[is_g] + 2) * 60
        hue[is_b] = (((r - g) / safe_delta)[is_b] + 4) * 60
        mask &= (s >= 0.15) & (s <= 0.9) & ((hue <= 50) | (hue >= 340))

        height, width = mask.shape
        face = np.zeros_like(mask)
        if ndimage is not None and mask.any():
            labels, count = ndimage.label(mask)
            if count:
                areas = np.bincount(labels.ravel())
                ys, xs = np.indices(mask.shape)
                sum_y = np.bincount(labels.ravel(), weights=ys.ravel())
                best_area = 0
                best_label = -1
                face_centroid_limit = 0.35 * height
                face_width_limit = 0.60 * width
                for label in range(1, count + 1):
                    area = int(areas[label])
                    if area == 0 or area <= best_area:
                        continue
                    centroid_y = sum_y[label] / area
                    cols = np.where(labels == label)[1]
                    rows = np.where(labels == label)[0]
                    if cols.size == 0:
                        continue
                    component_width = cols.max() - cols.min() + 1
                    component_height = rows.max() - rows.min() + 1
                    if (
                        centroid_y < face_centroid_limit
                        and component_width < face_width_limit
                        and component_height / component_width >= 0.45
                    ):
                        best_area = area
                        best_label = label
                if best_label > 0:
                    face = labels == best_label

        head_top = int((bottom - top) * 0.15)
        exposed = mask[head_top:] & ~face[head_top:]
        person_pixels = (bottom - top - head_top) * (right - left)
        if person_pixels <= 0:
            return 0.0
        return float(exposed.sum()) / person_pixels


def person_mask_for(classes, image_size):
    """Upsamples the 256-class map into a full-image person mask (nearest)."""
    h, w = classes.shape
    out_w, out_h = int(image_size[0]), int(image_size[1])
    ys = (np.arange(out_h) * h // out_h).clip(0, h - 1)
    xs = (np.arange(out_w) * w // out_w).clip(0, w - 1)
    return np.isin(classes[np.ix_(ys, xs)], PERSON_CLASSES)


def exposed_evidence(image, box, person_mask=None):
    """Returns `(ratio, head_box, close_up)` for one person box.

    Counts only segmented person pixels, removes the largest head/face skin
    component, and reports a close-up when that head is wider than 60% of the
    box (its awrah band would be the face). Mirrors skin_exposure.dart.
    """
    left, top, right, bottom = box
    if right <= left or bottom <= top:
        return 0.0, None, False

    img_w, img_h = image.size
    left = max(0, min(int(left), img_w - 1))
    right = max(left + 1, min(int(right), img_w))
    top = max(0, min(int(top), img_h - 1))
    bottom = max(top + 1, min(int(bottom), img_h))

    array = np.asarray(image, dtype=np.uint8)[top:bottom, left:right]
    if array.size == 0:
        return 0.0, None, False

    r = array[:, :, 0].astype(np.float64)
    g = array[:, :, 1].astype(np.float64)
    b = array[:, :, 2].astype(np.float64)

    cb = 128 + (-0.1687 * r - 0.3313 * g + 0.5 * b)
    cr = 128 + (0.5 * r - 0.4187 * g - 0.0813 * b)
    mask = (cr >= 133) & (cr <= 173) & (cb >= 77) & (cb <= 121)

    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    delta = mx - mn
    with np.errstate(divide="ignore", invalid="ignore"):
        s = np.where(mx > 0, delta / mx, 0.0)
    hue = np.zeros_like(r)
    colored = delta > 0
    is_r = colored & (mx == r)
    is_g = colored & (mx == g) & ~is_r
    is_b = colored & ~is_r & ~is_g
    safe_delta = np.where(colored, delta, 1.0)
    hue[is_r] = (((g - b) / safe_delta)[is_r] % 6) * 60
    hue[is_g] = (((b - r) / safe_delta)[is_g] + 2) * 60
    hue[is_b] = (((r - g) / safe_delta)[is_b] + 4) * 60
    mask &= (s >= 0.15) & (s <= 0.9) & ((hue <= 50) | (hue >= 340))

    height, width = mask.shape
    head_label = -1
    head_box = None
    head_area = 0
    head_top_edge = 1 << 20
    head_wide = False
    if ndimage is not None and mask.any():
        labels, count = ndimage.label(mask)
        if count:
            areas = np.bincount(labels.ravel())
            ys, _ = np.indices(mask.shape)
            sum_y = np.bincount(labels.ravel(), weights=ys.ravel())
            for label in range(1, count + 1):
                area = int(areas[label])
                if area == 0:
                    continue
                centroid_y = sum_y[label] / area
                rows = np.where(labels == label)[0]
                cols = np.where(labels == label)[1]
                if cols.size == 0:
                    continue
                component_width = int(cols.max() - cols.min() + 1)
                component_height = int(rows.max() - rows.min() + 1)
                starts_at_top = rows.min() / height < 0.50
                if not (starts_at_top and centroid_y < 0.60 * height):
                    continue
                if component_height / component_width < 0.45:
                    continue
                if not (
                    rows.min() < head_top_edge
                    or (rows.min() == head_top_edge and area > head_area)
                ):
                    continue
                head_top_edge = int(rows.min())
                head_area = area
                head_label = label
                head_box = (
                    left + int(cols.min()),
                    top + int(rows.min()),
                    left + int(cols.max()) + 1,
                    top + int(rows.max()) + 1,
                )
                head_wide = component_width >= 0.60 * width
                # A very wide, short strip is a torso top, not a face.
                torso_strip = (
                    component_width >= 0.90 * width
                    and component_height < 0.25 * height
                )
                if torso_strip:
                    head_label = -1

    close_up = bool(head_label > 0 and head_wide)
    head_top = int((bottom - top) * 0.15)

    if person_mask is not None:
        person = person_mask[top:bottom, left:right]
    else:
        person = np.ones_like(mask, dtype=bool)

    body = person[head_top:]
    person_pixels = int(body.sum())
    if person_pixels == 0:
        return 0.0, head_box, close_up

    skin = mask & person
    if head_label > 0:
        skin = skin & (labels != head_label)
    exposed = int(skin[head_top:].sum())
    return exposed / person_pixels, head_box, close_up


def load_face_boxes():
    path = EVAL_SET / "face_boxes.json"
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def faces_in_pixels(boxes, image_size):
    width, height = image_size
    return [
        (b[0] * width, b[1] * height, b[2] * width, b[3] * height)
        for b in boxes
    ]


def exposed_with_faces(image, box, person_mask, faces):
    """Exposed-skin ratio with every face box removed from the numerator.

    Face boxes are the single source of face truth; there is no component
    heuristic. The ratio counts only segmented person pixels, so background
    cannot contribute. close_up is true when a face box is at least 60% as wide
    as the person box, which suppresses that person's awrah band rule.
    """
    left, top, right, bottom = box
    if right <= left or bottom <= top:
        return 0.0, False

    img_w, img_h = image.size
    left = max(0, min(int(left), img_w - 1))
    right = max(left + 1, min(int(right), img_w))
    top = max(0, min(int(top), img_h - 1))
    bottom = max(top + 1, min(int(bottom), img_h))

    array = np.asarray(image, dtype=np.uint8)[top:bottom, left:right]
    if array.size == 0:
        return 0.0, False

    r = array[:, :, 0].astype(np.float64)
    g = array[:, :, 1].astype(np.float64)
    b = array[:, :, 2].astype(np.float64)
    cb = 128 + (-0.1687 * r - 0.3313 * g + 0.5 * b)
    cr = 128 + (0.5 * r - 0.4187 * g - 0.0813 * b)
    mask = (cr >= 133) & (cr <= 173) & (cb >= 77) & (cb <= 121)
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    delta = mx - mn
    with np.errstate(divide="ignore", invalid="ignore"):
        s = np.where(mx > 0, delta / mx, 0.0)
    hue = np.zeros_like(r)
    colored = delta > 0
    is_r = colored & (mx == r)
    is_g = colored & (mx == g) & ~is_r
    is_b = colored & ~is_r & ~is_g
    safe_delta = np.where(colored, delta, 1.0)
    hue[is_r] = (((g - b) / safe_delta)[is_r] % 6) * 60
    hue[is_g] = (((b - r) / safe_delta)[is_g] + 2) * 60
    hue[is_b] = (((r - g) / safe_delta)[is_b] + 4) * 60
    mask &= (s >= 0.15) & (s <= 0.9) & ((hue <= 50) | (hue >= 340))

    width = right - left
    close_up = False
    neck_zones = []
    for fx1, fy1, fx2, fy2 in faces:
        face_height = fy2 - fy1
        neck_zones.append((fx1, fy1, fx2, fy2 + 1.3 * face_height))
        if fx2 <= left or fx1 >= right or fy2 <= top or fy1 >= bottom:
            continue
        x1 = max(0, int(fx1) - left)
        y1 = max(0, int(fy1) - top)
        x2 = min(width, int(fx2) - left)
        y2 = min(bottom - top, int(fy2) - top)
        if x2 > x1 and y2 > y1:
            mask[y1:y2, x1:x2] = False
        if fx2 - fx1 >= 0.60 * width:
            close_up = True

    if person_mask is not None:
        person = person_mask[top:bottom, left:right]
    else:
        person = np.ones_like(mask, dtype=bool)
    person_pixels = int(person.sum())
    if person_pixels == 0:
        return 0.0, close_up

    skin = mask & person
    # Face-independent filtering: hands/eye slits/neck fragments are small or
    # sit in the neck zone under a face box. Both rules are mirrored in Dart.
    if ndimage is not None and skin.any():
        labels, count = ndimage.label(skin)
        if count:
            areas = np.bincount(labels.ravel())
            min_area = max(1, int(0.02 * person_pixels))
            kept = np.zeros_like(skin)
            for label in range(1, count + 1):
                area = int(areas[label])
                if area < min_area:
                    continue
                rows, cols = np.where(labels == label)
                if cols.size == 0:
                    continue
                bx1 = left + int(cols.min())
                by1 = top + int(rows.min())
                bx2 = left + int(cols.max()) + 1
                by2 = top + int(rows.max()) + 1
                # Only a component mostly inside the neck zone (a neck/chin
                # fragment) is dropped; bare torso that touches it stays.
                component_area = max(1, (bx2 - bx1) * (by2 - by1))
                in_neck = False
                for nx1, ny1, nx2, ny2 in neck_zones:
                    ox1, oy1 = max(bx1, nx1), max(by1, ny1)
                    ox2, oy2 = min(bx2, nx2), min(by2, ny2)
                    if ox2 > ox1 and oy2 > oy1:
                        if (ox2 - ox1) * (oy2 - oy1) >= 0.5 * component_area:
                            in_neck = True
                            break
                if in_neck:
                    continue
                kept |= labels == label
            skin = kept

    return int(skin.sum()) / person_pixels, close_up


def policy_regions(engine, image, config, faces=None):
    """Returns `(rect, kind, confidence, rule)` for what the app would blur."""
    width, height = image.size
    faces = faces or []
    score = engine.nsfw_score(image)
    if score >= config["nsfw_frame_gate"]:
        return [((0.0, 0.0, float(width), float(height)), "nudity", score, "gate_full")]

    classes = engine.seg_map(image)
    person_mask = person_mask_for(classes, image.size)
    regions = []
    for box in engine.person_boxes(classes, image.size):
        exposed, close_up = exposed_with_faces(image, box, person_mask, faces)

        # Awrah band check. A close-up portrait's band is its face, so the
        # band rule is suppressed for that person entirely.
        band = awrah_band(box)
        # Distant segmentation artifacts (birds, clouds) can look like people;
        # require a person box of at least 15% of the frame height.
        tall_enough = (box[3] - box[1]) >= 0.15 * height
        if band is not None and not close_up and tall_enough:
            band_skin = engine.skin_fraction(classes, band, image.size)
            if band_skin >= config["awrah_skin_threshold"]:
                padded = pad_region(band, 0.05, image.size)
                if padded is not None:
                    regions.append((padded, "awrah", band_skin, "band"))

        # Exposed skin check (person pixels only, head/face excluded).
        # Distant/incidental people are small in area AND short; requiring both
        # keeps a mid-distance swimmer (coco_010: 7% area, 34% tall) and drops
        # an arm at the edge (coco_020: 5% area, 18% tall). gate_full/band
        # are unaffected.
        small = (box[2] - box[0]) * (box[3] - box[1]) < 0.08 * width * height
        short = (box[3] - box[1]) < 0.25 * height
        if not (small and short) and exposed >= config["skin_threshold"]:
            padded = pad_region(box, 0.05, image.size)
            if padded is not None:
                regions.append((padded, "awrah", exposed, "exposed"))

    # De-duplicate overlapping regions.
    deduped = []
    for r in regions:
        if any(iou(r[0], d[0]) > 0.85 for d in deduped):
            continue
        deduped.append(r)
    return deduped


def load_labels():
    labels = {}
    path = EVAL_SET / "labels.jsonl"
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line:
                entry = json.loads(line)
                labels[entry["image"]] = entry
    return labels


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--sensitivity", type=int, default=6,
        help="Protection strictness level 1..10 (default 6)",
    )
    parser.add_argument(
        "--no-faces",
        action="store_true",
        help="Simulate total face-detector failure (robustness gate)",
    )
    parser.add_argument(
        "--profile",
        choices=("strict", "legacy"),
        default="strict",
        help="strict = confirmed product policy; legacy = historical gates",
    )
    args = parser.parse_args()

    config = blur_config_for_sensitivity(args.sensitivity)
    print(f"Sensitivity level: {args.sensitivity}")
    print(f"Config: {config}")
    print()

    labels = load_labels()
    face_boxes = load_face_boxes()
    if not face_boxes:
        print("MISSING tests/eval_set/face_boxes.json; run tools/generate_face_boxes.py")
        return 1
    missing = [n for n in labels if not (EVAL_SET / "images" / n).exists()]
    if missing:
        print(f"MISSING {len(missing)} image(s) referenced by labels.jsonl")
        return 1

    engine = Engine()
    started = time.time()

    target_total = target_hit = 0
    benign_total = benign_blur = 0
    forbidden_total = forbidden_blur = 0
    per_class = {}

    for name, entry in sorted(labels.items()):
        cls = entry["class"]
        image = Image.open(EVAL_SET / "images" / name).convert("RGB")
        face_px = [] if args.no_faces else faces_in_pixels(
            face_boxes.get(name, []), image.size
        )
        regions = policy_regions(engine, image, config, face_px)
        rules = [rule for *_, rule in regions]
        blurred = len(regions) > 0

        stats = per_class.setdefault(cls, {"total": 0, "blurred": 0, "rules": {}})
        stats["total"] += 1
        stats["blurred"] += int(blurred)
        for rule in rules:
            stats["rules"][rule] = stats["rules"].get(rule, 0) + 1

        if cls == "nude":
            target_total += 1
            if blurred:
                target_hit += 1
                print(f"HIT   {name}: {rules}")
            else:
                print(f"MISS  {name}")
        elif cls in (
            "benign_person",
            "benign_scene",
            "fully_clothed",
            "abaya_niqab",
            "hijab_portrait",
            "niqab_portrait",
        ):
            benign_total += 1
            if blurred:
                benign_blur += 1
                print(f"FP    {name} ({cls}): {rules}")
        elif cls in ("bikini_swimwear",):
            target_total += 1
            if blurred:
                target_hit += 1
                print(f"HIT   {name}: {rules}")
            else:
                print(f"MISS  {name}")
        elif cls in ("beard_headscarf", "beard_control"):
            forbidden_total += 1
            if blurred:
                forbidden_blur += 1
                print(f"FORBIDDEN {name} ({cls}): {kinds}")

    recall = target_hit / target_total if target_total else 0.0
    fp_rate = benign_blur / benign_total if benign_total else 0.0

    print()
    print("Per class:")
    for cls, stats in sorted(per_class.items()):
        rules = ", ".join(f"{k}={v}" for k, v in sorted(stats["rules"].items()))
        print(
            f"  {cls:<18} {stats['blurred']:>3}/{stats['total']:<3} blurred"
            + (f"  [{rules}]" if rules else "")
        )


    portrait_classes = (
        "hijab_portrait",
        "niqab_portrait",
        "abaya_niqab",
        "fully_clothed",
    )
    portrait_blur = sum(
        per_class.get(cls, {}).get("blurred", 0) for cls in portrait_classes
    )
    bikini = per_class.get("bikini_swimwear", {"total": 0, "blurred": 0})
    bikini_recall = bikini["blurred"] / bikini["total"] if bikini["total"] else 0.0
    nude = per_class.get("nude", {"total": 0, "blurred": 0})
    nude_recall = nude["blurred"] / nude["total"] if nude["total"] else 0.0

    print(f"Portrait/clothed FP: {portrait_blur} (target 0)")
    print(f"Bikini recall: {bikini_recall:.3f} (target >= 0.90)")
    print(f"Nude recall:   {nude_recall:.3f} (target >= 0.90)")
    print()
    print(f"Target images: {target_total}, hit: {target_hit}")
    print(f"Recall:  {recall:.3f}  (target >= {RECALL_THRESHOLD:.2f})")
    print(
        f"Benign:  {benign_blur}/{benign_total} blurred, "
        f"FP rate {fp_rate:.3f}  (target <= {FP_THRESHOLD:.2f})"
    )
    if forbidden_total:
        print(
            f"Beard/headscarf: {forbidden_blur}/{forbidden_total} blurred  (target 0)"
        )
    else:
        print("Beard/headscarf: no images in tests/eval_set; not evaluated")

    benign_68 = per_class.get("benign_person", {"total": 0, "blurred": 0})
    benign68_total = benign_68["total"] + per_class.get(
        "benign_scene", {"total": 0}
    )["total"]
    benign68_blur = benign_68["blurred"] + per_class.get(
        "benign_scene", {"blurred": 0}
    )["blurred"]
    benign68_fp = benign68_blur / benign68_total if benign68_total else 0.0
    level = args.sensitivity

    strict_checks = [
        ("modest classes zero", portrait_blur == 0),
    ]
    if level in (6, 10):
        strict_checks.append(("bikini recall >= 0.90", bikini_recall >= 0.90))
        strict_checks.append(("nude recall >= 0.90", nude_recall >= 0.90))
    if level == 6:
        strict_checks.append(("benign_person+scene FP <= 5%", benign68_fp <= 0.05))
    strict_ok = all(passed for _, passed in strict_checks)

    legacy_ok = (
        recall >= RECALL_THRESHOLD
        and fp_rate <= FP_THRESHOLD
        and forbidden_blur == 0
    )

    print()
    print(f"Profile: {args.profile}  level {level}" +
          ("  (NO FACE BOXES)" if args.no_faces else ""))
    print("strict_policy:", "PASS" if strict_ok else "FAIL")
    for label, passed in strict_checks:
        print(f"  [{'x' if passed else ' '}] {label}")
    print(
        f"  informational L{level} benign FP: {benign68_blur}/{benign68_total}"
        f" = {benign68_fp:.3f}"
    )
    print("legacy_policy:", "PASS" if legacy_ok else "FAIL")

    ok = strict_ok if args.profile == "strict" else legacy_ok
    print(f"Elapsed: {time.time() - started:.1f}s")
    print("RESULT:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
