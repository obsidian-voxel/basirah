"""Adds hijab_portrait and niqab_portrait classes to the eval set.

Openverse only returns CC BY / CC0 / PDM images, so the set stays redistributable.
Run: python tools/add_portrait_classes.py
"""
import io
import json
from pathlib import Path

import requests
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
EVAL_SET = ROOT / "tests" / "eval_set"
IMAGES = EVAL_SET / "images"
LABELS = EVAL_SET / "labels.jsonl"


def load_labels():
    entries = {}
    for line in LABELS.read_text(encoding="utf-8").splitlines():
        if line.strip():
            entry = json.loads(line)
            entries[entry["image"]] = entry
    return entries


def fetch(query, cls, count, prefix):
    entries = load_labels()
    got = 0
    page = 1
    while got < count and page <= 10:
        try:
            response = requests.get(
                "https://api.openverse.org/v1/images/",
                params={
                    "q": query,
                    "license": "by,cc0,pdm",
                    "page_size": 20,
                    "page": page,
                },
                timeout=60,
                headers={"User-Agent": "HaramBlurEval/1.0"},
            )
            results = response.json().get("results", [])
        except Exception as error:
            print(f"{cls}: request failed ({error})")
            break
        if not results:
            break
        for item in results:
            if got >= count:
                break
            url = item.get("url")
            if not url:
                continue
            try:
                data = requests.get(
                    url,
                    timeout=40,
                    headers={"User-Agent": "HaramBlurEval/1.0"},
                ).content
                Image.open(io.BytesIO(data)).verify()
            except Exception:
                continue
            name = f"{prefix}_{got:02d}.jpg"
            (IMAGES / name).write_bytes(data)
            entries[name] = {"image": name, "class": cls, "boxes": []}
            got += 1
            print(f"  {name} <- {url[:80]}")
        page += 1

    with LABELS.open("w", encoding="utf-8") as handle:
        for entry in sorted(entries.values(), key=lambda e: e["image"]):
            handle.write(json.dumps(entry) + "\n")
    print(f"{cls}: {got} image(s)")


if __name__ == "__main__":
    IMAGES.mkdir(parents=True, exist_ok=True)
    fetch("hijab portrait", "hijab_portrait", 12, "hijab")
    fetch("niqab portrait", "niqab_portrait", 12, "niqab")
