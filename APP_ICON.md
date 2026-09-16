# App icon

## The mark

Eight teal periodic-table tiles stepping up to a single gold one. It is an
abstract fragment of the table rather than a picture of it: the step reads as
progress, and the one gold tile is the element you are looking at.

The artwork is original, supplied as finished art, and contains no text, no
element symbol (which would privilege one element over the rest), and nothing
resembling another company's mark. The silhouette is solid geometry, so it
survives being shrunk to a Spotlight row.

## Files

```
Design/AppIconSource.png                      # the artwork — the design itself
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

## Regenerating

```bash
python3 -m pip install pillow
python3 Tools/make_app_icon.py
```

`Design/AppIconSource.png` is the source of truth for the *design*.
`Tools/make_app_icon.py` is only the packaging step: it copies the source out as
the light appearance and repaints it into the other two. It never moves, resizes
or re-composes the tiles, so the three appearances are guaranteed to be the same
mark.

The repaint works by measuring each pixel's distance from the source's
background color. Pixels at the background are the field, pixels far from it are
tile, and the ramp in between is what keeps the rounded corners smooth after
recoloring. Gold and teal are told apart by whether red exceeds blue. Every
color is a named constant in the `VARIANTS` table near the bottom of the file.

## The three appearances

**Light** — the artwork exactly as supplied: teal tiles and one gold tile on a
warm off-white field.

**Dark** — the same tiles on a deep neutral field, with both tile colors lifted
a step. It is *not* the light icon inverted; the teal that reads as ink against
off-white is too close to the field once the field goes dark, so it is
brightened until the tiles separate again.

**Tinted** — grayscale only. iOS maps luminance onto the tint the user picked,
so the tiles are light and the field near-black. The gold tile stays a step
brighter than the rest, which is the only way the mark's one accent survives the
loss of hue. Do not add color to this variant; it will be discarded.

## If you want to redraw it

The constraints worth keeping:

- One idea. Tiles, a step, one highlighted. Nothing else competes.
- Keep the mark centered. It currently spans about half the canvas width, which
  is the framing the artwork was supplied with; nothing in the pipeline changes
  it, and nothing depends on it either, so a redraw is free to fill more.
- Keep the tile corner radius proportional, so it reads as the same object as
  `ElementTile` in the app.
- Flat color. Cheap-looking gradients are the fastest way to make an icon look
  generic, and this mark does not use any.
- Test at 29pt before committing. If the individual tiles merge into a blob at
  that size, the gaps are too tight.

Replace `Design/AppIconSource.png` with a 1024×1024 RGB PNG, update `FIELD`,
`TEAL` and `GOLD` in `Tools/make_app_icon.py` to whatever the new artwork is
drawn in, and rerun the script.

## Checklist before uploading

- [ ] All three PNGs are exactly 1024×1024
- [ ] No alpha channel (`sips -g hasAlpha AppIcon-1024.png` reports `no`)
- [ ] sRGB color profile
- [ ] No transparency, no rounded corners baked in, no drop shadow outside the square
- [ ] `ASSETCATALOG_COMPILER_APPICON_NAME` is `AppIcon` (set in the target build settings)
