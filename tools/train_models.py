"""Train the small on-device classifier heads and export TFLite.

Models produced in assets/models/:
  * nsfw.tflite   [1,224,224,3] float32 -> [1,1] p(nsfw)     whole-frame gate
  * gender.tflite [1,160,160,3] float32 -> [1,1] p(female)   face gender
  * beard.tflite  [1,160,160,3] float32 -> [1,1] p(beard)    face beard (hard override)

Data (all downloaded from public HF datasets / COCO):
  * data/nsfw.zip        — DarkyMan nsfw-image-classification (positive class)
  * COCO val2017         — benign scenes (negative class)
  * data/celeba/*.parquet — CelebA faces w/ attributes (Male, No_Beard)

Usage: python tools/train_models.py [probe|nsfw|gender|beard|all]
"""
import io
import json
import random
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, r"C:\tf")
import numpy as np
import pandas as pd
import tensorflow as tf
from PIL import Image

ROOT = Path(r"C:\Users\H P\haram-blur")
DATA = ROOT / "data"
OUT = ROOT / "assets" / "models"
random.seed(0)
np.random.seed(0)

AUTOTUNE = tf.data.AUTOTUNE


def _decode(img_bytes, size):
    img = Image.open(io.BytesIO(img_bytes)).convert("RGB").resize((size, size))
    return np.asarray(img, dtype=np.float32) / 255.0


def _build_model(size):
    base = tf.keras.applications.MobileNetV3Small(
        input_shape=(size, size, 3), include_top=False, weights="imagenet")
    base.trainable = False
    return tf.keras.Sequential([
        tf.keras.layers.Input(shape=(size, size, 3)),
        tf.keras.layers.RandomFlip("horizontal"),
        tf.keras.layers.RandomBrightness(0.1),
        base,
        tf.keras.layers.GlobalAveragePooling2D(),
        tf.keras.layers.Dropout(0.2),
        tf.keras.layers.Dense(1, activation="sigmoid"),
    ])


def _train(x, y, size, epochs=6, name="model"):
    x = np.asarray(x, dtype=np.float32)
    y = np.asarray(y, dtype=np.float32)
    idx = np.arange(len(x))
    np.random.shuffle(idx)
    x, y = x[idx], y[idx]
    split = int(len(x) * 0.85)
    model = _build_model(size)
    model.compile(optimizer=tf.keras.optimizers.Adam(1e-3),
                  loss="binary_crossentropy", metrics=["accuracy"])
    model.fit(x[:split], y[:split], validation_data=(x[split:], y[split:]),
              epochs=epochs, batch_size=16, verbose=2)
    # fine-tune the top block
    model.layers[3].trainable = True
    model.compile(optimizer=tf.keras.optimizers.Adam(1e-5),
                  loss="binary_crossentropy", metrics=["accuracy"])
    model.fit(x[:split], y[:split], validation_data=(x[split:], y[split:]),
              epochs=3, batch_size=16, verbose=2)
    loss, acc = model.evaluate(x[split:], y[split:], verbose=0)
    print(f"[{name}] holdout acc={acc:.3f}")
    return model, acc


def _export(model, size, filename):
    conv = tf.lite.TFLiteConverter.from_keras_model(model)
    conv.optimizations = [tf.lite.Optimize.DEFAULT]
    data = conv.convert()
    path = OUT / filename
    path.write_bytes(data)
    print(f"wrote {path} ({len(data)} bytes)")
    return path


def _coco_negatives(count, size):
    zip_path = Path(r"C:\tmp\val2017.zip")
    if not zip_path.exists():
        zip_path = Path(r"C:\c\tmp\val2017.zip")
    out = []
    with zipfile.ZipFile(zip_path) as z:
        names = [n for n in z.namelist() if n.lower().endswith(".jpg")]
        for n in random.sample(names, min(count, len(names))):
            try:
                out.append(_decode(z.read(n), size))
            except Exception:
                pass
    return out


def probe():
    df = pd.read_parquet(sorted((DATA / "celeba").glob("*.parquet"))[0])
    print("celeba columns:", list(df.columns)[:50])
    print("rows:", len(df))
    for c in df.columns:
        if c != "image":
            print(" ", c, df[c].value_counts().to_dict() if df[c].nunique() < 5 else "many")


def train_nsfw():
    size = 224
    pos = []
    with zipfile.ZipFile(Path(r"C:\tmp\nsfw.zip")) as z:
        for n in z.namelist():
            if n.lower().endswith((".jpg", ".jpeg", ".png")):
                try:
                    pos.append(_decode(z.read(n), size))
                except Exception:
                    pass
    print(f"nsfw positives: {len(pos)}")
    neg = _coco_negatives(len(pos) * 2, size)
    print(f"benign negatives: {len(neg)}")
    x = pos + neg
    y = [1.0] * len(pos) + [0.0] * len(neg)
    model, acc = _train(x, y, size, epochs=6, name="nsfw")
    _export(model, size, "nsfw.tflite")


def _celeba_faces():
    frames = []
    for p in sorted((DATA / "celeba").glob("*.parquet")):
        frames.append(pd.read_parquet(p))
    return pd.concat(frames, ignore_index=True)


def train_gender():
    size = 128
    df = _celeba_faces()
    male_col = "Male" if "Male" in df.columns else next(c for c in df.columns if "male" in c.lower())
    x, y = [], []
    sample = df.sample(min(2400, len(df)), random_state=0)
    for _, row in sample.iterrows():
        img = row["image"]
        if isinstance(img, dict):
            img = img.get("bytes")
        try:
            x.append(_decode(img, size))
            # CelebA Male == 1 -> female probability 0
            y.append(0.0 if int(row[male_col]) == 1 else 1.0)
        except Exception:
            pass
    print(f"gender samples: {len(x)} (p(female) positives: {int(sum(y))})")
    model, acc = _train(x, y, size, epochs=6, name="gender")
    _export(model, size, "gender.tflite")


def train_beard():
    size = 128
    df = _celeba_faces()
    male_col = "Male" if "Male" in df.columns else next(c for c in df.columns if "male" in c.lower())
    nob_col = "No_Beard" if "No_Beard" in df.columns else next(
        c for c in df.columns if "beard" in c.lower())
    men = df[df[male_col] == 1].sample(min(2400, int((df[male_col] == 1).sum())), random_state=0)
    x, y = [], []
    for _, row in men.iterrows():
        img = row["image"]
        if isinstance(img, dict):
            img = img.get("bytes")
        try:
            x.append(_decode(img, size))
            y.append(0.0 if int(row[nob_col]) == 1 else 1.0)
        except Exception:
            pass
    print(f"beard samples: {len(x)} (bearded: {int(sum(y))})")
    model, acc = _train(x, y, size, epochs=6, name="beard")
    _export(model, size, "beard.tflite")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "all"
    if cmd in ("probe", "all"):
        probe()
    if cmd in ("nsfw", "all"):
        train_nsfw()
    if cmd in ("gender", "all"):
        train_gender()
    if cmd in ("beard", "all"):
        train_beard()
