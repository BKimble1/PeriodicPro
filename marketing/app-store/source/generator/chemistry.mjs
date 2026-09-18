/* ============================================================================
   Elemora — chemistry decoration library.

   Every representation here is scientifically checked:

   * atomic numbers, standard atomic weights (IUPAC 2021 abridged), groups,
     periods, categories and electron-shell occupancies are from reference data
   * molecular coordinates are real 3D geometries in angstroms, built from
     measured bond lengths and bond angles (see each entry)
   * the periodic-table fragment uses the true period-1..4 layout, gaps included
   * the lattice motif is a graphene honeycomb, not an invented node graph
   * equations are balanced

   Rendering is ball-and-stick: spheres are shaded with a light source at the
   upper left plus a lower-right rim light, bonds are shaded cylinders, and the
   whole molecule is depth-sorted with a painter's algorithm so atoms and bond
   halves interleave correctly.
   ========================================================================== */

import { n, esc, roundRect, C } from './system.mjs';

/* ------------------------------------------------------------- def collector
   Gradients and filters are emitted once per frame, no matter how many times
   an element or motif is used. */
export function deco() {
  const out = [];
  const seen = new Set();
  return {
    def(id, svg) { if (!seen.has(id)) { seen.add(id); out.push(svg); } return id; },
    has(id) { return seen.has(id); },
    defs() { return out.join('\n'); },
  };
}

/* ------------------------------------------------------------- element data
   Z, symbol, name, standard atomic weight, group, period, category, shells. */
export const ELEMENTS = {
  H:  { z: 1,  name: 'Hydrogen',  mass: '1.008',  group: 1,  period: 1, cat: 'Nonmetal',        shells: [1] },
  He: { z: 2,  name: 'Helium',    mass: '4.0026', group: 18, period: 1, cat: 'Noble gas',       shells: [2] },
  Li: { z: 3,  name: 'Lithium',   mass: '6.94',   group: 1,  period: 2, cat: 'Alkali metal',    shells: [2, 1] },
  Be: { z: 4,  name: 'Beryllium', mass: '9.0122', group: 2,  period: 2, cat: 'Alkaline earth',  shells: [2, 2] },
  B:  { z: 5,  name: 'Boron',     mass: '10.81',  group: 13, period: 2, cat: 'Metalloid',       shells: [2, 3] },
  C:  { z: 6,  name: 'Carbon',    mass: '12.011', group: 14, period: 2, cat: 'Nonmetal',        shells: [2, 4] },
  N:  { z: 7,  name: 'Nitrogen',  mass: '14.007', group: 15, period: 2, cat: 'Nonmetal',        shells: [2, 5] },
  O:  { z: 8,  name: 'Oxygen',    mass: '15.999', group: 16, period: 2, cat: 'Nonmetal',        shells: [2, 6] },
  F:  { z: 9,  name: 'Fluorine',  mass: '18.998', group: 17, period: 2, cat: 'Halogen',         shells: [2, 7] },
  Ne: { z: 10, name: 'Neon',      mass: '20.180', group: 18, period: 2, cat: 'Noble gas',       shells: [2, 8] },
  Na: { z: 11, name: 'Sodium',    mass: '22.990', group: 1,  period: 3, cat: 'Alkali metal',    shells: [2, 8, 1] },
  Mg: { z: 12, name: 'Magnesium', mass: '24.305', group: 2,  period: 3, cat: 'Alkaline earth',  shells: [2, 8, 2] },
  Al: { z: 13, name: 'Aluminium', mass: '26.982', group: 13, period: 3, cat: 'Post-transition', shells: [2, 8, 3] },
  Si: { z: 14, name: 'Silicon',   mass: '28.085', group: 14, period: 3, cat: 'Metalloid',       shells: [2, 8, 4] },
  P:  { z: 15, name: 'Phosphorus',mass: '30.974', group: 15, period: 3, cat: 'Nonmetal',        shells: [2, 8, 5] },
  S:  { z: 16, name: 'Sulfur',    mass: '32.06',  group: 16, period: 3, cat: 'Nonmetal',        shells: [2, 8, 6] },
  Cl: { z: 17, name: 'Chlorine',  mass: '35.45',  group: 17, period: 3, cat: 'Halogen',         shells: [2, 8, 7] },
  Ar: { z: 18, name: 'Argon',     mass: '39.95',  group: 18, period: 3, cat: 'Noble gas',       shells: [2, 8, 8] },
  K:  { z: 19, name: 'Potassium', mass: '39.098', group: 1,  period: 4, cat: 'Alkali metal',    shells: [2, 8, 8, 1] },
  Ca: { z: 20, name: 'Calcium',   mass: '40.078', group: 2,  period: 4, cat: 'Alkaline earth',  shells: [2, 8, 8, 2] },
  Fe: { z: 26, name: 'Iron',      mass: '55.845', group: 8,  period: 4, cat: 'Transition metal',shells: [2, 8, 14, 2] },
  Cu: { z: 29, name: 'Copper',    mass: '63.546', group: 11, period: 4, cat: 'Transition metal',shells: [2, 8, 18, 1] },
  Au: { z: 79, name: 'Gold',      mass: '196.97', group: 11, period: 6, cat: 'Transition metal',shells: [2, 8, 18, 32, 18, 1] },
};

