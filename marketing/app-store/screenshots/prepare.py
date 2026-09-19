"""Prepare raw Elemora captures for the App Store templates.

    python3 screenshots/prepare.py

Two surgical edits per capture, and nothing else:

1. The iOS status bar is rebuilt. Each capture was taken at a different moment,
   so they carry different clocks (7:14 through 7:50), weak-signal bars and
   different battery levels, several of them yellow from Low Power Mode. The
   strip is first cleared by extending the app's own background upward, sampled
   per column from the first clean row below it, then the reconstructed status
   bar in assets/status-bar.png is composited on top.

   That strip is drawn by source/generator/statusbar.mjs at the exact positions
   measured off these captures, so the clock, bars, Wi-Fi and battery land
   within a pixel of where the device itself drew them. Only the state changes:
   the canonical 9:41, full signal, full Wi-Fi and a full battery. Because the
   background underneath is the app's own, the bar sits on the screen rather
   than on a pasted-in band, and the template's Dynamic Island covers the gap
   between the clock and the icons exactly as it does on a real phone.

2. The content clipped under the floating tab bar is removed. Elemora's tab bar
   floats over a scrolling list, so every capture ends with a sliver of a half
   cut row ("Halogen", "Bonding hints", "graphite leaves a mark"). The band below
   the bar is refilled from the row just under it and faded into the page
   background, which keeps the bar's own shadow and drops the debris.

Everything between those two bands is left byte for byte identical, and the
script asserts that before it writes. Run it again after re-capturing; it is
idempotent and never edits in place.
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "raw")
OUT = os.path.join(HERE, "selected")
STATUS_BAR = os.path.join(HERE, os.pardir, "assets", "status-bar.png")

# Measured from the captures themselves, all 1170 x 2532:
#   status bar glyphs are gone by y = 120; sample the app background at 132
#   the tab bar pill's lower edge sits at y = 2467
#   the earliest clipped row starts at y = 2474
STATUS_H = 132
PILL_BOTTOM = 2468
FADE = 58

# raw capture -> (output name, does it carry a floating tab bar)
PLAN = [
    ("IMG_2838.png", "01-periodic-table.png", True),
    ("IMG_2840.png", "02-main-oxygen.png", True),
    ("IMG_2845.png", "02-build-caffeine.png", True),
    ("IMG_2845.png", "03-build-caffeine.png", True),
    ("IMG_2849.png", "04-carbon.png", True),
    ("IMG_2851.png", "05-back-identify.png", False),
    ("IMG_2852.png", "05-front-study.png", True),
    ("IMG_2853.png", "06-progress.png", True),
]


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def clean(src, tabbar, statusbar):
    im = src.convert("RGB")
    W, H = im.size
    px = im.load()
    out = im.copy()
    op = out.load()

    # ---- 1a. status bar: extend the app's own background upward
    for x in range(W):
        fill = px[x, STATUS_H]
        for y in range(STATUS_H):
            op[x, y] = fill

    # ---- 1b. composite the reconstructed bar over that clean background
    if statusbar is not None:
        if statusbar.size != (W, STATUS_H):
            raise SystemExit(
                "status bar is %dx%d but the capture needs %dx%d"
                % (statusbar.size + (W, STATUS_H)))
        out.paste(statusbar, (0, 0), statusbar)

    # ---- 2. below the tab bar: refill and fade into the page background
    if tabbar:
        far = []
        for y in range(H - 40, H):
            for x in range(0, 40):
                far.append(px[x, y])
        bg = tuple(round(sum(c[i] for c in far) / len(far)) for i in range(3))
        for x in range(W):
            edge = px[x, PILL_BOTTOM]
            for y in range(PILL_BOTTOM, H):
                t = min(1.0, (y - PILL_BOTTOM) / FADE)
                op[x, y] = lerp(edge, bg, t)

    # ---- the app content itself must be untouched
    lo, hi = STATUS_H, (PILL_BOTTOM if tabbar else H)
    a = im.crop((0, lo, W, hi)).tobytes()
    b = out.crop((0, lo, W, hi)).tobytes()
    if a != b:
        raise SystemExit("prepare.py altered app content; refusing to write")
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    if not os.path.exists(STATUS_BAR):
        raise SystemExit(
            "assets/status-bar.png is missing; run "
            "`node source/generator/build.mjs --status-bar` first")
    bar = Image.open(STATUS_BAR).convert("RGBA")
    made = 0
    for raw, name, tabbar in PLAN:
        p = os.path.join(RAW, raw)
        if not os.path.exists(p):
            print(f"  missing {raw}, skipped")
            continue
        img = Image.open(p)
        clean(img, tabbar, bar).save(os.path.join(OUT, name))
        print(f"  {raw} -> selected/{name}   status bar rebuilt 0..{STATUS_H}" +
              (f", tab-bar debris cleared {PILL_BOTTOM}..{img.size[1]}" if tabbar else ""))
        made += 1
    print(f"{made} captures prepared into screenshots/selected/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
