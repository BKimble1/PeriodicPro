#!/usr/bin/env python3
"""Renders the redesigned Study tab at three device widths.

Like Tools/preview_table.py and Tools/preview_detail.py this is a composition
check rather than a screenshot: it mirrors the section order, paddings, radii
and type sizes from Views/Study so the hierarchy can be judged, and — more
usefully — so it can be proved that the practice tiles are still reachable
above the fold on the smallest supported phone.

    python3 Tools/preview_study.py [out.png]
"""
from __future__ import annotations

import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOLD = "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"
REGULAR = "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"

SCALE = 3
MARGIN = 20          # Theme.Spacing.screenMargin
SECTION = 26         # Theme.Spacing.section
CARD_RADIUS = 20     # Theme.Radius.card

CANVAS, SURFACE, HAIRLINE = (249, 250, 252), (255, 255, 255), (229, 233, 239)
PRIMARY, SECONDARY, TERTIARY = (17, 22, 33), (99, 109, 126), (134, 143, 159)
ACCENT = (32, 102, 229)
WARNING = (216, 102, 50)
POSITIVE = (22, 163, 104)

# The four practice tiles, with the family fills they are drawn on.
MODE_TILES = [
    ("Flashcards", (224, 246, 244), (14, 101, 96)),        # metalloid
    ("Quiz", (242, 231, 251), (96, 50, 138)),              # lanthanide
    ("Identify", (254, 236, 217), (144, 69, 19)),          # alkalineEarth
    ("Smart Review", (254, 234, 234), (148, 41, 48)),      # alkaliMetal
]

DEVICES = [
    ("iPhone SE (3rd gen)", 375, 667),
    ("iPhone 17", 393, 852),
    ("iPhone 17 Pro Max", 440, 956),
]

# Chrome the content has to live under and over.
NAV_BAR = 44
TAB_BAR = 49
STATUS_BAR = 54


def px(value):
    return int(round(value * SCALE))


def font(path, size):
    return ImageFont.truetype(path, max(1, int(round(size * SCALE))))


