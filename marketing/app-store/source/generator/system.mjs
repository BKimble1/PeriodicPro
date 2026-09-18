/* ============================================================================
   Elemora — App Store campaign design system.

   Light, scientific, spacious. Near-white paper, pale chemistry blues, deep
   navy type, one large device per frame, and restrained chemistry decoration
   that always sits BEHIND the phone so no real app pixel is ever covered.

   Geometry is derived from a single screen width, so a device can be scaled or
   rotated as ONE rigid group without ever distorting the 1320:2868 opening.

   The palette is sampled from the Elemora brand reference artwork — see
   ../../README.md § Palette provenance.
   ========================================================================== */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));

/* App Store iPhone 6.9" portrait. */
export const CANVAS = { W: 1320, H: 2868 };
export const RATIO = CANVAS.W / CANVAS.H;              // 0.4602510460251046

/* Device proportions, expressed against the screen width so every frame scales
   identically. bezel = metal rim + black border; the screen opening always
   holds the exact canvas ratio. */
export const P = {
  bezel:   0.0425,
  screenR: 0.088,
  rim:     0.019,
};

export const MARGIN = 96;
export const COL_W = CANVAS.W - MARGIN * 2;            // 1128

/* -------------------------------------------------------------- typography */

export const TYPE = {
  headSize: 122, headLead: 119, headWeight: 800, headTrack: -3.4,
  subSize: 45, subLead: 59, subWeight: 500, subTrack: -0.2, subOpacity: 0.86,
};
/* Inter cap-height / em. */
export const CAP = 1490 / 2048;

/* ------------------------------------------------ palette (Elemora, light) */

export const C = {
  ink:        '#0E2039',   // headline navy  (sampled #102038)
  inkSoft:    '#425873',   // supporting copy
  accent:     '#2F6BE8',   // Elemora blue   (sampled #4884FC / #5490FC)
  accentLite: '#5490FC',
  paper:      '#FDFEFF',
  paleA:      '#EAF3FD',
  paleB:      '#DDEBFA',
  paleC:      '#D6EAF7',   // pale cyan
  mint:       '#DCF1E9',
  lavender:   '#E4E0F6',   // sampled #8478D8 family, heavily lightened
  screen:     '#F2F6FB',   // placeholder screen fill
  screenInk:  '#8FA3BE',
  shadow:     '#22456F',   // cool, never black
  metalHi:    '#F8FAFD',
  metalMid:   '#A9B6C7',
  metalLo:    '#7E8DA2',
  bezel:      '#070A11',
};

/* Near-white paper with the faintest cool drift. Frames differ by their
   radial light sources, not by this base. */
export const BASE_STOPS = [
  [0.00, '#FDFEFF'], [0.18, '#FAFCFE'], [0.40, '#F6FAFE'],
  [0.62, '#F4F9FD'], [0.82, '#F8FBFE'], [1.00, '#FDFEFF'],
];

/* ------------------------------------------------------------- primitives */

export function n(v) {
  if (!Number.isFinite(v)) throw new Error('bad number: ' + v);
  const s = v.toFixed(4).replace(/0+$/, '').replace(/\.$/, '');
  return s === '-0' ? '0' : s;
}

export function roundRect(x, y, w, h, r) {
  const rr = Math.min(r, w / 2, h / 2);
  return [
    `M ${n(x + rr)} ${n(y)}`, `H ${n(x + w - rr)}`,
    `A ${n(rr)} ${n(rr)} 0 0 1 ${n(x + w)} ${n(y + rr)}`, `V ${n(y + h - rr)}`,
    `A ${n(rr)} ${n(rr)} 0 0 1 ${n(x + w - rr)} ${n(y + h)}`, `H ${n(x + rr)}`,
    `A ${n(rr)} ${n(rr)} 0 0 1 ${n(x)} ${n(y + h - rr)}`, `V ${n(y + rr)}`,
    `A ${n(rr)} ${n(rr)} 0 0 1 ${n(x + rr)} ${n(y)}`, 'Z',
  ].join(' ');
}

