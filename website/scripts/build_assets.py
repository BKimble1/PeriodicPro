#!/usr/bin/env python3
"""
Regenerate everything under website/site/assets/img/ from the approved
marketing artwork that sits, untouched, at the repository root.

    pip install Pillow
    python3 website/scripts/build_assets.py

The originals are never written to. Nothing inside the app's UI is retouched:
each screenshot is resized and re-encoded, and that is all. The device status
bars are left exactly as captured, so the clock differs slightly from shot to
shot -- those are genuine captures from one evening's session, and unifying
them would mean painting pixels the app never drew.
"""

import io
import os
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:  # pragma: no cover - guidance only
    sys.exit("Pillow is required:  pip install Pillow")

ROOT = Path(__file__).resolve().parents[2]      # repository root
WEB = ROOT / "website"
OUT = WEB / "site" / "assets" / "img"
FONT = WEB / "src-assets" / "fonts" / "Inter-SemiBold.ttf"

# The approved app icon, as delivered.
ICON_SRC = ROOT / "ChatGPT Image Sep 15, 2026, 09_40_49 PM.png"

# The approved screenshots, as delivered, mapped to the names the site uses.
# Keep this table in step with the originals -- it is the only place the
# camera-roll filenames appear.
SCREENS = {
    "table":    ("IMG_2838.png", "The Elemora periodic table screen: a search field, "
                                 "category filters, and all 118 elements laid out in "
                                 "their real periodic positions."),
    "oxygen":   ("IMG_2840.png", "Elemora's element page for oxygen, showing a shell "
                                 "diagram, atomic number, atomic mass and electron "
                                 "configuration."),
    "build":    ("IMG_2845.png", "Elemora's Build tab showing caffeine: the formula "
                                 "C8H10N4O2, its molar mass, and a skeletal structure "
                                 "diagram."),
    "carbon":   ("IMG_2849.png", "Elemora's element page for carbon, with quick facts, "
                                 "an explanation of its bonding, and common uses."),
    "identify": ("IMG_2851.png", "An Elemora identification drill asking which element "
                                 "has atomic number 45, with the answer revealed as "
                                 "rhodium."),
    "study":    ("IMG_2852.png", "Elemora's Study tab with a day streak, a mastery "
                                 "percentage, a daily challenge and flashcards."),
    "progress": ("IMG_2853.png", "Elemora's Progress tab showing 13 of 118 elements "
                                 "mastered, a rank, and activity counts."),
}

# Brand palette, sampled from the approved icon and the app's own UI.
TEAL = (0x1B, 0x80, 0x8C)
AMBER = (0xD5, 0xA8, 0x55)
CANVAS = (0xF7, 0xF6, 0xF0)
INK = (0x16, 0x23, 0x27)
MUTED = (0x55, 0x6A, 0x6F)

OUT.mkdir(parents=True, exist_ok=True)


def log(path: Path) -> None:
    print(f"  {path.relative_to(WEB)}  ({path.stat().st_size // 1024} KB)")


def rounded_mask(size: int, radius_ratio: float = 0.2237) -> Image.Image:
    """An iOS-style rounded-square alpha mask, supersampled for clean edges."""
    ss = 4
    m = Image.new("L", (size * ss, size * ss), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        (0, 0, size * ss - 1, size * ss - 1),
        radius=int(size * ss * radius_ratio),
        fill=255,
    )
    return m.resize((size, size), Image.LANCZOS)


# ------------------------------------------------------------------ icons --