def card(draw, x, y, width, height, radius=CARD_RADIUS, fill=SURFACE, stroke=HAIRLINE):
    draw.rounded_rectangle(
        [px(x), px(y), px(x + width), px(y + height)],
        radius=px(radius),
        fill=fill,
        outline=stroke,
        width=max(1, SCALE // 2),
    )


def render(name: str, width: int, height: int) -> tuple[Image.Image, float]:
    """Draws the screen and returns the image plus the y of the tile row's bottom."""
    image = Image.new("RGB", (px(width), px(height)), CANVAS)
    draw = ImageDraw.Draw(image)
    content = width - MARGIN * 2

    # --- chrome -----------------------------------------------------------
    draw.rectangle([0, 0, px(width), px(STATUS_BAR)], fill=CANVAS)
    draw.text((px(MARGIN), px(STATUS_BAR - 24)), "9:41", font=font(BOLD, 13), fill=PRIMARY)
    centered(draw, "Study", font(BOLD, 15), PRIMARY, width / 2, STATUS_BAR + 12)
    y = STATUS_BAR + NAV_BAR + 8

    # --- greeting ---------------------------------------------------------
    title = font(BOLD, 33)
    draw.text((px(MARGIN), px(y)), "Good morning!", font=title, fill=PRIMARY)
    y += 39
    draw.text((px(MARGIN), px(y)), "Start exploring.", font=title, fill=PRIMARY)
    y += 41
    draw.text((px(MARGIN), px(y)), "Small steps. Big knowledge.",
              font=font(REGULAR, 15), fill=SECONDARY)
    y += 20 + SECTION

    # --- status cards -----------------------------------------------------
    gap = 12
    half = (content - gap) / 2
    status_height = 96
    for index, (glyph, glyph_color, value, caption) in enumerate([
        ("flame", WARNING, "0", "Day streak"),
        ("ring", POSITIVE, "0%", "Elements mastered"),
    ]):
        x = MARGIN + index * (half + gap)
        card(draw, x, y, half, status_height)
        if glyph == "flame":
            draw.ellipse([px(x + 16), px(y + 16), px(x + 34), px(y + 34)], fill=WARNING)
        else:
            draw.ellipse([px(x + 16), px(y + 16), px(x + 44), px(y + 44)],
                         outline=HAIRLINE, width=max(1, px(4.5)))
        draw.text((px(x + half - 20), px(y + 18)), "›", font=font(BOLD, 13), fill=TERTIARY)
        draw.text((px(x + 16), px(y + 46)), value, font=font(BOLD, 22), fill=PRIMARY)
        draw.text((px(x + 16), px(y + 74)), caption, font=font(REGULAR, 12), fill=SECONDARY)
    y += status_height + SECTION

    # --- hero card --------------------------------------------------------
    hero_height = 92
    draw.rounded_rectangle(
        [px(MARGIN), px(y), px(MARGIN + content), px(y + hero_height)],
        radius=px(CARD_RADIUS), fill=ACCENT,
    )
    draw.rounded_rectangle(
        [px(MARGIN + 16), px(y + 17), px(MARGIN + 74), px(y + 75)],
        radius=px(16), fill=(86, 141, 236),
    )
    draw.text((px(MARGIN + 90), px(y + 24)), "Flashcards", font=font(BOLD, 20), fill=(255, 255, 255))
    draw.text((px(MARGIN + 90), px(y + 50)), "Memorize, quiz and reinforce",
              font=font(REGULAR, 13), fill=(224, 233, 250))
    draw.text((px(MARGIN + 90), px(y + 64)), "your knowledge.",
              font=font(REGULAR, 13), fill=(224, 233, 250))
    draw.text((px(MARGIN + content - 22), px(y + 38)), "›", font=font(BOLD, 16),
              fill=(255, 255, 255))
    y += hero_height + SECTION

    # --- practice -------------------------------------------------------
    draw.text((px(MARGIN), px(y)), "Practice modes", font=font(BOLD, 19), fill=PRIMARY)
    allowance = "3 free rounds left today"
    allowance_font = font(REGULAR, 13)
    draw.text((px(MARGIN + content) - draw.textlength(allowance, font=allowance_font),
               px(y + 5)), allowance, font=allowance_font, fill=SECONDARY)
    y += 28

    tile_gap = 12
    tile = (content - tile_gap * 3) / 4
    for index, (label, fill, ink) in enumerate(MODE_TILES):
        x = MARGIN + index * (tile + tile_gap)
        draw.rounded_rectangle([px(x), px(y), px(x + tile), px(y + tile)],
                               radius=px(18), fill=fill)
        draw.ellipse([px(x + tile / 2 - 11), px(y + tile / 2 - 11),
                      px(x + tile / 2 + 11), px(y + tile / 2 + 11)], fill=ink)
        if label == "Smart Review":
            draw.rounded_rectangle([px(x + tile - 28), px(y + 5), px(x + tile - 5), px(y + 17)],
                                   radius=px(6), fill=(224, 233, 250))
            draw.text((px(x + tile - 25), px(y + 6)), "PRO", font=font(BOLD, 7), fill=ACCENT)
        label_font = font(REGULAR, 12)
        for line_index, line in enumerate(label.split(" ")
                                          if len(label) > 10 else [label]):
            centered(draw, line, label_font, PRIMARY,
                     x + tile / 2, y + tile + 5 + line_index * 14)
    tiles_bottom = y + tile + 5 + 14
    y = tiles_bottom + 8 + SECTION

    # --- recent searches --------------------------------------------------
    draw.text((px(MARGIN), px(y)), "Recent searches", font=font(BOLD, 19), fill=PRIMARY)
    clear_font = font(REGULAR, 13)
    draw.text((px(MARGIN + content) - draw.textlength("Clear", font=clear_font), px(y + 5)),
              "Clear", font=clear_font, fill=ACCENT)
    y += 26
    rows = ["sodium", "carbon", "oxygen"]
    row_height = 44
    card(draw, MARGIN, y, content, row_height * len(rows))
    for index, term in enumerate(rows):
        row_y = y + index * row_height
        if index:
            draw.line([px(MARGIN + 28), px(row_y), px(MARGIN + content), px(row_y)],
                      fill=HAIRLINE, width=max(1, SCALE // 2))
        draw.ellipse([px(MARGIN + 17), px(row_y + 16), px(MARGIN + 29), px(row_y + 28)],
                     outline=SECONDARY, width=max(1, SCALE // 2))
        draw.text((px(MARGIN + 40), px(row_y + 14)), term, font=font(REGULAR, 16), fill=PRIMARY)
        draw.ellipse([px(MARGIN + content - 30), px(row_y + 16),
                      px(MARGIN + content - 18), px(row_y + 28)],
                     outline=TERTIARY, width=max(1, SCALE // 2))
    y += row_height * len(rows) + SECTION

    # --- favorites --------------------------------------------------------
    draw.text((px(MARGIN), px(y)), "Favorites", font=font(BOLD, 19), fill=PRIMARY)

    # --- tab bar ----------------------------------------------------------
    draw.rectangle([0, px(height - TAB_BAR), px(width), px(height)], fill=(252, 253, 254))
    draw.line([0, px(height - TAB_BAR)], fill=HAIRLINE, width=max(1, SCALE // 2))
    for index, label in enumerate(["Table", "Study", "Progress"]):
        color = ACCENT if label == "Study" else TERTIARY
        centered(draw, label, font(REGULAR, 10), color,
                 width * (index + 0.5) / 3, height - TAB_BAR + 30)

    return image, tiles_bottom


def centered(draw, text, fnt, color, center_x, y):
    text_width = draw.textlength(text, font=fnt)
    draw.text((px(center_x) - text_width / 2, px(y)), text, font=fnt, fill=color)


def main() -> int:
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "Design", "study-preview.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)

    images = []
    failures = []
    print(f"{'device':<24}{'width':>7}{'tiles end':>11}{'fold':>7}  above fold")
    for name, width, height in DEVICES:
        image, tiles_bottom = render(name, width, height)
        images.append(image)
        fold = height - TAB_BAR
        ok = tiles_bottom <= fold
        print(f"{name:<24}{width:>7}{tiles_bottom:>11.0f}{fold:>7}  {'yes' if ok else 'NO'}")
        if not ok:
            failures.append(
                f"{name}: the practice tiles end at {tiles_bottom:.0f}pt but the "
                f"content area ends at {fold}pt, so they are below the fold"
            )

    gap = 24 * SCALE
    total = sum(i.width for i in images) + gap * (len(images) - 1)
    sheet = Image.new("RGB", (total, max(i.height for i in images)), (232, 235, 240))
    x = 0
    for image in images:
        sheet.paste(image, (x, 0))
        x += image.width + gap
    sheet.save(out)
    print(f"\nwrote {os.path.relpath(out, ROOT)}")

    if failures:
        for failure in failures:
            print(f"error: {failure}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
