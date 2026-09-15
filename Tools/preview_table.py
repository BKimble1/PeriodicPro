#!/usr/bin/env python3
"""Renders the fitted periodic table at real device widths.

This is a design check, not a screenshot: it mirrors the layout arithmetic in
PeriodicTableScreen/PeriodicTableGrid and the palette in CategoryPalette.swift
so tile size, spacing and symbol legibility can be judged without a Mac. The
substitute typeface is a little wider than SF Pro, so anything that fits here
fits on device.

    python3 Tools/preview_table.py [out.png]
"""
from __future__ import annotations

import json
import os
import sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ELEMENTS = os.path.join(ROOT, "PeriodicPro", "Data", "elements.json")
FONT_BOLD = "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"
FONT_REGULAR = "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"

SCALE = 3                       # render at @3x so small type can be judged
COLUMNS = 18
FITTED_SPACING = 1.5
HORIZONTAL_INSET = 16           # Theme.Spacing.l
SCREEN_MARGIN = 20              # Theme.Spacing.screenMargin

# Mirrors ElementCategory.tileFill / .onTileColor (light mode).
PALETTE = {
    "alkaliMetal":         ((254, 234, 234), (148, 41, 48)),
    "alkalineEarthMetal":  ((254, 239, 224), (146, 77, 25)),
    "transitionMetal":     ((254, 247, 221), (128, 96, 14)),
    "postTransitionMetal": ((229, 247, 236), (30, 102, 61)),
    "metalloid":           ((224, 246, 244), (14, 101, 96)),
    "reactiveNonmetal":    ((225, 242, 254), (19, 86, 126)),
    "halogen":             ((229, 236, 254), (38, 69, 150)),
    "nobleGas":            ((237, 234, 254), (75, 61, 150)),
    "lanthanide":          ((242, 231, 251), (96, 50, 138)),
    "actinide":            ((252, 229, 246), (133, 47, 108)),
}

CANVAS = (249, 250, 252)
TEXT_PRIMARY = (17, 22, 33)
TEXT_SECONDARY = (99, 109, 126)
TEXT_TERTIARY = (140, 149, 165)
ACCENT = (41, 115, 239)
SURFACE = (255, 255, 255)
HAIRLINE = (229, 233, 239)

DEVICES = [
    ("iPhone SE (3rd gen)", 375, 667),
    ("iPhone 17", 393, 852),
    ("iPhone 17 Pro Max", 440, 956),
]


def font(path, size):
    return ImageFont.truetype(path, max(1, int(round(size * SCALE))))


def px(value):
    return int(round(value * SCALE))


