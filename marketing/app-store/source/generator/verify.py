"""Elemora App Store campaign, full QA sweep.

    python3 source/generator/verify.py

Everything is checked against the built artefacts or against reference data held
in THIS file, never against the generator's own constants, so a mistake in the
design system cannot quietly validate itself. The molecular formulas are
re-derived from the drawn skeletal graphs rather than read off their labels, and
the compositing pipeline is proved end to end by placing a marker image through
the real compositor and looking for leaks.
"""
import json
import os
import re
import sys
import math
import glob

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
CW, CH = 1320, 2868
EM_DASH = "\u2014"

sys.path.insert(0, ROOT)
import place_screenshot as PS                                    # noqa: E402

fails, warns, checks = [], [], [0]


def ok(cond, msg):
    checks[0] += 1
    if not cond:
        fails.append(msg)
    return cond


def warn(cond, msg):
    checks[0] += 1
    if not cond:
        warns.append(msg)


def r(*a):
    return os.path.join(ROOT, *a)


# ---------------------------------------------------------------- reference --
# Independent copy of the element facts. Atomic weights: IUPAC 2021 abridged.
REF = {
    "H":  (1,  "1.008",  [1]),          "He": (2,  "4.0026", [2]),
    "Li": (3,  "6.94",   [2, 1]),       "Be": (4,  "9.0122", [2, 2]),
    "B":  (5,  "10.81",  [2, 3]),       "C":  (6,  "12.011", [2, 4]),
    "N":  (7,  "14.007", [2, 5]),       "O":  (8,  "15.999", [2, 6]),
    "F":  (9,  "18.998", [2, 7]),       "Ne": (10, "20.180", [2, 8]),
    "Na": (11, "22.990", [2, 8, 1]),    "Mg": (12, "24.305", [2, 8, 2]),
    "Al": (13, "26.982", [2, 8, 3]),    "Si": (14, "28.085", [2, 8, 4]),
    "P":  (15, "30.974", [2, 8, 5]),    "S":  (16, "32.06",  [2, 8, 6]),
    "Cl": (17, "35.45",  [2, 8, 7]),    "Ar": (18, "39.95",  [2, 8, 8]),
    "K":  (19, "39.098", [2, 8, 8, 1]), "Ca": (20, "40.078", [2, 8, 8, 2]),
    "Fe": (26, "55.845", [2, 8, 14, 2]),"Cu": (29, "63.546", [2, 8, 18, 1]),
    "Au": (79, "196.97", [2, 8, 18, 32, 18, 1]),
}
VALENCE = {"C": 4, "N": 3, "O": 2, "S": 2, "H": 1}
HILL = ["C", "H", "N", "O", "S"]


# ------------------------------------------------------------ equation maths --
def parse_formula(f):
    m = re.match(r"^(\d*)(.*)$", f)
    coef = int(m.group(1)) if m.group(1) else 1
    atoms = {}
    for sym, cnt in re.findall(r"([A-Z][a-z]?)(\d*)", m.group(2)):
        if sym:
            atoms[sym] = atoms.get(sym, 0) + (int(cnt) if cnt else 1)
    return coef, atoms


def side_atoms(side):
    total = {}
    for term in side.split("+"):
        term = term.strip()
        if not term:
            continue
        coef, atoms = parse_formula(term)
        for s, c in atoms.items():
            total[s] = total.get(s, 0) + coef * c
    return total


def balanced(eq):
    parts = re.split(r"\u2192|\u21CC|->", eq)
    if len(parts) != 2:
        return False, "no reaction arrow"
    left, right = side_atoms(parts[0]), side_atoms(parts[1])
    return left == right, f"{left} vs {right}"


src = open(r("source", "generator", "chemistry.mjs"), encoding="utf-8").read()

print("== element data ==")
for sym, (z, mass, shells) in REF.items():
    m = re.search(
        r"^\s*%s:\s*\{\s*z:\s*(\d+),\s*name:\s*'([^']+)',\s*mass:\s*'([^']+)',"
        r"\s*group:\s*(\d+),\s*period:\s*(\d+),\s*cat:\s*'([^']*)',"
        r"\s*shells:\s*\[([0-9, ]+)\]" % re.escape(sym), src, re.M)
    if not ok(m, f"element {sym} missing from chemistry.mjs"):
        continue
    gz, _name, gmass, group, period, _cat, gsh = m.groups()
    ok(int(gz) == z, f"{sym}: atomic number {gz} should be {z}")
    ok(gmass == mass, f"{sym}: atomic weight {gmass} should be {mass}")
    got = [int(x) for x in gsh.replace(" ", "").split(",") if x]
    ok(got == shells, f"{sym}: shells {got} should be {shells}")
    ok(sum(got) == z, f"{sym}: shells sum to {sum(got)}, should equal Z={z}")
    ok(1 <= int(period) <= 7, f"{sym}: period {period} out of range")
    ok(1 <= int(group) <= 18, f"{sym}: group {group} out of range")
