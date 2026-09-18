/* 01  HERO.  One full, straight, centred device: the calm introduction.

   Background hierarchy
     anchor     a naphthalene ring system straddling the phone's left edge:
                about a third of it sits in the open margin and the rest
                disappears behind the device, which is what gives the slide
                depth rather than decoration
     secondary  one element tile in the top right
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
    skeletal('naphthalene', { cx: 150, cy: 1880, scale: 248, rot: 12, opacity: 0.095, width: 12 }),
    elementTile('C', { x: 1150, y: 120, w: 178, opacity: 0.035, rot: 4 }),
    formula(EQUATIONS.combustionH2, { x: 660, y: 2848, size: 46, opacity: 0.028, anchor: 'middle' }),
  ],
};