def build_icons() -> None:
    if not ICON_SRC.exists():
        sys.exit(f"missing app icon: {ICON_SRC}")
    src = Image.open(ICON_SRC).convert("RGB")

    # The delivered icon is a flat mark carrying fine rendering grain, which
    # costs far more in PNG than it shows on screen. A 64-colour palette is
    # visually identical here and roughly 25x smaller.
    def palettize(img: Image.Image) -> Image.Image:
        if img.mode == "RGBA":
            return img.quantize(colors=64, method=Image.FASTOCTREE, dither=Image.NONE)
        return img.quantize(colors=64, method=Image.MEDIANCUT, dither=Image.NONE)

    # Square, un-rounded: Apple applies its own mask to apple-touch-icon.
    palettize(src.resize((180, 180), Image.LANCZOS)).save(
        OUT / "apple-touch-icon.png", optimize=True
    )
    log(OUT / "apple-touch-icon.png")

    # Rounded, for use on the page where it stands in for the app icon.
    for px in (512, 256, 128, 64):
        img = src.resize((px, px), Image.LANCZOS).convert("RGBA")
        img.putalpha(rounded_mask(px))
        palettize(img).save(OUT / f"elemora-icon-{px}.png", optimize=True)
        log(OUT / f"elemora-icon-{px}.png")

    # Favicons. The full mark loses its shape below ~48px, so the small sizes
    # use a cropped detail of the tile cluster instead of the whole icon.
    w, h = src.size
    detail = src.crop((int(w * 0.20), int(h * 0.26), int(w * 0.82), int(h * 0.76)))
    dw, dh = detail.size
    side = max(dw, dh)
    tile = Image.new("RGB", (side, side), CANVAS)
    tile.paste(detail, ((side - dw) // 2, (side - dh) // 2))

    palettize(tile.resize((32, 32), Image.LANCZOS)).save(
        OUT / "favicon-32.png", optimize=True
    )
    log(OUT / "favicon-32.png")

    ico = WEB / "site" / "favicon.ico"
    tile.resize((64, 64), Image.LANCZOS).save(
        ico, sizes=[(16, 16), (32, 32), (48, 48)]
    )
    log(ico)


# ------------------------------------------------------------ screenshots --

def build_screens() -> None:
    for name, (filename, _alt) in SCREENS.items():
        src_path = ROOT / filename
        if not src_path.exists():
            sys.exit(f"missing approved screenshot: {src_path}")
        # 16-bit PNGs come off the device; normalise to 8-bit sRGB.
        img = Image.open(src_path).convert("RGB")

        for width in (440, 880):
            height = round(img.height * width / img.width)
            small = img.resize((width, height), Image.LANCZOS)
            p = OUT / f"shot-{name}-{width}.webp"
            small.save(p, "WEBP", quality=82, method=6)
            log(p)

        # One JPEG fallback per shot, at the larger width.
        height = round(img.height * 880 / img.width)
        p = OUT / f"shot-{name}-880.jpg"
        img.resize((880, height), Image.LANCZOS).save(
            p, "JPEG", quality=86, optimize=True, progressive=True
        )
        log(p)


# --------------------------------------------------------------- og card --

def build_og() -> None:
    """The 1200x630 social card: the app icon, the name, and one real screen."""
    W, H = 1200, 630
    card = Image.new("RGB", (W, H), CANVAS)
    d = ImageDraw.Draw(card)

    # A restrained periodic-tile motif bleeding off the top-right corner.
    cell, gap = 46, 10
    for row in range(4):
        for col in range(6):
            x = W - 330 + col * (cell + gap)
            y = -20 + row * (cell + gap)
            on = (row + col) % 3 != 0
            if not on:
                continue
            colour = AMBER if (row, col) == (1, 4) else TEAL
            fade = 0.10 + 0.05 * row
            blend = tuple(
                round(c * fade + b * (1 - fade)) for c, b in zip(colour, CANVAS)
            )
            d.rounded_rectangle((x, y, x + cell, y + cell), radius=11, fill=blend)

    if FONT.exists():
        f_title = ImageFont.truetype(str(FONT), 88)
        f_sub = ImageFont.truetype(str(FONT), 34)
        f_pub = ImageFont.truetype(str(FONT), 25)
    else:  # pragma: no cover
        f_title = f_sub = f_pub = ImageFont.load_default()

    # The icon's own field is the same warm off-white as this card, so without
    # a hairline it reads as a floating mark rather than an app icon.
    icon = Image.open(ICON_SRC).convert("RGB").resize((132, 132), Image.LANCZOS)
    icon = icon.convert("RGBA")
    icon.putalpha(rounded_mask(132))
    ring = Image.new("RGBA", (132, 132), (0, 0, 0, 0))
    ImageDraw.Draw(ring).rounded_rectangle(
        (0, 0, 131, 131), radius=int(132 * 0.2237),
        outline=(0x1B, 0x80, 0x8C, 46), width=2,
    )
    icon.alpha_composite(ring)
    card.paste(icon, (84, 92), icon)

    d.text((84, 264), "Elemora", font=f_title, fill=INK)
    d.text((84, 378), "Understand the elements,", font=f_sub, fill=MUTED)
    d.text((84, 424), "not just their symbols.", font=f_sub, fill=MUTED)
    d.text((84, 502), "Idlery Services LLC", font=f_pub, fill=TEAL)

    # A real screen, cropped to its top, standing on the right.
    shot = Image.open(ROOT / SCREENS["table"][0]).convert("RGB")
    sw = 300
    sh = round(shot.height * sw / shot.width)
    shot = shot.resize((sw, sh), Image.LANCZOS).crop((0, 0, sw, 470))
    framed = Image.new("RGBA", (sw, 470), (255, 255, 255, 0))
    framed.paste(shot, (0, 0))
    mask = Image.new("L", (sw, 470), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw - 1, 469), radius=34, fill=255)
    framed.putalpha(mask)
    card.paste(framed, (784, 140), framed)

    p = OUT / "og-elemora.png"
    card.save(p, optimize=True)
    log(p)


def build_quiz_card() -> None:
    """The 1200x630 card a link-preview service gets for /quiz/<payload>.

    The site is static and the quiz lives inside the URL, so this card is the
    same for every shared quiz: branded, and honest about being generic. Inside
    iOS the app attaches its own preview carrying the quiz's real title, which
    is what Messages and Mail actually show.
    """
    W, H = 1200, 630
    card = Image.new("RGB", (W, H), CANVAS)
    d = ImageDraw.Draw(card)

    # The same tile motif as the main social card, dropped to the bottom-right
    # so the two cards read as a set rather than as a duplicate. It stays well
    # clear of the type: nothing here is allowed to sit behind a word.
    cell, gap = 46, 10
    for row in range(4):
        for col in range(6):
            x = W - 252 + col * (cell + gap)
            y = H - 242 + row * (cell + gap)
            if (row + col) % 3 == 0:
                continue
            colour = AMBER if (row, col) == (1, 3) else TEAL
            fade = 0.10 + 0.05 * (3 - row)
            blend = tuple(
                round(c * fade + b * (1 - fade)) for c, b in zip(colour, CANVAS)
            )
            d.rounded_rectangle((x, y, x + cell, y + cell), radius=11, fill=blend)

    if FONT.exists():
        f_title = ImageFont.truetype(str(FONT), 80)
        f_sub = ImageFont.truetype(str(FONT), 34)
        f_chip = ImageFont.truetype(str(FONT), 27)
        f_pub = ImageFont.truetype(str(FONT), 25)
    else:  # pragma: no cover
        f_title = f_sub = f_chip = f_pub = ImageFont.load_default()

    icon = Image.open(ICON_SRC).convert("RGB").resize((132, 132), Image.LANCZOS)
    icon = icon.convert("RGBA")
    icon.putalpha(rounded_mask(132))
    ring = Image.new("RGBA", (132, 132), (0, 0, 0, 0))
    ImageDraw.Draw(ring).rounded_rectangle(
        (0, 0, 131, 131), radius=int(132 * 0.2237),
        outline=(0x1B, 0x80, 0x8C, 46), width=2,
    )
    icon.alpha_composite(ring)
    card.paste(icon, (84, 92), icon)

    # The chip, beside the icon, so the card says what it is at thumbnail size.
    label = "ELEMORA QUIZ"
    box = d.textbbox((0, 0), label, font=f_chip)
    pad_x, pad_y = 24, 13
    chip_w = box[2] - box[0] + pad_x * 2
    chip_h = box[3] - box[1] + pad_y * 2
    chip_x, chip_y = 248, 92 + (132 - chip_h) // 2
    d.rounded_rectangle((chip_x, chip_y, chip_x + chip_w, chip_y + chip_h),
                        radius=chip_h / 2, fill=TEAL)
    d.text((chip_x + pad_x - box[0], chip_y + pad_y - box[1]), label,
           font=f_chip, fill=(255, 255, 255))

    d.text((84, 272), "A shared quiz", font=f_title, fill=INK)
    d.text((84, 388), "Someone shared an Elemora quiz with you.", font=f_sub, fill=MUTED)
    d.text((84, 434), "Open it in Elemora to save and play it.", font=f_sub, fill=MUTED)
    d.text((84, 512), "Idlery Services LLC", font=f_pub, fill=TEAL)

    p = OUT / "og-quiz.png"
    card.save(p, optimize=True)
    log(p)


if __name__ == "__main__":
    print("icons")
    build_icons()
    print("screenshots")
    build_screens()
    print("social card")
    build_og()
    print("shared-quiz card")
    build_quiz_card()
    print("\ndone")
