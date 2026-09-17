#!/usr/bin/env python3
"""Builds the 1200 x 630 card that link previews show for a shared quiz.

The same mark as the app icon — four columns by three rows of tiles, one of
them gold — over the Elemora off-white, with the wordmark and a single line of
copy. Geometry rather than a supplied raster, for the same reason the icon is:
every edge lands on a sample boundary at the 3x master and downsamples once
with a box filter, so there is no ringing and no soft edge.

    python3 -m pip install pillow
    python3 Tools/make_share_card.py

Output:

    Website/site/assets/elemora-quiz-card.png    1200 x 630, RGB, no alpha

The app draws its own version of this card at share time (`QuizShareCard`), so
that Messages can show the quiz's own title; this static one is what a service
fetching the https URL gets from the page's og:image.
"""
from __future__ import annotations

import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT = 1200, 630
SCALE = 3

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Website", "site", "assets", "elemora-quiz-card.png")

FIELD = (247, 245, 240)
FIELD_EDGE = (234, 240, 242)
TEAL = (27, 128, 141)
GOLD = (213, 168, 84)
INK = (17, 28, 33)
MUTED = (96, 112, 120)

TILE = 26
GAP = 4
COLUMNS, ROWS = 4, 3
TEAL_TILES = [(0, 0), (0, 1), (2, 1), (3, 1), (0, 2), (1, 2), (2, 2), (3, 2)]
GOLD_TILE = (3, 0)

FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf",
]
FONT_REGULAR_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
]


def font(candidates: list[str], size: int) -> ImageFont.FreeTypeFont:
    for path in candidates:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    raise SystemExit(
        "No usable TrueType font found. Install fonts-dejavu-core, or add a path "
        "to FONT_CANDIDATES."
    )


def rounded_square(draw: ImageDraw.ImageDraw, x: float, y: float, size: float,
                   color: tuple[int, int, int]) -> None:
    radius = size * 0.22
    draw.rounded_rectangle([x, y, x + size, y + size], radius=radius, fill=color)


def mark(draw: ImageDraw.ImageDraw, x: float, y: float, tile: float, gap: float,
         teal: tuple[int, int, int], gold: tuple[int, int, int]) -> None:
    pitch = tile + gap
    for column, row in TEAL_TILES:
        rounded_square(draw, x + column * pitch, y + row * pitch, tile, teal)
    rounded_square(draw, x + GOLD_TILE[0] * pitch, y + GOLD_TILE[1] * pitch, tile, gold)


def blend(base: tuple[int, int, int], other: tuple[int, int, int],
          amount: float) -> tuple[int, int, int]:
    return tuple(round(a + (b - a) * amount) for a, b in zip(base, other))


def render() -> Image.Image:
    width, height = WIDTH * SCALE, HEIGHT * SCALE
    image = Image.new("RGB", (width, height), FIELD)
    draw = ImageDraw.Draw(image)

    # A soft diagonal wash, drawn as horizontal bands: flat colour throughout,
    # so the box filter has nothing to ring against.
    for row in range(height):
        amount = row / max(height - 1, 1)
        draw.line([(0, row), (width, row)], fill=blend(FIELD, FIELD_EDGE, amount))

    # The mark, enlarged and bled off the right edge at low contrast.
    ghost = blend(FIELD_EDGE, TEAL, 0.10)
    mark(draw, width * 0.72, height * 0.18, 150 * SCALE * 0.55, 22 * SCALE * 0.55, ghost, ghost)

    margin = 72 * SCALE
    mark(draw, margin, margin, TILE * SCALE, GAP * SCALE, TEAL, GOLD)

    wordmark = font(FONT_CANDIDATES, 40 * SCALE)
    title = font(FONT_CANDIDATES, 86 * SCALE)
    subtitle = font(FONT_REGULAR_CANDIDATES, 36 * SCALE)
    chip = font(FONT_CANDIDATES, 32 * SCALE)

    mark_width = (TILE * SCALE + GAP * SCALE) * COLUMNS - GAP * SCALE
    draw.text((margin + mark_width + 28 * SCALE, margin - 4 * SCALE),
              "E L E M O R A", font=wordmark, fill=TEAL)

    draw.text((margin, height * 0.42), "A quiz to study", font=title, fill=INK)
    draw.text((margin, height * 0.42 + 100 * SCALE),
              "Open it in Elemora to save and play it.", font=subtitle, fill=MUTED)

    # The chip, bottom left.
    label = "Elemora Quiz"
    box = draw.textbbox((0, 0), label, font=chip)
    pad_x, pad_y = 30 * SCALE, 16 * SCALE
    chip_width = box[2] - box[0] + pad_x * 2
    chip_height = box[3] - box[1] + pad_y * 2
    chip_x = margin
    chip_y = height - margin - chip_height
    draw.rounded_rectangle(
        [chip_x, chip_y, chip_x + chip_width, chip_y + chip_height],
        radius=chip_height / 2, fill=TEAL,
    )
    draw.text((chip_x + pad_x - box[0], chip_y + pad_y - box[1]), label, font=chip,
              fill=(255, 255, 255))

    return image.resize((WIDTH, HEIGHT), Image.BOX)


def main() -> int:
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    image = render()
    image.save(OUT, "PNG", optimize=True)
    size = os.path.getsize(OUT)
    print(f"wrote {os.path.relpath(OUT, ROOT)} — {image.width}x{image.height}, {size // 1024} KB")
    if image.size != (WIDTH, HEIGHT):
        print("error: the card is not 1200x630")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