print(f"   {len(REF)} elements cross-checked against IUPAC 2021 reference")

print("== balanced equations ==")
eq_block = src[src.index("export const EQUATIONS"):]
for name, eq in re.findall(r"(\w+):\s*'([^']+)'", eq_block):
    eq = eq.replace("\\u2192", "\u2192").replace("\\u21CC", "\u21CC")
    good, detail = balanced(eq)
    ok(good, f"equation {name} is not balanced: {eq}  ({detail})")
    print(f"   {name:16s} {eq}   balanced")

# --------------------------------------------------- skeletal structure maths
print("== skeletal structures ==")
SK = json.load(open(r("source", "skeletal.json"), encoding="utf-8"))
ok(len(SK) >= 8, f"only {len(SK)} skeletal structures; the set needs a real library")

for key, S in SK.items():
    pts, bonds = S["pts"], S["bonds"]
    labels = {int(k): v for k, v in S["labels"].items()}

    # 1. every drawn bond must be exactly one bond length: rings regular, chains
    #    at a true 120 deg, no accidental stretching
    lens = [math.dist(pts[i], pts[j]) for i, j, *_ in bonds]
    ok(max(abs(L - 1.0) for L in lens) < 2e-3,
       f"{key}: bond lengths vary ({min(lens):.4f}..{max(lens):.4f}), rings not regular")

    # 2. re-derive the molecular formula from the graph itself
    order_sum = [0] * len(pts)
    for i, j, *rest in bonds:
        o = rest[0] if rest else 1
        order_sum[i] += o
        order_sum[j] += o
    counts = {}
    overvalent = []
    for idx in range(len(pts)):
        lab = labels.get(idx, "C")
        el = re.match(r"^([A-Z][a-z]?)", lab).group(1)
        v = VALENCE.get(el)
        if v is None:
            fails.append(f"{key}: no reference valence for {el}")
            continue
        if order_sum[idx] > v:
            overvalent.append(f"{el}{idx}={order_sum[idx]}")
        counts[el] = counts.get(el, 0) + 1
        counts["H"] = counts.get("H", 0) + max(0, v - order_sum[idx])
    ok(not overvalent, f"{key}: over-valent atoms {overvalent}")

    derived = "".join(f"{e}{counts[e] if counts[e] > 1 else ''}"
                      for e in HILL if counts.get(e))
    ok(derived == S["formula"],
       f"{key}: graph gives {derived}, but it is labelled {S['formula']}")
    print(f"   {S['name']:14s} {S['formula']:12s} derived {derived:12s} "
          f"{len(pts)} vertices, {len(bonds)} bonds")

# ---------------------------------- the 3D ball-and-stick language is retired
print("== decorative language ==")
ok("export function molecule(" not in src,
   "the 3D ball-and-stick renderer is back in chemistry.mjs")
ok("elAtomSpec" not in src and "RAMP" not in src,
   "3D atom sphere gradients are back in chemistry.mjs")
ok(not os.path.isdir(r("assets", "molecules")),
   "assets/molecules (3D ball-and-stick renders) still exists")
ok(os.path.isdir(r("assets", "skeletal")),
   "assets/skeletal is missing; skeletal art should be the decorative library")
sk_assets = glob.glob(r("assets", "skeletal", "*.svg"))
ok(len(sk_assets) >= 8, f"only {len(sk_assets)} skeletal assets exported")
print(f"   no 3D ball-and-stick renderer, {len(sk_assets)} skeletal assets present")

# ------------------------------------------------------------------- frames --
print("== frames ==")
frames = json.load(open(r("source", "frames.json"), encoding="utf-8"))
ok(len(frames) == 6, f"expected 6 frames, found {len(frames)}")
WANT = ["Learn Chemistry Visually", "Explore Every Element", "Build Real Molecules",
        "See More Than Symbols", "Study Smarter", "See Your Progress"]

