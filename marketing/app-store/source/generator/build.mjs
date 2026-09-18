/* ============================================================================
   Elemora — build the whole App Store campaign.

       node source/generator/build.mjs

   For every frame this writes, from one definition:

     source/template-NN-slug.svg            editable vector master
     source/template-NN-slug.geometry.json  device placement, read by the compositor
     source/template-NN-slug.placement.txt  the same placement, for a human
     assets/backgrounds/NN-slug.png         layer 1 (opaque)
     assets/device/NN-slug-overlay.png      layer 3 (RGBA, real hole in the screen)
     exports/iphone/NN-slug.png             the finished template, flattened to RGB

   Plus the standalone decoration assets under assets/, and a contact sheet.
   ========================================================================== */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

import {
  CANVAS, MARGIN, COL_W, TYPE, C, P, n,
  stdDevice, deviceBounds, copyBlock, composeFrame, svgDoc, baseDefs,
} from './system.mjs';
import {
  deco, molecule, elementTile, bohr, orbits, skeletalBenzene, lattice,
  periodicFragment, formula, MOLECULES, ELEMENTS, EQUATIONS,
} from './chemistry.mjs';
import { rasterize } from './render.mjs';
import { measureCopy } from './measure.mjs';
import { FRAMES } from './frames/index.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');            // marketing/app-store
const p = (...a) => path.join(ROOT, ...a);
const write = (f, s) => { fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f, s); };

/** App Store uploads must not carry an alpha channel. */
function flatten(file) {
  execFileSync('python3', ['-c',
    'import sys;from PIL import Image;' +
    'im=Image.open(sys.argv[1]);' +
    'bg=Image.new("RGB",im.size,(255,255,255));' +
    'bg.paste(im,mask=im.split()[3] if im.mode=="RGBA" else None);' +
    'bg.save(sys.argv[1])', file], { stdio: ['ignore', 'ignore', 'pipe'] });
}

/* ------------------------------------------------------------- placement -- */

