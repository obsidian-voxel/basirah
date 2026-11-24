"""Writes deterministic face boxes for the eval set.

Live catches faces with ML Kit (bundled, offline). The oracle and the Dart
tests need a repeatable, host-runnable detector, so they use OpenCV's YuNet
(ONNX, deterministic, detects profile and partially covered faces). Boxes are
normalised to the image and expanded by a 12% margin.

Fetch the model once with tools/fetch_yunet.py.

Run: python tools/generate_face_boxes.py
"""
import json
from pathlib import Path

import cv2

ROOT = Path(__file__).resolve().parent.parent
EVAL_SET = ROOT / "tests" / "eval_set"
IMAGES = EVAL_SET / "images"
LABELS = EVAL_SET / "labels.jsonl"
OUT = EVAL_SET / "face_boxes.json"

MARGIN = 0.12


def main():
    model = ROOT / "tools" / "models" / "face_detection_yunet_2023mar.onnx"
    if not model.exists():
        raise SystemExit(
            f"missing {model}; run python tools/fetch_yunet.py first"
        )
    detector = cv2.FaceDetectorYN.create(
        str(model),
        "",
        (320, 320),
        score_threshold=0.4,
        nms_threshold=0.3,
        top_k=5000,
    )

    entries = [
        json.loads(line)
        for line in LABELS.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]

    boxes = {}
    with_faces = 0
    for entry in entries:
        name = entry["image"]
        image = cv2.imread(str(IMAGES / name))
        if image is None:
            boxes[name] = []
            continue
        height, width = image.shape[:2]
        detector.setInputSize((width, height))
        _, found = detector.detect(image)
        image_boxes = []
        for face in found if found is not None else []:
            x, y, w, h = (float(v) for v in face[:4])
            mx = w * MARGIN
            my = h * MARGIN
            image_boxes.append(
                [
                    max(0.0, (x - mx) / width),
                    max(0.0, (y - my) / height),
                    min(1.0, (x + w + mx) / width),
                    min(1.0, (y + h + my) / height),
                ]
            )
        boxes[name] = image_boxes
        if image_boxes:
            with_faces += 1

    OUT.write_text(json.dumps(boxes, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    print(f"{with_faces}/{len(entries)} eval images have at least one face box")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
