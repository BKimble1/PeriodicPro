/* 01  HERO.  One full, straight, centred device: the calm introduction.

   Background hierarchy
     anchor     a decane chain crossing the whole canvas, entering at the left
                margin, vanishing behind the phone and reappearing on the right
     secondary  two element tiles, one of them tucked behind the phone edge
     ambient    a balanced equation along the bottom                          */
import { C } from '../system.mjs';
import { skeletal, elementTile, formula, EQUATIONS } from '../chemistry.mjs';

export default {
  id: '01', slug: 'hero',
  title: 'Elemora 01 Hero',
  headline: ['Learn Chemistry', 'Visually'],
  sub: ['Explore elements, build molecules, and', 'master chemistry, all in one app.'],
  copy: { top: 236, align: 'start' },
  devices: [{
    role: 'hero', label: 'Home', screenW: 912, x: 165.24, y: 762, rot: 0,
    need: 'Home screen. The strongest top level introduction to Elemora, and the most important capture in the set.',
  }],
  light: [
    { x: 240, y: 400, r: 1180, c: C.paleC, o: 0.56 },
    { x: 1180, y: 1520, r: 1060, c: C.paleB, o: 0.42 },
    { x: 660, y: 2780, r: 940, c: C.paleA, o: 0.50 },
  ],
  deco: () => [
    skeletal('decane', { cx: 660, cy: 2150, scale: 150, rot: 5, opacity: 0.10, width: 9 }),
    elementTile('C', { x: 1150, y: 120, w: 178, opacity: 0.055, rot: 4 }),
    elementTile('O', { x: 30, y: 1180, w: 186, opacity: 0.05, rot: -5 }),
    formula(EQUATIONS.combustionH2, { x: 660, y: 2848, size: 46, opacity: 0.032, anchor: 'middle' }),
  ],
};
