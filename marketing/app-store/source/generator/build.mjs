/* ============================================================================
   Elemora, build the whole App Store campaign.

       node source/generator/build.mjs

   For every frame this writes, from one definition:

     source/template-NN-slug.svg            editable vector master
     source/template-NN-slug.geometry.json  device placement, read by the compositor
     source/template-NN-slug.placement.txt  the same placement, for a human
     assets/backgrounds/NN-slug.png         layer 1 (opaque)
     assets/device/NN-slug-overlay*.png     device chrome (RGBA, real hole in the screen)
     exports/iphone/NN-slug.png             the finished template, flattened to RGB

   Plus the standalone decoration assets under assets/, and a contact sheet.
   ========================================================================== */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

import {
  CANVAS, MARGIN, COL_W, TYPE, C, n,
  deviceGeom, deviceBounds, copyBlock, composeFrame, SFX,
} from './system.mjs';
import {
  deco, skeletal, elementTile, bohr, orbits, lattice,
  periodicFragment, formula, SKELETAL, ELEMENTS, EQUATIONS,
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

function placementText(f, devices, cp, m) {
  const off = (v) => (v > 0 ? `${v.toFixed(1)}px` : 'none');
  const blocks = devices.map((d, i) => {
    const spec = f.devices[i];
    const b = deviceBounds(d);
    return `
DEVICE ${i + 1} of ${devices.length}   role = ${spec.role}   layer = ${i === 0 ? 'backmost' : 'in front of device ' + i}
  Wanted screen = ${spec.label}
  ${spec.need}

  X        = ${n(d.x)}          (unrotated top-left)
  Y        = ${n(d.y)}
  W        = ${n(d.w)}
  H        = ${n(d.h)}
  Rotation = ${n(d.rot)} deg    (about the device centre, ${n(d.cx)}, ${n(d.cy)})
  Corner radius   = ${n(d.r)}
  Bezel thickness = ${n(d.bezel)} on every side

  ROTATED BOUNDING BOX
    Left = ${n(b.minX)}   Top = ${n(b.minY)}   Right = ${n(b.maxX)}   Bottom = ${n(b.maxY)}
    Off-canvas left ${off(-b.minX)}, right ${off(b.maxX - CANVAS.W)}, bottom ${off(b.maxY - CANVAS.H)}

  SCREENSHOT  (place the real ${CANVAS.W}x${CANVAS.H} capture here)
    Centre        = ${n(d.screen.cx)}, ${n(d.screen.cy)}
    Unrotated X,Y = ${n(d.screen.x)}, ${n(d.screen.y)}
    Unrotated W,H = ${n(d.screen.w)} x ${n(d.screen.h)}
    Rotation      = ${n(d.rot)} deg  (identical to the device, one rigid group)
    Corner radius = ${n(d.screen.r)}   (the overlay rounds this for you)
    Aspect ratio  = ${(d.screen.w / d.screen.h).toFixed(16)}
    Required      = ${CANVAS.W} / ${CANVAS.H} = ${(CANVAS.W / CANVAS.H).toFixed(16)}
    Delta         = ${Math.abs(d.screen.w / d.screen.h - CANVAS.W / CANVAS.H).toExponential(3)}
    Uniform scale of the source screenshot = ${(d.screen.w / CANVAS.W).toFixed(10)}
    NEVER scale X and Y independently, and never rotate the screenshot
    separately from the bezel. Set the size first, then apply the rotation.`;
  }).join('\n');

  const layers = ['  1. ' + `assets/backgrounds/${f.id}-${f.slug}.png` +
                  `      ${CANVAS.W}x${CANVAS.H}, opaque`];
  devices.forEach((d, i) => {
    layers.push(`  ${2 + i * 2}. your real capture for device ${i + 1} (${f.devices[i].label})`);
    layers.push(`  ${3 + i * 2}. ${overlayPath(f, i, devices.length)}   RGBA, transparent screen`);
  });

  return `Elemora, App Store image ${f.id}  (${f.slug})
${f.headline.join(' ')}
Production placement data, measured from the finished composition. Pixels.

CANVAS
  W = ${CANVAS.W}
  H = ${CANVAS.H}
  Devices = ${devices.length}
${blocks}

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
${layers.join('\n')}

  python3 place_screenshot.py ${f.id} ${f.devices.map((s) => '<' + s.role + '>.png').join(' ')}
`;
}

function overlayPath(f, i, total) {
  const suffix = total === 1 ? 'overlay' : `overlay-${f.devices[i].role}`;
  return `assets/device/${f.id}-${f.slug}-${suffix}.png`;
}

/* ----------------------------------------------------------------- frames -- */

function buildFrame(f) {
  const devices = f.devices.map((s) =>
    deviceGeom({ screenW: s.screenW, x: s.x, y: s.y, rot: s.rot || 0 }));
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
  const topMost = Math.min(...devices.map((d) => deviceBounds(d).minY));
  if (cp.bottom > topMost - 40) {
    throw new Error(`${f.id}: copy bottom ${cp.bottom.toFixed(1)} collides with the ` +
                    `topmost device edge ${topMost.toFixed(1)}`);
  }
  for (const line of [...f.headline, ...f.sub]) {
    if (line.includes('\u2014')) throw new Error(`${f.id}: em dash in marketing copy: ${line}`);
  }

  const D = deco();
  const decoItems = f.deco ? f.deco(D) : [];
  const decoSvg = decoItems.join('\n');
  const inventory = decoItems.map((svg) => {
    const kind = (svg.match(/id="([A-Za-z-]+?)[-"]/) || [, 'Formula'])[1];
    const op = svg.match(/\sopacity="([\d.]+)"/) || svg.match(/fill-opacity="([\d.]+)"/);
    return { kind, opacity: op ? Number(op[1]) : 1 };
  }).sort((a, c2) => c2.opacity - a.opacity);
  const out = composeFrame({
    title: f.title, devices, copy: cp, light: f.light,
    deco: `\n  <g id="Chemistry-Decoration">\n${decoSvg}\n  </g>`,
    decoDefs: D.defs(),
    labels: f.devices.map((s) => ({ text: s.label, dx: s.labelDX || 0, dy: s.labelDY || 0, hide: !!s.hideLabel })),
    glow: f.devices.map((s, i) => (s.glow === undefined ? i === 0 : s.glow)),
  });

  const stem = `template-${f.id}-${f.slug}`;
  write(p('source', `${stem}.svg`), out.master);

  const geom = {
    id: f.id, slug: f.slug, headline: f.headline, sub: f.sub,
    canvasW: CANVAS.W, canvasH: CANVAS.H, margin: MARGIN,
    deviceCount: devices.length,
    devices: devices.map((d, i) => ({
      role: f.devices[i].role, label: f.devices[i].label, need: f.devices[i].need,
      bleed: !!f.devices[i].bleed, masterX: f.devices[i].masterX,
      sfx: SFX[i],
      x: d.x, y: d.y, w: d.w, h: d.h, r: d.r, rot: d.rot,
      cx: d.cx, cy: d.cy, bezel: d.bezel, scale: d.scale,
      screenX: d.screen.x, screenY: d.screen.y, screenW: d.screen.w, screenH: d.screen.h,
      screenR: d.screen.r, screenCX: d.screen.cx, screenCY: d.screen.cy,
      uniformScale: d.screen.w / CANVAS.W,
      bounds: deviceBounds(d),
      overlay: overlayPath(f, i, devices.length),
    })),
    background: `assets/backgrounds/${f.id}-${f.slug}.png`,
    output: `exports/iphone/${f.id}-${f.slug}.png`,
    copyTop: cp.capTop, copyBottom: cp.bottom, copyX: cp.x,
    decoration: inventory,
  };
  write(p('source', `${stem}.geometry.json`), JSON.stringify(geom, null, 1) + '\n');
  write(p('source', `${stem}.placement.txt`), placementText(f, devices, cp, m));

  const bg = p('assets', 'backgrounds', `${f.id}-${f.slug}.png`);
  const ex = p('exports', 'iphone', `${f.id}-${f.slug}.png`);
  rasterize(out.background, bg, CANVAS.W, CANVAS.H);
  out.overlays.forEach((svg, i) => rasterize(svg, p(geom.devices[i].overlay), CANVAS.W, CANVAS.H));
  rasterize(out.master, ex, CANVAS.W, CANVAS.H);
  flatten(bg);
  flatten(ex);

  const sizes = devices.map((d) => `${Math.round(d.w)}x${Math.round(d.h)}@${n(d.rot)}`).join('  ');
  console.log(`  ${f.id} ${f.slug.padEnd(15)} ${devices.length} device(s)  ${sizes}   ` +
              `copy ${widest.toFixed(0)}/${COL_W}px`);
  return geom;
}