export const esc = (s) =>
  String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

/* -------------------------------------------------------------- font embed */

let _font = null;
export function fontFace() {
  if (_font === null) {
    const b64 = fs.readFileSync(path.join(HERE, 'fonts', 'Inter-latin-var.woff2')).toString('base64');
    _font = `@font-face{font-family:'Inter';font-style:normal;font-weight:100 900;` +
            `src:url(data:font/woff2;base64,${b64}) format('woff2');}`;
  }
  return _font;
}

export function typeCSS() {
  return `
    ${fontFace()}
    text { font-family:'Inter','Segoe UI',Arial,sans-serif; -webkit-font-smoothing:antialiased; }
    .el-headline { font-weight:${TYPE.headWeight}; font-size:${TYPE.headSize}px;
                   letter-spacing:${TYPE.headTrack}px; fill:${C.ink}; }
    .el-sub      { font-weight:${TYPE.subWeight}; font-size:${TYPE.subSize}px;
                   letter-spacing:${TYPE.subTrack}px; fill:${C.inkSoft}; fill-opacity:${TYPE.subOpacity}; }
    .el-ph       { font-weight:600; font-size:31px; letter-spacing:3.4px; fill:${C.screenInk}; fill-opacity:0.78; }
    .el-ph2      { font-weight:600; font-size:27px; letter-spacing:1.2px; fill:${C.accent}; fill-opacity:0.62; }
    .el-ph3      { font-weight:500; font-size:24px; letter-spacing:1.6px; fill:${C.screenInk}; fill-opacity:0.48; }
    .el-tag      { font-weight:600; font-size:30px; letter-spacing:6.5px; fill:${C.inkSoft}; fill-opacity:0.42; }
  `;
}

/* ------------------------------------------------------ device: geometry --
   ONE rigid group. Scale changes screenW; rotation is applied to the whole
   group about its centre, so the real screenshot follows the bezel exactly
   and is never independently stretched.
   -------------------------------------------------------------------------- */

export function deviceGeom({ screenW, x, y, rot = 0 }) {
  const bezel = screenW * P.bezel;
  const screenH = (screenW * CANVAS.H) / CANVAS.W;     // exact 1320:2868, always
  const w = screenW + bezel * 2;
  const h = screenH + bezel * 2;
  const screenR = screenW * P.screenR;
  return {
    x, y, w, h, rot,
    r: screenR + bezel,                                 // concentric with screen
    rim: screenW * P.rim,
    bezel,
    cx: x + w / 2, cy: y + h / 2,
    scale: screenW / 990,                               // 990 is the campaign base
    k: screenW / CANVAS.W,                              // screenshot px -> canvas px
    screen: {
      x: x + bezel, y: y + bezel, w: screenW, h: screenH, r: screenR,
      cx: x + bezel + screenW / 2, cy: y + bezel + screenH / 2,
    },
  };
}

/* Campaign device placement. The phone runs from 26% to 96% of the canvas
   height — dominant in the lower three quarters — and leaves ~178px of clear
   margin either side for the chemistry decoration to breathe. */
export const BASE_SCREEN_W = 888;
export const DEVICE_TOP = 745;

export function stdDevice({ screenW = BASE_SCREEN_W, dx = 0, dy = 0, rot = 0 } = {}) {
  const bezel = screenW * P.bezel;
  const w = screenW + bezel * 2;
  return deviceGeom({ screenW, x: (CANVAS.W - w) / 2 + dx, y: DEVICE_TOP + dy, rot });
}

/** Axis-aligned bounding box of the device after its rigid rotation. */
export function deviceBounds(d) {
  const a = Math.abs(d.rot) * Math.PI / 180;
  const hw = d.w / 2, hh = d.h / 2;
  const ex = hw * Math.cos(a) + hh * Math.sin(a);
  const ey = hw * Math.sin(a) + hh * Math.cos(a);
  return { minX: d.cx - ex, maxX: d.cx + ex, minY: d.cy - ey, maxY: d.cy + ey };
}

