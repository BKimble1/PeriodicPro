# App icon

## The mark

A single periodic-table tile, with one electron orbit sweeping behind it and a
nucleus at its center. Two electrons sit on the orbit where it passes outside
the tile.

It is deliberately reductive: at 60 points on a Home Screen the shapes still
separate cleanly, and at 29 points in Settings the tile silhouette alone is
recognisable. The tile echoes `ElementTile`, the component the whole app is
built around, and the accent blue is the same `AppColor.accent` used for every
interactive element.

The artwork is original. It contains no text, no element symbol (which would
privilege one element over the rest), and nothing resembling another company's
mark.

## Files

```
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

`Tools/make_app_icon.py` is the source of truth. It renders at 4× and
downsamples with Lanczos, so the curves stay clean without any hand-retouching.
Every color, radius and stroke width is a named constant near the bottom of the
file in the `VARIANTS` table.

## The three appearances

**Light** — accent-blue gradient field, off-white tile, blue nucleus, white
electrons. Matches the app's light-first visual direction.

**Dark** — deep navy field so the icon keeps weight against a dark Home Screen
wallpaper, with a brighter blue tile and a white nucleus. It is *not* the light
icon inverted; the tile and field swap roles so contrast is preserved.

**Tinted** — grayscale only. iOS maps luminance onto the tint the user picked,
so the tile is light (it takes the tint) and the nucleus is punched out dark.
The field is near-black so the mark reads as a silhouette. Do not add color to
this variant; it will be discarded.

## If you want to redraw it

The constraints worth keeping:

- One idea. A tile and an orbit. Nothing else competes for attention.
- Keep the 1024px safe area: the mark occupies the middle ~80%, because iOS
  rounds the corners and widgets crop further.
- Keep the tile's corner radius proportional (currently 26.5% of the tile) so it
  reads as the same object as `ElementTile` in the app.
- No gradients steeper than about two stops. Cheap-looking gradients are the
  fastest way to make an icon look generic.
- Test at 29pt before committing. If the electrons disappear at that size, they
  are too small — but the tile silhouette must still carry the icon.

## Checklist before uploading

- [ ] All three PNGs are exactly 1024×1024
- [ ] No alpha channel (`sips -g hasAlpha AppIcon-1024.png` reports `no`)
- [ ] sRGB color profile
- [ ] No transparency, no rounded corners baked in, no drop shadow outside the square
- [ ] `ASSETCATALOG_COMPILER_APPICON_NAME` is `AppIcon` (set in the target build settings)
