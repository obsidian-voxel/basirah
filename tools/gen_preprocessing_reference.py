"""Writes the Python-side preprocessing reference for the parity test.

Runs the exact resize/normalisation `tools/evaluate.py` uses (PIL BILINEAR,
224x224, /255) on three eval images and stores per-channel means that
`test/preprocessing_parity_test.dart` asserts the Dart runtime matches.

Run: python tools/gen_preprocessing_reference.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path


import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
IMAGES = ROOT / "tests" / "eval_set" / "images"
OUT = ROOT / "test" / "fixtures" / "preprocessing_reference.json"

# One nude, one benign person, one benign scene: different content, sizes and
# colour distributions, so a resize bug cannot hide behind similar statistics.
def pick(labels: dict) -> list[str]:
    wanted = ["nude", "benign_person", "benign_scene"]
    chosen = []
    for cls in wanted:
        match = sorted(n for n, e in labels.items() if e["class"] == cls)
        if match:
            chosen.append(match[0])
    return chosen


def main() -> int:
    labels = {}
    with open(ROOT / "tests" / "eval_set" / "labels.jsonl", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line:
                entry = json.loads(line)
                labels[entry["image"]] = entry

    names = pick(labels)
    if not names:
        print(f"No images in {IMAGES}")
        return 1

    entries = {}
    for name in names:
        image = Image.open(IMAGES / name).convert("RGB")
        resized = image.resize((224, 224), Image.BILINEAR)
        array = np.asarray(resized, dtype=np.float32) / 255.0
        entries[name] = {
            "source_width": image.width,
            "source_height": image.height,
            "mean_r": float(array[:, :, 0].mean()),
            "mean_g": float(array[:, :, 1].mean()),
            "mean_b": float(array[:, :, 2].mean()),
        }
        print(name, entries[name])

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"size": 224, "scale": 255.0, "entries": entries}, indent=2))
    print(f"Wrote {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
