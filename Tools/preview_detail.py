#!/usr/bin/env python3
"""Renders the element detail screen at a real device width.

Like Tools/preview_table.py this is a composition check rather than a
screenshot: it mirrors the card order, paddings, radii and type sizes from
Views/Detail so density and rhythm can be judged without a Mac.

    python3 Tools/preview_detail.py [Na] [out.png]
"""
from __future__ import annotations

import json
import math
import os
import sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ELEMENTS = os.path.join(ROOT, "PeriodicPro", "Data", "elements.json")
BOLD = "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"
REGULAR = "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"
MONO = "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf"

SCALE = 3
WIDTH, HEIGHT = 393, 1500          # tall canvas: the whole scroll, unrolled
MARGIN = 20

PALETTE = {
    "alkaliMetal":         ((254, 234, 234), (148, 41, 48), (230, 83, 90)),
    "alkalineEarthMetal":  ((254, 236, 217), (144, 69, 19), (223, 106, 37)),
    "transitionMetal":     ((251, 249, 211), (113, 101, 11), (163, 138, 20)),
    "postTransitionMetal": ((229, 247, 236), (30, 102, 61), (50, 142, 86)),
    "metalloid":           ((224, 246, 244), (14, 101, 96), (33, 144, 138)),
    "reactiveNonmetal":    ((225, 242, 254), (19, 86, 126), (51, 152, 211)),
    "halogen":             ((229, 236, 254), (38, 69, 150), (75, 122, 233)),
    "nobleGas":            ((237, 234, 254), (75, 61, 150), (126, 111, 229)),
    "lanthanide":          ((242, 231, 251), (96, 50, 138), (162, 101, 216)),
    "actinide":            ((252, 229, 246), (133, 47, 108), (212, 96, 179)),
}
CANVAS, SURFACE, MUTED = (249, 250, 252), (255, 255, 255), (245, 247, 250)
HAIRLINE, PRIMARY, SECONDARY, TERTIARY = (229, 233, 239), (17, 22, 33), (99, 109, 126), (134, 143, 159)
POSITIVE = (22, 163, 104)

SUPERSCRIPT = {"0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
               "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹"}


def superscripted(configuration: str) -> str:
    out, after_letter = "", False
    for character in configuration:
        if character.isdigit() and after_letter:
            out += SUPERSCRIPT[character]
            continue
        after_letter = character in "spdf"
        out += character
    return out


def px(value):
    return int(round(value * SCALE))


def font(path, size):
    return ImageFont.truetype(path, max(1, int(round(size * SCALE))))


def wrap(draw, text, fnt, max_width):
    words, lines, line = text.split(), [], ""
    for word in words:
        candidate = f"{line} {word}".strip()
        if draw.textlength(candidate, font=fnt) / SCALE <= max_width:
            line = candidate
        else:
            if line:
                lines.append(line)
            line = word
    if line:
        lines.append(line)
    return lines


def paragraph(draw, text, fnt, color, x, y, max_width, leading):
    for line in wrap(draw, text, fnt, max_width):
        draw.text((px(x), px(y)), line, font=fnt, fill=color)
        y += leading
    return y


def card(draw, x, y, width, height, radius=20):
    draw.rounded_rectangle([px(x), px(y), px(x + width), px(y + height)],
                           radius=px(radius), fill=SURFACE, outline=HAIRLINE, width=px(0.8))


def centered(draw, text, fnt, color, center_x, y):
    width = draw.textlength(text, font=fnt)
    draw.text((px(center_x) - width / 2, px(y)), text, font=fnt, fill=color)


