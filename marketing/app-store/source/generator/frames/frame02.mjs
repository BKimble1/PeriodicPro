/* 02  PERIODIC TABLE.  Composition: OVERSIZED DIAGONAL ENTRY. The largest
   single device in the set leans in from the lower right and runs off both the
   right and bottom edges, opening a wide diagonal of negative space on the
   left. That space carries a true period 1-4 table fragment and two oversized
   element tiles, so the decoration says "periodic table" before the screenshot
   does. */
import { C } from '../system.mjs';
import { skeletal, elementTile, periodicFragment } from '../chemistry.mjs';

export default {
  id: '02', slug: 'elements',
  title: 'Elemora 02 Periodic table',
  headline: ['Explore Every', 'Element'],
  sub: ['Browse the periodic table and open', 'any element for the full picture.'],
  copy: { top: 236, align: 'start' },
  devices: [{
    role: 'hero', label: 'Periodic Table', screenW: 1040, x: 470, y: 860, rot: -5,
    need: 'The full periodic table, scrolled so the grid fills the screen. The lower right of this capture is cropped by the canvas, so keep the important rows high.',
  }],
  light: [
    { x: 250, y: 1500, r: 1140, c: C.paleC, o: 0.62 },
    { x: 1080, y: 380, r: 960, c: C.paleB, o: 0.42 },
    { x: 220, y: 2760, r: 900, c: C.paleA, o: 0.46 },
  ],
  deco: () => [
    periodicFragment({ x: -80, y: 1204, cell: 58, gap: 9, opacity: 0.058 }),
    elementTile('C', { x: 28, y: 1560, w: 238, variant: 'soft', opacity: 0.13, rot: -4 }),
    elementTile('Fe', { x: 44, y: 1910, w: 206, opacity: 0.075, rot: 3 }),
    elementTile('O', { x: 1116, y: 168, w: 172, opacity: 0.065, rot: 5 }),
    skeletal('benzene', { cx: 6, cy: 2424, scale: 152, opacity: 0.072, width: 10 }),
  ].join('\n'),
};
