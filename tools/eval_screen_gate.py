"""Diagnostic for the screenshot framing problem (does not change the eval).

`tools/evaluate.py` scores a cropped photo. The phone scores a whole screen:
browser chrome, status bar, letterboxing. This script asks what happens if the
gate is also evaluated on the two centre crops the runtime uses (85% and 60%)
and the best score wins, while the awrah cascade stays on the full frame.

Run: python tools/eval_screen_gate.py [--sensitivity LEVEL]
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

from evaluate import (  # noqa: E402
    EVAL_SET,
    Engine,
    blur_config_for_sensitivity,
    load_labels,
    policy_regions,
)


def centre_crop(image: Image.Image, fraction: float) -> Image.Image:
    width = max(1, round(image.width * fraction))
    height = max(1, round(image.height * fraction))
    left = (image.width - width) // 2
    top = (image.height - height) // 2
    return image.crop((left, top, left + width, top + height))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sensitivity", type=int, default=6)
    args = parser.parse_args()

    config = blur_config_for_sensitivity(args.sensitivity)
    gate = config["nsfw_frame_gate"]
    labels = load_labels()
    engine = Engine()

    rows = []
    for name, entry in sorted(labels.items()):
        image = Image.open(EVAL_SET / "images" / name).convert("RGB")
        full = engine.nsfw_score(image)
        crop_scores = [engine.nsfw_score(centre_crop(image, f)) for f in (0.85, 0.60)]
        best = max([full, *crop_scores])
        gate_hit = best >= gate
        regions = [] if gate_hit else policy_regions(engine, image, config)
        rows.append((name, entry["class"], full, max(crop_scores), gate_hit, bool(regions)))

    targets = {"nude", "bikini_swimwear"}
    benign = {"benign_person", "benign_scene", "fully_clothed", "abaya_niqab"}

    def rate(classes: set[str]) -> tuple[int, int]:
        total = sum(1 for r in rows if r[1] in classes)
        hit = sum(1 for r in rows if r[1] in classes and (r[4] or r[5]))
        return hit, total

    hit, total = rate(targets)
    fp, benign_total = rate(benign)
    forbidden = [r for r in rows if r[1] in {"beard_headscarf", "beard_control"} and (r[4] or r[5])]

    print(f"Gate {gate:.3f}")
    print(f"Recall: {hit}/{total} = {hit / max(1, total):.3f}")
    print(f"Benign blurred: {fp}/{benign_total} = {fp / max(1, benign_total):.3f}")
    print(f"Forbidden blurred: {len(forbidden)}")
    print()
    crosstalk = [
        r for r in rows if not r[4] and max(r[3], 0) >= gate
    ]
    print("Images where only a centre crop crossed the gate:")
    for name, cls, full, crop_best, _, _ in crosstalk:
        print(f"  {name:<18} {cls:<14} full={full:.3f} crop={crop_best:.3f}")
    print()
    missed = [r for r in rows if r[1] in targets and not (r[4] or r[5])]
    print("Still missed by the screenshot-style scoring:")
    for name, cls, full, crop_best, _, _ in missed:
        print(f"  {name:<18} {cls:<14} full={full:.3f} crop={crop_best:.3f}")

    ok = hit / max(1, total) >= 0.90 and fp / max(1, benign_total) <= 0.05 and not forbidden
    print("\nRESULT:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
