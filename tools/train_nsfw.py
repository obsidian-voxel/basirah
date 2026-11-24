"""Train the on-device whole-frame nudity/exposure gate (nsfw.tflite).

Deliberately a small ConvNet trained from scratch: the MobileNetV3 pretrained
weights are unavailable in this environment (download blocked), and a frozen
random backbone never converges.

Data (public, free):
  * C:\\tmp\\nsfw.zip      — DarkyMan nsfw-image-classification (positive class)
  * C:\\tmp\\val2017.zip   — COCO val2017 (negative/benign class)
"""
import io
import random
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, r"C:\tf")
import numpy as np
import tensorflow as tf
from PIL import Image

ROOT = Path(r"C:\Users\H P\haram-blur")
SIZE = 128
random.seed(11)
np.random.seed(11)


def decode(raw):
    img = Image.open(io.BytesIO(raw)).convert("RGB").resize((SIZE, SIZE))
    return np.asarray(img, dtype=np.float32) / 255.0


def load():
    pos = []
    with zipfile.ZipFile(r"C:\tmp\nsfw.zip") as z:
        for n in z.namelist():
            if n.lower().endswith((".jpg", ".jpeg", ".png")):
                try:
                    pos.append(decode(z.read(n)))
                except Exception:
                    pass
    neg = []
    with zipfile.ZipFile(r"C:\tmp\val2017.zip") as z:
        names = [n for n in z.namelist() if n.lower().endswith(".jpg")]
        for n in random.sample(names, min(900, len(names))):
            try:
                neg.append(decode(z.read(n)))
            except Exception:
                pass
    return pos, neg


def main():
    pos, neg = load()
    print(f"positives={len(pos)} negatives={len(neg)}")

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
        tf.keras.layers.Conv2D(16, 3, strides=2, activation="relu"),
        tf.keras.layers.Conv2D(32, 3, strides=2, activation="relu"),
        tf.keras.layers.Conv2D(64, 3, strides=2, activation="relu"),
        tf.keras.layers.Conv2D(96, 3, strides=2, activation="relu"),
        tf.keras.layers.GlobalAveragePooling2D(),
        tf.keras.layers.Dropout(0.3),
        tf.keras.layers.Dense(1, activation="sigmoid"),
    ])
    model.compile(optimizer=tf.keras.optimizers.Adam(1e-3),
                  loss="binary_crossentropy", metrics=["accuracy"])
    model.fit(xtr, ytr, validation_data=(xva, yva), epochs=25, batch_size=32,
              verbose=2)

    # Pick the threshold maximizing balanced accuracy on the holdout.
    probs = model.predict(xva, verbose=0).ravel()
    best_t, best_b = 0.5, -1.0
    for t in np.arange(0.05, 0.95, 0.05):
        tp = ((probs > t) & (yva == 1)).sum() / max(1, (yva == 1).sum())
        tn = ((probs <= t) & (yva == 0)).sum() / max(1, (yva == 0).sum())
        if (tp + tn) / 2 > best_b:
            best_b, best_t = (tp + tn) / 2, float(t)
    print(f"holdout balanced acc={best_b:.3f} at threshold={best_t:.2f}")

    conv = tf.lite.TFLiteConverter.from_keras_model(model)
    data = conv.convert()
    (ROOT / "assets" / "models" / "nsfw.tflite").write_bytes(data)
    (ROOT / "assets" / "models" / "nsfw_threshold.txt").write_text(f"{best_t:.2f}\n")
    print("exported nsfw.tflite", len(data), "threshold", best_t)


if __name__ == "__main__":
    main()