/* Display radii, angstroms. A compressed map of the covalent radii
   (r = 0.30 + 0.45 * r_cov) so hydrogen stays clearly smaller than carbon
   without disappearing at decorative sizes. */
const RADIUS = { H: 0.440, C: 0.642, N: 0.620, O: 0.597, Cl: 0.746, S: 0.773, Na: 1.047, Fe: 0.894 };

/* CPK-derived sphere ramps: [highlight, mid, low, edge]. */
const RAMP = {
  H:  ['#FFFFFF', '#F1F4F9', '#C2CCD9', '#A6B3C5'],
  C:  ['#78808F', '#3D4553', '#1A2029', '#0D1119'],
  N:  ['#A9C8F5', '#4F87DA', '#2C5696', '#22447A'],
  O:  ['#F6ABA2', '#DC5A50', '#A03A32', '#7E2C25'],
  Cl: ['#BDEBB4', '#62B856', '#367E2E', '#2A6624'],
  S:  ['#FBE6A0', '#E2BC42', '#9A7C18', '#7C6413'],
  Na: ['#D2C9F4', '#8478D8', '#514799', '#40397B'],
  Fe: ['#F6C894', '#D9843E', '#91501A', '#743F14'],
};

/* ----------------------------------------------------------------- geometry
   Real 3D coordinates in angstroms. Each entry records its source geometry. */
