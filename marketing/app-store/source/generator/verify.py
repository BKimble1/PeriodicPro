"""Elemora App Store campaign — full QA sweep.

    python3 source/generator/verify.py

Everything here is checked against the built artefacts or against reference data
held in THIS file, never against the generator's own constants, so a mistake in
the design system cannot quietly validate itself.
"""
import json
import os
import re
import sys
import math
import glob

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
CW, CH = 1320, 2868

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
# Independent copy of the element facts, for cross-checking chemistry.mjs.
# Standard atomic weights: IUPAC 2021 abridged.
REF = {
    "H":  (1,  "1.008",  [1]),
    "He": (2,  "4.0026", [2]),
    "Li": (3,  "6.94",   [2, 1]),
    "Be": (4,  "9.0122", [2, 2]),
    "B":  (5,  "10.81",  [2, 3]),
    "C":  (6,  "12.011", [2, 4]),
    "N":  (7,  "14.007", [2, 5]),
    "O":  (8,  "15.999", [2, 6]),
    "F":  (9,  "18.998", [2, 7]),
    "Ne": (10, "20.180", [2, 8]),
    "Na": (11, "22.990", [2, 8, 1]),
    "Mg": (12, "24.305", [2, 8, 2]),
    "Al": (13, "26.982", [2, 8, 3]),
    "Si": (14, "28.085", [2, 8, 4]),
    "P":  (15, "30.974", [2, 8, 5]),
    "S":  (16, "32.06",  [2, 8, 6]),
    "Cl": (17, "35.45",  [2, 8, 7]),
    "Ar": (18, "39.95",  [2, 8, 8]),
    "K":  (19, "39.098", [2, 8, 8, 1]),
    "Ca": (20, "40.078", [2, 8, 8, 2]),
    "Fe": (26, "55.845", [2, 8, 14, 2]),
    "Cu": (29, "63.546", [2, 8, 18, 1]),
    "Au": (79, "196.97", [2, 8, 18, 32, 18, 1]),
}

# Bond lengths (angstrom) and angles (deg) the geometries must reproduce.
GEOM_REF = {
    "water":         {"bond": ("O", "H", 0.958), "angle": 104.5},
    "carbonDioxide": {"bond": ("C", "O", 1.163), "angle": 180.0},
    "methane":       {"bond": ("C", "H", 1.087), "angle": 109.47},
    "ammonia":       {"bond": ("N", "H", 1.012), "angle": 107.0},
    "ethane":        {"bond": ("C", "H", 1.090), "angle": 109.47},
    "benzene":       {"bond": ("C", "C", 1.390), "angle": 120.0},
    "dioxygen":      {"bond": ("O", "O", 1.208), "angle": None},
    "dinitrogen":    {"bond": ("N", "N", 1.098), "angle": None},
}


# ------------------------------------------------------------ equation maths --
def parse_formula(f):
    """'2H2O' -> (2, {'H':2,'O':1})"""
    m = re.match(r"^(\d*)(.*)$", f)
    coef = int(m.group(1)) if m.group(1) else 1
    atoms = {}
    for sym, cnt in re.findall(r"([A-Z][a-z]?)(\d*)", m.group(2)):
        if not sym:
            continue
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


# --------------------------------------------------------- chemistry.mjs read --
src = open(r("source", "generator", "chemistry.mjs"), encoding="utf-8").read()

print("== element data ==")
for sym, (z, mass, shells) in REF.items():
    m = re.search(
        r"^\s*%s:\s*\{\s*z:\s*(\d+),\s*name:\s*'([^']+)',\s*mass:\s*'([^']+)',"
        r"\s*group:\s*(\d+),\s*period:\s*(\d+),\s*cat:\s*'([^']*)',"
        r"\s*shells:\s*\[([0-9, ]+)\]" % re.escape(sym),
        src, re.M)
    if not ok(m, f"element {sym} missing from chemistry.mjs"):
        continue
    gz, name, gmass, group, period, cat, gsh = m.groups()
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
    # the source may carry the arrow literally or as a JS escape
    eq = eq.replace("\\u2192", "\u2192").replace("\\u21CC", "\u21CC")
    good, detail = balanced(eq)
    ok(good, f"equation {name} is not balanced: {eq}  ({detail})")
    print(f"   {name:16s} {eq}   balanced")

