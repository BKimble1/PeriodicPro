#!/usr/bin/env python3
"""Builds the three Elemora app-icon appearances from one source artwork.

The mark is supplied as finished artwork in `Design/AppIconSource.png`: teal
periodic-table tiles stepping up to a single gold tile, on a warm off-white
field. That file is the design; this script is only the packaging step that
turns it into the light, dark and tinted 1024x1024 PNGs iOS 18+ expects.

Nothing here re-composes the mark. The tiles keep their size, spacing and
position; only the palette changes between appearances, and only because iOS
composites the dark and tinted icons against dark surfaces where a near-white
field would glare.

    python3 -m pip install pillow
    python3 Tools/make_app_icon.py
"""
from __future__ import annotations

import os
import sys

from PIL import Image

SIZE = 1024

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "Design", "AppIconSource.png")
OUT_DIR = os.path.join(
    ROOT, "PeriodicPro", "Assets.xcassets", "AppIcon.appiconset",
)

# The three flat colors the source artwork is drawn in. Sampled from the file
# rather than guessed; `_classify` tolerates the grain around them.
FIELD = (247, 245, 240)     # warm off-white background
TEAL = (27, 128, 141)       # the eight regular tiles
GOLD = (213, 168, 84)       # the one highlighted tile

# How far from FIELD a pixel has to be before it counts as part of the mark.
# The artwork's paper grain moves the field by two or three levels; the tiles
# are more than a hundred away, so anything in between is an antialiased edge.
FIELD_TOLERANCE = 18.0
FIELD_SOLID = 90.0


def _distance(pixel: tuple[int, int, int], color: tuple[int, int, int]) -> float:
    return sum((pixel[i] - color[i]) ** 2 for i in range(3)) ** 0.5


def _coverage(pixel: tuple[int, int, int]) -> float:
    """0 where the pixel is field, 1 where it is solid tile, ramped between.

    Using a ramp rather than a threshold is what keeps the tiles' rounded
    corners smooth after recoloring.
    """
    distance = _distance(pixel, FIELD)
    if distance <= FIELD_TOLERANCE:
        return 0.0
    if distance >= FIELD_SOLID:
        return 1.0
    return (distance - FIELD_TOLERANCE) / (FIELD_SOLID - FIELD_TOLERANCE)


def _is_gold(pixel: tuple[int, int, int]) -> bool:
    """Gold is warm, teal is cool; red-minus-blue separates them cleanly."""
    return pixel[0] > pixel[2]


def _blend(a: tuple[int, int, int], b: tuple[int, int, int], t: float):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def render(field: tuple[int, int, int],
           teal: tuple[int, int, int],
           gold: tuple[int, int, int]) -> Image.Image:
    """Repaints the source into one appearance's palette, edges intact."""
    source = Image.open(SOURCE).convert("RGB")
    if source.size != (SIZE, SIZE):
        source = source.resize((SIZE, SIZE), Image.LANCZOS)

    if (field, teal, gold) == (FIELD, TEAL, GOLD):
        return source  # light appearance: the artwork, untouched

    read = source.load()
    output = Image.new("RGB", (SIZE, SIZE))
    write = output.load()
    for y in range(SIZE):
        for x in range(SIZE):
            pixel = read[x, y]
            coverage = _coverage(pixel)
            if coverage == 0.0:
                write[x, y] = field
            else:
                target = gold if _is_gold(pixel) else teal
                write[x, y] = _blend(field, target, coverage)
    return output


VARIANTS = {
    # Light: the supplied artwork verbatim.
    "AppIcon-1024.png": dict(field=FIELD, teal=TEAL, gold=GOLD),

    # Dark: the same tiles on a deep neutral field. Both tile colors are
    # lifted a little, because the teal that reads as ink on off-white is too
    # close to the field once the field goes dark.
    "AppIcon-1024-Dark.png": dict(
        field=(18, 20, 21),
        teal=(52, 166, 180),
        gold=(226, 181, 96),
    ),

    # Tinted: grayscale only. iOS maps luminance onto the tint the user picked,
    # so the tiles have to be light and the field near-black. The gold tile
    # stays a step brighter than the others so the mark keeps its one accent.
    "AppIcon-1024-Tinted.png": dict(
        field=(12, 12, 12),
        teal=(168, 168, 168),
        gold=(236, 236, 236),
    ),
}


def main() -> int:
    if not os.path.exists(SOURCE):
        print(f"error: {SOURCE} is missing", file=sys.stderr)
        return 1

    os.makedirs(OUT_DIR, exist_ok=True)
    for filename, palette in VARIANTS.items():
        image = render(**palette)
        assert image.mode == "RGB", "App Store Connect rejects icons with alpha"
        path = os.path.join(OUT_DIR, filename)
        image.save(path, "PNG", optimize=True)
        print(f"wrote {path} ({image.size[0]}x{image.size[1]}, {image.mode})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