for g, want in zip(frames, WANT):
    tag = f"{g['id']}-{g['slug']}"
    ok(" ".join(g["headline"]) == want,
       f"{tag}: headline is {' '.join(g['headline'])!r}, the agreed sequence says {want!r}")

    for path_key in ("background", "output"):
        p = r(g[path_key])
        if not ok(os.path.exists(p), f"{tag}: missing {g[path_key]}"):
            continue
        im = Image.open(p)
        ok(im.size == (CW, CH), f"{tag}: {g[path_key]} is {im.size}, must be {CW}x{CH}")

    bg = Image.open(r(g["background"]))
    ex = Image.open(r(g["output"]))
    ok(bg.mode == "RGB", f"{tag}: background must be flattened RGB, is {bg.mode}")
    ok(ex.mode == "RGB", f"{tag}: App Store export must have no alpha, is {ex.mode}")

    # the renderer used to stop painting ~88px short of the window height
    ok(bg.convert("RGB").getpixel((CW // 2, CH - 1)) != (255, 255, 255),
       f"{tag}: background bottom row is bare white, raster clipping regression")

    svg = open(r("source", f"template-{tag}.svg"), encoding="utf-8").read()
    ok("replace" in svg, f"{tag}: template lost its screenshot placeholder")

    # no em dash anywhere in the artwork, marketing copy first of all
    for line in g["headline"] + g["sub"]:
        ok(EM_DASH not in line, f"{tag}: em dash in marketing copy: {line!r}")
    body = re.sub(r"<!--.*?-->", "", svg, flags=re.S)
    rendered = " ".join(re.findall(r">([^<>]*)<", body))
    ok(EM_DASH not in rendered, f"{tag}: em dash in rendered SVG text")

    for line in g["headline"] + g["sub"]:
        esc = line.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        ok(esc in svg, f"{tag}: copy line not found in the SVG: {line!r}")

    # decoration stays at watermark strength
    for op in re.findall(
            r'<g id="(?:Skeletal|Tile|Bohr|Orbits|Lattice|Periodic)[^"]*"[^>]*opacity="([\d.]+)"',
            svg):
        ok(float(op) <= 0.11,
           f"{tag}: decoration opacity {op} is louder than a watermark")

    ok(g["copyBottom"] < min(d["bounds"]["minY"] for d in g["devices"]) - 40,
       f"{tag}: copy runs into the topmost device edge")

    for i, d in enumerate(g["devices"]):
        ratio = d["screenW"] / d["screenH"]
        ok(abs(ratio - CW / CH) < 1e-12,
           f"{tag}/{d['role']}: screen ratio {ratio!r} != {CW}/{CH}")
        # a square capture must stay inside the bezel, corners included; rigid
        # rotation makes this rotation-invariant, so prove it unrotated
        gap = (d["bezel"] + d["screenR"]) - math.sqrt(2) * d["screenR"]
        ok(gap > 0.5,
           f"{tag}/{d['role']}: square capture corner escapes the bezel ({gap:.2f}px)")

        ovp = r(d["overlay"])
        if not ok(os.path.exists(ovp), f"{tag}: missing {d['overlay']}"):
            continue
        ov = Image.open(ovp)
        ok(ov.mode == "RGBA", f"{tag}/{d['role']}: overlay must be RGBA, is {ov.mode}")
        ok(ov.size == (CW, CH), f"{tag}/{d['role']}: overlay is {ov.size}")
        a = ov.split()[3]
        # the bezel is genuinely opaque, sampled mid-bezel through the rotation
        ang = math.radians(d["rot"])
        ux = d["x"] + d["bezel"] / 2 - d["cx"]
        bx = d["cx"] + ux * math.cos(ang)
        by = d["cy"] + ux * math.sin(ang)
        if 0 <= round(bx) < CW and 0 <= round(by) < CH:
            ok(a.getpixel((round(bx), round(by))) > 200,
               f"{tag}/{d['role']}: overlay bezel is not opaque at the left edge")

    sizes = "  ".join(f"{d['role']}:{d['w']:.0f}x{d['h']:.0f}@{d['rot']:+g}"
                      for d in g["devices"])
    print(f"   {tag:20s} {len(g['devices'])} device(s)  {sizes}")

# ----------------------------------------- end to end: place a marker capture
print("== compositing (marker capture through the real compositor) ==")
marker = Image.new("RGB", (CW, CH), (255, 255, 255))
md = ImageDraw.Draw(marker)
md.rectangle([0, 0, CW - 1, CH - 1], outline=(255, 0, 170), width=14)
for (x, y) in [(0, 0), (CW - 240, 0), (0, CH - 240), (CW - 240, CH - 240)]:
    md.rectangle([x, y, x + 240, y + 240], fill=(255, 0, 170))
md.line([(CW // 2, 0), (CW // 2, CH)], fill=(20, 40, 80), width=8)
md.line([(0, CH // 2), (CW, CH // 2)], fill=(20, 40, 80), width=8)
tmp = os.path.join(ROOT, ".qa-marker.png")
marker.save(tmp)


def silhouettes(g, grow=1, pad=900):
    """Union of the device outlines. Drawn on a padded canvas so a device that
    starts outside the frame is not clipped away BEFORE its rotation carries it
    back into view, which would make the mask lie about where the device is."""
    m = Image.new("L", (CW, CH), 0)
    for d in g["devices"]:
        one = Image.new("L", (CW + 2 * pad, CH + 2 * pad), 0)
        dd = ImageDraw.Draw(one)
        dd.rounded_rectangle([pad + d["x"] - grow, pad + d["y"] - grow,
                              pad + d["x"] + d["w"] + grow, pad + d["y"] + d["h"] + grow],
                             radius=d["r"] + grow, fill=255)
        if d["rot"]:
            one = one.rotate(-d["rot"], resample=Image.BICUBIC,
                             center=(pad + d["cx"], pad + d["cy"]))
        m.paste(255, (0, 0), one.crop((pad, pad, pad + CW, pad + CH)))
    return m


for g in frames:
    tag = f"{g['id']}-{g['slug']}"
    out = os.path.join(ROOT, f".qa-{tag}.png")
    PS.place(g, [tmp] * len(g["devices"]), out, quiet=True)
    im = Image.open(out).convert("RGB")
    sil = silhouettes(g).load()
    px = im.load()
    leaks = 0
    for y in range(0, CH, 2):
        for x in range(0, CW, 2):
            rr, gg, bb = px[x, y]
            if rr > 215 and gg < 70 and 120 < bb < 215 and sil[x, y] < 128:
                leaks += 1
    ok(leaks == 0, f"{tag}: {leaks} capture pixels leaked outside the device silhouette")

    # and the captures really did land (guards against a silently empty stack)
    seen = 0
    for d in g["devices"]:
        cx, cy = round(d["screenCX"]), round(d["screenCY"])
        if 0 <= cx < CW and 0 <= cy < CH and px[cx, cy] != (255, 255, 255):
            seen += 1
    ok(seen >= 1, f"{tag}: no capture is visible after compositing")
    print(f"   {tag:20s} {len(g['devices'])} capture(s) placed, {leaks} leaks")
    os.remove(out)
os.remove(tmp)

# ------------------------------------------------------------ set consistency
print("== set consistency ==")
tops = {round(g["copyTop"]) for g in frames}
ok(tops <= {236, 296}, f"headline cap-tops drift across the set: {sorted(tops)}")
centres = {round((g["copyTop"] + g["copyBottom"]) / 2) for g in frames}
ok(max(centres) - min(centres) < 14,
   f"copy blocks are not optically aligned: {sorted(centres)}")

rots = [d["rot"] for g in frames for d in g["devices"]]
ok(all(abs(x) <= 5 for x in rots), f"a device is tilted too far: {rots}")

# Screenshot 2's primary device must be dead straight: the real periodic table
# carries the visual complexity, the frame around it stays calm.
f02 = next(g for g in frames if g["id"] == "02")
main02 = next(d for d in f02["devices"] if d["role"] == "main")
ok(main02["rot"] == 0, f"02: the periodic table device is rotated {main02['rot']} deg, must be 0")
ok(main02["bounds"]["minX"] >= -2 and main02["bounds"]["maxX"] <= CW + 2,
   "02: the periodic table device must be fully visible")

# Screenshot 6 closes the set with a perfectly vertical device, pushed right,
# cropped on the right edge alone.
f06 = next(g for g in frames if g["id"] == "06")
d06 = f06["devices"][0]
ok(d06["rot"] == 0, f"06: the progress device is rotated {d06['rot']} deg, must be 0")
off_r = d06["bounds"]["maxX"] - CW
frac = off_r / d06["w"]
ok(0.08 <= frac <= 0.15,
   f"06: {100*frac:.1f}% of the device runs off the right edge, wanted 8 to 15%")
ok(d06["bounds"]["minX"] > 0, "06: the device's left edge must stay on the canvas")
ok(d06["bounds"]["minY"] > 0 and d06["bounds"]["maxY"] <= CH + 2,
   "06: only the RIGHT side should leave the canvas")
print(f"   06 progress: vertical, {100*frac:.1f}% off the right edge, "
      f"left margin {d06['bounds']['minX']:.0f}px")

# Only a device explicitly marked to bleed may leave the canvas. Everything
# else has to read as a complete phone.
for g in frames:
    for d in g["devices"]:
        b = d["bounds"]
        inside = (b["minX"] >= -2 and b["maxX"] <= CW + 2
                  and b["minY"] >= -2 and b["maxY"] <= CH + 2)
        if d.get("bleed"):
            ok(not inside, f"{g['id']}/{d['role']}: marked bleed but sits wholly on canvas")
        else:
            ok(inside,
               f"{g['id']}/{d['role']}: device is cut by the canvas "
               f"(x {b['minX']:.0f}..{b['maxX']:.0f}, y {b['minY']:.0f}..{b['maxY']:.0f}); "
               f"only a device marked bleed may do that")

# Slide 3 is one device and one device only: the continuation is the idea.
f03 = next(g for g in frames if g["id"] == "03")
ok(len(f03["devices"]) == 1,
   f"03 carries {len(f03['devices'])} devices; the Build phone should stand alone")

# The 2 + 3 master composition. Both slides derive the Build device from one
# 2640 x 2868 master, so the slice at x = 1320 must be exact: identical screen
# width, rotation and y, and an x that differs by exactly one panel.
b2 = next((d for d in f02["devices"] if d["role"] == "build"), None)
b3 = next((d for d in f03["devices"] if d["role"] == "build"), None)
if ok(b2 and b3, "the Build device is missing from frame 02 or 03"):
    ok(abs(b2["screenW"] - b3["screenW"]) < 1e-9,
       f"build screen widths differ: {b2['screenW']} vs {b3['screenW']}")
    ok(b2["rot"] == b3["rot"], f"build rotations differ: {b2['rot']} vs {b3['rot']}")
    ok(abs(b2["y"] - b3["y"]) < 1e-9, f"build y differs: {b2['y']} vs {b3['y']}")
    ok(abs((b2["x"] - b3["x"]) - CW) < 1e-9,
       f"build x differs by {b2['x'] - b3['x']:.4f}, must be exactly {CW} for the slice")
    # most of it lives on slide 3, only a corner reaches back into slide 2
    on2 = CW - b2["bounds"]["minX"]
    total = b2["bounds"]["maxX"] - b2["bounds"]["minX"]
    share = on2 / total
    ok(0.07 <= share <= 0.16,
       f"the Build device puts {100*share:.1f}% of itself on slide 2, wanted 8 to 15%")
    ok(b3["bounds"]["maxX"] <= CW + 2, "the Build device should not also leave slide 3 at the right")
    # its top left corner clears the seam, so what crosses is a lower corner
    a = math.radians(b2["rot"])
    tl_x = b2["cx"] + (-b2["w"] / 2) * math.cos(a) - (-b2["h"] / 2) * math.sin(a)
    ok(tl_x >= CW,
       f"the Build device's top left corner is at x {tl_x:.0f}, it should clear the seam "
       f"at {CW} so only a LOWER corner reaches slide 2")
    # and almost none of the Build UI is split by the seam. Measure the real
    # clipped area of the rotated screen, not the unrotated left edge.
    ra = math.radians(b2["rot"])
    hw, hh = b2["screenW"] / 2, b2["screenH"] / 2
    quad = [(b2["screenCX"] + px * math.cos(ra) - py * math.sin(ra),
             b2["screenCY"] + px * math.sin(ra) + py * math.cos(ra))
            for px, py in ((-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh))]

    def clip_left(poly, X):
        out = []
        for i in range(len(poly)):
            c, nx = poly[i], poly[(i + 1) % len(poly)]
            ci, ni = c[0] <= X, nx[0] <= X
            if ci:
                out.append(c)
            if ci != ni:
                k = (X - c[0]) / (nx[0] - c[0])
                out.append((X, c[1] + k * (nx[1] - c[1])))
        return out

    def area(poly):
        return abs(sum(poly[i][0] * poly[(i + 1) % len(poly)][1]
                       - poly[(i + 1) % len(poly)][0] * poly[i][1]
                       for i in range(len(poly)))) / 2 if len(poly) > 2 else 0.0

    split = area(clip_left(quad, CW)) / (b2["screenW"] * b2["screenH"])
    ok(split < 0.08,
       f"{100*split:.1f}% of the Build screen area falls on slide 2; the seam should "
       f"cross device body, not app UI")
    # the bottom of the device must be on canvas, so slide 2 shows a real corner
    ok(b2["bounds"]["maxY"] <= CH,
       "the Build device runs off the bottom; its bottom corner should be visible")
    # the two devices on slide 2 must not collide
    ok(b2["bounds"]["minX"] > main02["bounds"]["maxX"],
       "02: the Build sliver overlaps the periodic table device")
    print(f"   02 + 03 master: one device, slice exact at x={CW}, "
          f"{100*share:.1f}% on slide 2, {100*split:.1f}% of screen area split, "
          f"top-left corner clears by {tl_x - CW:.0f}px, bottom on canvas")

# Background hierarchy: one clear anchor per frame, a couple of secondaries,
# the rest ambient, and never more than a handful of marks in total.
for g in frames:
    inv = g.get("decoration", [])
    tag = f"{g['id']}-{g['slug']}"
    ok(inv, f"{tag}: no decoration inventory recorded")
    if not inv:
        continue
    ops = [d["opacity"] for d in inv]
    anchor = max(ops)
    ok(0.07 <= anchor <= 0.105,
       f"{tag}: anchor motif is at {anchor}, should sit between 0.07 and 0.10")
    ok(sum(1 for o in ops if o >= 0.07) == 1,
       f"{tag}: {sum(1 for o in ops if o >= 0.07)} motifs at anchor strength, want exactly 1")
    ok(max([o for o in ops if o < 0.07] or [0]) <= 0.06,
       f"{tag}: a secondary mark is louder than 0.06")
    ok(min(ops) <= 0.04,
       f"{tag}: nothing is ambient; the faintest mark is {min(ops)}")
    ok(len(inv) <= 5, f"{tag}: {len(inv)} decorative marks, too busy")
    detail = ", ".join("{} {:g}".format(d["kind"], d["opacity"]) for d in inv)
    print(f"   {tag:20s} anchor {anchor:.3f} ({inv[0]['kind']}), {len(inv)} marks: {detail}")

# the whole point of the revision: six compositions, not one repeated six times
sig = set()
for g in frames:
    d0 = max(g["devices"], key=lambda d: d["w"])
    sig.add((len(g["devices"]),
             round(d0["w"] / 60),
             round(d0["bounds"]["minX"] / 220),
             round(d0["rot"])))
ok(len(sig) >= 5,
   f"only {len(sig)} distinct compositions across {len(frames)} frames; too repetitive")
# A ratio, not an absolute pixel spread: what matters is that the biggest device
# is visibly bigger than the smallest, whatever the set's absolute sizes.
widths = sorted({round(d["w"]) for g in frames for d in g["devices"]})
ok(max(widths) / min(widths) >= 1.25,
   f"device scales barely vary: {widths} "
   f"(largest is only {100*max(widths)/min(widths)-100:.0f}% wider than smallest)")
multi = [g["id"] for g in frames if len(g["devices"]) > 1]
ok(len(multi) == 2, f"expected two multi-device frames, got {multi}")
# the product has to stay the hero: every main device big enough to inspect
for g in frames:
    biggest = max(d["w"] for d in g["devices"])
    ok(biggest >= 0.63 * CW,
       f"{g['id']}: largest device is only {100 * biggest / CW:.0f}% of canvas width")
print(f"   {len(sig)} distinct compositions, device widths {widths}, "
      f"multi-device frames {multi}")

for f in sorted(glob.glob(r("assets", "**", "*.svg"), recursive=True)):
    head = open(f, encoding="utf-8").read(200)
    ok(head.startswith("<?xml"), f"asset {os.path.basename(f)} is not a well-formed SVG")
print(f"   {len(glob.glob(r('assets', '**', '*.svg'), recursive=True))} decoration assets present")

# ----------------------------------------------------------------- report ----
print()
for w in warns:
    print("WARN  " + w)
for f in fails:
    print("FAIL  " + f)
print(f"\n{checks[0]} checks, {len(fails)} failures, {len(warns)} warnings")
sys.exit(1 if fails else 0)
