#!/usr/bin/env python3
"""Renders the Periodic Pro app icon.

Concept: a single periodic-table tile, with one abstract electron orbit
sweeping behind it. Original artwork, no text, no third-party marks, and
legible all the way down to a Spotlight-row glyph.

Outputs the three 1024x1024 variants iOS 18+ expects (light, dark, tinted)
into PeriodicPro/Assets.xcassets/AppIcon.appiconset/.

    python3 Tools/make_app_icon.py
"""
from __future__ import annotations

import os
from PIL import Image, ImageDraw, ImageFilter

SS = 4                      # supersampling factor
SIZE = 1024
CANVAS = SIZE * SS
OUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "PeriodicPro", "Assets.xcassets", "AppIcon.appiconset",
)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def diagonal_gradient(top_left, bottom_right):
    """A soft corner-to-corner wash drawn at full canvas resolution."""
    image = Image.new("RGB", (CANVAS, CANVAS), top_left)
    draw = ImageDraw.Draw(image)
    steps = 320
    band = int(CANVAS * 2 / steps) + 6
    for index in range(steps):
        t = index / (steps - 1)
        offset = int(t * CANVAS * 2)
        draw.line([(offset - CANVAS, 0), (offset, CANVAS)],
                  fill=lerp(top_left, bottom_right, t), width=band)
    return image


def orbit_layer(color, alpha, stroke, rx, ry, angle, center, electron=None):
    """One tilted elliptical ring — a single orbit, not an atom cluster.

    Optionally places two electrons at the ring's extremes, which is what makes
    the mark read as an atom rather than as a button.
    """
    ring = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    draw = ImageDraw.Draw(ring)
    draw.ellipse(
        [center[0] - rx, center[1] - ry, center[0] + rx, center[1] + ry],
        outline=color + (alpha,),
        width=stroke,
    )
    if electron is not None:
        er = int(CANVAS * 0.030)
        for sign in (-1, 1):
            cx = center[0] + sign * rx
            draw.ellipse([cx - er, center[1] - er, cx + er, center[1] + er],
                         fill=electron + (255,))
    return ring.rotate(angle, resample=Image.BICUBIC, center=center)


def render(bg_a, bg_b, tile_a, tile_b, orbit, orbit_alpha, nucleus, shadow, electron):
    base = diagonal_gradient(bg_a, bg_b).convert("RGBA")
    center = (CANVAS // 2, CANVAS // 2)

    # 1. The orbit sits behind the tile so only its ends read.
    base = Image.alpha_composite(
        base,
        orbit_layer(
            color=orbit, alpha=orbit_alpha,
            stroke=int(CANVAS * 0.020),
            rx=int(CANVAS * 0.395), ry=int(CANVAS * 0.150),
            angle=-22, center=center, electron=electron,
        ),
    )

    # 2. The element tile.
    tile_size = int(CANVAS * 0.505)
    inset = (CANVAS - tile_size) // 2
    box = [inset, inset, inset + tile_size, inset + tile_size]
    radius = int(tile_size * 0.265)

    if shadow is not None:
        shade = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
        ImageDraw.Draw(shade).rounded_rectangle(
            [box[0], box[1] + int(CANVAS * 0.018),
             box[2], box[3] + int(CANVAS * 0.018)],
            radius=radius, fill=shadow,
        )
        shade = shade.filter(ImageFilter.GaussianBlur(int(CANVAS * 0.022)))
        base = Image.alpha_composite(base, shade)

    mask = Image.new("L", (CANVAS, CANVAS), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    tile = diagonal_gradient(tile_a, tile_b).convert("RGBA")
    base.paste(tile, (0, 0), mask)

    # 3. The nucleus, centred in the tile.
    dot = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    dot_draw = ImageDraw.Draw(dot)
    r = int(CANVAS * 0.050)
    dot_draw.ellipse([center[0] - r, center[1] - r, center[0] + r, center[1] + r],
                     fill=nucleus + (255,))
    halo = int(CANVAS * 0.098)
    dot_draw.ellipse([center[0] - halo, center[1] - halo, center[0] + halo, center[1] + halo],
                     outline=nucleus + (70,), width=int(CANVAS * 0.0085))
    base = Image.alpha_composite(base, dot)

    return base.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)


VARIANTS = {
    # Light: the app's accent blue, with the tile in the app's off-white canvas.
    "AppIcon-1024.png": dict(
        bg_a=(66, 136, 250), bg_b=(22, 78, 204),
        tile_a=(255, 255, 255), tile_b=(232, 240, 253),
        orbit=(255, 255, 255), orbit_alpha=150,
        nucleus=(33, 96, 226),
        shadow=(10, 34, 90, 120),
        electron=(255, 255, 255),
    ),
    # Dark: a deeper field so the icon keeps weight on a dark home screen.
    "AppIcon-1024-Dark.png": dict(
        bg_a=(26, 46, 94), bg_b=(9, 16, 36),
        tile_a=(86, 150, 255), tile_b=(38, 98, 224),
        orbit=(150, 190, 255), orbit_alpha=130,
        nucleus=(255, 255, 255),
        shadow=(0, 0, 0, 150),
        electron=(186, 214, 255),
    ),
    # Tinted: grayscale only. iOS maps luminance onto the user's chosen tint.
    "AppIcon-1024-Tinted.png": dict(
        bg_a=(26, 26, 26), bg_b=(8, 8, 8),
        tile_a=(238, 238, 238), tile_b=(186, 186, 186),
        orbit=(150, 150, 150), orbit_alpha=200,
        nucleus=(20, 20, 20),
        shadow=None,
        electron=(230, 230, 230),
    ),
}


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for filename, kwargs in VARIANTS.items():
        image = render(**kwargs)
        path = os.path.join(OUT_DIR, filename)
        image.save(path, "PNG", optimize=True)
        print(f"wrote {path} ({image.size[0]}x{image.size[1]})")


if __name__ == "__main__":
    main()
