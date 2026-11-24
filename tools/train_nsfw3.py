"""Train nsfw.tflite v2: 224px input, 50 epochs, heavy augmentation,
eval images strictly excluded from training."""
import io
import json
import random
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, r"C:\tf")
import numpy as np
import tensorflow as tf
from PIL import Image

ROOT = Path(r"C:\Users\H P\haram-blur")
EVAL_SET = ROOT / "tests" / "eval_set"
SIZE = 224
random.seed(7)
np.random.seed(7)


def eval_image_names():
    names = set()
    with open(EVAL_SET / "labels.jsonl") as f:
        for line in f:
            line = line.strip()
            if line:
                names.add(json.loads(line)["image"])
    return names


EVAL_NAMES = eval_image_names()


def decode(raw):
    img = Image.open(io.BytesIO(raw)).convert("RGB").resize((SIZE, SIZE))
    return np.asarray(img, dtype=np.float32) / 255.0


def load():
    pos = []
    with zipfile.ZipFile(r"C:\tmp\nsfw.zip") as z:
        for n in z.namelist():
            if n.lower().endswith((".jpg", ".jpeg", ".png")):
                name = Path(n).name
                if name in EVAL_NAMES:
                    continue
                try:
                    pos.append(decode(z.read(n)))
                except Exception:
                    pass
    neg = []
    with zipfile.ZipFile(r"C:\tmp\val2017.zip") as z:
        names = [n for n in z.namelist() if n.lower().endswith(".jpg")]
        random.shuffle(names)
        for n in names:
            base = Path(n).name
            if base in EVAL_NAMES:
                continue
            try:
                neg.append(decode(z.read(n)))
            except Exception:
                pass
            if len(neg) >= 1200:
                break
    print(f"positives={len(pos)} negatives={len(neg)} (eval names excluded)")
    return pos, neg


def main():
    pos, neg = load()
    x = np.array(pos + neg, dtype=np.float32)
    y = np.array([1.0] * len(pos) + [0.0] * len(neg), dtype=np.float32)
    idx = np.arange(len(x))
    np.random.shuffle(idx)
    x, y = x[idx], y[idx]
    split = int(len(x) * 0.85)
    xtr, ytr, xva, yva = x[:split], y[:split], x[split:], y[split:]

    model = tf.keras.Sequential([
        tf.keras.Input((SIZE, SIZE, 3)),
        tf.keras.layers.RandomFlip("horizontal"),
        tf.keras.layers.RandomRotation(0.05),
        tf.keras.layers.RandomZoom(0.1),
        tf.keras.layers.RandomBrightness(0.15),
        tf.keras.layers.RandomContrast(0.15),
        tf.keras.layers.Conv2D(32, 3, strides=2, activation="relu"),
        tf.keras.layers.Conv2D(64, 3, strides=2, activation="relu"),
        tf.keras.layers.Conv2D(128, 3, strides=2, activation="relu"),
        tf.keras.layers.Conv2D(128, 3, strides=2, activation="relu"),
        tf.keras.layers.GlobalAveragePooling2D(),
        tf.keras.layers.Dropout(0.4),
        tf.keras.layers.Dense(1, activation="sigmoid"),
    ])
    model.compile(optimizer=tf.keras.optimizers.Adam(8e-4),
                  loss="binary_crossentropy", metrics=["accuracy"])
    model.fit(xtr, ytr, validation_data=(xva, yva), epochs=50, batch_size=32,
              verbose=2)

    probs = model.predict(xva, verbose=0).ravel()
    best_t, best_b = 0.5, -1.0
    for t in np.arange(0.05, 0.95, 0.05):
        tp = ((probs > t) & (yva == 1)).sum() / max(1, (yva == 1).sum())
        tn = ((probs <= t) & (yva == 0)).sum() / max(1, (yva == 0).sum())
        b = (tp + tn) / 2
        if b > best_b:
            best_b = b
            best_t = float(t)
    print(f"validation balanced acc={best_b:.3f} at threshold={best_t:.2f}")

    conv = tf.lite.TFLiteConverter.from_keras_model(model)
    conv.optimizations = [tf.lite.Optimize.DEFAULT]
    data = conv.convert()
    (ROOT / "assets" / "models" / "nsfw.tflite").write_bytes(data)
    (ROOT / "assets" / "models" / "nsfw_threshold.txt").write_text(
        f"{best_t:.4f}\n")
    print(f"exported nsfw.tflite {len(data)} threshold {best_t:.4f}")


if __name__ == "__main__":
    main()