function placementText(f, d, cp, m) {
  const b = deviceBounds(d);
  const off = (v) => (v > 0 ? `${v.toFixed(1)}px` : 'none');
  return `Elemora — App Store image ${f.id}  (${f.slug})
${f.headline.join(' ')}
Production placement data — measured from the finished composition. Pixels.

CANVAS
  W = ${CANVAS.W}
  H = ${CANVAS.H}

DEVICE
  X        = ${n(d.x)}          (unrotated top-left)
  Y        = ${n(d.y)}
  W        = ${n(d.w)}
  H        = ${n(d.h)}
  Rotation = ${n(d.rot)} deg    (about the device centre, ${n(d.cx)}, ${n(d.cy)})
  Centre   = ${n(d.cx)}, ${n(d.cy)}
  Corner radius   = ${n(d.r)}
  Bezel thickness = ${n(d.bezel)} on every side
  Scale vs the ${888}px campaign base opening = ${n(d.scale)}

DEVICE ROTATED BOUNDING BOX
  Left = ${n(b.minX)}   Top = ${n(b.minY)}
  Right = ${n(b.maxX)}  Bottom = ${n(b.maxY)}
  Off-canvas left   = ${off(-b.minX)}
  Off-canvas right  = ${off(b.maxX - CANVAS.W)}
  Off-canvas bottom = ${off(b.maxY - CANVAS.H)}

SCREENSHOT  (place the real ${CANVAS.W}x${CANVAS.H} Elemora capture here)
  Wanted screen = ${f.label}
  ${f.need}

  Centre X      = ${n(d.screen.cx)}
  Centre Y      = ${n(d.screen.cy)}
  Unrotated W   = ${n(d.screen.w)}
  Unrotated H   = ${n(d.screen.h)}
  Rotation      = ${n(d.rot)} deg  (identical to the device — one rigid group)
  Unrotated X,Y = ${n(d.screen.x)}, ${n(d.screen.y)}   (top-left before rotation)
  Corner radius = ${n(d.screen.r)}   (the overlay rounds this for you)

  Aspect ratio = ${(d.screen.w / d.screen.h).toFixed(16)}
  Required     = ${CANVAS.W} / ${CANVAS.H} = ${(CANVAS.W / CANVAS.H).toFixed(16)}
  Delta        = ${Math.abs(d.screen.w / d.screen.h - CANVAS.W / CANVAS.H).toExponential(3)}
  Uniform scale of the source screenshot = ${(d.screen.w / CANVAS.W).toFixed(10)}
  NEVER scale X and Y independently, and never rotate the screenshot separately
  from the bezel — set the size first, then apply the single rotation above.

SCREENSHOT AS CANVAS PERCENTAGES (unrotated box)
  Left = ${(100 * d.screen.x / CANVAS.W).toFixed(4)}%   Top = ${(100 * d.screen.y / CANVAS.H).toFixed(4)}%
  Width = ${(100 * d.screen.w / CANVAS.W).toFixed(4)}%  Height = ${(100 * d.screen.h / CANVAS.H).toFixed(4)}%

TYPOGRAPHY
  Family     = Inter (latin variable, embedded in the SVG)
  Headline   = ${cp.headSize}px / ${TYPE.headLead}px, weight ${TYPE.headWeight}, tracking ${TYPE.headTrack}px
  Supporting = ${cp.subSize}px / ${TYPE.subLead}px, weight ${TYPE.subWeight}, ${C.inkSoft} at ${TYPE.subOpacity}
  Left margin = ${MARGIN}px  (column ${COL_W}px)
  Headline cap-top y = ${n(cp.capTop)}   Supporting baseline y = ${n(cp.subBaseline)}
  Measured headline widths = ${m.head.map((w) => w.toFixed(1)).join(', ')}
  Measured supporting widths = ${m.sub.map((w) => w.toFixed(1)).join(', ')}
  Widest line vs column = ${Math.max(m.maxHead, m.maxSub).toFixed(1)} / ${COL_W}

COPY
  Headline   = ${f.headline.map((s) => JSON.stringify(s)).join(' + ')}
  Supporting = ${f.sub.map((s) => JSON.stringify(s)).join(' + ')}

LAYER ORDER (bottom to top)
  1. assets/backgrounds/${f.id}-${f.slug}.png       — ${CANVAS.W}x${CANVAS.H}, opaque
  2. your real Elemora screenshot — sized + rotated exactly as above
  3. assets/device/${f.id}-${f.slug}-overlay.png    — ${CANVAS.W}x${CANVAS.H}, transparent screen

  python3 place_screenshot.py ${f.id} screenshots/selected/<capture>.png
`;
}

/* ----------------------------------------------------------------- frames -- */

