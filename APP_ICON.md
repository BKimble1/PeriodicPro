# App icon

## The mark

Eight teal periodic-table tiles stepping up to a single gold one. It is an
abstract fragment of the table rather than a picture of it: the step reads as
progress, and the one gold tile is the element you are looking at.

The artwork is original, contains no text, no element symbol (which would
privilege one element over the rest), and nothing resembling another company's
mark. The silhouette is solid geometry, so it survives being shrunk to a
Spotlight row.

## Files

```
Tools/make_app_icon.py                        # the design — geometry, not a raster
Design/AppIconSource.png                      # the light appearance, for humans
Design/AppIconPreview.png                     # the mark at real Home Screen sizes
PeriodicPro/Assets.xcassets/AppIcon.appiconset/
├── Contents.json
├── AppIcon-1024.png          # light / default
├── AppIcon-1024-Dark.png     # dark appearance
└── AppIcon-1024-Tinted.png   # tinted appearance (grayscale)
```

iOS 18 and later use a **single 1024×1024 image per appearance**; the system
generates every smaller size. There is no need for the old ladder of 20pt/29pt/
40pt/60pt assets, and adding them back would only bloat the bundle.

The rounded-corner mask is applied by iOS. All three PNGs are full-bleed squares
with square corners and **no alpha channel**, which is what App Store Connect
requires — an icon with transparency is rejected at upload.

## Why it was blurry, and what changed

The first icon was supplied as finished raster artwork and looked soft on a
real Home Screen. Three things were wrong with it, none of them visible at
1024 pixels:

- **The mark was small.** It spanned 51% of the canvas. At 60 points on an
  iPhone a tile was 21 pixels wide and the gaps between tiles were under two
  pixels — one downsample away from disappearing.
- **The grid was uneven.** Horizontal gaps of 11, 11 and 12 units; vertical
  gaps of 15 and 16. No tile edge landed on a pixel boundary at any size iOS
  renders, so every edge was a half-covered pixel in both directions.
- **It had grain.** A paper texture on the field and the tiles (6,730 distinct
  colors in what should be a three-color image). iOS's own downsampler turns
  texture into a mottled, soft edge.

The mark is now **defined as geometry** in `Tools/make_app_icon.py`: four
columns by three rows on a 1024-unit canvas, tile 144, gap 20, pitch 164, with
continuous (superellipse) corners at 22% of the tile — the same ratio
`ElementTileShape` uses in the app. Every coordinate is an even integer. The
mark is 636 × 472, centered, so it fills 62% of the canvas width: inside
Apple's safe zone for a masked icon, and half again as large on the Home Screen.

It is rendered once at **4096 × 4096 with no antialiasing**, then downsampled
**exactly once** to 1024 × 1024 with a box filter — the exact area average of
sixteen samples per pixel, which is the correct antialiasing for flat color
and adds no ringing, glow or blur. There is no Gaussian step, no grain, and
nothing is ever resized up from a smaller raster.

## Regenerating

```bash
python3 -m pip install pillow
python3 Tools/make_app_icon.py
```

The script writes all three appearances, the human-readable source preview and
`Design/AppIconPreview.png`, which shows the light and dark icons at the pixel
sizes iOS actually draws (60pt at 3× and 2×, 40pt, 29pt at 3× and 2×, and the
iPad sizes) under the Home Screen mask. Look at that file before committing.

## The three appearances

**Light** — teal tiles and one gold tile on a warm off-white field.

**Dark** — the same tiles on a deep neutral field, with both tile colors lifted
a step. It is *not* the light icon inverted; the teal that reads as ink against
off-white is too close to the field once the field goes dark, so it is
brightened until the tiles separate again.

**Tinted** — grayscale only. iOS maps luminance onto the tint the user picked,
so the tiles are light and the field near-black. The gold tile stays a step
brighter than the rest, which is the only way the mark's one accent survives the
loss of hue. Do not add color to this variant; it will be discarded.

All three come from the same geometry, so they are guaranteed to be the same
mark. Only the palette differs.

## If you want to redraw it

The constraints worth keeping:

- One idea. Tiles, a step, one highlighted. Nothing else competes.
- Keep it geometry. Change the numbers at the top of `make_app_icon.py`
  rather than painting a raster; the checker below will refuse anything that
  did not come through the pipeline.
- Keep every coordinate an even integer, so the 4× master lands edges on
  sample boundaries.
- Keep the tile corner radius proportional, so it reads as the same object as
  `ElementTile` in the app.
- Flat color. Cheap-looking gradients are the fastest way to make an icon look
  generic, and this mark does not use any.
- Look at `Design/AppIconPreview.png` at 29pt before committing. If the tiles
  merge into a blob at that size, the gaps are too tight.

## What is checked automatically

`Tools/check_app_icon.py` runs in `Tools/verify.sh` and in CI. It decodes the
PNGs by hand — no Pillow, so it works on a bare CI image — and fails if:

- an appearance is missing from `Contents.json`, or declared with the wrong one;
- any PNG is not exactly 1024×1024;
- any PNG is not truecolor, carries a `tRNS` chunk (transparency by another
  name) or embeds an ICC profile. App Store Connect rejects an icon with an
  alpha channel, and it does so after the archive, sign and export have
  already run;
- any PNG lacks the `elemora:master-size` record the generator writes, or was
  rendered from a master under 2048 units — which is to say it was upscaled,
  or did not come through the pipeline at all;
- the edges are soft: on every fourth scanline it measures the run of
  intermediate pixels between two flat colors, and requires the typical edge
  to be one pixel wide with nine in ten within three. A Gaussian blur, a
  resize from a smaller raster, or a glow around the tiles widens every edge
  and fails this; a rounded corner crossing a scanline at a shallow tangent is
  the small minority the percentile allows for;
- the field is not one flat color in all four corners (grain);
- more than 512 distinct colors appear (grain, noise or a gradient);
- `ASSETCATALOG_COMPILER_APPICON_NAME` is no longer `AppIcon`, which would ship
  a build with no icon at all.

The check was proved against three bad inputs when it was written: a Gaussian
blur of the real icon (typical edge 6 px), a 256-pixel copy scaled back up
(typical edge 14 px) and the original raster (no pipeline record).

Left to a human, because it is not mechanically decidable:

- [ ] It still reads at 29pt — see `Design/AppIconPreview.png`
- [ ] The compiled app's icon on the simulator Home Screen is razor-sharp. The
      screenshot tour captures it (`14-home-screen-icon`) so it can be
      compared against the system icons beside it.
