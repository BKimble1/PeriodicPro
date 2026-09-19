# Elemora, App Store screenshot system

Six iPhone App Store screenshots at **1320 x 2868**, plus the deterministic
toolchain that generates them. No design tool and no image generation is
involved: every asset is drawn as SVG, rasterised through headless Chromium at
an exact pixel size, and verified programmatically.

> **Status: finished. The six exports carry the real Elemora screens.**
> Every pixel of app UI in `exports/iphone/` came out of a real device capture,
> placed into its device mask by `place_screenshot.py` under a single uniform
> scale. Nothing in this repository redraws, approximates or regenerates
> Elemora's interface; the marketing artwork lives entirely outside the bezels.
> See **[The captures](#the-captures)** for what each slide shows and the two
> surgical edits every capture receives before it is composited.

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
no device is tilted more than 6 degrees.

| # | file | headline | composition | devices |
|---|---|---|---|---|
| 1 | `01-hero.png` | Learn Chemistry Visually | one full straight device, centred, wide margins | 1 |
| 2 | `02-elements.png` | Explore Every Element | full straight periodic table device, plus the lower left corner of slide 3's Build phone entering at the right | 2 |
| 3 | `03-build.png` | Build Real Molecules | that same Build phone, now the hero, filling the lower two thirds. Nothing else | 1 |
| 4 | `04-element-detail.png` | See More Than Symbols | one very large device, 0.75 degrees, fully visible | 1 |
| 5 | `05-study.png` | Study Smarter | two complete overlapping devices, rear high and left, front low and right | 2 |
| 6 | `06-progress.png` | See Your Progress | one device, perfectly vertical, pushed right with an eighth of its width off the right edge | 1 |

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
device: 74 percent of a panel's width at 6 degrees, and seated so its **bottom
sits on the canvas** rather than running off it, which means slide 2 shows a real
corner of the phone rather than an open-ended edge.

Its top left corner clears the seam, so what appears on slide 2 is a wedge, and
the angle is what decides that wedge's shape. At 4.5 degrees it began a fifth of
the way down and read as a long thin strip; at 6 degrees the apex drops to 36
percent down and the bottom corner widens to 178px, so the curved corner, the
bezel and a band of screen all read as a phone arriving. The share is 15 percent,
the top of the agreed range, leaving 85 percent on slide 3. Only **5.0 percent of
the Build screen area** falls on slide 2, and it is the bottom left corner of it,
so nothing worth reading is split.

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

## The captures

**Seven** captures, each 1170 x 2532 off the device, fill **eight** device slots:
the Build capture is used twice, once on either side of the 02 + 03 seam. Each is
cover-fitted to its slot under a single uniform scale, which costs 3 to 4 pixels
of centre crop horizontally and none vertically.

| slide | device | capture | what it shows |
|---|---|---|---|
| 01 hero | hero | `01-periodic-table.png` | the full periodic table, search field, family filters and legend |
| 02 elements | main | `02-main-oxygen.png` | the Oxygen detail: hero card, `Reactive Nonmetal` pill, description, Atomic Structure |
| 02 elements | build | `02-build-caffeine.png` | the same Build capture as slide 03. Only its bottom left corner, about 5 percent of the screen area, lands here |
| 03 build | build | `03-build-caffeine.png` | Caffeine in the builder: `C8H10N4O2`, the skeletal formula, Save / Favorite / Details, `Explore in 3D` |
| 04 element detail | hero | `04-carbon.png` | Carbon: Quick Facts, About Carbon, Common Uses |
| 05 study | front | `05-front-study.png` | the Study home: streak, mastery, Daily Challenge, Flashcards, practice modes |
| 05 study | back | `05-back-identify.png` | the Identify quiz mid-question, a visibly different state from the front phone |
| 06 progress | hero | `06-progress.png` | Periodic Mastery ring, Periodic Pathfinder, Activity stats |

Two captures meet a canvas edge by design. The Build capture is split across the
02 / 03 seam, so nothing load-bearing may sit in its bottom left corner. The
Progress capture runs about 12 percent off the right edge, so its headline
numbers and labels stay left of centre; the trailing settings control is
deliberately cropped, the same way the reference campaigns crop a bleeding device.

### Capturing

```sh
xcrun simctl boot "iPhone 17 Pro Max"
xcrun simctl launch booted <your.bundle.id>
xcrun simctl io booted screenshot marketing/app-store/screenshots/raw/IMG_0001.png
```

Captures taken off a physical device work equally well and are what shipped here.
Populate the app with believable sample data first; empty states sell nothing.

### Preparing a capture

Raw captures go in `screenshots/raw/`. `screenshots/prepare.py` writes the
cleaned files into `screenshots/selected/` under the names the compositor looks
for. It makes exactly two edits per capture and asserts that it made no others:

1. **The status bar is removed.** The shipped captures were taken across a
   36 minute window, so they carried seven different clocks and several yellow
   Low Power Mode batteries. Rather than fake a marketing status bar, the top
   132px is filled per column with the app's own background sampled from the
   first clean row below it. That is what the app actually draws up there, so
   the result reads as a real screen and the template's Dynamic Island sits on
   it naturally.
2. **The debris under the floating tab bar is removed.** Elemora's tab bar floats
   over a scrolling list, so most captures end in a sliver of a half cut row. The
   band below the pill is refilled from the row just under it and faded into the
   page background over 58px, which keeps the bar's own shadow and drops the
   fragment.

Everything between those two bands is compared byte for byte before the file is
written, and the script exits rather than write a capture whose app content it
changed. It never edits in place and is safe to re-run.

```sh
python3 screenshots/prepare.py
```

To swap in a new capture, drop it in `screenshots/raw/`, point its row in
`PLAN` at the new filename, re-run `prepare.py`, then re-run the compositor.

### Inserting a capture

The compositor works straight from a fresh clone; each frame carries its own
geometry, so no build products are needed.

```sh
cd marketing/app-store
python3 place_screenshot.py --all                         # everything in selected/
python3 place_screenshot.py 01 screenshots/selected/01-periodic-table.png
python3 place_screenshot.py hero screenshots/selected/01-periodic-table.png   # slug works too
python3 place_screenshot.py 03 screenshots/selected/03-build-caffeine.png
python3 place_screenshot.py 02 --main oxygen.png --build caffeine.png        # or by role
```

Output overwrites `exports/iphone/NN-slug.png`. `--all` matches files in
`screenshots/selected/` to device slots by their `NN-` prefix and role word, and
lists any device it could not fill.

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
carry more than one device, three carry one. Tilts stay between 0 and 6 degrees
and are rigid 2D rotations of the whole device group, never a perspective
homography, which is why a real screenshot follows the bezel exactly. The QA pass
fingerprints each frame by device count, scale band, horizontal placement and
rotation, and fails if the six do not produce at least five distinct signatures.
It also fails if any frame's largest device drops below 63 percent of the canvas
width, because the product has to stay the hero.

**Background hierarchy.** Every frame carries exactly one anchor motif at 8 to 10
percent and one to three supporting marks at 2 to 4 percent, with at most five
marks in total. The single exception is frame 03's molecular formula at 5.5
percent, which is deliberately the clearest supporting detail in the set. The build records the
inventory into each frame's geometry file and the QA pass enforces those bands,
so no frame can drift back into uniformly faint wallpaper. The anchors are sized
to pass *behind* the devices and surface again on the far side: a naphthalene ring
system straddling frame 01's left bezel, an aromatic ring system entering frame
05 from the top right, an iron shell diagram wider than the phone in frame 04, a
caffeine skeleton centred on frame 03's device, and period 1-4 table fragments
sliding under frames 02 and 06. Frame 02's fragment also dissolves toward the
middle of the slide, so it reads as atmosphere rather than a band of squares. Frame 02's fragment also
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
node source/generator/build.mjs             # all six frames, assets and sheets
python3 place_screenshot.py --all           # put the real screens back in
node source/generator/build.mjs --sheets    # refresh the sheets from the exports
python3 source/generator/verify.py          # full QA sweep
```

> A full `build.mjs` run writes **empty** templates over `exports/iphone/`, so it
> must be followed by `place_screenshot.py --all` or the deliverables lose their
> screenshots. `--sheets` skips the build entirely and only rebuilds the contact
> sheets, the gallery and the pair views from whatever is in `exports/iphone/`;
> that is the safe way to refresh a sheet once the captures are in.

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
  percent or below, something at 4 percent or below, no single mark above 11
  percent, and no more than five decorative marks
- no fabricated app UI: the templates carry labelled screenshot slots, never drawn
  Elemora interface, and a marker capture pushed through the real compositor leaves
  zero pixels outside the device silhouettes on any frame
- no 3D ball-and-stick renderer or assets
- chemistry: derived formulas match their labels, no over-valent atoms, uniform
  bond lengths, shells sum to Z, weights match reference data, equations balance

Current state: **519 checks, 0 failures, 0 warnings.**

## Relationship to CoreCredit

The structure follows `BKimble1/corecredit-appstore`: layered frames, one
`geometry.json` per frame, a `place_screenshot.py` compositor, SVG masters
rasterised through Chromium, a QA script that proves the invariants, and the same
appetite for varied device arrangements including overlapping phones. The visual
language deliberately does not: CoreCredit is a dark royal-blue financial
campaign, Elemora is near-white paper, pale chemistry blues, deep navy type and
skeletal linework.