export const MOLECULES = {
  /* Water: O-H 0.958 A, H-O-H 104.5 deg. */
  water: {
    formula: 'H2O', name: 'Water',
    atoms: [['O', 0, 0, 0], ['H', 0.757, 0.586, 0], ['H', -0.757, 0.586, 0]],
    bonds: [[0, 1, 1], [0, 2, 1]],
  },
  /* Carbon dioxide: linear, C=O 1.163 A, O=C=O 180 deg. */
  carbonDioxide: {
    formula: 'CO2', name: 'Carbon dioxide',
    atoms: [['C', 0, 0, 0], ['O', 1.163, 0, 0], ['O', -1.163, 0, 0]],
    bonds: [[0, 1, 2], [0, 2, 2]],
  },
  /* Methane: regular tetrahedron, C-H 1.087 A, H-C-H 109.47 deg. */
  methane: {
    formula: 'CH4', name: 'Methane',
    atoms: [
      ['C', 0, 0, 0],
      ['H', 0.6276, 0.6276, 0.6276], ['H', 0.6276, -0.6276, -0.6276],
      ['H', -0.6276, 0.6276, -0.6276], ['H', -0.6276, -0.6276, 0.6276],
    ],
    bonds: [[0, 1, 1], [0, 2, 1], [0, 3, 1], [0, 4, 1]],
  },
  /* Ammonia: trigonal pyramidal, N-H 1.012 A, H-N-H 107 deg
     (bond axis 68.16 deg off the C3 axis). */
  ammonia: {
    formula: 'NH3', name: 'Ammonia',
    atoms: [
      ['N', 0, 0, 0],
      ['H', 0, 0.9393, 0.3765],
      ['H', -0.8134, -0.4697, 0.3765],
      ['H', 0.8134, -0.4697, 0.3765],
    ],
    bonds: [[0, 1, 1], [0, 2, 1], [0, 3, 1]],
  },
  /* Ethane: staggered, C-C 1.540 A, C-H 1.090 A, H-C-H 109.47 deg. */
  ethane: {
    formula: 'C2H6', name: 'Ethane',
    atoms: [
      ['C', 0, 0, 0.77], ['C', 0, 0, -0.77],
      ['H', 1.0277, 0, 1.1333],
      ['H', -0.5139, 0.8900, 1.1333],
      ['H', -0.5139, -0.8900, 1.1333],
      ['H', 0.5139, 0.8900, -1.1333],
      ['H', -1.0277, 0, -1.1333],
      ['H', 0.5139, -0.8900, -1.1333],
    ],
    bonds: [[0, 1, 1], [0, 2, 1], [0, 3, 1], [0, 4, 1], [1, 5, 1], [1, 6, 1], [1, 7, 1]],
  },
  /* Benzene: planar regular hexagon, C-C 1.39 A, C-H 1.09 A.
     Drawn in the Kekule form; the ring is flagged aromatic for the
     skeletal renderer. */
  benzene: {
    formula: 'C6H6', name: 'Benzene',
    atoms: (() => {
      const a = [];
      for (let i = 0; i < 6; i++) {
        const t = (Math.PI / 3) * i;
        a.push(['C', 1.39 * Math.cos(t), 1.39 * Math.sin(t), 0]);
      }
      for (let i = 0; i < 6; i++) {
        const t = (Math.PI / 3) * i;
        a.push(['H', 2.48 * Math.cos(t), 2.48 * Math.sin(t), 0]);
      }
      return a;
    })(),
    bonds: (() => {
      const b = [];
      for (let i = 0; i < 6; i++) b.push([i, (i + 1) % 6, i % 2 ? 1 : 2]);
      for (let i = 0; i < 6; i++) b.push([i, i + 6, 1]);
      return b;
    })(),
  },
  /* Dioxygen: O=O 1.208 A. */
  dioxygen: {
    formula: 'O2', name: 'Oxygen',
    atoms: [['O', 0.604, 0, 0], ['O', -0.604, 0, 0]],
    bonds: [[0, 1, 2]],
  },
  /* Dinitrogen: N#N 1.098 A. */
  dinitrogen: {
    formula: 'N2', name: 'Nitrogen',
    atoms: [['N', 0.549, 0, 0], ['N', -0.549, 0, 0]],
    bonds: [[0, 1, 3]],
  },
};

/* ------------------------------------------------------------- projection */

function rotate3(p, rx, ry, rz) {
  const d = Math.PI / 180;
  let [x, y, z] = p;
  let c = Math.cos(rx * d), s = Math.sin(rx * d);
  [y, z] = [y * c - z * s, y * s + z * c];
  c = Math.cos(ry * d); s = Math.sin(ry * d);
  [x, z] = [x * c + z * s, -x * s + z * c];
  c = Math.cos(rz * d); s = Math.sin(rz * d);
  [x, y] = [x * c - y * s, x * s + y * c];
  return [x, y, z];
}

/* ---------------------------------------------------------- sphere + bond */

function atomDefs(D, sym) {
  const [hi, mid, lo, edge] = RAMP[sym];
  D.def(`elAtom${sym}`, `
  <radialGradient id="elAtom${sym}" cx="0.35" cy="0.30" r="0.76">
    <stop offset="0"    stop-color="${hi}"/>
    <stop offset="0.36" stop-color="${mid}"/>
    <stop offset="0.80" stop-color="${lo}"/>
    <stop offset="1"    stop-color="${edge}"/>
  </radialGradient>`);
  D.def('elAtomRim', `
  <radialGradient id="elAtomRim" cx="0.70" cy="0.76" r="0.60">
    <stop offset="0.55" stop-color="#FFFFFF" stop-opacity="0"/>
    <stop offset="0.88" stop-color="#FFFFFF" stop-opacity="0.16"/>
    <stop offset="1"    stop-color="#FFFFFF" stop-opacity="0.34"/>
  </radialGradient>`);
  D.def('elAtomSpec', `
  <radialGradient id="elAtomSpec" cx="0.5" cy="0.5" r="0.5">
    <stop offset="0"    stop-color="#FFFFFF" stop-opacity="0.92"/>
    <stop offset="0.45" stop-color="#FFFFFF" stop-opacity="0.40"/>
    <stop offset="1"    stop-color="#FFFFFF" stop-opacity="0"/>
  </radialGradient>`);
  D.def('elBondG', `
  <linearGradient id="elBondG" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0"    stop-color="#A5B2C4"/>
    <stop offset="0.14" stop-color="#D6DEE9"/>
    <stop offset="0.36" stop-color="#EBEFF6"/>
    <stop offset="0.66" stop-color="#BEC9D7"/>
    <stop offset="0.88" stop-color="#9CAABD"/>
    <stop offset="1"    stop-color="#8794A8"/>
  </linearGradient>`);
  D.def('elMolShadow', `
  <filter id="elMolShadow" x="-25%" y="-25%" width="160%" height="160%" color-interpolation-filters="sRGB">
    <feDropShadow dx="7" dy="16" stdDeviation="17" flood-color="${C.shadow}" flood-opacity="0.20"/>
  </filter>`);
}