/* ------------------------------------------------- standalone deco assets -- */

function asset(name, body, w, h) {
  const svg = `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">
  <defs>
    <style type="text/css"><![CDATA[text{font-family:'Inter','Segoe UI',Arial,sans-serif}]]></style>
  </defs>
${body}
</svg>
`;
  write(p('assets', name), svg);
}

function buildAssets() {
  const slug = {
    benzene: 'benzene-c6h6', cyclohexane: 'cyclohexane-c6h12', toluene: 'toluene-c7h8',
    phenol: 'phenol-c6h6o', naphthalene: 'naphthalene-c10h8', ethanol: 'ethanol-c2h6o',
    acetone: 'acetone-c3h6o', aceticAcid: 'acetic-acid-c2h4o2', butane: 'butane-c4h10',
    hexane: 'hexane-c6h14', caffeine: 'caffeine-c8h10n4o2',
  };
  const sc = { caffeine: 52, naphthalene: 62, hexane: 56, butane: 62 };
  for (const key of Object.keys(SKELETAL)) {
    const S = 460, s = sc[key] || 76;
    asset(`skeletal/${slug[key]}.svg`,
      skeletal(key, { cx: S / 2, cy: S / 2, scale: s, opacity: 1, width: 6 }), S, S);
  }
  asset('skeletal/benzene-aromatic.svg',
    skeletal('benzene', { cx: 230, cy: 230, scale: 76, opacity: 1, width: 6, mode: 'aromatic' }), 460, 460);
  for (const sym of ['H', 'C', 'N', 'O', 'Na', 'Cl', 'Fe', 'He', 'Ne', 'Si', 'Ca', 'Au']) {
    const w = 260, h = w * 1.16;
    asset(`element-tiles/${ELEMENTS[sym].z}-${sym.toLowerCase()}.svg`,
      elementTile(sym, { x: 8, y: 8, w: w - 16, variant: 'soft', opacity: 1 }), w, h + 16);
  }
  for (const sym of ['H', 'C', 'N', 'O', 'Na', 'Cl', 'Ne', 'Fe']) {
    const S = 560;
    asset(`orbital/bohr-${sym.toLowerCase()}.svg`,
      bohr(sym, { cx: S / 2, cy: S / 2, r: S * 0.44, opacity: 1, label: true }), S, S);
  }
  asset('orbital/orbit-rings.svg', orbits({ cx: 300, cy: 300, r: 260, opacity: 1 }), 600, 600);
  asset('orbital/graphene-lattice.svg',
    lattice({ x: 40, y: 40, cols: 6, rows: 6, a: 70, opacity: 1, width: 5 }), 840, 740);
  asset('orbital/periodic-fragment.svg',
    periodicFragment({ x: 10, y: 10, cell: 44, gap: 7, opacity: 1 }), 940, 230);
  const eq = {
    'combustion-hydrogen': EQUATIONS.combustionH2, 'combustion-methane': EQUATIONS.combustionCH4,
    'haber-process': EQUATIONS.haber, 'sodium-chloride': EQUATIONS.saltFormation,
    photosynthesis: EQUATIONS.photosynthesis,
  };
  for (const [name, text] of Object.entries(eq)) {
    asset(`formulas/${name}.svg`,
      formula(text, { x: 20, y: 86, size: 72, opacity: 1, fill: C.ink }), 1240, 120);
  }
  for (const [name, text] of Object.entries({
    water: 'H2O', 'carbon-dioxide': 'CO2', methane: 'CH4', benzene: 'C6H6',
    'sodium-chloride': 'NaCl', ammonia: 'NH3', glucose: 'C6H12O6', caffeine: 'C8H10N4O2',
  })) {
    asset(`formulas/formula-${name}.svg`,
      formula(text, { x: 16, y: 96, size: 96, opacity: 1, fill: C.ink }), 640, 130);
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
cols, rows, pad = 3, 2, 30
tw, th = 606, 1317
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
cols, pad = 6, 14
tw, th = 208, 452
sheet = Image.new('RGB', (cols*tw + pad*(cols+1), th + pad*2), (244, 247, 251))
for i, f in enumerate(files):
    im = Image.open(f).convert('RGB').resize((tw, th), Image.LANCZOS)
    sheet.paste(im, (pad + i*(tw+pad), pad))
sheet.save(out)
`, ...files, p('exports', 'contact-sheet-thumbnail.png')], { stdio: ['ignore', 'inherit', 'pipe'] });
  console.log('  contact sheets written to exports/');
}

/* The 2 + 3 pair, and the first three at gallery scale, so the continuation can
   be judged both edge to edge and with the gap the App Store actually puts
   between cards. */
function previews(geoms) {
  const by = Object.fromEntries(geoms.map((g) => [g.id, p(g.output)]));
  execFileSync('python3', ['-c', `
import sys
from PIL import Image
two, three, one, out2, out3, out4 = sys.argv[1:7]
W, H = 620, 1347

def card(path):
    return Image.open(path).convert('RGB').resize((W, H), Image.LANCZOS)

# a) edge to edge: the master composition, reassembled
touch = Image.new('RGB', (2*W, H), (255, 255, 255))
touch.paste(card(two), (0, 0)); touch.paste(card(three), (W, 0))
touch.save(out2)

# b) with the gap a gallery really shows
gap, pad = 34, 30
gal = Image.new('RGB', (2*W + gap + 2*pad, H + 2*pad), (247, 248, 251))
gal.paste(card(two), (pad, pad)); gal.paste(card(three), (pad + W + gap, pad))
gal.save(out3)

# c) slides 1, 2, 3 as the store lists them
w2, h2 = 420, 913
g2, p2 = 24, 26
row = Image.new('RGB', (3*w2 + 2*g2 + 2*p2, h2 + 2*p2), (247, 248, 251))
for i, f in enumerate([one, two, three]):
    row.paste(Image.open(f).convert('RGB').resize((w2, h2), Image.LANCZOS),
              (p2 + i*(w2+g2), p2))
row.save(out4)
`, by['02'], by['03'], by['01'],
     p('exports', 'pair-2-3-touching.png'),
     p('exports', 'pair-2-3-gallery.png'),
     p('exports', 'gallery-1-2-3.png')], { stdio: ['ignore', 'inherit', 'pipe'] });
  console.log('  pair and gallery previews written to exports/');
}

/* ------------------------------------------------------------------- main -- */

console.log(`Elemora App Store build: ${CANVAS.W} x ${CANVAS.H}, ${FRAMES.length} frames`);
const geoms = FRAMES.map(buildFrame);
buildAssets();
contactSheet(geoms);
previews(geoms);
write(p('source', 'frames.json'), JSON.stringify(geoms, null, 1) + '\n');

/* The drawn skeletal graphs, exported so the QA pass can re-derive each
   molecular formula from the geometry instead of trusting the label. */
write(p('source', 'skeletal.json'), JSON.stringify(
  Object.fromEntries(Object.entries(SKELETAL).map(([k, v]) => [k, {
    name: v.name, formula: v.formula, pts: v.pts, bonds: v.bonds, labels: v.labels || {},
  }])), null, 1) + '\n');
console.log('done.');
