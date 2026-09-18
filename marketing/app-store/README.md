# Elemora, App Store screenshot system

Six iPhone App Store screenshots at **1320 x 2868**, plus the deterministic
toolchain that generates them. No design tool and no image generation is
involved: every asset is drawn as SVG, rasterised through headless Chromium at
an exact pixel size, and verified programmatically.

> **Status: the templates are finished; the real app captures are not in yet.**
> This session had no macOS, Xcode or iOS Simulator (it ran on Linux), and the
> repository contains no Elemora source to build, so no Elemora UI could be
> captured. Rather than invent screens, every device carries a precisely sized,
> labelled screenshot slot. See **[What is still needed](#what-is-still-needed)**.
> Nothing here depicts Elemora's interface. Not a redraw, not an approximation.

## Layout

| path | what it is |
|---|---|
| `exports/iphone/` | the six deliverables, `01-hero.png` to `06-progress.png` |
| `exports/contact-sheet.png` | 3 x 2 review sheet |
| `exports/contact-sheet-thumbnail.png` | the six at App Store browsing scale |
| `source/template-NN-slug.svg` | editable vector master for one frame |
| `source/template-NN-slug.geometry.json` | that frame's device placement, read by the compositor |
| `source/template-NN-slug.placement.txt` | the same placement, written out for a human |
| `source/frames.json` | all six geometries in one file |
| `source/skeletal.json` | the drawn skeletal graphs, so QA can re-derive their formulas |
| `assets/backgrounds/` | layer 1, opaque, everything behind the first capture |
| `assets/device/` | device chrome, RGBA, a genuine hole where each screen is |
| `assets/skeletal/`, `element-tiles/`, `orbital/`, `formulas/` | the decoration library as standalone SVGs |
| `screenshots/raw/` | captures straight off the simulator |
| `screenshots/selected/` | the chosen, prepared capture per device |
| `place_screenshot.py` | drops real captures into the frames |
| `source/generator/` | the generator: design system, chemistry library, per-frame composition, build and QA |

## The sequence

Six compositions, deliberately not one template repeated six times. Variety
comes from scale, cropping, overlap and position rather than from steep angles;
no device is tilted more than 5 degrees.

| # | file | headline | composition | devices |
|---|---|---|---|---|
| 1 | `01-hero.png` | Learn Chemistry Visually | centred, upright, fully visible, wide margins | 1 |
| 2 | `02-elements.png` | Explore Every Element | oversized, leaning in from the lower right, cropped right and bottom | 1 |
| 3 | `03-build.png` | Build Real Molecules | two phones, front low and left, rear high and right | 2 |
| 4 | `04-element-detail.png` | See More Than Symbols | the largest device, near upright, edge to edge, bleeding off the bottom | 1 |
| 5 | `05-study.png` | Study Smarter | two phones, mirrored from 03: rear enters left, front sits right | 2 |
| 6 | `06-progress.png` | See Your Progress | rising out of the lower left corner, cropped on two sides | 1 |

Frames 1 to 3 carry the pitch on their own: what the app is, the table, the
builder. Eight captures are needed in total, because frames 3 and 5 hold two
devices each.

### Before you ship this copy

The copy was written without access to a build, so **check each line against the
app before uploading**. In particular: frame 3 promises visual compound creation
and a finished-compound view, frame 5 promises more than one study surface, and
frame 6 promises mastery and activity tracking. If any of that is not in the
shipping build, change the line. Every string lives in one place,
`source/generator/frames/frameNN.mjs`, and `build.mjs` re-measures and re-renders
it.

Nothing in the set claims a grade improvement, an award, a ranking or an AI
feature, and there is no em dash in any customer-facing string. The build fails
if an em dash appears in marketing copy and the QA pass rejects one anywhere in
the rendered artwork.

## What is still needed

Eight captures at **1320 x 2868** (iPhone 17 Pro Max or 16 Pro Max, or any
device whose captures you can render at that size). Anything with a close aspect
ratio is centre-cropped by a pixel or two rather than distorted.

| frame | device | capture | make sure |
|---|---|---|---|
| 01 | hero | Home | the strongest top level state; the most important image in the set |
| 02 | hero | Periodic Table | scrolled so the grid fills the screen. The lower right is cropped, so keep the important rows high |
| 03 | front | Build canvas | mid-assembly, with a molecule actually on the canvas. Never an empty builder |
| 03 | back | Finished compound | the result of a build: a compound sheet, or the 3D viewer if the app has one. Cropped by the right edge, so keep the subject left of centre |
| 04 | hero | Element detail | the most visually complete element, usually Carbon or Iron. The lower sixth is cropped, so keep the tile, name and key properties high |
| 05 | front | Study overview | the Study home or dashboard, with real progress on it |
| 05 | back | Quiz or flashcard | a quiz mid-question, or a flashcard. Cropped by the left edge, so keep the subject right of centre |
| 06 | hero | Progress | enough real activity to look earned. Cropped left and bottom, so keep the headline numbers high and right |

Populate the app with believable sample data first. Empty states sell nothing.

### Capturing

```sh
xcrun simctl boot "iPhone 17 Pro Max"
xcrun simctl launch booted <your.bundle.id>
xcrun simctl io booted screenshot marketing/app-store/screenshots/raw/01-home.png
```

Give each capture the marketing status bar before compositing:

```sh
xcrun simctl status_bar booted override \
  --time "9:41" --cellularBars 4 --wifiBars 3 --batteryLevel 100 --batteryState charged
```

Then copy the chosen file into `screenshots/selected/`, keeping the `NN-` prefix,
and for the two-device frames include the word `front` or `back` in the name:

```
01-home.png   02-periodic-table.png
03-front-build.png   03-back-compound.png
04-element-detail.png
05-front-study.png   05-back-quiz.png
06-progress.png
```

### Inserting a real screenshot

This is the only step left between the templates and finished store assets. It
works straight from a fresh clone; each frame carries its own geometry, so no
build products are needed.

```sh
cd marketing/app-store
python3 place_screenshot.py --all                         # everything it can find
python3 place_screenshot.py 01 screenshots/selected/01-home.png
python3 place_screenshot.py hero screenshots/selected/01-home.png      # slug works too
python3 place_screenshot.py 03 back.png front.png                     # layer order
python3 place_screenshot.py 03 --front build.png --back compound.png  # or by role
```

Output overwrites `exports/iphone/NN-slug.png`. `--all` places what it finds and
lists the devices still waiting.

Each capture is scaled by a **single uniform factor** (cover fit, centre-cropped
by at most a pixel or two) and rotated by its device's own angle, as one rigid
group with that device. It is never stretched, recoloured, cropped into or
redrawn. To change a design and keep the captures, edit the frame, re-run the
build, then re-run `place_screenshot.py --all`.

## Design

**Layout.** Copy occupies the top quarter, with headline cap-tops at 236px
(two-line) or 296px (one-line), which puts every copy block on the same optical
centre; the QA pass enforces that. Margin is 96px, giving a 1128px column, and
every line is measured in the real renderer at build time so the build fails if
one exceeds it.

**Variety.** Device widths run from 792px to 1199px across the set. Two frames
carry two devices, four carry one. Tilts stay between 0 and 5 degrees and are
rigid 2D rotations of the whole device group, never a perspective homography,
which is why a real screenshot follows the bezel exactly. The QA pass fingerprints
each frame by device count, scale band, horizontal placement and which edges it
crops, and fails if the six do not produce at least five distinct signatures.

**Integration.** Every device sits on three shadow passes: a wide ambient bloom,
a mid body shadow, and a tight contact shadow hugging the silhouette, plus a
faint pool of cool light behind the backmost device. In the two-phone frames the
front device casts its shadow across the rear one, which is what makes the
overlap read as depth rather than collage.

**Typography.** Inter (latin variable subset), embedded in every SVG so a render
is self-contained. Headline 122px/119px ExtraBold, tracking -3.4. Supporting
45px/59px Medium.

**Device.** One rigid group derived from a single screen width, so the 1320:2868
opening can never distort. Light titanium rim, thin black border, and a Dynamic
Island drawn *over* the screenshot, because it is hardware rather than app UI.

### Palette provenance

Sampled from the Elemora brand reference artwork rather than invented:

| token | value | where it came from |
|---|---|---|
| `ink` | `#0E2039` | headline navy, sampled `#102038` |
| `accent` | `#2F6BE8` | Elemora blue, sampled `#4884FC` / `#5490FC` |
| `paleA/B/C` | `#EAF3FD` `#DDEBFA` `#D6EAF7` | the dominant pale-blue tints |
| `lavender` | `#E4E0F6` | the study/lavender family, heavily lightened |
| `shadow` | `#22456F` | cool, never black on this paper |

When you have the app to hand, reconcile these against its real tokens in
`source/generator/system.mjs`; everything downstream follows automatically.

### The supplied reference

`source/brand-reference.png` is the art-direction reference this campaign was
built from, and where the palette above was sampled. Treat it as mood and colour
only: the phone screen inside it is a concept mock, **not** Elemora's real
interface, and none of it was traced, copied or reproduced into these templates.

### Chemistry

The decorative language is **skeletal**: line-angle structural formulas, rings,
fused ring systems, orbital and electron-shell diagrams, periodic tiles and
balanced equations, all drawn as thin scientific linework between 3 and 8 percent
opacity so it behaves like a watermark. Larger structures are allowed to run off
the canvas rather than being shrunk to fit.

There is deliberately **no 3D ball-and-stick artwork** anywhere in the marketing
layer; the QA pass fails if that renderer or its assets reappear. The only
molecular rendering these screenshots show in three dimensions is whatever the
real app draws inside a real capture.

The structure library, all checked:

| structure | formula | structure | formula |
|---|---|---|---|
| Benzene | C6H6 | Ethanol | C2H6O |
| Cyclohexane | C6H12 | Acetone | C3H6O |
| Toluene | C7H8 | Acetic acid | C2H4O2 |
| Phenol | C6H6O | Butane | C4H10 |
| Naphthalene | C10H8 | Hexane | C6H14 |
| Caffeine | C8H10N4O2 | | |

`verify.py` does not trust those labels. It reads the drawn graph out of
`source/skeletal.json` and re-derives each molecular formula from the bond orders
plus implicit hydrogens, using valences held in the QA script itself, and rejects
any over-valent atom. It also checks that every drawn bond is exactly one bond
length, which is what proves the rings are regular and the chains sit at a true
120 degrees. Atomic numbers, IUPAC 2021 abridged atomic weights and electron
shells are cross-checked the same way, and every equation is parsed and balanced.

## Regenerating

```sh
cd marketing/app-store
node source/generator/build.mjs     # all six frames, assets and contact sheets
python3 source/generator/verify.py  # full QA sweep
```

Requires Node 18+, Python 3 with Pillow, and Chromium (set `CHROME_PATH` if it is
not in a standard location). To change one frame, edit
`source/generator/frames/frameNN.mjs`: headline, supporting copy, device
placement, background lights and decoration are all declared there, and
everything else is derived.

## Invariants the QA pass enforces

- every PNG is exactly 1320 x 2868
- every screen opening holds the exact 1320:2868 ratio (delta 0.0)
- App Store exports and backgrounds carry no alpha; device overlays are RGBA with
  a genuinely transparent screen and a genuinely opaque bezel
- a square 1320 x 2868 capture is fully contained by its bezel, corners included,
  proved in unrotated space, which is valid because the tilt is rigid
- **end to end**: a marker image is pushed through the real compositor and every
  frame is scanned for capture pixels outside the device silhouettes. Zero leaks,
  including the two-phone frames
- backgrounds paint to the last row (headless Chromium silently stops about 88px
  short of the requested window height, so the renderer oversizes and crops; this
  check is the regression guard)
- no em dash in marketing copy or anywhere in the rendered artwork
- marketing copy read back out of each SVG matches the frame definition, and the
  six headlines match the agreed sequence
- decoration never exceeds 20 percent opacity
- the six frames produce at least five distinct composition signatures, device
  widths span more than 250px, and exactly two frames carry two devices
- no fabricated app UI: every template still carries its screenshot placeholder
- no 3D ball-and-stick renderer or assets
- chemistry: derived formulas match their labels, no over-valent atoms, uniform
  bond lengths, shells sum to Z, weights match reference data, equations balance

Current state: **455 checks, 0 failures, 0 warnings.**

## Relationship to CoreCredit

The structure follows `BKimble1/corecredit-appstore`: layered frames, one
`geometry.json` per frame, a `place_screenshot.py` compositor, SVG masters
rasterised through Chromium, a QA script that proves the invariants, and the same
appetite for varied device arrangements including overlapping phones. The visual
language deliberately does not: CoreCredit is a dark royal-blue financial
campaign, Elemora is near-white paper, pale chemistry blues, deep navy type and
skeletal linework.
