#!/usr/bin/env python3
"""Regenerate all Basirah launcher icons from one shared mark geometry.

The Basirah mark is an abstract aperture: three concentric circles
(lens outline, iris ring, centre dot) on the Basirah blue field. It has
no points, no star geometry, no animate being and no religious symbol.

Usage:
    python3 tools/generate_icons.py
Run from C:/Users/H P/haram-blur. It rewrites:
  android/app/src/main/res/mipmap-*/ic_launcher{,_round}.png
  web/icons/Icon-{192,512}.png
  web/icons/Icon-maskable-{192,512}.png
  web/favicon.png
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

BLUE = (47, 111, 235, 255)
WHITE = (255, 255, 255, 255)
TRANSPARENT = (0, 0, 0, 0)

ROOT = Path(__file__).resolve().parent.parent


def _rounded_square(size: int) -> Image.Image:
    im = Image.new("RGBA", (size, size), TRANSPARENT)
    draw = ImageDraw.Draw(im)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), size * 0.115, fill=BLUE)
    return im


def _draw_mark(draw: ImageDraw.ImageDraw, cx: float, cy: float, scale: float) -> None:
    """Aperture mark: lens outline, iris ring, centre dot; no points."""
    outer_r = 44.0 * scale
    iris_r = 28.0 * scale
    pupil_r = 12.0 * scale
    stroke_w = 10.0 * scale
    inner_stroke_w = 7.0 * scale

    # Lens outline.
    draw.ellipse(
        (cx - outer_r, cy - outer_r, cx + outer_r, cy + outer_r),
        outline=WHITE,
        width=int(round(stroke_w)),
    )
    # Iris ring.
    draw.ellipse(
        (cx - iris_r, cy - iris_r, cx + iris_r, cy + iris_r),
        outline=WHITE,
        width=int(round(inner_stroke_w)),
    )
    # Centre dot (aperture).
    draw.ellipse(
        (cx - pupil_r, cy - pupil_r, cx + pupil_r, cy + pupil_r),
        fill=WHITE,
    )


def _launcher_icon(size: int) -> Image.Image:
    """Full square rounded-square launcher icon (legacy mipmaps)."""
    im = _rounded_square(size)
    draw = ImageDraw.Draw(im)
    _draw_mark(draw, size / 2, size / 2, size / 192.0)
    return im


def _round_icon(size: int) -> Image.Image:
    """Circular adaptive foreground (transparent outside the circle)."""
    im = Image.new("RGBA", (size, size), TRANSPARENT)
    draw = ImageDraw.Draw(im)
    draw.ellipse((0, 0, size - 1, size - 1), fill=BLUE)
    _draw_mark(draw, size / 2, size / 2, size / 192.0)
    return im


def _maskable_icon(size: int) -> Image.Image:
    """PWA maskable icon: content inside the centre safe zone."""
    im = Image.new("RGBA", (size, size), TRANSPARENT)
    draw = ImageDraw.Draw(im)
    r = size * 0.40
    draw.ellipse((size / 2 - r, size / 2 - r, size / 2 + r, size / 2 + r), fill=BLUE)
    _draw_mark(draw, size / 2, size / 2, (size * 0.625) / 192.0)
    return im


def main() -> None:
    mipmap_root = ROOT / "android" / "app" / "src" / "main" / "res"
    for density, size in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
        _launcher_icon(size).save(mipmap_root / f"mipmap-{density}" / "ic_launcher.png", "PNG")
        _round_icon(size).save(mipmap_root / f"mipmap-{density}" / "ic_launcher_round.png", "PNG")

    web_icons = ROOT / "web" / "icons"
    _launcher_icon(192).save(web_icons / "Icon-192.png", "PNG")
    _launcher_icon(512).save(web_icons / "Icon-512.png", "PNG")
    _maskable_icon(192).save(web_icons / "Icon-maskable-192.png", "PNG")
    _maskable_icon(512).save(web_icons / "Icon-maskable-512.png", "PNG")

    favicon = _launcher_icon(32)
    favicon.save(ROOT / "web" / "favicon.png", "PNG")
    print("icons regenerated")


if __name__ == "__main__":
    main()