function sphere(sym, x, y, r) {
  return `<g><circle cx="${n(x)}" cy="${n(y)}" r="${n(r)}" fill="url(#elAtom${sym})"/>` +
    `<circle cx="${n(x)}" cy="${n(y)}" r="${n(r)}" fill="url(#elAtomRim)"/>` +
    `<ellipse cx="${n(x - r * 0.33)}" cy="${n(y - r * 0.37)}" rx="${n(r * 0.30)}" ry="${n(r * 0.21)}" ` +
    `fill="url(#elAtomSpec)" transform="rotate(-27 ${n(x - r * 0.33)} ${n(y - r * 0.37)})"/></g>`;
}

function cylinder(x1, y1, x2, y2, w) {
  const dx = x2 - x1, dy = y2 - y1;
  const len = Math.hypot(dx, dy);
  if (len < 0.01) return '';
  const a = Math.atan2(dy, dx) * 180 / Math.PI;
  return `<g transform="translate(${n(x1)} ${n(y1)}) rotate(${n(a)})">` +
    `<rect x="0" y="${n(-w / 2)}" width="${n(len)}" height="${n(w)}" fill="url(#elBondG)"/></g>`;
}

/* --------------------------------------------------------------- molecule
   opts: cx, cy, scale (px per angstrom), rx/ry/rz (deg), opacity, dist,
   shadow (bool), clip (optional {x,y,w,h} for corner crops). */
export function molecule(D, key, opts = {}) {
  const m = MOLECULES[key];
  if (!m) throw new Error('unknown molecule: ' + key);
  const {
    cx = 0, cy = 0, scale = 60, rx = 0, ry = 0, rz = 0,
    opacity = 1, dist = 16, shadow = true, bondW = 0.30,
  } = opts;

  for (const [sym] of m.atoms) atomDefs(D, sym);

  /* rotate, then mild perspective about the molecular centroid */
  const pts = m.atoms.map(([sym, x, y, z]) => {
    const [X, Y, Z] = rotate3([x, y, z], rx, ry, rz);
    const f = dist / (dist - Z);
    return { sym, X, Y, Z, f, sx: cx + X * scale * f, sy: cy - Y * scale * f, r: RADIUS[sym] * scale * f };
  });

  const draw = [];
  for (const [i, j, order] of m.bonds) {
    const a = pts[i], b = pts[j];
    const mx = (a.sx + b.sx) / 2, my = (a.sy + b.sy) / 2;
    const ux = b.sx - a.sx, uy = b.sy - a.sy;
    const L = Math.hypot(ux, uy) || 1;
    const px = -uy / L, py = ux / L;                    // unit perpendicular
    const offs = order === 1 ? [0] : order === 2 ? [-0.115, 0.115] : [-0.19, 0, 0.19];
    for (const o of offs) {
      const ox = px * o * scale, oy = py * o * scale;
      const wA = bondW * scale * a.f, wB = bondW * scale * b.f;
      draw.push({ z: (a.Z * 3 + b.Z) / 4, svg: cylinder(a.sx + ox, a.sy + oy, mx + ox, my + oy, wA) });
      draw.push({ z: (b.Z * 3 + a.Z) / 4, svg: cylinder(mx + ox, my + oy, b.sx + ox, b.sy + oy, wB) });
    }
  }
  for (const p of pts) draw.push({ z: p.Z, svg: sphere(p.sym, p.sx, p.sy, p.r) });

  draw.sort((a, b) => a.z - b.z);                       // painter's algorithm
  const inner = draw.map((d) => d.svg).join('');
  const body = shadow ? `<g filter="url(#elMolShadow)">${inner}</g>` : inner;
  const op = opacity === 1 ? '' : ` opacity="${n(opacity)}"`;
  const clip = opts.clip ? ` clip-path="url(#${opts.clip})"` : '';
  return `<g id="Molecule-${m.formula}"${op}${clip}>${body}</g>`;
}

