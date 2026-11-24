"""Measure BlockP reference screenshots so the clone can be matched numerically.

Prints, for each capture:
  * size and the inferred dp scale (screenshots are 1080 px wide),
  * the dominant palette with the area each colour occupies,
  * horizontal colour runs down a set of probe columns (card edges, gaps),
  * vertical colour runs along the centre to find band boundaries.

Usage:  python tools/shot_metrics.py <dir-or-file> [...]
"""

import sys
from pathlib import Path

from PIL import Image


def runs(pixels, tolerance=6):
    """Collapse a 1-D list of RGB tuples into (start, end, colour) runs."""
    out = []
    start = 0
    base = pixels[0]
    for i in range(1, len(pixels)):
        p = pixels[i]
        if max(abs(p[j] - base[j]) for j in range(3)) > tolerance:
            out.append((start, i - 1, base))
            start = i
            base = p
    out.append((start, len(pixels) - 1, base))
    return [r for r in out if r[1] - r[0] >= 2]


def hexc(c):
    return "#%02X%02X%02X" % c[:3]


def palette(img, top=10):
    small = img.convert("RGB").resize((135, 300), Image.NEAREST)
    counts = {}
    for p in small.getdata():
        q = (p[0] // 4 * 4, p[1] // 4 * 4, p[2] // 4 * 4)
        counts[q] = counts.get(q, 0) + 1
    total = 135 * 300
    return sorted(counts.items(), key=lambda kv: -kv[1])[:top], total


def main(paths):
    files = []
    for raw in paths:
        p = Path(raw)
        files.extend(sorted(p.glob("*.png")) + sorted(p.glob("*.jpg"))
                     if p.is_dir() else [p])

    for f in files:
        img = Image.open(f).convert("RGB")
        w, h = img.size
        print(f"\n=== {f.name}  {w}x{h}  scale={w / 360:.2f}x")
        pal, total = palette(img)
        print("palette:")
        for c, n in pal:
            print(f"  {hexc(c)}  {n / total * 100:5.1f}%")

        for label, x in (("col 54", int(w * 0.05)), ("col mid", w // 2),
                         ("col 1026", int(w * 0.95))):
            col = [img.getpixel((x, y)) for y in range(h)]
            bands = [r for r in runs(col) if r[1] - r[0] > 6]
            print(f"{label} (x={x}) vertical runs:")
            for a, b, c in bands:
                print(f"  y {a:4d}-{b:4d} ({b - a + 1:4d}px)  {hexc(c)}")

        for y in (int(h * 0.20), int(h * 0.50), int(h * 0.80)):
            row = [img.getpixel((x, y)) for x in range(w)]
            bands = [r for r in runs(row) if r[1] - r[0] > 10]
            print(f"row y={y}:")
            for a, b, c in bands:
                print(f"  x {a:4d}-{b:4d} ({b - a + 1:4d}px)  {hexc(c)}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("usage: shot_metrics.py <file-or-dir> [...]")
    main(sys.argv[1:])
