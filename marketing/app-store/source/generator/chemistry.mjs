/* ============================================================================
   Elemora, chemistry decoration library.

   The decorative language is SKELETAL: line-angle structural formulas, rings,
   fused ring systems, orbital and electron-shell diagrams, periodic tiles and
   balanced equations, all drawn as thin scientific linework at watermark
   strength. There is deliberately no 3D ball-and-stick artwork here; the only
   molecular rendering Elemora's marketing shows in three dimensions is whatever
   the real app draws inside a real screenshot.

   Everything is scientifically checked:

   * atomic numbers, standard atomic weights (IUPAC 2021 abridged), groups,
     periods, categories and electron-shell occupancies are from reference data
   * every skeletal structure carries its real molecular formula, and verify.py
     re-derives that formula from the drawn graph (bond orders plus implicit
     hydrogens) rather than trusting the label
   * ring geometry is exact: regular hexagons of unit bond length, a regular
     pentagon fused at a shared edge for the purine system
   * the lattice motif is a graphene honeycomb, not an invented node graph
   * the periodic fragment uses the true period 1-4 layout, gaps included
   ========================================================================== */

import { n, esc, roundRect, C } from './system.mjs';

/* Kept so frames and the build share one signature; the skeletal language
   needs no gradients, so this is usually empty. */
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

/* ----------------------------------------------------- skeletal structures
   Coordinates are in bond lengths: every drawn bond is exactly 1 unit and
   every ring is regular, which is what makes line-angle formulas read as
   chemistry rather than as decoration. Unlabelled vertices are carbon with
   implicit hydrogens, the standard convention. */

const D2R = Math.PI / 180;

/** Regular hexagon, unit side (circumradius 1). */
function hex(cx, cy, start) {
  return Array.from({ length: 6 }, (_, i) => {
    const t = (start + 60 * i) * D2R;
    return [cx + Math.cos(t), cy + Math.sin(t)];
  });
}

/** Zig-zag carbon chain of `k` vertices, 120 deg at every vertex. */
function chain(k, x0 = 0, y0 = 0) {
  const dx = Math.cos(30 * D2R), dy = Math.sin(30 * D2R);
  return Array.from({ length: k }, (_, i) => [x0 + i * dx, y0 + (i % 2 ? 0 : dy)]);
}

/** Unit vector from the ring centre through vertex `p`, for substituents. */
function out(p, c) {
  const dx = p[0] - c[0], dy = p[1] - c[1], L = Math.hypot(dx, dy) || 1;
  return [p[0] + dx / L, p[1] + dy / L];
}

/* -- benzene, and the rings built on it ---------------------------------- */
const BZ = hex(0, 0, 90);
const ringBonds = (o = 0) =>
  Array.from({ length: 6 }, (_, i) => [i, (i + 1) % 6, (i + o) % 2 ? 1 : 2]);

/* -- naphthalene: two hexagons fused across a shared edge ----------------- */
const NA_A = hex(0, 0, 0);                       // vertices at 0,60,...,300
const NA_B = hex(0, 2 * Math.sin(60 * D2R), 0);  // centre sqrt(3) above
/* A[1] and A[2] are the shared edge; they are B[5] and B[4]. */
const NA = [...NA_A, NA_B[0], NA_B[1], NA_B[2], NA_B[3]];

/* -- caffeine: 1,3,7-trimethylpurine-2,6-dione ---------------------------- */
const CAF6 = hex(0, 0, 30);            // 0:C5 1:C6 2:N1 3:C2 4:N3 5:C4
const R5 = 1 / (2 * Math.sin(36 * D2R));
const AP5 = R5 * Math.cos(36 * D2R);
const P5C = [CAF6[0][0] + AP5, 0];
const pent = (deg) => [P5C[0] + R5 * Math.cos(deg * D2R), P5C[1] + R5 * Math.sin(deg * D2R)];
const CAF = [
  ...CAF6,
  pent(72), pent(0), pent(288),        // 6:N7 7:C8 8:N9
  [0, 2],                              // 9:  O on C6
  out(CAF6[3], [0, 0]),                // 10: O on C2
  out(CAF6[2], [0, 0]),                // 11: methyl on N1
  [0, -2],                             // 12: methyl on N3
  out(pent(72), P5C),                  // 13: methyl on N7
];

const C3 = chain(3);

