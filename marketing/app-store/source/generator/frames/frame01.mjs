/* 01 — HERO.  Centre hero, straight-on device for maximum screenshot clarity.
   A cropped ethane model enters the top-right corner above the headline; water
   and methane sit at the side margins and tuck behind the phone. */
import { C } from '../system.mjs';
import { molecule, elementTile, bohr, formula, EQUATIONS } from '../chemistry.mjs';

export default {
  id: '01', slug: 'hero',
  title: 'Elemora — 01 Hero',
  label: 'Home',
  need: 'Home screen. The single strongest top-level introduction to Elemora.',
  headline: ['Learn Chemistry', 'Visually'],
  sub: ['Explore elements, build molecules, and', 'master chemistry — all in one app.'],
  copy: { top: 236, align: 'start' },
  device: { rot: 0 },
  light: [
    { x: 210, y: 380, r: 1180, c: C.paleC, o: 0.60 },
    { x: 1210, y: 1560, r: 1080, c: C.paleB, o: 0.46 },
    { x: 640, y: 2760, r: 940, c: C.paleA, o: 0.52 },
  ],
  deco: (D) => [
    elementTile('O', { x: -34, y: 900, w: 214, opacity: 0.085, rot: -6 }),
    elementTile('H', { x: 1178, y: 604, w: 196, opacity: 0.075, rot: 5 }),
    bohr('C', { cx: 58, cy: 2706, r: 262, opacity: 0.075 }),
    formula(EQUATIONS.combustionH2, { x: 1224, y: 2812, size: 56, opacity: 0.13, anchor: 'end' }),
    molecule(D, 'ethane', { cx: 1300, cy: 30, scale: 98, rx: -18, ry: 38, rz: -16 }),
    molecule(D, 'water', { cx: 30, cy: 1420, scale: 122, rx: -10, ry: 24, rz: -6 }),
    molecule(D, 'methane', { cx: 1302, cy: 2080, scale: 152, rx: -16, ry: 30, rz: 8 }),
  ].join('\n'),
};