def render(element):
    fill, ink, accent = PALETTE[element["category"]]
    image = Image.new("RGB", (px(WIDTH), px(HEIGHT)), CANVAS)
    draw = ImageDraw.Draw(image)

    # Tinted backdrop that fades into the page background.
    for row in range(px(520)):
        t = row / px(520)
        blend = tuple(round(fill[i] + (CANVAS[i] - fill[i]) * min(1, t * 1.25)) for i in range(3))
        draw.line([(0, row), (px(WIDTH), row)], fill=blend)

    y = 58
    draw.text((px(MARGIN), px(y)), "‹", font=font(BOLD, 30), fill=accent)
    draw.text((px(WIDTH - MARGIN - 20), px(y + 6)), "♡", font=font(REGULAR, 20), fill=SECONDARY)
    y += 46

    # --- hero ---------------------------------------------------------------
    hero = 196
    hx = (WIDTH - hero) / 2
    # Mirrors ElementTileShape.cornerRadius(for:) so the preview shows the same
    # silhouette the zoom transition grows.
    draw.rounded_rectangle([px(hx), px(y), px(hx + hero), px(y + hero)],
                           radius=px(max(5, hero * 0.22)), fill=fill, outline=accent, width=px(1))
    pad = hero * 0.11
    draw.text((px(hx + pad), px(y + pad)), str(element["atomicNumber"]),
              font=font(REGULAR, hero * 0.115), fill=ink)
    centered(draw, element["symbol"], font(BOLD, hero * 0.40), ink, WIDTH / 2, y + hero * 0.30)
    centered(draw, element["name"], font(REGULAR, hero * 0.105), ink, WIDTH / 2, y + hero * 0.66)
    mass = (f"{int(element['atomicMass'])} u" if element["atomicMassIsMassNumber"]
            else f"{element['atomicMass']:.3f} u".rstrip("0").rstrip(".") + (" u" if False else ""))
    mass_font = font(REGULAR, hero * 0.072)
    draw.text((px(hx + hero - pad) - draw.textlength(mass, font=mass_font), px(y + hero - pad - 9)),
              mass, font=mass_font, fill=ink)
    y += hero + 16

    # family badge
    label = {"alkaliMetal": "Alkali Metal", "alkalineEarthMetal": "Alkaline Earth Metal",
             "transitionMetal": "Transition Metal", "postTransitionMetal": "Post-Transition Metal",
             "metalloid": "Metalloid", "reactiveNonmetal": "Reactive Nonmetal",
             "halogen": "Halogen", "nobleGas": "Noble Gas", "lanthanide": "Lanthanide",
             "actinide": "Actinide"}[element["category"]]
    badge_font = font(BOLD, 12)
    bw = draw.textlength(label, font=badge_font) / SCALE + 30
    draw.rounded_rectangle([px((WIDTH - bw) / 2), px(y), px((WIDTH + bw) / 2), px(y + 24)],
                           radius=px(12), fill=fill, outline=accent, width=px(0.6))
    centered(draw, label, badge_font, ink, WIDTH / 2, y + 6)
    y += 36

    tagline_font = font(REGULAR, 20)
    for line in wrap(draw, element["tagline"], tagline_font, WIDTH - MARGIN * 2 - 16):
        centered(draw, line, tagline_font, SECONDARY, WIDTH / 2, y)
        y += 26
    y += 16

    inner = WIDTH - MARGIN * 2
    body = inner - 32

    # --- structure card -----------------------------------------------------
    card_height = 306
    card(draw, MARGIN, y, inner, card_height)
    cy = y + 16
    draw.text((px(MARGIN + 16), px(cy)), "Atomic Structure", font=font(BOLD, 17), fill=PRIMARY)
    cy += 30

    # shell diagram
    diameter = 152
    cx, cyy = MARGIN + 16 + diameter / 2, cy + diameter / 2
    shells = element["shellElectrons"]
    inner_r, outer_r = diameter * 0.185, diameter * 0.46
    for index, count in enumerate(shells):
        r = outer_r if len(shells) == 1 else inner_r + (outer_r - inner_r) * index / (len(shells) - 1)
        draw.ellipse([px(cx - r), px(cyy - r), px(cx + r), px(cyy + r)],
                     outline=tuple(list(accent) ), width=max(1, px(0.75)))
        dot = max(2.0, min(5.5, (2 * math.pi * r / max(count, 1)) * 0.42))
        for e in range(count):
            angle = 2 * math.pi * e / count - math.pi / 2
            ex, ey = cx + r * math.cos(angle), cyy + r * math.sin(angle)
            draw.ellipse([px(ex - dot / 2), px(ey - dot / 2), px(ex + dot / 2), px(ey + dot / 2)],
                         fill=accent)
    nucleus = diameter * 0.235 / 2
    draw.ellipse([px(cx - nucleus), px(cyy - nucleus), px(cx + nucleus), px(cyy + nucleus)], fill=accent)
    centered(draw, element["symbol"], font(BOLD, nucleus * 0.88), (255, 255, 255), cx, cyy - nucleus * 0.55)

    # fact rows
    fx = MARGIN + 16 + diameter + 12
    fw = WIDTH - MARGIN - 16 - fx
    facts = [("Atomic number", str(element["atomicNumber"]), REGULAR),
             ("Atomic mass", mass, REGULAR),
             ("Electron configuration", superscripted(element["electronConfiguration"]), MONO)]
    fy = cy
    for label_text, value, face in facts:
        rows = wrap(draw, value, font(face, 15), fw - 24)
        height = 20 + 19 * len(rows) + 8
        draw.rounded_rectangle([px(fx), px(fy), px(fx + fw), px(fy + height)], radius=px(14), fill=MUTED)
        draw.text((px(fx + 12), px(fy + 8)), label_text, font=font(REGULAR, 12), fill=SECONDARY)
        ry = fy + 24
        for line in rows:
            draw.text((px(fx + 12), px(ry)), line, font=font(face, 15), fill=PRIMARY)
            ry += 19
        fy += height + 8
    cy += diameter + 10

    cy = paragraph(draw, "A simplified shell model. Each ring stands for an energy level and how "
                         "many electrons it holds — electrons do not travel on fixed circular paths.",
                   font(REGULAR, 11), TERTIARY, MARGIN + 16, cy, body, 15)
    cy += 8
    draw.line([px(MARGIN + 16), px(cy), px(WIDTH - MARGIN - 16), px(cy)], fill=HAIRLINE, width=px(0.6))
    cy += 12

    draw.rounded_rectangle([px(MARGIN + 16), px(cy), px(MARGIN + 16 + 104), px(cy + 74)],
                           radius=px(14), fill=MUTED)
    draw.text((px(MARGIN + 132), px(cy + 6)), "Elemental form", font=font(REGULAR, 12), fill=SECONDARY)
    draw.text((px(MARGIN + 132), px(cy + 24)), element["elementalForm"], font=font(BOLD, 15), fill=PRIMARY)
    struct = {"diatomic": "Diatomic molecule", "polyatomicMolecule": "Polyatomic molecule",
              "metallicLattice": "Metallic lattice", "covalentNetwork": "Covalent network",
              "monatomicGas": "Monatomic gas", "atom": "Single atoms"}[element["structure"]]
    draw.text((px(MARGIN + 132), px(cy + 46)), struct, font=font(REGULAR, 11), fill=TERTIARY)
    y += card_height + 16

    # --- quick facts --------------------------------------------------------
    qf_height = 176
    card(draw, MARGIN, y, inner, qf_height)
    draw.text((px(MARGIN + 16), px(y + 16)), "Quick Facts", font=font(BOLD, 17), fill=PRIMARY)
    grid = [("Category", label), ("State at 25 °C", element["phase"].title()),
            ("Group", str(element["group"]) if element["group"] else "—"),
            ("Period", str(element["period"]))]
    cell_w = (body - 8) / 2
    for index, (label_text, value) in enumerate(grid):
        gx = MARGIN + 16 + (index % 2) * (cell_w + 8)
        gy = y + 48 + (index // 2) * 56
        draw.rounded_rectangle([px(gx), px(gy), px(gx + cell_w), px(gy + 48)], radius=px(14), fill=MUTED)
        draw.text((px(gx + 12), px(gy + 8)), label_text, font=font(REGULAR, 12), fill=SECONDARY)
        draw.text((px(gx + 12), px(gy + 24)), value, font=font(BOLD, 15), fill=PRIMARY)
    centered(draw, "More properties  ⌄", font(REGULAR, 15), (32, 102, 229), WIDTH / 2, y + 150)
    y += qf_height + 16

    # --- about --------------------------------------------------------------
    about_font = font(REGULAR, 16)
    lines = wrap(draw, element["about"], about_font, body)
    about_height = 52 + 22 * len(lines)
    card(draw, MARGIN, y, inner, about_height)
    draw.text((px(MARGIN + 16), px(y + 16)), f"About {element['name']}", font=font(BOLD, 17), fill=PRIMARY)
    paragraph(draw, element["about"], about_font, SECONDARY, MARGIN + 16, y + 44, body, 22)
    y += about_height + 16

    # --- uses ---------------------------------------------------------------
    uses_height = 164
    card(draw, MARGIN, y, inner, uses_height)
    draw.text((px(MARGIN + 16), px(y + 16)), "Common Uses", font=font(BOLD, 17), fill=PRIMARY)
    count = len(element["uses"])
    use_w = (body - 8 * (count - 1)) / count
    for index, use in enumerate(element["uses"]):
        ux = MARGIN + 16 + index * (use_w + 8)
        uy = y + 48
        draw.rounded_rectangle([px(ux), px(uy), px(ux + use_w), px(uy + 108)], radius=px(14),
                               fill=tuple(round(accent[i] * 0.08 + SURFACE[i] * 0.92) for i in range(3)))
        draw.ellipse([px(ux + use_w / 2 - 10), px(uy + 16), px(ux + use_w / 2 + 10), px(uy + 36)],
                     outline=accent, width=px(1.5))
        title_lines = wrap(draw, use["title"], font(BOLD, 13), use_w - 8)
        ty = uy + 48
        for line in title_lines:
            centered(draw, line, font(BOLD, 13), PRIMARY, ux + use_w / 2, ty)
            ty += 16
        for line in wrap(draw, use["detail"], font(REGULAR, 11), use_w - 8)[:3]:
            centered(draw, line, font(REGULAR, 11), SECONDARY, ux + use_w / 2, ty)
            ty += 13
    y += uses_height + 16

    # --- memory hook --------------------------------------------------------
    hook_font = font(REGULAR, 16)
    hook_lines = wrap(draw, element["memoryHook"], hook_font, body - 46)
    hook_height = 48 + 22 * len(hook_lines)
    card(draw, MARGIN, y, inner, hook_height)
    draw.ellipse([px(MARGIN + 16), px(y + 16), px(MARGIN + 50), px(y + 50)], fill=fill)
    draw.text((px(MARGIN + 28), px(y + 24)), "●", font=font(BOLD, 12), fill=accent)
    draw.text((px(MARGIN + 62), px(y + 16)), "Remember it", font=font(BOLD, 17), fill=PRIMARY)
    paragraph(draw, element["memoryHook"], hook_font, SECONDARY, MARGIN + 62, y + 42, body - 46, 22)
    y += hook_height + 16

    # --- familiarity --------------------------------------------------------
    card(draw, MARGIN, y, inner, 100)
    draw.text((px(MARGIN + 16), px(y + 16)), "Your familiarity", font=font(BOLD, 17), fill=PRIMARY)
    status = "Familiar"
    sf = font(BOLD, 12)
    draw.text((px(WIDTH - MARGIN - 16) - draw.textlength(status, font=sf), px(y + 20)),
              status, font=sf, fill=POSITIVE)
    bar_y = y + 52
    draw.rounded_rectangle([px(MARGIN + 16), px(bar_y), px(WIDTH - MARGIN - 16), px(bar_y + 6)],
                           radius=px(3), fill=MUTED)
    draw.rounded_rectangle([px(MARGIN + 16), px(bar_y), px(MARGIN + 16 + body * 0.66), px(bar_y + 6)],
                           radius=px(3), fill=POSITIVE)
    draw.text((px(MARGIN + 16), px(y + 68)), "6 correct · 2 to review",
              font=font(REGULAR, 12), fill=SECONDARY)
    y += 100 + 40

    return image.crop((0, 0, px(WIDTH), px(min(y, HEIGHT))))


def main() -> int:
    symbol = sys.argv[1] if len(sys.argv) > 1 else "Na"
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "Design", f"detail-{symbol}.png")

    with open(ELEMENTS, encoding="utf-8") as handle:
        elements = {e["symbol"]: e for e in json.load(handle)}
    if symbol not in elements:
        print(f"unknown symbol {symbol}", file=sys.stderr)
        return 2

    image = render(elements[symbol])
    os.makedirs(os.path.dirname(out), exist_ok=True)
    image.save(out, "PNG")
    print(f"wrote {os.path.relpath(out, ROOT)} ({image.width // SCALE}x{image.height // SCALE}pt)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
