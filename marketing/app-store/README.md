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
| `exports/gallery-1-2-3.png` | slides 1 to 3 at gallery scale, the mini campaign |
| `exports/pair-2-3-touching.png` | slides 2 and 3 edge to edge, the master reassembled |
| `exports/pair-2-3-gallery.png` | the same pair with a realistic gallery gap |
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
no device is tilted more than 4.5 degrees.

| # | file | headline | composition | devices |
|---|---|---|---|---|
| 1 | `01-hero.png` | Learn Chemistry Visually | one full straight device, centred, wide margins | 1 |
| 2 | `02-elements.png` | Explore Every Element | full straight periodic table device, plus the lower left corner of slide 3's Build phone entering at the right | 2 |
| 3 | `03-build.png` | Build Real Molecules | that same Build phone, now the hero, filling the lower two thirds. Nothing else | 1 |
| 4 | `04-element-detail.png` | See More Than Symbols | one very large device, 1 degree, fully visible | 1 |
| 5 | `05-study.png` | Study Smarter | two complete overlapping devices, rear high and left, front low and right | 2 |
| 6 | `06-progress.png` | See Your Progress | one device, perfectly vertical, pushed right with a seventh of its width off the right edge | 1 |

Frames 1 to 3 are designed as one mini campaign: a calm hero, a calm periodic
table, then the layered Build composition. Every device is a complete phone
except the one handoff device described below.

### Slides 2 and 3 are one composition

Slides 2 and 3 are designed together on a **2640 x 2868 master canvas** and
sliced at x = 1320. The Build device is defined once, in master coordinates, in
`source/generator/frames/pair23.mjs`; each slide derives its own placement by
subtracting its panel origin. The slice is therefore exact by construction, not
by eye, and the QA pass asserts all four conditions: identical screen width,
identical rotation, identical y, and an x differing by exactly one panel width.

The Build phone is the hero of slide 3 and reaches back into slide 2 with its
lower left corner only. It is sized and angled after CoreCredit's own spanning
device: 74 percent of a panel's width at 4.5 degrees, and seated so its **bottom
sits on the canvas** rather than running off it, which means slide 2 shows a real
corner of the phone rather than an open-ended edge.

Its top left corner clears the seam by 10px, so what appears on slide 2 is a
wedge starting a little under a fifth of the way down and widening to 167px at
the bottom left corner: 13.2 percent of the device. Only **4.3 percent of the
Build screen area** falls on slide 2, and it is the bottom left corner of it, so
nothing worth reading is split; the continuation is carried by the device body.

Each slide still works alone. Slide 2 reads as a calm periodic table with a
device entering at the edge; slide 3 reads as a large Build phone arriving from
off-frame.

Three devices are allowed to leave the canvas, and they are marked `bleed` in
their frame definition: the Build phone on both slides, and the Progress phone on
slide 6. Every other device is a whole phone, and the QA pass fails if one is
clipped.

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

**Seven** captures at **1320 x 2868** (iPhone 17 Pro Max or 16 Pro Max, or any
device whose captures you can render at that size). Eight device slots, but the
Build capture fills two of them. Anything with a close aspect ratio is
centre-cropped by a pixel or two rather than distorted.

| capture | used by | make sure |
|---|---|---|
| Home | 01 hero | the strongest top level state; the most important image in the set |
| Periodic Table | 02 main | scrolled so the grid fills the screen. Fully visible and straight on |
| Build canvas | 02 build, 03 build | mid-assembly, with a molecule actually on the canvas, never an empty builder. Almost all of it lands on slide 3; only the bottom left corner of the screen, about 5 percent of its area, falls on slide 2 |
| Element detail | 04 hero | the most visually complete element. Iron matches frame 04's shell diagram |
| Study overview | 05 front | the Study home or dashboard, with real progress on it |
| Quiz or flashcard | 05 back | a quiz mid-question, or a flashcard |
| Progress | 06 hero | enough real activity to look earned. The rightmost ninth runs off the canvas, so keep headline numbers and labels left of centre |

Only the Build and Progress captures meet a canvas edge, and both are noted
above; everything else can be composed for its full frame.

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
01-home.png
02-main-periodic-table.png      02-build-canvas.png
03-build-canvas.png
04-element-detail.png
05-front-study.png              05-back-quiz.png
06-progress.png
```

The three Build entries are the same capture under three names; copy the file
rather than taking three screenshots.

### Inserting a real screenshot

This is the only step left between the templates and finished store assets. It
works straight from a fresh clone; each frame carries its own geometry, so no
build products are needed.

```sh
cd marketing/app-store
python3 place_screenshot.py --all                         # everything it can find
python3 place_screenshot.py 01 screenshots/selected/01-home.png
python3 place_screenshot.py hero screenshots/selected/01-home.png      # slug works too
python3 place_screenshot.py 03 build.png                               # 03 is one device
python3 place_screenshot.py 02 --main table.png --build build.png      # or by role
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

