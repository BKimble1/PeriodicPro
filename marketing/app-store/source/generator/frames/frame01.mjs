/* 01  HERO.  One large centred device, dead straight so the hero capture stays
   pixel sharp. Composition: CENTRE HERO. The quietest decoration in the set:
   a half benzene leaving the left edge, half a naphthalene leaving the right,
   two element tiles and a barely-there orbit diagram in the bottom corner. */
import { C } from '../system.mjs';
import { skeletal, elementTile, orbits } from '../chemistry.mjs';

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
    elementTile('C', { x: 1152, y: 116, w: 176, opacity: 0.07, rot: 4 }),
    elementTile('O', { x: -34, y: 2364, w: 182, opacity: 0.06, rot: -5 }),
    orbits({ cx: 36, cy: 2768, r: 232, opacity: 0.05 }),
    skeletal('benzene', { cx: 16, cy: 1480, scale: 152, opacity: 0.062, width: 8 }),
    skeletal('naphthalene', { cx: 1316, cy: 2076, scale: 112, rot: 90, opacity: 0.058, width: 8 }),
  ].join('\n'),
};