/* ------------------------------------------------------- chemical formulae
   Digits that follow a letter or ')' render as subscripts; leading digits stay
   full size so stoichiometric coefficients read correctly. */
export function chemText(str, size) {
  const sub = size * 0.20;
  let out = '';
  let prev = '';
  for (const ch of str) {
    const isSub = /[0-9]/.test(ch) && /[A-Za-z)\]]/.test(prev);
    if (isSub) {
      out += `<tspan dy="${n(sub)}" style="font-size:${n(size * 0.62)}px">${esc(ch)}</tspan>` +
             `<tspan dy="${n(-sub)}">&#8203;</tspan>`;
    } else {
      out += esc(ch);
    }
    if (ch !== ' ') prev = ch;
  }
  return out;
}

export function formula(str, { x, y, size = 80, fill = C.accent, opacity = 0.10,
                               weight = 600, anchor = 'start', track = 0, rot = 0 } = {}) {
  const t = rot ? ` transform="rotate(${n(rot)} ${n(x)} ${n(y)})"` : '';
  return `<text x="${n(x)}" y="${n(y)}"${t} text-anchor="${anchor}" ` +
    `style="font-size:${n(size)}px;font-weight:${weight};letter-spacing:${n(track)}px" ` +
    `fill="${fill}" fill-opacity="${n(opacity)}">${chemText(str, size)}</text>`;
}

/* --------------------------------------------------------------- element tile
   variant 'ghost' = outline only (background texture)
   variant 'soft'  = pale fill + hairline (closer, still quiet) */
export function elementTile(sym, { x, y, w = 150, variant = 'ghost', opacity = 0.10,
                                   stroke = C.accent, fill = C.paleA, ink = C.ink,
                                   rot = 0, showMass = true } = {}) {
  const e = ELEMENTS[sym];
  if (!e) throw new Error('unknown element: ' + sym);
  const h = w * 1.16, r = w * 0.145;
  const cx = x + w / 2;
  const t = rot ? ` transform="rotate(${n(rot)} ${n(cx)} ${n(y + h / 2)})"` : '';
  const box = variant === 'soft'
    ? `<path d="${roundRect(x, y, w, h, r)}" fill="${fill}" fill-opacity="0.85"/>` +
      `<path d="${roundRect(x, y, w, h, r)}" fill="none" stroke="${stroke}" stroke-opacity="0.22" stroke-width="${n(w * 0.011)}"/>`
    : `<path d="${roundRect(x, y, w, h, r)}" fill="none" stroke="${stroke}" stroke-opacity="0.85" stroke-width="${n(w * 0.013)}"/>`;
  const mass = showMass
    ? `<text x="${n(cx)}" y="${n(y + h * 0.855)}" text-anchor="middle" style="font-size:${n(w * 0.100)}px;font-weight:500" fill="${ink}" fill-opacity="0.62">${e.mass}</text>`
    : '';
  return `<g id="Tile-${sym}"${t} opacity="${n(opacity)}">
    ${box}
    <text x="${n(x + w * 0.135)}" y="${n(y + h * 0.20)}" style="font-size:${n(w * 0.135)}px;font-weight:600" fill="${ink}" fill-opacity="0.72">${e.z}</text>
    <text x="${n(cx)}" y="${n(y + h * 0.545)}" text-anchor="middle" style="font-size:${n(w * 0.400)}px;font-weight:650;letter-spacing:${n(-w * 0.008)}px" fill="${ink}" fill-opacity="0.95">${sym}</text>
    <text x="${n(cx)}" y="${n(y + h * 0.715)}" text-anchor="middle" style="font-size:${n(w * 0.108)}px;font-weight:500" fill="${ink}" fill-opacity="0.72">${e.name}</text>
    ${mass}
  </g>`;
}