/** Wraps content in the device's rigid rotation, if any. */
export function rigid(d, inner) {
  return d.rot ? `<g transform="rotate(${n(d.rot)} ${n(d.cx)} ${n(d.cy)})">${inner}</g>` : inner;
}

export function deviceDefs(d, sfx = '') {
  return `
  <linearGradient id="elRim${sfx}" x1="${n(d.x)}" y1="0" x2="${n(d.x + d.w)}" y2="0" gradientUnits="userSpaceOnUse">
    <stop offset="0"    stop-color="#C6D0DE"/>
    <stop offset="0.028" stop-color="${C.metalHi}"/>
    <stop offset="0.10" stop-color="#B2BFD0"/>
    <stop offset="0.34" stop-color="${C.metalMid}"/>
    <stop offset="0.66" stop-color="#9FADC0"/>
    <stop offset="0.90" stop-color="${C.metalLo}"/>
    <stop offset="0.972" stop-color="#EEF2F7"/>
    <stop offset="1"    stop-color="#AEBBCC"/>
  </linearGradient>
  <linearGradient id="elBody${sfx}" x1="${n(d.x)}" y1="0" x2="${n(d.x + d.w)}" y2="0" gradientUnits="userSpaceOnUse">
    <stop offset="0"    stop-color="#1B2231"/>
    <stop offset="0.05" stop-color="#0C1119"/>
    <stop offset="0.5"  stop-color="${C.bezel}"/>
    <stop offset="0.95" stop-color="#0C1119"/>
    <stop offset="1"    stop-color="#1D2534"/>
  </linearGradient>
  <filter id="elShadowA${sfx}" x="-45%" y="-35%" width="190%" height="180%" color-interpolation-filters="sRGB">
    <feGaussianBlur stdDeviation="${n(70 * d.scale)}"/>
  </filter>
  <filter id="elShadowB${sfx}" x="-40%" y="-30%" width="180%" height="170%" color-interpolation-filters="sRGB">
    <feGaussianBlur stdDeviation="${n(24 * d.scale)}"/>
  </filter>`;
}

/** One restrained, cool shadow language shared by all eight frames. */
export function deviceShadow(d, sfx = '') {
  const s = d.scale;
  return `
  <g id="Device-Shadow${sfx}">${rigid(d, `
    <path d="${roundRect(d.x + 16 * s, d.y + 62 * s, d.w - 32 * s, d.h, d.r)}"
          fill="${C.shadow}" fill-opacity="0.20" filter="url(#elShadowA${sfx})"/>
    <path d="${roundRect(d.x + 30 * s, d.y + 20 * s, d.w - 60 * s, d.h, d.r)}"
          fill="${C.shadow}" fill-opacity="0.15" filter="url(#elShadowB${sfx})"/>`)}
  </g>`;
}

/* The Dynamic Island is physical hardware, not app UI, so it is drawn OVER the
   screenshot. Proportions are the iPhone 6.9" cutout measured in screenshot
   pixels (375 x 110, 33px from the top of a 1320 x 2868 capture). */
export function dynamicIsland(d) {
  const s = d.screen, k = d.k;
  const iw = 375 * k, ih = 110 * k, top = s.y + 33 * k;
  return `<rect id="Dynamic-Island" x="${n(s.cx - iw / 2)}" y="${n(top)}"
        width="${n(iw)}" height="${n(ih)}" rx="${n(ih / 2)}" fill="#05070C"/>`;
}

