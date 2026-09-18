# Elemora — App Store screenshot system

Eight iPhone App Store screenshots at **1320 × 2868**, plus the deterministic
toolchain that generates them. No design tool and no image generation is
involved: every asset is drawn as SVG, rasterised through headless Chromium at
an exact pixel size, and verified programmatically.

> **Status: the templates are finished; the eight real app captures are not in
> yet.** This session had no macOS, Xcode or iOS Simulator (it ran on Linux), and
> the repository contains no Elemora source to build, so no Elemora UI could be
> captured. Rather than invent screens, every frame carries a precisely sized,
> labelled screenshot slot. See **[What is still needed](#what-is-still-needed)**.
> Nothing here depicts Elemora's interface — not a redraw, not an approximation.

## Layout

| path | what it is |
|---|---|
| `exports/iphone/` | the eight deliverables, `01-hero.png` … `08-overview.png` |
| `exports/contact-sheet.png` | 4 × 2 review sheet |
| `exports/contact-sheet-thumbnail.png` | the eight at App Store browsing scale |
| `source/template-NN-slug.svg` | editable vector master for one frame |
| `source/template-NN-slug.geometry.json` | that frame's device placement, read by the compositor |
| `source/template-NN-slug.placement.txt` | the same placement, written out for a human |
| `source/frames.json` | all eight geometries in one file |
| `assets/backgrounds/` | layer 1 — opaque, everything behind the screenshot |
| `assets/device/` | layer 3 — RGBA, a genuine hole where the screen is |
| `assets/molecules/`, `element-tiles/`, `orbital/`, `formulas/` | the decoration library as standalone SVGs |
| `screenshots/raw/` | captures straight off the simulator |
| `screenshots/selected/` | the chosen, prepared capture per frame |
| `place_screenshot.py` | drops real captures into the frames |
| `source/generator/` | the generator: design system, chemistry library, per-frame composition, build and QA |

Each frame is three layers. `background` and `overlay` sandwich your screenshot,
so replacing a capture never touches the design.

## The sequence

| # | file | headline | screen you need |
|---|---|---|---|
| 1 | `01-hero.png` | Learn Chemistry Visually | **Home** |
| 2 | `02-elements.png` | Explore Every Element | **Periodic Table** |
| 3 | `03-build.png` | Build Real Molecules | **Build** |
| 4 | `04-element-detail.png` | See More Than Symbols | **Element detail** |
| 5 | `05-study.png` | Study Smarter | **Study** (one mode only) |
| 6 | `06-progress.png` | See Your Progress | **Progress / mastery** |
| 7 | `07-favorites.png` | Keep What Matters Close | **Favourites / saved** |
| 8 | `08-overview.png` | Chemistry, Made Clear | **Home or Periodic Table** again |

Frames 1–3 carry the pitch on their own: what the app is, the table, the builder.

### Before you ship this copy

The copy was written without access to a build, so **check each line against the
app before uploading**. In particular: frame 3 says "Build Real Molecules /
Create compounds visually and see how atoms connect", frame 6 promises mastery
and activity tracking, and frame 7 promises saving elements *and* compounds. If
any of that is not in the shipping build, change the line — every string lives in
one place, `source/generator/frames/frameNN.mjs`, and `build.mjs` re-measures and
re-renders it. Nothing in the set claims a grade improvement, an award, a ranking
or an AI feature.

## What is still needed

Eight captures, at **1320 × 2868** (iPhone 17 Pro Max / 16 Pro Max, or any
device whose captures you can render at that size). Anything with a close aspect
ratio is centre-cropped by a pixel or two rather than distorted.

| frame | capture | make sure |
|---|---|---|
| 01 | Home | the strongest top-level state; this is the most important image in the set |
| 02 | Periodic Table | scrolled so the table fills the screen |
| 03 | Build | a molecule actually assembled, not an empty canvas |
| 04 | Element detail | the most visually complete element — Carbon or Iron |
| 05 | Study | **one** mode: study home, a quiz mid-question, or a flashcard |
| 06 | Progress | enough real activity on it to look earned |
| 07 | Favourites | populated with several elements and compounds |
| 08 | Home or Periodic Table | may reuse 01's capture |

Populate the app with believable sample data first — empty states sell nothing.

### Capturing

```sh
xcrun simctl boot "iPhone 17 Pro Max"
xcrun simctl launch booted <your.bundle.id>
# navigate to the screen, then:
xcrun simctl io booted screenshot marketing/app-store/screenshots/raw/01-home.png
```

Give each capture the marketing status bar before compositing — 9:41, full
signal, Wi-Fi, 100% battery:

```sh
xcrun simctl status_bar booted override \
  --time "9:41" --cellularBars 4 --wifiBars 3 --batteryLevel 100 --batteryState charged
```

Then copy the chosen file to `screenshots/selected/NN-<name>.png`, keeping the
`NN-` prefix — that is how `--all` finds it.

### Inserting a real screenshot

This is the only step left between the templates and finished store assets. It
works straight from a fresh clone; each frame carries its own geometry, so no
build products are needed.

```sh
cd marketing/app-store
python3 place_screenshot.py 01 screenshots/selected/01-home.png
python3 place_screenshot.py hero screenshots/selected/01-home.png   # slug also works
python3 place_screenshot.py --all                                   # every frame at once
```

Output overwrites `exports/iphone/NN-slug.png`. Pass a further `.png` path to send
it somewhere else instead. `--all` reads `screenshots/selected/NN-*.png`, places
what it finds, and lists the frames still waiting.

The screenshot is scaled by a **single uniform factor** (cover fit, centre-cropped
by at most a pixel or two) and rotated by the frame's own angle, as one rigid
group with the device. It is never stretched, recoloured, cropped into or
redrawn, and no marketing graphic is ever drawn on top of it — all decoration
sits behind the phone by construction.

To change a design and keep the captures, edit the frame and re-run the build,
then re-run `place_screenshot.py --all`.

## Design

**Layout.** Copy occupies the top ~26%; the device runs from 26% to ~96% of the
canvas and dominates everything below. Margin is 96px, giving a 1128px column.
Headline cap-tops sit at 236px (two-line) or 296px (one-line), which puts every
copy block on the same optical centre — the QA pass enforces that.

**Variation, not noise.** Four frames are straight on (01, 04, 06, 08) and four
carry a gentle rigid tilt of 3–4° (02, 03, 05, 07), alternating direction so
02/03 and 05/07 read as spreads. There is no perspective homography anywhere:
tilts are rigid 2D rotations of the whole device group, which is why a real
screenshot follows the bezel exactly. 04 varies by scale instead of angle — it
carries the largest device in the set, because element detail is the densest
screen.

**Typography.** Inter (latin variable subset), embedded in every SVG so a render
is self-contained. Headline 122px/119px ExtraBold, tracking −3.4. Supporting
45px/59px Medium. Every line is measured in the real renderer at build time and
the build fails if one exceeds the column.

**Device.** One rigid group derived from a single screen width, so the 1320:2868
opening can never distort. Light titanium rim, thin black border, and a Dynamic
Island drawn *over* the screenshot — it is hardware, not app UI.

### Palette provenance

Sampled from the Elemora brand reference artwork rather than invented:

| token | value | where it came from |
|---|---|---|
| `ink` | `#0E2039` | headline navy, sampled `#102038` |
| `accent` | `#2F6BE8` | Elemora blue, sampled `#4884FC` / `#5490FC` |
| `paleA/B/C` | `#EAF3FD` `#DDEBFA` `#D6EAF7` | the dominant pale-blue tints |
| `lavender` | `#E4E0F6` | the study/lavender family, heavily lightened |
| `shadow` | `#22456F` | cool — never black on this paper |

When you have the app to hand, reconcile these against its real tokens in
`source/generator/system.mjs`; everything downstream follows automatically.

### Chemistry

Decoration is drawn from a checked library, not clip art. Ball-and-stick models
use real 3D geometries in ångströms, depth-sorted with a painter's algorithm so
atoms and bond halves interleave correctly:

| molecule | geometry |
|---|---|
| H₂O | O–H 0.958 Å, H–O–H 104.5° |
| CO₂ | linear, C=O 1.163 Å |
| CH₄ | regular tetrahedron, C–H 1.087 Å, 109.47° |
| NH₃ | trigonal pyramidal, N–H 1.012 Å, 107° |
| C₂H₆ | staggered, C–C 1.540 Å, C–H 1.090 Å |
| C₆H₆ | planar hexagon, C–C 1.39 Å, C–H 1.09 Å |
| O₂ / N₂ | 1.208 Å / 1.098 Å |

Atomic numbers, IUPAC 2021 abridged atomic weights, groups, periods and electron
shells come from reference data. The lattice motif is a graphene honeycomb, not
an invented node graph. Every equation is balanced. `verify.py` re-derives all of
it from an independent table held in the QA script itself, so a mistake in the
library cannot validate itself.

## Regenerating

```sh
cd marketing/app-store
node source/generator/build.mjs     # all eight frames, assets and contact sheets
python3 source/generator/verify.py  # full QA sweep
```

Requires Node 18+, Python 3 with Pillow, and Chromium (set `CHROME_PATH` if it is
not in a standard location).

To change one frame, edit `source/generator/frames/frameNN.mjs` — headline,
supporting copy, device placement, background lights and decoration are all
declared there, and everything else is derived.

## Invariants the QA pass enforces

- every PNG is exactly 1320 × 2868
- every screen opening holds the exact 1320:2868 ratio (delta 0.0)
- App Store exports and backgrounds carry no alpha channel; device overlays are
  RGBA with a genuinely transparent screen and a genuinely opaque bezel
- a square 1320 × 2868 screenshot is fully contained by the bezel, corners
  included — proved in unrotated space, which is valid because the tilt is rigid
- backgrounds paint to the last row (headless Chromium silently stops ~88px
  short of the requested window height, so the renderer oversizes and crops;
  this check is the regression guard)
- marketing copy read back out of each SVG matches the frame definition
- copy blocks stay inside the column and clear of the device
- no fabricated app UI: every template still carries its screenshot placeholder
- atomic numbers, weights and shell occupancies match reference data, shells sum
  to Z, bond lengths and angles match measured geometry, equations balance

Current state: **424 checks, 0 failures, 0 warnings.**

## Relationship to CoreCredit

The structure follows `BKimble1/corecredit-appstore` — three-layer frames, one
`geometry.json` per frame, a `place_screenshot.py` compositor, SVG masters
rasterised through Chromium, and a QA script that proves the invariants. The
visual language deliberately does not: CoreCredit is a dark royal-blue financial
campaign, Elemora is near-white paper, pale chemistry blues and deep navy type.

### The supplied reference

`source/brand-reference.png` is the art-direction reference this campaign was
built from — it is where the palette above was sampled. Treat it as mood and
colour only: the phone screen inside it is a concept mock, **not** Elemora's real
interface, and none of it was traced, copied or reproduced into these templates.
