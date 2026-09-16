#!/usr/bin/env python3
"""Builds the three Elemora app-icon appearances from exact geometry.

The mark is nine periodic-table tiles — eight teal, one gold — on a flat field,
and it is defined here as geometry rather than supplied as a raster: every
tile is an integer-aligned rounded square on a 1024-unit grid, drawn with
continuous (superellipse) corners like `ElementTile` in the app.

Why geometry. The previous source artwork was a finished raster with three
problems that read as "blurry" on a Home Screen:

* the mark spanned only 51% of the canvas, so at 60 points a tile was 21
  pixels wide and the gaps between tiles were under two pixels;
* the gaps were uneven (11, 11, 12 and 15, 16 units), so no tile edge landed
  on a pixel boundary at any size iOS renders;
* the field and the tiles carried a paper-grain texture, which iOS's own
  downsampling turns into a mottled, soft edge.

This renders the geometry once at 4× (4096 × 4096) with no antialiasing, then
downsamples exactly once to 1024 × 1024 with a box filter — the area-average
of sixteen samples per output pixel, which is the correct antialiasing for
flat color and adds no ringing, no glow and no blur. There is no Gaussian
step anywhere, no grain, and nothing is ever resized from a smaller raster.

    python3 -m pip install pillow
    python3 Tools/make_app_icon.py

Outputs (all 1024 × 1024, RGB, no alpha, sRGB, square corners — iOS masks):

    PeriodicPro/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
    PeriodicPro/Assets.xcassets/AppIcon.appiconset/AppIcon-1024-Dark.png
    PeriodicPro/Assets.xcassets/AppIcon.appiconset/AppIcon-1024-Tinted.png
    Design/AppIconSource.png          the light appearance, for humans
    Design/AppIconPreview.png         the mark at real Home Screen sizes
"""
from __future__ import annotations

import math
import os
import sys

from PIL import Image, ImageDraw
from PIL.PngImagePlugin import PngInfo

SIZE = 1024
# Supersampling factor. 4 gives sixteen coverage samples per output pixel.
MASTER_SCALE = 4
MASTER_SIZE = SIZE * MASTER_SCALE

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "PeriodicPro", "Assets.xcassets", "AppIcon.appiconset")
DESIGN_DIR = os.path.join(ROOT, "Design")

# --- Geometry, in 1024-unit canvas coordinates ------------------------------
#
# Four columns by three rows. Tile 144, gap 20, pitch 164: the mark is 636
# wide and 472 tall, centered, so it fills 62% of the canvas width — inside
# Apple's safe zone for a masked icon with room to spare, and half again as
# large on the Home Screen as the raster it replaces. Every number is an even
# integer, so at the 4× master every edge lands exactly on a sample boundary.
TILE = 144
GAP = 20
PITCH = TILE + GAP
COLUMNS = 4
ROWS = 3
MARK_WIDTH = COLUMNS * TILE + (COLUMNS - 1) * GAP     # 636
MARK_HEIGHT = ROWS * TILE + (ROWS - 1) * GAP          # 472
ORIGIN_X = (SIZE - MARK_WIDTH) // 2                   # 194
ORIGIN_Y = (SIZE - MARK_HEIGHT) // 2                  # 276
# 22% of the tile, the same ratio `ElementTileShape.cornerRadius(for:)` uses.
CORNER_RADIUS = round(TILE * 0.22)                    # 32
# Exponent of the superellipse that shapes each corner: 2 is a circle, higher
# is squarer. 3.2 reads as iOS's continuous corner at icon sizes.
CORNER_EXPONENT = 3.2

# (column, row) of every tile, row 0 at the top. The one gold tile is the
# top-right: the element you are looking at.
TEAL_TILES = [
    (0, 0),
    (0, 1), (2, 1), (3, 1),
    (0, 2), (1, 2), (2, 2), (3, 2),
]
GOLD_TILE = (3, 0)

# --- Palette ----------------------------------------------------------------
FIELD = (247, 245, 240)     # warm off-white
TEAL = (27, 128, 141)
GOLD = (213, 168, 84)