/** Everything above the real screenshot. The opening is a genuine hole. */
export function deviceOverlay(d, sfx = '') {
  const s = d.screen, RIM = d.rim;
  const hole = roundRect(s.x, s.y, s.w, s.h, s.r);
  const btn = (name, bx, by, bw, bh) =>
    `<rect id="Button-${name}${sfx}" x="${n(bx)}" y="${n(by)}" width="${n(bw)}" height="${n(bh)}" rx="${n(4 * d.scale)}" fill="#94A2B5"/>`;
  const buttons = [
    btn('Action', d.x - 4.5 * d.scale, d.y + 0.224 * d.h, 9 * d.scale, 0.047 * d.h),
    btn('Volume-Up', d.x - 4.5 * d.scale, d.y + 0.306 * d.h, 9 * d.scale, 0.080 * d.h),
    btn('Volume-Down', d.x - 4.5 * d.scale, d.y + 0.399 * d.h, 9 * d.scale, 0.080 * d.h),
    btn('Power', d.x + d.w - 4.5 * d.scale, d.y + 0.336 * d.h, 9 * d.scale, 0.141 * d.h),
  ].join('\n      ');

  return `
  <g id="Device-Overlay${sfx}">${rigid(d, `
      ${buttons}
      <path id="Device-Rim${sfx}" fill-rule="evenodd" fill="url(#elRim${sfx})"
            d="${roundRect(d.x, d.y, d.w, d.h, d.r)} ${hole}"/>
      <path id="Device-Body${sfx}" fill-rule="evenodd" fill="url(#elBody${sfx})"
            d="${roundRect(d.x + RIM, d.y + RIM, d.w - RIM * 2, d.h - RIM * 2, d.r - RIM)} ${hole}"/>
      <path id="Device-Edge-Light${sfx}" fill="none" stroke="#FFFFFF" stroke-opacity="0.38" stroke-width="${n(1.5 * d.scale)}"
            d="${roundRect(d.x + 0.75, d.y + 0.75, d.w - 1.5, d.h - 1.5, d.r - 0.75)}"/>
      <path id="Screen-Edge${sfx}" fill="none" stroke="#FFFFFF" stroke-opacity="0.10" stroke-width="${n(1.4 * d.scale)}"
            d="${roundRect(s.x + 0.7, s.y + 0.7, s.w - 1.4, s.h - 1.4, s.r - 0.7)}"/>
      ${dynamicIsland(d)}`)}
  </g>`;
}

