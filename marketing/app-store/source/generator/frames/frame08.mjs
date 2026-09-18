/* 08 — OVERVIEW.  The closer. Straight on, a touch more air above and below the
   device, and the most restrained decoration in the set: one benzene model
   cropped into the top-right, one water model at the left margin, one balanced
   equation along the bottom. */
import { C } from '../system.mjs';
import { molecule, elementTile, formula, EQUATIONS } from '../chemistry.mjs';

export default {
  id: '08', slug: 'overview',
  title: 'Elemora — 08 Overview',
  label: 'Home or Periodic Table',
  need: 'Whichever single screen best sums the app up — usually the same capture as 01, or the periodic table.',
  headline: ['Chemistry,', 'Made Clear'],
  sub: ['A visual toolkit for exploring, building,', 'and understanding chemistry.'],
  copy: { top: 236, align: 'start' },
  device: { screenW: 862, dy: 40, rot: 0 },
  light: [
    { x: 1140, y: 380, r: 1160, c: C.paleC, o: 0.58 },
    { x: 180, y: 1640, r: 1080, c: C.paleB, o: 0.46 },
    { x: 660, y: 2800, r: 1000, c: C.paleA, o: 0.54 },
  ],
  deco: (D) => [
    elementTile('H', { x: -24, y: 980, w: 188, opacity: 0.085, rot: -5 }),
    formula(EQUATIONS.saltFormation, { x: 660, y: 2836, size: 54, opacity: 0.12, anchor: 'middle' }),
    molecule(D, 'benzene', { cx: 1276, cy: 206, scale: 96, rx: -52, ry: 18, rz: 14 }),
    molecule(D, 'water', { cx: 26, cy: 1640, scale: 130, rx: -10, ry: 24, rz: -8 }),
  ].join('\n'),
};