/* ------------------------------------------------------------ Bohr diagram
   Nucleus plus one ring per occupied shell, with that shell's electron count
   drawn as evenly spaced dots. */
export function bohr(sym, { cx, cy, r = 220, opacity = 0.10, stroke = C.accent,
                            dot = C.accent, label = false } = {}) {
  const e = ELEMENTS[sym];
  if (!e) throw new Error('unknown element: ' + sym);
  const sh = e.shells;
  const nucleusR = r * 0.085;
  let out = `<circle cx="${n(cx)}" cy="${n(cy)}" r="${n(nucleusR)}" fill="${stroke}" fill-opacity="0.55"/>`;
  sh.forEach((count, i) => {
    const rr = r * (0.26 + (0.74 * (i + 1)) / sh.length);
    out += `<circle cx="${n(cx)}" cy="${n(cy)}" r="${n(rr)}" fill="none" stroke="${stroke}" stroke-opacity="0.45" stroke-width="${n(r * 0.009)}"/>`;
    for (let k = 0; k < count; k++) {
      const a = (2 * Math.PI * k) / count - Math.PI / 2 + i * 0.28;
      out += `<circle cx="${n(cx + rr * Math.cos(a))}" cy="${n(cy + rr * Math.sin(a))}" r="${n(r * 0.030)}" fill="${dot}" fill-opacity="0.9"/>`;
    }
  });
  if (label) {
    out += `<text x="${n(cx)}" y="${n(cy + r * 1.30)}" text-anchor="middle" style="font-size:${n(r * 0.17)}px;font-weight:600" fill="${C.ink}" fill-opacity="0.8">${sym}</text>`;
  }
  return `<g id="Bohr-${sym}" opacity="${n(opacity)}">${out}</g>`;
}

/* --------------------------------------------------------- skeletal benzene
   mode 'aromatic' = hexagon + inner circle (delocalised)
   mode 'kekule'   = hexagon + three alternating inner double-bond lines */
export function skeletalBenzene({ cx, cy, r = 160, opacity = 0.08, stroke = C.accent,
                                  width = 7, mode = 'aromatic', rot = 0 } = {}) {
  const pt = (i) => {
    const a = (Math.PI / 3) * i - Math.PI / 2 + (rot * Math.PI) / 180;
    return [cx + r * Math.cos(a), cy + r * Math.sin(a)];
  };
  const ring = Array.from({ length: 6 }, (_, i) => pt(i))
    .map(([x, y], i) => `${i ? 'L' : 'M'} ${n(x)} ${n(y)}`).join(' ') + ' Z';
  let inner;
  if (mode === 'aromatic') {
    inner = `<circle cx="${n(cx)}" cy="${n(cy)}" r="${n(r * 0.56)}" fill="none" stroke="${stroke}" stroke-opacity="0.9" stroke-width="${n(width)}"/>`;
  } else {
    /* Kekule: a short line inside, parallel to every other ring edge. */
    inner = '';
    const d = r * 0.17, t = 0.18;
    for (let i = 0; i < 6; i += 2) {
      const [x1, y1] = pt(i), [x2, y2] = pt(i + 1);
      const mx = (x1 + x2) / 2, my = (y1 + y2) / 2;
      const L = Math.hypot(cx - mx, cy - my) || 1;
      const ux = ((cx - mx) / L) * d, uy = ((cy - my) / L) * d;
      const ax = x1 + (mx - x1) * t + ux, ay = y1 + (my - y1) * t + uy;
      const bx = x2 + (mx - x2) * t + ux, by = y2 + (my - y2) * t + uy;
      inner += `<path d="M ${n(ax)} ${n(ay)} L ${n(bx)} ${n(by)}" fill="none" stroke="${stroke}" stroke-opacity="0.9" stroke-width="${n(width)}" stroke-linecap="round"/>`;
    }
  }
  return `<g id="Skeletal-C6H6" opacity="${n(opacity)}">
    <path d="${ring}" fill="none" stroke="${stroke}" stroke-opacity="0.9" stroke-width="${n(width)}" stroke-linejoin="round"/>
    ${inner}
  </g>`;
}

/* -------------------------------------------------------- graphene lattice
   A honeycomb of sp2 carbon — a real structure, used as quiet background
   texture rather than an invented node graph. */