/** Plain placeholder — no fabricated app UI, no dashed guides. */
export function screenPlaceholder(d, label, sfx = '') {
  const s = d.screen;
  return `
  <g id="Screen-Placeholder${sfx}">${rigid(d, `
      <path d="${roundRect(s.x, s.y, s.w, s.h, s.r)}" fill="${C.screen}"/>
      <text x="${n(s.cx)}" y="${n(s.cy - 46)}" class="el-ph"  text-anchor="middle">REPLACE WITH REAL SCREENSHOT</text>
      <text x="${n(s.cx)}" y="${n(s.cy + 14)}" class="el-ph2" text-anchor="middle">${esc(label)}</text>
      <text x="${n(s.cx)}" y="${n(s.cy + 66)}" class="el-ph3" text-anchor="middle">1320 &#215; 2868</text>`)}
  </g>`;
}

/** What sits under a real screenshot in the Background layer. */
export function screenWell(d, sfx = '') {
  const s = d.screen;
  return `
  <g id="Screen-Well${sfx}">${rigid(d, `
      <path d="${roundRect(s.x, s.y, s.w, s.h, s.r)}" fill="${C.screen}"/>`)}
  </g>`;
}

/* ------------------------------------------------------------ copy block -- */

export function copyBlock({
  lines, sub, top, gap = 34, align = 'start', x: edge = MARGIN,
  headSize = TYPE.headSize, headLead = TYPE.headLead,
  subSize = TYPE.subSize, subLead = TYPE.subLead,
}) {
  const centred = align === 'center';
  const x = centred ? CANVAS.W / 2 : edge;
  const anchor = centred ? ' text-anchor="middle"' : '';
  const hStyle = headSize === TYPE.headSize ? '' :
    ` style="font-size:${headSize}px;letter-spacing:${n(TYPE.headTrack * headSize / TYPE.headSize)}px"`;
  const sStyle = subSize === TYPE.subSize ? '' :
    ` style="font-size:${subSize}px;letter-spacing:${n(TYPE.subTrack * subSize / TYPE.subSize)}px"`;

  const b0 = top + headSize * CAP;
  const heads = lines
    .map((t, i) => `<tspan x="${n(x)}" y="${n(b0 + i * headLead)}">${esc(t)}</tspan>`)
    .join('');
  const last = b0 + (lines.length - 1) * headLead;

  const subArr = Array.isArray(sub) ? sub : [sub];
  const sb0 = last + gap + subSize * CAP;
  const subs = subArr
    .map((t, i) => `<tspan x="${n(x)}" y="${n(sb0 + i * subLead)}">${esc(t)}</tspan>`)
    .join('');

  return {
    svg: `
  <g id="Marketing-Copy">
    <text id="Headline" class="el-headline"${anchor}${hStyle} text-rendering="geometricPrecision">${heads}</text>
    <text id="Supporting" class="el-sub"${anchor}${sStyle} text-rendering="geometricPrecision">${subs}</text>
  </g>`,
    capTop: top, lastBaseline: last, subBaseline: sb0,
    bottom: sb0 + (subArr.length - 1) * subLead + subSize * 0.24,
    align, headSize, subSize, x,
  };
}

/* ------------------------------------------------------------ background -- */

export function baseDefs(light) {
  const stops = BASE_STOPS.map(([p, c]) => `<stop offset="${p}" stop-color="${c}"/>`).join('\n    ');
  const lights = light.map((L, i) => `
  <radialGradient id="elLight${i}" cx="${n(L.x)}" cy="${n(L.y)}" r="${n(L.r)}" gradientUnits="userSpaceOnUse">
    <stop offset="0"    stop-color="${L.c}" stop-opacity="${L.o}"/>
    <stop offset="0.40" stop-color="${L.c}" stop-opacity="${(L.o * 0.52).toFixed(4)}"/>
    <stop offset="0.74" stop-color="${L.c}" stop-opacity="${(L.o * 0.16).toFixed(4)}"/>
    <stop offset="1"    stop-color="${L.c}" stop-opacity="0"/>
  </radialGradient>`).join('');
  return `
  <linearGradient id="elBase" x1="0" y1="0" x2="0" y2="${CANVAS.H}" gradientUnits="userSpaceOnUse">
    ${stops}
  </linearGradient>${lights}`;
}

export function background(light) {
  const l = light.map((_, i) =>
    `    <rect width="${CANVAS.W}" height="${CANVAS.H}" fill="url(#elLight${i})"/>`).join('\n');
  return `
  <g id="Background">
    <rect width="${CANVAS.W}" height="${CANVAS.H}" fill="url(#elBase)"/>
${l}
  </g>`;
}

/* -------------------------------------------------------------- document -- */

export function svgDoc({ defs = '', body = '', title = 'Elemora' }) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${CANVAS.W}" height="${CANVAS.H}" viewBox="0 0 ${CANVAS.W} ${CANVAS.H}">
  <title>${esc(title)}</title>
  <defs>
    <style type="text/css"><![CDATA[${typeCSS()}]]></style>
${defs}
  </defs>
${body}
</svg>
`;
}

/* Compose the three deliverable layers from one frame definition.
   `deco` is chemistry artwork; it is ALWAYS behind the device. */
export function composeFrame({ title, dev, copy, light, deco = '', decoDefs = '', label }) {
  const defs = baseDefs(light) + decoDefs + deviceDefs(dev);
  const under = [background(light), deco, deviceShadow(dev), copy.svg];
  return {
    master: svgDoc({
      title, defs,
      body: [...under, screenPlaceholder(dev, label), deviceOverlay(dev)].join('\n'),
    }),
    background: svgDoc({
      title: title + ' — background',
      defs,
      body: [...under, screenWell(dev)].join('\n'),
    }),
    overlay: svgDoc({
      title: title + ' — device overlay',
      defs: deviceDefs(dev),
      body: deviceOverlay(dev),
    }),
  };
}