**Variety.** Device widths run from 803px to 1042px across the set. Three frames
carry more than one device, three carry one. Tilts stay between 0 and 4.5 degrees
and are rigid 2D rotations of the whole device group, never a perspective
homography, which is why a real screenshot follows the bezel exactly. The QA pass
fingerprints each frame by device count, scale band, horizontal placement and
rotation, and fails if the six do not produce at least five distinct signatures.
It also fails if any frame's largest device drops below 63 percent of the canvas
width, because the product has to stay the hero.

**Background hierarchy.** Every frame carries exactly one anchor motif at 7 to 10
percent, one to three secondary marks at 4 to 6 percent, and at least one ambient
mark at 2 to 4 percent, with at most five marks in total. The build records the
inventory into each frame's geometry file and the QA pass enforces those bands,
so no frame can drift back into uniformly faint wallpaper. The anchors are sized
to pass *behind* the devices and surface again on the far side: a naphthalene ring
system straddling frame 01's left bezel, an iron shell diagram wider than the
phone in frame 04, a caffeine skeleton centred on frame 03's device, and period
1-4 table fragments sliding under frames 02 and 06. Frame 02's fragment also
dissolves toward the middle of the slide, so it reads as atmosphere rather than a
band of squares. That occlusion is what
seats the devices in the composition.

Everything is crisp vector linework at low opacity. Nothing is blurred to make it
subtle, so the chemistry is legible to anyone who looks closely.

**Integration.** Every device sits on three shadow passes: a wide ambient bloom,
a mid body shadow, and a tight contact shadow hugging the silhouette, plus a
faint pool of cool light behind the backmost device. In the two-phone frames the
front device casts its shadow across the rear one, which is what makes the
overlap read as depth rather than collage.

**Typography.** Inter (latin variable subset), embedded in every SVG so a render
is self-contained. Headline 122px/119px ExtraBold, tracking -3.4. Supporting
50px/64px Medium, raised from 45px so it stays readable at App Store browsing
scale without competing with the headline.

**Device.** A neutral, custom-drawn vector frame: no Apple product imagery is
used anywhere in this system, so rotating, overlapping or cropping a device does
not touch Apple marketing assets. One rigid group derived from a single screen
width, so the 1320:2868 opening can never distort. Light titanium rim, thin black
border, and a Dynamic Island drawn *over* the screenshot, because it is hardware
rather than app UI. The hardware stays understated; the app UI is the product.

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
| Caffeine | C8H10N4O2 | Decane | C10H22 |

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
- the six frames produce at least five distinct composition signatures, the largest
  device is at least 25 percent wider than the smallest, exactly two frames carry more than one device,
  and every frame's largest device is at least 63 percent of the canvas width
- frame 02's periodic table device is exactly 0 degrees and fully visible
- frame 06's device is exactly 0 degrees, leaves the canvas on the RIGHT ONLY,
  and by 8 to 15 percent of its width
- frame 03 carries exactly one device
- only a device marked `bleed` leaves the canvas; every other device is complete
- the 02 + 03 master slices exactly: same screen width, same rotation, same y,
  x differing by exactly 1320. Between 8 and 15 percent of the Build device sits
  on slide 2, its top left corner clears the seam and its bottom stays on canvas,
  under 8 percent of its screen AREA is split (measured by clipping the rotated
  screen, not by its unrotated edge), and it never collides with the periodic
  table device
- exactly one anchor motif per frame at 7 to 10 percent, every other mark at 6
  percent or below, something ambient at 4 percent or below, no single mark above
  11 percent, and no more than five decorative marks
- no fabricated app UI: every template still carries its screenshot placeholder
- no 3D ball-and-stick renderer or assets
- chemistry: derived formulas match their labels, no over-valent atoms, uniform
  bond lengths, shells sum to Z, weights match reference data, equations balance

Current state: **520 checks, 0 failures, 0 warnings.**

## Relationship to CoreCredit

The structure follows `BKimble1/corecredit-appstore`: layered frames, one
`geometry.json` per frame, a `place_screenshot.py` compositor, SVG masters
rasterised through Chromium, a QA script that proves the invariants, and the same
appetite for varied device arrangements including overlapping phones. The visual
language deliberately does not: CoreCredit is a dark royal-blue financial
campaign, Elemora is near-white paper, pale chemistry blues, deep navy type and
skeletal linework.
