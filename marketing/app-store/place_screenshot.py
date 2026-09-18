"""Drop real Elemora screenshots into the finished template frames.

    python3 place_screenshot.py 01 shots/home.png
    python3 place_screenshot.py hero shots/home.png          # slug works too
    python3 place_screenshot.py 03 shots/build.png out.png   # explicit destination
    python3 place_screenshot.py --all                        # every frame at once

`--all` picks each frame's capture up from screenshots/selected/, matching on the
frame id: 01-*.png, 02-*.png and so on. Frames with no capture are skipped and
listed, so a half-finished set still builds.

Each frame's placement lives beside its template in
source/template-NN-slug.geometry.json, so this works straight from a fresh clone
with no build step.

Your screenshot is scaled by a SINGLE uniform factor (cover fit, centre-cropped
by at most a pixel or two when the source aspect is not exactly 1320:2868) and
rotated by the frame's own angle, as one rigid group with the device. It is
never stretched, recoloured, cropped into, or redrawn.
"""
import glob
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
CW, CH = 1320, 2868


def frames():
    out = {}
    for p in sorted(glob.glob(os.path.join(HERE, "source", "template-*.geometry.json"))):
        g = json.load(open(p, encoding="utf-8"))
        out[g["id"]] = g
        out[g["slug"]] = g
    return out


def fit(shot, w, h):
    """Uniform cover-fit to w x h, centre-cropped. Never distorts."""
    sw, sh = shot.size
    k = max(w / sw, h / sh)
    nw, nh = max(1, round(sw * k)), max(1, round(sh * k))
    im = shot.resize((nw, nh), Image.LANCZOS)
    left, top = (nw - round(w)) // 2, (nh - round(h)) // 2
    return im.crop((left, top, left + round(w), top + round(h))), k, (nw - round(w), nh - round(h))


def place(g, shot_path, dst=None):
    bg = Image.open(os.path.join(HERE, g["background"])).convert("RGBA")
    ov = Image.open(os.path.join(HERE, g["overlay"])).convert("RGBA")

    shot = Image.open(shot_path).convert("RGBA")
    aspect = shot.size[0] / shot.size[1]
    if abs(aspect - CW / CH) > 0.004:
        print(f"      note: source aspect {aspect:.5f} differs from {CW}/{CH} = "
              f"{CW / CH:.5f}; it will be centre-cropped, never stretched")

    placed, k, crop = fit(shot, g["screenW"], g["screenH"])
    print(f"      {os.path.basename(shot_path)} {shot.size[0]}x{shot.size[1]} -> "
          f"uniform scale {k:.6f}, centre-crop {crop[0]}px wide / {crop[1]}px tall, "
          f"rotation {g['rot']}deg")

    layer = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    rot = g["rot"]
    if rot:
        r = placed.rotate(-rot, resample=Image.BICUBIC, expand=True)
        layer.alpha_composite(r, (round(g["deviceCX"] - r.width / 2),
                                  round(g["deviceCY"] - r.height / 2)))
    else:
        layer.alpha_composite(placed, (round(g["screenX"]), round(g["screenY"])))

    out = Image.alpha_composite(bg, layer)
    out = Image.alpha_composite(out, ov)

    dst = dst or os.path.join(HERE, g["output"])
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    out.convert("RGB").save(dst)          # App Store uploads carry no alpha
    print(f"      written -> {os.path.relpath(dst, HERE)}  ({out.size[0]}x{out.size[1]})")
    return dst


def main(argv):
    F = frames()
    if not F:
        raise SystemExit("no geometry files found; run source/generator/build.mjs first")

    if argv and argv[0] == "--all":
        todo, missing = [], []
        for fid in sorted({g["id"] for g in F.values()}):
            g = F[fid]
            hits = sorted(glob.glob(os.path.join(HERE, "screenshots", "selected", f"{fid}-*.png")))
            (todo.append((g, hits[0])) if hits else missing.append(f"{fid}-{g['slug']} ({g['label']})"))
        for g, shot in todo:
            print(f"  {g['id']}-{g['slug']}")
            place(g, shot)
        if missing:
            print("\n  still waiting on a real capture for:")
            for m in missing:
                print("    " + m)
        if not todo:
            print("  nothing placed - put captures in screenshots/selected/ named 01-*.png ...")
        return

    if len(argv) < 2:
        print(__doc__)
        return 1

    key, shot = argv[0], argv[1]
    if key not in F:
        raise SystemExit(f"unknown frame {key!r}; try one of "
                         f"{sorted({g['id'] for g in F.values()})}")
    dst = argv[2] if len(argv) > 2 and argv[2].lower().endswith(".png") else None
    g = F[key]
    print(f"  {g['id']}-{g['slug']}  ({g['label']})")
    place(g, shot, dst)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]) or 0)