export function lattice({ x, y, cols = 6, rows = 4, a = 64, opacity = 0.05,
                          stroke = C.accent, width = 4 } = {}) {
  /* Pointy-top hexagons of circumradius `a` (= the C-C bond length) tiled on
     the standard hex grid, then de-duplicated so shared edges are stroked once
     and never read heavier than the rest. */
  const W = Math.sqrt(3) * a;
  const edges = new Map();
  const key = (p, q) => {
    const A = `${p[0].toFixed(2)},${p[1].toFixed(2)}`;
    const B = `${q[0].toFixed(2)},${q[1].toFixed(2)}`;
    return A < B ? `${A}|${B}` : `${B}|${A}`;
  };
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const hx = x + c * W + (r % 2 ? W / 2 : 0);
      const hy = y + r * 1.5 * a;
      const v = [];
      for (let i = 0; i < 6; i++) {
        const t = (Math.PI / 3) * i + Math.PI / 6;
        v.push([hx + a * Math.cos(t), hy + a * Math.sin(t)]);
      }
      for (let i = 0; i < 6; i++) {
        const p = v[i], q = v[(i + 1) % 6];
        const k = key(p, q);
        if (!edges.has(k)) edges.set(k, [p, q]);
      }
    }
  }
  const d = [...edges.values()]
    .map(([p, q]) => `M ${n(p[0])} ${n(p[1])} L ${n(q[0])} ${n(q[1])}`).join(' ');
  return `<g id="Lattice" opacity="${n(opacity)}"><path d="${d}" fill="none" stroke="${stroke}" stroke-opacity="0.9" stroke-width="${n(width)}" stroke-linecap="round"/></g>`;
}

/* --------------------------------------------------- periodic table fragment
   The true period 1-4 layout: H and He split across groups 1 and 18, the
   p-block starting at group 13 in periods 2 and 3, period 4 filled 1-18. */
const PT_ROWS = [
  [1, 18],
  [1, 2, 13, 14, 15, 16, 17, 18],
  [1, 2, 13, 14, 15, 16, 17, 18],
  Array.from({ length: 18 }, (_, i) => i + 1),
];

export function periodicFragment({ x, y, cell = 54, gap = 9, opacity = 0.055,
                                   fill = C.accent, rows = 4, highlight = {} } = {}) {
  let out = '';
  for (let r = 0; r < Math.min(rows, PT_ROWS.length); r++) {
    for (const g of PT_ROWS[r]) {
      const px = x + (g - 1) * (cell + gap);
      const py = y + r * (cell + gap);
      const hi = highlight[`${r}-${g}`];
      out += `<path d="${roundRect(px, py, cell, cell, cell * 0.2)}" fill="${hi || fill}" ` +
             `fill-opacity="${hi ? 0.85 : 0.5}"/>`;
    }
  }
  return `<g id="Periodic-Fragment" opacity="${n(opacity)}">${out}</g>`;
}

/* ------------------------------------------------------------- orbit rings
   Three ellipses at 60 deg — the classic electron-orbit motif. */
export function orbits({ cx, cy, r = 200, opacity = 0.07, stroke = C.accent,
                         width = 5, flatten = 0.36, nucleus = true } = {}) {
  let out = '';
  for (const a of [0, 60, 120]) {
    out += `<ellipse cx="${n(cx)}" cy="${n(cy)}" rx="${n(r)}" ry="${n(r * flatten)}" ` +
      `fill="none" stroke="${stroke}" stroke-opacity="0.9" stroke-width="${n(width)}" ` +
      `transform="rotate(${a} ${n(cx)} ${n(cy)})"/>`;
  }
  if (nucleus) out += `<circle cx="${n(cx)}" cy="${n(cy)}" r="${n(r * 0.085)}" fill="${stroke}" fill-opacity="0.8"/>`;
  return `<g id="Orbits" opacity="${n(opacity)}">${out}</g>`;
}

/* ---------------------------------------------------------------- equations
   All balanced. */
export const EQUATIONS = {
  combustionH2: '2H2 + O2 → 2H2O',
  combustionCH4: 'CH4 + 2O2 → CO2 + 2H2O',
  haber: 'N2 + 3H2 ⇌ 2NH3',
  saltFormation: '2Na + Cl2 → 2NaCl',
};