function buildFrame(f) {
  const d = stdDevice(f.device || {});
  const cp = copyBlock({
    lines: f.headline, sub: f.sub,
    top: f.copy.top, align: f.copy.align, x: f.copy.x ?? MARGIN,
    headSize: f.copy.headSize, subSize: f.copy.subSize,
  });
  const m = measureCopy(f, COL_W);

  /* Hard guarantees before anything is drawn. */
  const widest = Math.max(m.maxHead, m.maxSub);
  if (widest > COL_W) {
    throw new Error(`${f.id}: copy is ${widest.toFixed(1)}px wide, column is ${COL_W}px`);
  }
  if (cp.bottom > d.y - 40) {
    throw new Error(`${f.id}: copy bottom ${cp.bottom.toFixed(1)} collides with device top ${d.y.toFixed(1)}`);
  }

  const D = deco();
  const decoSvg = f.deco ? f.deco(D, d) : '';
  const out = composeFrame({
    title: f.title, dev: d, copy: cp, light: f.light,
    deco: `\n  <g id="Chemistry-Decoration">\n${decoSvg}\n  </g>`,
    decoDefs: D.defs(), label: f.label,
  });

  const stem = `template-${f.id}-${f.slug}`;
  write(p('source', `${stem}.svg`), out.master);

  const geom = {
    id: f.id, slug: f.slug, label: f.label, need: f.need,
    headline: f.headline, sub: f.sub,
    canvasW: CANVAS.W, canvasH: CANVAS.H, margin: MARGIN,
    deviceX: d.x, deviceY: d.y, deviceW: d.w, deviceH: d.h, deviceR: d.r,
    deviceCX: d.cx, deviceCY: d.cy, rot: d.rot, bezel: d.bezel, scale: d.scale,
    screenX: d.screen.x, screenY: d.screen.y, screenW: d.screen.w, screenH: d.screen.h,
    screenR: d.screen.r, screenCX: d.screen.cx, screenCY: d.screen.cy,
    uniformScale: d.screen.w / CANVAS.W,
    background: `assets/backgrounds/${f.id}-${f.slug}.png`,
    overlay: `assets/device/${f.id}-${f.slug}-overlay.png`,
    output: `exports/iphone/${f.id}-${f.slug}.png`,
    bounds: deviceBounds(d),
    copyTop: cp.capTop, copyBottom: cp.bottom, copyX: cp.x,
  };
  write(p('source', `${stem}.geometry.json`), JSON.stringify(geom, null, 1) + '\n');
  write(p('source', `${stem}.placement.txt`), placementText(f, d, cp, m));

  const bg = p('assets', 'backgrounds', `${f.id}-${f.slug}.png`);
  const ov = p('assets', 'device', `${f.id}-${f.slug}-overlay.png`);
  const ex = p('exports', 'iphone', `${f.id}-${f.slug}.png`);
  rasterize(out.background, bg, CANVAS.W, CANVAS.H);
  rasterize(out.overlay, ov, CANVAS.W, CANVAS.H);
  rasterize(out.master, ex, CANVAS.W, CANVAS.H);
  flatten(bg);
  flatten(ex);

  console.log(`  ${f.id} ${f.slug.padEnd(15)} device ${n(d.w)}x${n(d.h)} @ ${n(d.rot)}deg   ` +
              `copy ${widest.toFixed(0)}/${COL_W}px   screen ${n(d.screen.w)}x${n(d.screen.h)}`);
  return geom;
}

/* ------------------------------------------------- standalone deco assets -- */

function asset(name, body, D, w, h) {
  const svg = `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">
  <defs>
    <style type="text/css"><![CDATA[text{font-family:'Inter','Segoe UI',Arial,sans-serif}]]></style>
${D ? D.defs() : ''}
  </defs>
${body}
</svg>
`;
  write(p('assets', name), svg);
}