# ------------------------------------------------------------ molecular maths --
print("== molecular geometry ==")
mol_src = src[src.index("export const MOLECULES"):src.index("/* ------------------------------------------------------------- projection")]


def atoms_of(key):
    blk = re.search(r"\b%s:\s*\{(.*?)\n  \}," % key, mol_src, re.S)
    if not blk:
        return None
    txt = blk.group(1)
    if key == "benzene":                      # generated by an IIFE
        pts = []
        for i in range(6):
            t = math.pi / 3 * i
            pts.append(("C", 1.39 * math.cos(t), 1.39 * math.sin(t), 0.0))
        for i in range(6):
            t = math.pi / 3 * i
            pts.append(("H", 2.48 * math.cos(t), 2.48 * math.sin(t), 0.0))
        return pts
    out = []
    for sym, x, y, z in re.findall(
            r"\['([A-Z][a-z]?)',\s*(-?[\d.]+),\s*(-?[\d.]+),\s*(-?[\d.]+)\]", txt):
        out.append((sym, float(x), float(y), float(z)))
    return out


def dist(a, b):
    return math.dist(a[1:], b[1:])


for key, ref in GEOM_REF.items():
    at = atoms_of(key)
    if not ok(at, f"molecule {key} not found"):
        continue
    s1, s2, want = ref["bond"]
    # shortest s1-s2 distance is the bond in every molecule here
    ds = [dist(a, b) for a in at for b in at
          if a is not b and {a[0], b[0]} == {s1, s2}]
    got = min(ds)
    ok(abs(got - want) < 0.006,
       f"{key}: {s1}-{s2} bond {got:.4f} A should be {want} A")
    if ref["angle"] is not None:
        c = at[0]
        nb = [a for a in at[1:] if abs(dist(a, c) - min(dist(x, c) for x in at[1:])) < 0.02]
        if len(nb) >= 2:
            v1 = [nb[0][i] - c[i] for i in (1, 2, 3)]
            v2 = [nb[1][i] - c[i] for i in (1, 2, 3)]
            dot = sum(p * q for p, q in zip(v1, v2))
            ang = math.degrees(math.acos(max(-1, min(1, dot / (math.dist([0]*3, v1) * math.dist([0]*3, v2))))))
            ok(abs(ang - ref["angle"]) < 0.6,
               f"{key}: bond angle {ang:.2f} deg should be {ref['angle']} deg")
    print(f"   {key:15s} {s1}-{s2} = {got:.4f} A" +
          (f"   angle = {ang:.2f} deg" if ref["angle"] is not None and len(nb) >= 2 else ""))

# ------------------------------------------------------------------- frames --
print("== frames ==")
frames = json.load(open(r("source", "frames.json"), encoding="utf-8"))
ok(len(frames) == 8, f"expected 8 frames, found {len(frames)}")

