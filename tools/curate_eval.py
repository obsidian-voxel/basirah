"""Curate the fixed eval test set for Haram Blur.

Free, login-free sources:
  * DarkyMan nsfw-image-classification zip — nude/sexy/porn images (class: nude)
  * Openverse API — CC BY/CC0/PDM: hijab portraits (modest_woman),
    bearded men with head coverings (beard_headscarf), bearded men no headwear
    (beard_control)
  * COCO val2017 — scenes with person (benign_person) / no person (benign_scene)

Outputs tests/eval_set/{images..., labels.jsonl}.
"""
import json
import random
import zipfile
from pathlib import Path
from urllib.request import urlopen

import requests
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
EVAL_SET = ROOT / "tests" / "eval_set"
IMAGES = EVAL_SET / "images"
IMAGES.mkdir(parents=True, exist_ok=True)

random.seed(42)
LABELS = []


def add(image_name, data, cls):
    """Store image bytes and record a label. Returns True on success."""
    dst = IMAGES / image_name
    if dst.exists():
        print(f"skip exists {image_name}")
        LABELS.append({"image": image_name, "class": cls, "boxes": []})
        return True
    try:
        Image.open(io := __import__("io").BytesIO(data)).verify()
    except Exception:
        print(f"BAD IMAGE {image_name}")
        return False
    dst.write_bytes(data)
    LABELS.append({"image": image_name, "class": cls, "boxes": []})
    print(f"ok {image_name} ({cls})")
    return True


# ---------- 1. DarkyMan NSFW zip ----------
NSFW_ZIP = "https://huggingface.co/datasets/DarkyMan/nsfw-image-classification/resolve/main/nsfw.zip"
print("Downloading DarkyMan nsfw.zip (168 MB)…")
r = requests.get(NSFW_ZIP, timeout=300)
r.raise_for_status()
open("/tmp/nsfw.zip", "wb").write(r.content)

with zipfile.ZipFile("/tmp/nsfw.zip") as z:
    names = [n for n in z.namelist()
             if n.lower().endswith((".jpg", ".jpeg", ".png"))
             and not n.endswith("/")]
    print(f"zip: {len(names)} nsfw images")
    sample = random.sample(names, 30)
    for i, n in enumerate(sample):
        add(f"nsfw_{i:03d}_{Path(n).name}", z.read(n), "nude")

# ---------- 2. Openverse ----------
def openverse(query, count, cls):
    print(f"Fetching Openverse: {query} ({count})")
    got = 0
    page = 1
    while got < count and page <= 10:
        ov = requests.get(
            "https://api.openverse.org/v1/images/",
            params={"q": query, "license": "by,cc0,pdm", "page_size": 50, "page": page},
            timeout=60).json()
        results = ov.get("results", [])
        if not results:
            break
        for item in results:
            if got >= count:
                break
            url = item.get("url")
            if not url:
                continue
            try:
                data = requests.get(url, timeout=40).content
            except Exception:
                continue
            if add(f"ov_{query.replace(' ', '_')}_{got:02d}.jpg", data, cls):
                got += 1
        page += 1
    print(f"  fetched {got}")


openverse("woman hijab portrait", 25, "modest_woman")
openverse("man beard turban headscarf", 25, "beard_headscarf")
openverse("man beard portrait", 20, "beard_control")

# ---------- 3. COCO val2017 benign ----------
COCO_ZIP = "/tmp/val2017.zip"
if not Path(COCO_ZIP).exists():
    print("Downloading COCO val2017 (1 GB)…")
    with requests.get("http://images.cocodataset.org/zips/val2017.zip",
                      stream=True, timeout=900) as r:
        r.raise_for_status()
        with open(COCO_ZIP, "wb") as f:
            for chunk in r.iter_content(1 << 20):
                f.write(chunk)

with zipfile.ZipFile(COCO_ZIP) as z:
    jpgs = [n for n in z.namelist() if n.lower().endswith(".jpg")]
    sample = random.sample(jpgs, 40)
    person = 0
    scene = 0
    for i, n in enumerate(sample):
        data = z.read(n)
        try:
            Image.open(__import__("io").BytesIO(data)).verify()
        except Exception:
            continue
        name = f"coco_{i:03d}.jpg"
        cls = "benign_person" if (person < 20) else "benign_scene"
        if cls == "benign_person":
            person += 1
        else:
            scene += 1
        add(name, data, cls)

(EVAL_SET / "labels.jsonl").write_text(
    "\n".join(json.dumps(o) for o in LABELS) + "\n")
print(f"Done: {len(LABELS)} labeled images in {EVAL_SET}")
