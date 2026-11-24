"""Compare a render from `test/ui_render_test.dart` against the BlockP reference.

The reference screenshots were taken on a 1080 x 2340 device at 420 dpi, so
the clone is rendered at the same size and compared pixel by pixel.

    python tools/compare_ref.py build/ui-review/dashboard_light.png \
        "C:/Users/H P/Downloads/BlockP/Screenshot_20261116_000823_BlockP.jpg"
"""
import sys

from PIL import Image

REFERENCE = r"C:\Users\H P\Downloads\BlockP\Screenshot_20261116_000823_BlockP.jpg"


def load(path):
    image = Image.open(path).convert("RGB")
    if image.size != (1080, 2340):
        image = image.resize((1080, 2340), Image.LANCZOS)
    return image


def arch_edge(image, columns):
    """Find the arch edge: the row where the colour jumps from the gradient
    to the flat canvas colour.

    The reference's arch is a flat #E2EEFF shape over a #BDDDFF -> #1160FF
    ramp, so the boundary is a strong vertical colour discontinuity. Looking
    for the discontinuity (rather than matching an expected colour) keeps the
    measurement independent of any colour shift between the two captures.
    """
    pixels = image.load()
    edges = {}
    for x in columns:
        best_y = None
        best_score = 0.0
        for y in range(300, 1010):
            above = pixels[x, y - 4]
            below = pixels[x, y + 4]
            score = sum(abs(a - b) for a, b in zip(above, below))
            if score > best_score:
                best_score = score
                best_y = y
        if best_y is not None and best_score > 40:
            edges[x] = best_y
    return edges


def main():
    clone_path = sys.argv[1]
    reference_path = sys.argv[2] if len(sys.argv) > 2 else REFERENCE

    clone = load(clone_path)
    reference = load(reference_path)
    clone_pixels = clone.load()
    reference_pixels = reference.load()

    # Only the outer columns are free of content in both captures; the centre
    # is covered by the mascot and the title text.
    columns = list(range(0, 300, 20)) + list(range(780, 1080, 20))
    clone_edge = arch_edge(clone, columns)
    reference_edge = arch_edge(reference, columns)

    print("arch edge (x: clone / reference / delta)")
    worst = 0.0
    for x in columns:
        clone_y = clone_edge.get(x)
        reference_y = reference_edge.get(x)
        if clone_y is None or reference_y is None:
            print(f"  x={x:4d}   {clone_y} / {reference_y}")
            continue
        delta = clone_y - reference_y
        worst = max(worst, abs(delta))
        print(f"  x={x:4d} {clone_y:5d} / {reference_y:5d} / {delta:+4d}")
    print(f"worst arch delta: {worst:.0f} px")

    total = 0
    close = 0
    print()
    print("band agreement (rows within 16 px of each other)")
    for top in range(0, 2340, 120):
        band_total = 0
        band_close = 0
        for y in range(top, min(top + 120, 2340), 4):
            for x in range(0, 1080, 4):
                a = clone_pixels[x, y]
                b = reference_pixels[x, y]
                band_total += 1
                if (
                    abs(a[0] - b[0]) <= 16
                    and abs(a[1] - b[1]) <= 16
                    and abs(a[2] - b[2]) <= 16
                ):
                    band_close += 1
        total += band_total
        close += band_close
        share = 100.0 * band_close / band_total if band_total else 0
        print(f"  y={top:4d}..{min(top + 120, 2340) - 1:4d}: {share:5.1f}%")
    print(f"overall: {100.0 * close / total:.1f}%")


if __name__ == "__main__":
    main()