function buildAssets() {
  const slug = { water: 'water-h2o', carbonDioxide: 'carbon-dioxide-co2', methane: 'methane-ch4',
    ammonia: 'ammonia-nh3', ethane: 'ethane-c2h6', benzene: 'benzene-c6h6',
    dioxygen: 'dioxygen-o2', dinitrogen: 'dinitrogen-n2' };
  const view = { water: [-10, 24, -6], carbonDioxide: [-12, 26, 12], methane: [-16, 30, 6],
    ammonia: [-24, 20, -8], ethane: [-18, 38, -16], benzene: [-54, 16, 12],
    dioxygen: [0, 20, -18], dinitrogen: [0, 20, 14] };
  for (const key of Object.keys(MOLECULES)) {
    const D = deco();
    const S = 420, sc = key === 'benzene' ? 66 : key === 'ethane' ? 78 : 118;
    const [rx, ry, rz] = view[key];
    const body = molecule(D, key, { cx: S / 2, cy: S / 2, scale: sc, rx, ry, rz });
    asset(`molecules/${slug[key]}.svg`, body, D, S, S);
  }
  for (const sym of ['H', 'C', 'N', 'O', 'Na', 'Cl', 'Fe', 'He', 'Ne', 'Si', 'Ca', 'Au']) {
    const w = 260, h = w * 1.16;
    asset(`element-tiles/${ELEMENTS[sym].z}-${sym.toLowerCase()}.svg`,
      elementTile(sym, { x: 8, y: 8, w: w - 16, variant: 'soft', opacity: 1 }), null, w, h + 16);
  }
  for (const sym of ['H', 'C', 'N', 'O', 'Na', 'Cl', 'Ne', 'Fe']) {
    const S = 560;
    asset(`orbital/bohr-${sym.toLowerCase()}.svg`,
      bohr(sym, { cx: S / 2, cy: S / 2, r: S * 0.44, opacity: 1, label: true }), null, S, S);
  }
  asset('orbital/orbit-rings.svg', orbits({ cx: 300, cy: 300, r: 260, opacity: 1 }), null, 600, 600);
  asset('orbital/graphene-lattice.svg',
    lattice({ x: 40, y: 40, cols: 6, rows: 6, a: 70, opacity: 1, width: 5 }), null, 840, 740);
  asset('orbital/periodic-fragment.svg',
    periodicFragment({ x: 10, y: 10, cell: 44, gap: 7, opacity: 1 }), null, 940, 230);
  asset('molecules/skeletal-benzene-aromatic.svg',
    skeletalBenzene({ cx: 220, cy: 220, r: 170, opacity: 1, width: 9, mode: 'aromatic' }), null, 440, 440);
  asset('molecules/skeletal-benzene-kekule.svg',
    skeletalBenzene({ cx: 220, cy: 220, r: 170, opacity: 1, width: 9, mode: 'kekule' }), null, 440, 440);
  const eq = { 'combustion-hydrogen': EQUATIONS.combustionH2, 'combustion-methane': EQUATIONS.combustionCH4,
    'haber-process': EQUATIONS.haber, 'sodium-chloride': EQUATIONS.saltFormation };
  for (const [name, text] of Object.entries(eq)) {
    asset(`formulas/${name}.svg`,
      formula(text, { x: 20, y: 86, size: 72, opacity: 1, fill: C.ink }), null, 1100, 120);
  }
  for (const [name, text] of Object.entries({ water: 'H2O', 'carbon-dioxide': 'CO2',
    methane: 'CH4', benzene: 'C6H6', 'sodium-chloride': 'NaCl', ammonia: 'NH3',
    dioxygen: 'O2', dinitrogen: 'N2' })) {
    asset(`formulas/formula-${name}.svg`,
      formula(text, { x: 16, y: 96, size: 96, opacity: 1, fill: C.ink }), null, 420, 130);
  }
  console.log('  decoration assets written to assets/');
}

/* ----------------------------------------------------------- contact sheet */

function contactSheet(geoms) {
  const files = geoms.map((g) => p(g.output));
  execFileSync('python3', ['-c', `
import sys
from PIL import Image
files = sys.argv[1:-1]
out = sys.argv[-1]
cols, rows, pad = 4, 2, 26
tw, th = 462, 1004
sheet = Image.new('RGB', (cols*tw + pad*(cols+1), rows*th + pad*(rows+1)), (14, 20, 32))
for i, f in enumerate(files):
    im = Image.open(f).convert('RGB').resize((tw, th), Image.LANCZOS)
    c, r = i % cols, i // cols
    sheet.paste(im, (pad + c*(tw+pad), pad + r*(th+pad)))
sheet.save(out)
`, ...files, p('exports', 'contact-sheet.png')], { stdio: ['ignore', 'inherit', 'pipe'] });

  execFileSync('python3', ['-c', `
import sys
from PIL import Image
files = sys.argv[1:-1]
out = sys.argv[-1]
cols, pad = 8, 12
tw, th = 168, 365
sheet = Image.new('RGB', (cols*tw + pad*(cols+1), th + pad*2), (244, 247, 251))
for i, f in enumerate(files):
    im = Image.open(f).convert('RGB').resize((tw, th), Image.LANCZOS)
    sheet.paste(im, (pad + i*(tw+pad), pad))
sheet.save(out)
`, ...files, p('exports', 'contact-sheet-thumbnail.png')], { stdio: ['ignore', 'inherit', 'pipe'] });
  console.log('  contact sheets written to exports/');
}

/* ------------------------------------------------------------------- main -- */

console.log(`Elemora App Store build — ${CANVAS.W} x ${CANVAS.H}, ${FRAMES.length} frames`);
const geoms = FRAMES.map(buildFrame);
buildAssets();
contactSheet(geoms);
write(p('source', 'frames.json'), JSON.stringify(geoms, null, 1) + '\n');
console.log('done.');
void P;
