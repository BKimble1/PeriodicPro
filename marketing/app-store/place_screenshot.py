"""Drop real Elemora screenshots into the finished template frames.

    python3 place_screenshot.py 01 shots/home.png
    python3 place_screenshot.py hero shots/home.png              # slug works too
    python3 place_screenshot.py 03 shots/compound.png shots/build.png
    python3 place_screenshot.py 03 --front shots/build.png --back shots/compound.png
    python3 place_screenshot.py 06 shots/progress.png out.png    # explicit destination
    python3 place_screenshot.py --all                            # every frame at once

Frames 03 and 05 carry two devices. Positional captures are taken in LAYER
order, back first, exactly as the frame's placement.txt lists them; the --role
flags remove the ambiguity if you would rather be explicit.

`--all` picks captures up from screenshots/selected/, matching on frame id and,
for two-device frames, on the words "front" and "back" in the filename:

    01-home.png   03-back-compound.png   03-front-build.png

Frames with no capture are skipped and listed, so a half-finished set still
builds.

Each frame's placement lives beside its template in
source/template-NN-slug.geometry.json, so this works straight from a fresh clone
with no build step.

Your screenshot is scaled by a SINGLE uniform factor (cover fit, centre-cropped
by at most a pixel or two when the source aspect is not exactly 1320:2868) and
rotated by its device's own angle, as one rigid group with that device. It is
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
    for path in sorted(glob.glob(os.path.join(HERE, "source", "template-*.geometry.json"))):
        g = json.load(open(path, encoding="utf-8"))
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


def shot_layer(dev, shot_path, quiet=False):
    """One capture, sized and rotated to sit exactly in `dev`'s screen opening."""
    shot = Image.open(shot_path).convert("RGBA")
    aspect = shot.size[0] / shot.size[1]
    if not quiet and abs(aspect - CW / CH) > 0.004:
        print(f"      note: source aspect {aspect:.5f} differs from {CW}/{CH} = "
              f"{CW / CH:.5f}; it will be centre-cropped, never stretched")

    placed, k, crop = fit(shot, dev["screenW"], dev["screenH"])
    if not quiet:
        print(f"      [{dev['role']:>5}] {os.path.basename(shot_path)} "
              f"{shot.size[0]}x{shot.size[1]} -> uniform scale {k:.6f}, "
              f"centre-crop {crop[0]}px wide / {crop[1]}px tall, rotation {dev['rot']}deg")

    layer = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    rot = dev["rot"]
    if rot:
        r = placed.rotate(-rot, resample=Image.BICUBIC, expand=True)
        layer.alpha_composite(r, (round(dev["cx"] - r.width / 2),
                                  round(dev["cy"] - r.height / 2)))
    else:
        layer.alpha_composite(placed, (round(dev["screenX"]), round(dev["screenY"])))
    return layer


def place(g, shots, dst=None, quiet=False):
    """Replay the frame's layer stack: background, then for every device back to
    front, its capture followed by its chrome overlay."""
    devs = g["devices"]
    if len(shots) != len(devs):
        raise SystemExit(f"frame {g['id']} needs {len(devs)} capture(s) "
                         f"({', '.join(d['role'] for d in devs)}), got {len(shots)}")

    out = Image.open(os.path.join(HERE, g["background"])).convert("RGBA")
    for dev, shot in zip(devs, shots):
        out.alpha_composite(shot_layer(dev, shot, quiet))
        ov = Image.open(os.path.join(HERE, dev["overlay"])).convert("RGBA")
        out = Image.alpha_composite(out, ov)

    dst = dst or os.path.join(HERE, g["output"])
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    out.convert("RGB").save(dst)          # App Store uploads carry no alpha
    if not quiet:
        print(f"      written -> {os.path.relpath(dst, HERE)}  ({out.size[0]}x{out.size[1]})")
    return dst


def find_selected(g):
    """Captures for one frame from screenshots/selected/, or None if incomplete."""
    devs = g["devices"]
    pool = sorted(glob.glob(os.path.join(HERE, "screenshots", "selected", f"{g['id']}-*.png")))
    if len(devs) == 1:
        return pool[:1] or None
    picked = []
    for d in devs:
        hit = [f for f in pool if d["role"] in os.path.basename(f).lower()]
        if not hit:
            return None
        picked.append(hit[0])
    return picked


def main(argv):
    F = frames()
    if not F:
        raise SystemExit("no geometry files found; run source/generator/build.mjs first")
    ids = sorted({g["id"] for g in F.values()})

    if argv and argv[0] == "--all":
        done, missing = 0, []
        for fid in ids:
            g = F[fid]
            shots = find_selected(g)
            if shots:
                print(f"  {g['id']}-{g['slug']}")
                place(g, shots)
                done += 1
            else:
                missing.append(f"{fid}-{g['slug']}: " +
                               ", ".join(f"{d['role']} ({d['label']})" for d in g["devices"]))
        if missing:
            print("\n  still waiting on a real capture for:")
            for m in missing:
                print("    " + m)
        if not done:
            print("  nothing placed. Put captures in screenshots/selected/ named 01-*.png, "
                  "and 03-front-*.png / 03-back-*.png for the two-device frames.")
        return 0

    if len(argv) < 2:
        print(__doc__)
        return 1

    key, rest = argv[0], list(argv[1:])
    if key not in F:
        raise SystemExit(f"unknown frame {key!r}; try one of {ids}")
    g = F[key]
    roles = [d["role"] for d in g["devices"]]

    dst = None
    if rest and rest[-1].lower().endswith(".png") and not os.path.exists(rest[-1]) \
            and len(rest) > len(roles):
        dst = rest.pop()

    named, positional = {}, []
    i = 0
    while i < len(rest):
        a = rest[i]
        if a.startswith("--") and a[2:] in roles:
            named[a[2:]] = rest[i + 1]
            i += 2
        else:
            positional.append(a)
            i += 1

    if named:
        shots = [named.get(r) for r in roles]
        if any(s is None for s in shots):
            raise SystemExit(f"frame {g['id']} also needs " +
                             ", ".join(f"--{r}" for r in roles if r not in named))
    else:
        shots = positional

    print(f"  {g['id']}-{g['slug']}  ({', '.join(d['label'] for d in g['devices'])})")
    place(g, shots, dst)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]) or 0)