export const SKELETAL = {
  benzene: {
    name: 'Benzene', formula: 'C6H6',
    pts: BZ, bonds: ringBonds(), rings: [[0, 1, 2, 3, 4, 5]],
  },
  cyclohexane: {
    name: 'Cyclohexane', formula: 'C6H12',
    pts: BZ, bonds: Array.from({ length: 6 }, (_, i) => [i, (i + 1) % 6, 1]),
  },
  toluene: {
    name: 'Toluene', formula: 'C7H8',
    pts: [...BZ, out(BZ[0], [0, 0])],
    bonds: [...ringBonds(), [0, 6, 1]], rings: [[0, 1, 2, 3, 4, 5]],
  },
  phenol: {
    name: 'Phenol', formula: 'C6H6O',
    pts: [...BZ, out(BZ[0], [0, 0])],
    bonds: [...ringBonds(), [0, 6, 1]], labels: { 6: 'OH' },
    rings: [[0, 1, 2, 3, 4, 5]],
  },
  naphthalene: {
    name: 'Naphthalene', formula: 'C10H8',
    pts: NA,
    /* ring A: 0-1 1-2 2-3 3-4 4-5 5-0 ; ring B: 1-6 6-7 7-8 8-9 9-2 */
    bonds: [
      [0, 1, 2], [1, 2, 1], [2, 3, 2], [3, 4, 1], [4, 5, 2], [5, 0, 1],
      [1, 6, 1], [6, 7, 2], [7, 8, 1], [8, 9, 2], [9, 2, 1],
    ],
    rings: [[0, 1, 2, 3, 4, 5], [1, 6, 7, 8, 9, 2]],
  },
  ethanol: {
    name: 'Ethanol', formula: 'C2H6O',
    pts: chain(3), bonds: [[0, 1, 1], [1, 2, 1]], labels: { 2: 'OH' },
  },
  /* The carbonyl points opposite the bisector of the two other bonds, so all
     three angles at the central carbon are a true 120 deg. */
  acetone: {
    name: 'Acetone', formula: 'C3H6O',
    pts: [...C3, [C3[1][0], C3[1][1] - 1]],
    bonds: [[0, 1, 1], [1, 2, 1], [1, 3, 2]], labels: { 3: 'O' },
  },
  aceticAcid: {
    name: 'Acetic acid', formula: 'C2H4O2',
    pts: [...C3, [C3[1][0], C3[1][1] - 1]],
    bonds: [[0, 1, 1], [1, 2, 1], [1, 3, 2]], labels: { 2: 'OH', 3: 'O' },
  },
  butane: {
    name: 'Butane', formula: 'C4H10',
    pts: chain(4), bonds: [[0, 1, 1], [1, 2, 1], [2, 3, 1]],
  },
  hexane: {
    name: 'Hexane', formula: 'C6H14',
    pts: chain(6),
    bonds: [[0, 1, 1], [1, 2, 1], [2, 3, 1], [3, 4, 1], [4, 5, 1]],
  },
  decane: {
    name: 'Decane', formula: 'C10H22',
    pts: chain(10),
    bonds: Array.from({ length: 9 }, (_, i) => [i, i + 1, 1]),
  },
  caffeine: {
    name: 'Caffeine', formula: 'C8H10N4O2',
    pts: CAF,
    bonds: [
      [2, 3, 1], [3, 4, 1], [4, 5, 1], [5, 0, 2], [0, 1, 1], [1, 2, 1],
      [1, 9, 2], [3, 10, 2],
      [0, 6, 1], [6, 7, 1], [7, 8, 2], [8, 5, 1],
      [2, 11, 1], [4, 12, 1], [6, 13, 1],
    ],
    labels: { 2: 'N', 4: 'N', 6: 'N', 8: 'N', 9: 'O', 10: 'O' },
  },
};

/* ------------------------------------------------------- skeletal renderer
   Bonds are drawn on the line-angle axis. A double bond in a ring gets a
   shortened inner companion line; a double bond to a terminal atom gets a
   symmetric pair, which is how C=O is conventionally set. Bonds stop short of
   a labelled atom so the glyph sits in clear space. */

function seg(a, b) {
  return `M ${n(a[0])} ${n(a[1])} L ${n(b[0])} ${n(b[1])}`;
}