def rounded(draw, box, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def tile_size(width):
    """PeriodicTableScreen.tileSize, fitted layout."""
    usable = max(width - HORIZONTAL_INSET * 2, 260)
    gaps = FITTED_SPACING * (COLUMNS - 1)
    import math
    return max(13, math.floor((usable - gaps) / COLUMNS))


def draw_table(draw, elements, origin_x, origin_y, tile, spacing):
    step = tile + spacing
    symbol_font = font(FONT_BOLD, tile * 0.46)

    def block(rows, base_row, y):
        for element in rows:
            x = origin_x + (element["gridX"] - 1) * step
            row_y = y + (element["gridY"] - base_row) * step
            fill, ink = PALETTE[element["category"]]
            radius = max(5, tile * 0.22)
            rounded(draw,
                    [px(x), px(row_y), px(x + tile), px(row_y + tile)],
                    radius=px(radius), fill=fill)
            text = element["symbol"]
            bbox = draw.textbbox((0, 0), text, font=symbol_font)
            tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
            draw.text((px(x + tile / 2) - tw / 2 - bbox[0],
                       px(row_y + tile / 2) - th / 2 - bbox[1]),
                      text, font=symbol_font, fill=ink)

    main = [e for e in elements if e["gridY"] <= 7]
    lanth = [e for e in elements if e["gridY"] == 9]
    actin = [e for e in elements if e["gridY"] == 10]

    block(main, 1, origin_y)
    y = origin_y + 7 * step - spacing + max(8, tile * 0.45)

    caption_font = font(FONT_REGULAR, max(9, min(11, tile * 0.5)))
    label_gap = max(4, tile * 0.2)
    for label, rows, base in (("Lanthanides", lanth, 9), ("Actinides", actin, 10)):
        draw.text((px(origin_x), px(y)), label, font=caption_font, fill=TEXT_TERTIARY)
        y += max(11, tile * 0.55) + label_gap
        block(rows, base, y)
        y += tile + label_gap
    return y


def render(name, width, height, elements):
    image = Image.new("RGB", (px(width), px(height)), CANVAS)
    draw = ImageDraw.Draw(image)

    y = 58
    draw.text((px(SCREEN_MARGIN), px(y)), "Periodic Table",
              font=font(FONT_BOLD, 34), fill=TEXT_PRIMARY)
    y += 46

    # Search field
    rounded(draw, [px(SCREEN_MARGIN), px(y), px(width - SCREEN_MARGIN), px(y + 36)],
            radius=px(10), fill=(238, 240, 245))
    draw.text((px(SCREEN_MARGIN + 12), px(y + 10)), "Element, symbol, or number",
              font=font(FONT_REGULAR, 15), fill=TEXT_TERTIARY)
    y += 50

    draw.text((px(SCREEN_MARGIN), px(y)),
              "Tap an element to explore its structure, key facts",
              font=font(FONT_REGULAR, 15), fill=TEXT_SECONDARY)
    draw.text((px(SCREEN_MARGIN), px(y + 19)), "and everyday uses.",
              font=font(FONT_REGULAR, 15), fill=TEXT_SECONDARY)
    y += 48

    # Filter chips
    chip_x = SCREEN_MARGIN
    chip_font = font(FONT_REGULAR, 15)
    for index, label in enumerate(["All", "Metals", "Nonmetals", "Metalloids"]):
        w = draw.textlength(label, font=chip_font) / SCALE + 32
        selected = index == 0
        rounded(draw, [px(chip_x), px(y), px(chip_x + w), px(y + 34)], radius=px(17),
                fill=ACCENT if selected else SURFACE,
                outline=None if selected else HAIRLINE, width=px(0.8))
        draw.text((px(chip_x + 16), px(y + 8)), label, font=chip_font,
                  fill=(255, 255, 255) if selected else TEXT_PRIMARY)
        chip_x += w + 8
    y += 48

    tile = tile_size(width)
    table_width = COLUMNS * tile + (COLUMNS - 1) * FITTED_SPACING
    origin_x = (width - table_width) / 2
    y = draw_table(draw, elements, origin_x, y, tile, FITTED_SPACING)

    # Legend card
    y += 14
    legend_height = 132
    rounded(draw, [px(SCREEN_MARGIN), px(y), px(width - SCREEN_MARGIN), px(y + legend_height)],
            radius=px(20), fill=SURFACE, outline=HAIRLINE, width=px(0.8))
    draw.text((px(SCREEN_MARGIN + 16), px(y + 14)), "FAMILIES",
              font=font(FONT_BOLD, 12), fill=TEXT_SECONDARY)
    names = [
        ("alkaliMetal", "Alkali"), ("metalloid", "Metalloid"),
        ("alkalineEarthMetal", "Alkaline Earth"), ("reactiveNonmetal", "Nonmetal"),
        ("transitionMetal", "Transition"), ("halogen", "Halogen"),
        ("postTransitionMetal", "Post-Transition"), ("nobleGas", "Noble Gas"),
        ("lanthanide", "Lanthanide"), ("actinide", "Actinide"),
    ]
    column_width = (width - SCREEN_MARGIN * 2 - 32) / 2
    for index, (key, label) in enumerate(names):
        col, row = index % 2, index // 2
        lx = SCREEN_MARGIN + 16 + col * column_width
        ly = y + 36 + row * 19
        fill, ink = PALETTE[key]
        rounded(draw, [px(lx), px(ly), px(lx + 16), px(ly + 16)], radius=px(4), fill=fill)
        draw.text((px(lx + 22), px(ly + 2)), label,
                  font=font(FONT_REGULAR, 12), fill=TEXT_SECONDARY)
    y += legend_height

    # Tab bar
    bar_top = height - 83
    draw.rectangle([0, px(bar_top), px(width), px(height)], fill=(252, 252, 253))
    draw.line([0, px(bar_top), px(width), px(bar_top)], fill=HAIRLINE, width=px(0.5))
    for index, label in enumerate(["Table", "Study", "Progress"]):
        cx = width * (index + 0.5) / 3
        tab_font = font(FONT_REGULAR, 10)
        tw = draw.textlength(label, font=tab_font)
        draw.text((px(cx) - tw / 2, px(bar_top + 34)), label, font=tab_font,
                  fill=ACCENT if index == 0 else TEXT_TERTIARY)

    footer = font(FONT_REGULAR, 11)
    caption = f"{name}  ·  {width}x{height}pt  ·  tile {tile}pt  ·  table {table_width:.1f}pt"
    draw.text((px(SCREEN_MARGIN), px(y + 10)), caption, font=footer, fill=TEXT_TERTIARY)

    fits = table_width <= width - HORIZONTAL_INSET * 2 + 0.5
    return image, fits, tile, table_width


def main() -> int:
    with open(ELEMENTS, encoding="utf-8") as handle:
        elements = json.load(handle)

    images, report = [], []
    for name, width, height in DEVICES:
        image, fits, tile, table_width = render(name, width, height, elements)
        images.append(image)
        report.append((name, width, tile, table_width, fits))

    gap = px(24)
    total_width = sum(i.width for i in images) + gap * (len(images) + 1)
    total_height = max(i.height for i in images) + gap * 2
    sheet = Image.new("RGB", (total_width, total_height), (226, 230, 238))
    x = gap
    for image in images:
        sheet.paste(image, (x, gap))
        x += image.width + gap

    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "Design", "table-preview.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    sheet.save(out, "PNG")

    print(f"{'device':24} {'width':>6} {'tile':>6} {'table':>8}  fits")
    ok = True
    for name, width, tile, table_width, fits in report:
        print(f"{name:24} {width:6} {tile:6} {table_width:8.1f}  {'yes' if fits else 'NO'}")
        ok = ok and fits
    print(f"\nwrote {os.path.relpath(out, ROOT)}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