VARIANTS = {
    # Light: the mark as designed.
    "AppIcon-1024.png": dict(field=FIELD, teal=TEAL, gold=GOLD),

    # Dark: the same tiles on a deep neutral field. Both tile colors are
    # lifted a step, because the teal that reads as ink on off-white is too
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

# Written into every PNG as tEXt chunks. `Tools/check_app_icon.py` reads them
# back: an icon that was not produced by this pipeline, or was produced from a
# master smaller than 2048, fails the check.
METADATA_SOFTWARE = "Tools/make_app_icon.py"
METADATA_MASTER_KEY = "elemora:master-size"


def superellipse_rounded_rect(x0: float, y0: float, size: float, radius: float,
                              exponent: float, steps: int = 48) -> list[tuple[float, float]]:
    """Polygon for a square with continuous corners, clockwise from top-left.

    Each corner is one quadrant of a superellipse |u|^n + |v|^n = r^n, which
    is a circle at n = 2 and squarer as n rises. Straight edges between the
    corners are exact, so at the 4× master a tile edge is a hard sample
    boundary and the only antialiasing is the box filter's own.
    """
    points: list[tuple[float, float]] = []
    x1, y1 = x0 + size, y0 + size
    # Corner centers, then the angular range each quadrant sweeps.
    corners = [
        (x1 - radius, y0 + radius, -math.pi / 2, 0.0),           # top-right
        (x1 - radius, y1 - radius, 0.0, math.pi / 2),            # bottom-right
        (x0 + radius, y1 - radius, math.pi / 2, math.pi),        # bottom-left
        (x0 + radius, y0 + radius, math.pi, 3 * math.pi / 2),    # top-left
    ]
    power = 2.0 / exponent
    for cx, cy, start, end in corners:
        for step in range(steps + 1):
            t = start + (end - start) * step / steps
            c, s = math.cos(t), math.sin(t)
            u = math.copysign(abs(c) ** power, c) * radius
            v = math.copysign(abs(s) ** power, s) * radius
            points.append((cx + u, cy + v))
    return points


def render_master(field, teal, gold) -> Image.Image:
    """The 4096 × 4096 master: flat fills, hard edges, no antialiasing."""
    image = Image.new("RGB", (MASTER_SIZE, MASTER_SIZE), field)
    draw = ImageDraw.Draw(image)
    scale = MASTER_SCALE

    def tile(column: int, row: int, color):
        x = (ORIGIN_X + column * PITCH) * scale
        y = (ORIGIN_Y + row * PITCH) * scale
        polygon = superellipse_rounded_rect(
            x, y, TILE * scale, CORNER_RADIUS * scale, CORNER_EXPONENT
        )
        draw.polygon(polygon, fill=color)

    for column, row in TEAL_TILES:
        tile(column, row, teal)
    tile(*GOLD_TILE, gold)
    return image


def render(field, teal, gold) -> Image.Image:
    """One appearance at 1024: the master, box-downsampled exactly once."""
    master = render_master(field, teal, gold)
    # `reduce` is an exact area average over MASTER_SCALE × MASTER_SCALE blocks.
    # It is the one resampling step in the whole pipeline.
    return master.reduce(MASTER_SCALE)


def metadata() -> PngInfo:
    info = PngInfo()
    info.add_text("Software", METADATA_SOFTWARE)
    info.add_text(METADATA_MASTER_KEY, str(MASTER_SIZE))
    info.add_text(
        "Comment",
        f"Elemora app icon. Geometry rendered at {MASTER_SIZE}x{MASTER_SIZE}, "
        f"box-downsampled once to {SIZE}x{SIZE}. sRGB, no alpha, square corners.",
    )
    return info


def home_screen_preview(light: Image.Image, dark: Image.Image) -> Image.Image:
    """The icon at the pixel sizes iOS actually draws it, for a human to judge.

    LANCZOS stands in for the system's own downsampler here. The sizes are
    the Home Screen (60pt at 3× and 2×), Spotlight (40pt at 3×), Settings
    (29pt at 3× and 2×) and the iPad Home Screen (76pt at 2×, 83.5pt at 2×).
    """
    sizes = [180, 120, 120, 87, 58, 152, 167]
    labels = ["60@3x", "60@2x", "40@3x", "29@3x", "29@2x", "76@2x", "83.5@2x"]
    gap = 24
    width = sum(sizes) + gap * (len(sizes) + 1)
    height = 2 * (180 + gap) + gap
    sheet = Image.new("RGB", (width, height), (120, 124, 130))
    for row, source in enumerate((light, dark)):
        x = gap
        for size in sizes:
            small = source.resize((size, size), Image.LANCZOS)
            # The Home Screen mask, so the preview shows what a person sees.
            mask = Image.new("L", (size * 4, size * 4), 0)
            ImageDraw.Draw(mask).rounded_rectangle(
                [0, 0, size * 4 - 1, size * 4 - 1], radius=int(size * 4 * 0.2237), fill=255
            )
            mask = mask.resize((size, size), Image.LANCZOS)
            sheet.paste(small, (x, gap + row * (180 + gap) + (180 - size)), mask)
            x += size + gap
    return sheet, list(zip(labels, sizes))


def main() -> int:
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(DESIGN_DIR, exist_ok=True)

    rendered: dict[str, Image.Image] = {}
    for filename, palette in VARIANTS.items():
        image = render(**palette)
        assert image.mode == "RGB", "App Store Connect rejects icons with alpha"
        assert image.size == (SIZE, SIZE)
        path = os.path.join(OUT_DIR, filename)
        image.save(path, "PNG", optimize=True, pnginfo=metadata())
        rendered[filename] = image
        print(f"wrote {os.path.relpath(path, ROOT)} ({image.size[0]}x{image.size[1]}, {image.mode})")

    # The design, for humans: the light appearance verbatim.
    source_path = os.path.join(DESIGN_DIR, "AppIconSource.png")
    rendered["AppIcon-1024.png"].save(source_path, "PNG", optimize=True, pnginfo=metadata())
    print(f"wrote {os.path.relpath(source_path, ROOT)}")

    preview, sizes = home_screen_preview(
        rendered["AppIcon-1024.png"], rendered["AppIcon-1024-Dark.png"]
    )
    preview_path = os.path.join(DESIGN_DIR, "AppIconPreview.png")
    preview.save(preview_path, "PNG", optimize=True)
    print(f"wrote {os.path.relpath(preview_path, ROOT)} "
          + ", ".join(f"{label}={size}px" for label, size in sizes))
    return 0


if __name__ == "__main__":
    sys.exit(main())