export function skeletal(name, {
  cx, cy, scale = 90, rot = 0, opacity = 0.06, stroke = C.accent,
  width = 7, labelSize = 0, mode = 'kekule',
} = {}) {
  const S = SKELETAL[name];
  if (!S) throw new Error('unknown skeletal structure: ' + name);
  const ls = labelSize || scale * 0.40;
  const cosr = Math.cos(rot * D2R), sinr = Math.sin(rot * D2R);
  const P = S.pts.map(([x, y]) => [
    cx + (x * cosr - y * sinr) * scale,
    cy - (x * sinr + y * cosr) * scale,        // SVG y runs down
  ]);

  const label = (i) => (S.labels || {})[i];
  const gapAt = (i) => (label(i) ? ls * 0.72 : 0);

  const deg = P.map(() => 0);
  const nbr = P.map(() => []);
  for (const [i, j] of S.bonds) { deg[i]++; deg[j]++; nbr[i].push(j); nbr[j].push(i); }

  const aromatic = mode === 'aromatic' && S.rings;
  let d = '';

  for (const [i, j, order = 1] of S.bonds) {
    const A = P[i], B = P[j];
    const dx = B[0] - A[0], dy = B[1] - A[1], L = Math.hypot(dx, dy) || 1;
    const ux = dx / L, uy = dy / L;
    const gi = gapAt(i), gj = gapAt(j);
    const a = [A[0] + ux * gi, A[1] + uy * gi];
    const b = [B[0] - ux * gj, B[1] - uy * gj];
    const px = -uy, py = ux;
    const off = scale * 0.135;

    if (order === 1 || aromatic) {
      d += seg(a, b) + ' ';
      continue;
    }
    if (order === 2 && (deg[i] === 1 || deg[j] === 1)) {
      /* terminal double bond (C=O): symmetric pair */
      d += seg([a[0] + px * off * 0.62, a[1] + py * off * 0.62],
               [b[0] + px * off * 0.62, b[1] + py * off * 0.62]) + ' ';
      d += seg([a[0] - px * off * 0.62, a[1] - py * off * 0.62],
               [b[0] - px * off * 0.62, b[1] - py * off * 0.62]) + ' ';
      continue;
    }
    /* interior double bond: main axis plus a shortened inner companion */
    d += seg(a, b) + ' ';
    const others = [...nbr[i].filter((k) => k !== j), ...nbr[j].filter((k) => k !== i)];
    let sx = 0, sy = 0;
    for (const k of others) { sx += P[k][0]; sy += P[k][1]; }
    const mx = (a[0] + b[0]) / 2, my = (a[1] + b[1]) / 2;
    const side = others.length
      ? Math.sign(px * (sx / others.length - mx) + py * (sy / others.length - my)) || 1
      : 1;
    const t = 0.16;
    const ia = [a[0] + (b[0] - a[0]) * t + px * off * side, a[1] + (b[1] - a[1]) * t + py * off * side];
    const ib = [b[0] - (b[0] - a[0]) * t + px * off * side, b[1] - (b[1] - a[1]) * t + py * off * side];
    d += seg(ia, ib) + ' ';
    if (order === 3) {
      d += seg([a[0] - px * off, a[1] - py * off], [b[0] - px * off, b[1] - py * off]) + ' ';
    }
  }

  let extra = '';
  if (aromatic) {
    for (const ring of S.rings) {
      let rx = 0, ry = 0;
      for (const k of ring) { rx += P[k][0]; ry += P[k][1]; }
      rx /= ring.length; ry /= ring.length;
      extra += `<circle cx="${n(rx)}" cy="${n(ry)}" r="${n(scale * 0.56)}" fill="none" ` +
        `stroke="${stroke}" stroke-opacity="0.9" stroke-width="${n(width)}"/>`;
    }
  }
  for (const [i, txt] of Object.entries(S.labels || {})) {
    const [x, y] = P[i];
    extra += `<text x="${n(x)}" y="${n(y + ls * 0.35)}" text-anchor="middle" ` +
      `style="font-size:${n(ls)}px;font-weight:600" fill="${stroke}" fill-opacity="0.95">${esc(txt)}</text>`;
  }

  return `<g id="Skeletal-${S.formula}" opacity="${n(opacity)}">
    <path d="${d.trim()}" fill="none" stroke="${stroke}" stroke-opacity="0.9" stroke-width="${n(width)}" stroke-linecap="round" stroke-linejoin="round"/>
    ${extra}
  </g>`;
}

/* ------------------------------------------------------- chemical formulae
   Digits that follow a letter or ')' render as subscripts; leading digits stay
   full size so stoichiometric coefficients read correctly. */
export function chemText(str, size) {
  const sub = size * 0.20;
  let out2 = '';
  let prev = '';
  for (const ch of str) {
    const isSub = /[0-9]/.test(ch) && /[A-Za-z)\]]/.test(prev);
    if (isSub) {
      out2 += `<tspan dy="${n(sub)}" style="font-size:${n(size * 0.62)}px">${esc(ch)}</tspan>` +
              `<tspan dy="${n(-sub)}">&#8203;</tspan>`;
    } else {
      out2 += esc(ch);
    }
    if (ch !== ' ') prev = ch;
  }
  return out2;
}