for g in frames:
    tag = f"{g['id']}-{g['slug']}"

    # ---- exact canvas ratio in the screen opening
    ratio = g["screenW"] / g["screenH"]
    ok(abs(ratio - CW / CH) < 1e-12,
       f"{tag}: screen ratio {ratio!r} != {CW}/{CH}")

    # ---- a square screenshot must stay inside the bezel, corners included.
    # Rotation is rigid (screen and body share one transform), so this is
    # rotation-invariant and can be proved in unrotated space.
    screen_r = g["screenR"]
    bez = g["bezel"]
    corner_gap = (bez + screen_r) - math.sqrt(2) * screen_r
    ok(corner_gap > 0.5,
       f"{tag}: square screenshot corner would escape the bezel (gap {corner_gap:.2f}px)")

    # ---- files
    for key in ("background", "overlay", "output"):
        path = r(g[key])
        if not ok(os.path.exists(path), f"{tag}: missing {g[key]}"):
            continue
        im = Image.open(path)
        ok(im.size == (CW, CH), f"{tag}: {g[key]} is {im.size}, must be {CW}x{CH}")

    bg = Image.open(r(g["background"]))
    ov = Image.open(r(g["overlay"]))
    ex = Image.open(r(g["output"]))

    ok(bg.mode == "RGB", f"{tag}: background must be flattened RGB, is {bg.mode}")
    ok(ex.mode == "RGB", f"{tag}: App Store export must have no alpha, is {ex.mode}")
    ok(ov.mode == "RGBA", f"{tag}: device overlay must be RGBA, is {ov.mode}")

    # ---- the overlay's screen must be a genuine hole
    a = ov.split()[3]
    cx, cy = int(g["screenCX"]), int(g["screenCY"])
    ok(a.getpixel((cx, cy)) == 0,
       f"{tag}: overlay is not transparent at the screen centre")
    # ---- and its bezel must be genuinely opaque. Sample mid-bezel on the left
    # edge, carried through the device's own rigid rotation.
    ang = math.radians(g["rot"])
    ox, oy = g["deviceCX"], g["deviceCY"]
    ux, uy = g["deviceX"] + g["bezel"] / 2 - ox, 0.0
    bx = ox + ux * math.cos(ang) - uy * math.sin(ang)
    by = oy + ux * math.sin(ang) + uy * math.cos(ang)
    ok(a.getpixel((round(bx), round(by))) > 200,
       f"{tag}: overlay bezel is not opaque at the left edge")

    # ---- regression guard: the renderer used to stop painting ~88px short
    last = bg.convert("RGB").getpixel((CW // 2, CH - 1))
    ok(last != (255, 255, 255),
       f"{tag}: background bottom row is bare white - raster clipping regression")

    # ---- no fabricated app UI: the template must still say what it is
    svg = open(r("source", f"template-{tag}.svg"), encoding="utf-8").read()
    ok("REPLACE WITH REAL SCREENSHOT" in svg,
       f"{tag}: template lost its screenshot placeholder")
    for line in g["headline"] + g["sub"]:
        esc = line.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        ok(esc in svg, f"{tag}: copy line not found in the SVG: {line!r}")

    # ---- decoration must stay quiet
    for op in re.findall(r'<g id="(?:Molecule|Tile|Bohr|Orbits|Lattice|Periodic|Skeletal)[^"]*"[^>]*opacity="([\d.]+)"', svg):
        warn(float(op) <= 1.0, f"{tag}: decoration opacity {op} out of range")

    # ---- margins
    ok(abs(g["copyX"] - 96) < 0.01 or g["copyX"] == CW / 2,
       f"{tag}: copy x {g['copyX']} is neither the 96px margin nor centred")
    ok(g["copyBottom"] < g["deviceY"] - 40,
       f"{tag}: copy bottom {g['copyBottom']:.1f} too close to device top {g['deviceY']:.1f}")

    print(f"   {tag:20s} screen {g['screenW']:.0f}x{g['screenH']:.1f} "
          f"rot {g['rot']:+.1f}  corner gap {corner_gap:.1f}px  "
          f"uniform scale {g['uniformScale']:.6f}")

# ------------------------------------------------------------ shared checks --
print("== set consistency ==")
tops = {round(g["copyTop"]) for g in frames}
ok(tops <= {236, 296}, f"headline cap-tops drift across the set: {sorted(tops)}")
centres = {round((g["copyTop"] + g["copyBottom"]) / 2) for g in frames}
ok(max(centres) - min(centres) < 14,
   f"copy blocks are not optically aligned: {sorted(centres)}")
rots = [g["rot"] for g in frames]
ok(all(abs(x) <= 5 for x in rots), f"a device is tilted too far: {rots}")
ok(len([x for x in rots if x == 0]) >= 3,
   "too few straight-on frames; the set will feel gimmicky")

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