export function formula(str, { x, y, size = 80, fill = C.accent, opacity = 0.08,
                               weight = 600, anchor = 'start', track = 0, rot = 0 } = {}) {
  const t = rot ? ` transform="rotate(${n(rot)} ${n(x)} ${n(y)})"` : '';
  return `<text x="${n(x)}" y="${n(y)}"${t} text-anchor="${anchor}" ` +
    `style="font-size:${n(size)}px;font-weight:${weight};letter-spacing:${n(track)}px" ` +
    `fill="${fill}" fill-opacity="${n(opacity)}">${chemText(str, size)}</text>`;
}

/* --------------------------------------------------------------- element tile
   variant 'ghost' = outline only (background texture)
   variant 'soft'  = pale fill + hairline (closer, still quiet) */
export function elementTile(sym, { x, y, w = 150, variant = 'ghost', opacity = 0.07,
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

/* ------------------------------------------------------------ Bohr diagram */
export function bohr(sym, { cx, cy, r = 220, opacity = 0.07, stroke = C.accent,
                            dot = C.accent, label = false } = {}) {
  const e = ELEMENTS[sym];
  if (!e) throw new Error('unknown element: ' + sym);
  const sh = e.shells;
  let out2 = `<circle cx="${n(cx)}" cy="${n(cy)}" r="${n(r * 0.085)}" fill="${stroke}" fill-opacity="0.55"/>`;
  sh.forEach((count, i) => {
    const rr = r * (0.26 + (0.74 * (i + 1)) / sh.length);
    out2 += `<circle cx="${n(cx)}" cy="${n(cy)}" r="${n(rr)}" fill="none" stroke="${stroke}" stroke-opacity="0.45" stroke-width="${n(r * 0.009)}"/>`;
    for (let k = 0; k < count; k++) {
      const a = (2 * Math.PI * k) / count - Math.PI / 2 + i * 0.28;
      out2 += `<circle cx="${n(cx + rr * Math.cos(a))}" cy="${n(cy + rr * Math.sin(a))}" r="${n(r * 0.030)}" fill="${dot}" fill-opacity="0.9"/>`;
    }
  });
  if (label) {
    out2 += `<text x="${n(cx)}" y="${n(cy + r * 1.30)}" text-anchor="middle" style="font-size:${n(r * 0.17)}px;font-weight:600" fill="${C.ink}" fill-opacity="0.8">${sym}</text>`;
  }
  return `<g id="Bohr-${sym}" opacity="${n(opacity)}">${out2}</g>`;
}

/* -------------------------------------------------------- graphene lattice */
export function lattice({ x, y, cols = 6, rows = 4, a = 64, opacity = 0.045,
                          stroke = C.accent, width = 4 } = {}) {
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

export function periodicFragment({ x, y, cell = 54, gap = 9, opacity = 0.05,
                                   fill = C.accent, rows = 4, highlight = {} } = {}) {
  let out2 = '';
  for (let r = 0; r < Math.min(rows, PT_ROWS.length); r++) {
    for (const g of PT_ROWS[r]) {
      const px = x + (g - 1) * (cell + gap);
      const py = y + r * (cell + gap);
      const hi = highlight[`${r}-${g}`];
      out2 += `<path d="${roundRect(px, py, cell, cell, cell * 0.2)}" fill="${hi || fill}" ` +
              `fill-opacity="${hi ? 0.85 : 0.5}"/>`;
    }
  }
  return `<g id="Periodic-Fragment" opacity="${n(opacity)}">${out2}</g>`;
}

/* ------------------------------------------------------------- orbit rings */
export function orbits({ cx, cy, r = 200, opacity = 0.06, stroke = C.accent,
                         width = 5, flatten = 0.36, nucleus = true, rot = 0 } = {}) {
  let out2 = '';
  for (const a of [0, 60, 120]) {
    out2 += `<ellipse cx="${n(cx)}" cy="${n(cy)}" rx="${n(r)}" ry="${n(r * flatten)}" ` +
      `fill="none" stroke="${stroke}" stroke-opacity="0.9" stroke-width="${n(width)}" ` +
      `transform="rotate(${n(a + rot)} ${n(cx)} ${n(cy)})"/>`;
  }
  if (nucleus) out2 += `<circle cx="${n(cx)}" cy="${n(cy)}" r="${n(r * 0.085)}" fill="${stroke}" fill-opacity="0.8"/>`;
  return `<g id="Orbits" opacity="${n(opacity)}">${out2}</g>`;
}

/* ---------------------------------------------------------------- equations
   All balanced. */
export const EQUATIONS = {
  combustionH2: '2H2 + O2 → 2H2O',
  combustionCH4: 'CH4 + 2O2 → CO2 + 2H2O',
  haber: 'N2 + 3H2 ⇌ 2NH3',
  saltFormation: '2Na + Cl2 → 2NaCl',
  photosynthesis: '6CO2 + 6H2O → C6H12O6 + 6O2',
};
