/* 02 — PERIODIC TABLE.  Right-biased, gently tilted device. The left margin
   carries a true period 1-4 table fragment and three legible element tiles. */
import { C } from '../system.mjs';
import { molecule, elementTile, periodicFragment, orbits, formula } from '../chemistry.mjs';

export default {
  id: '02', slug: 'elements',
  title: 'Elemora — 02 Periodic table',
  label: 'Periodic Table',
  need: 'The full periodic table view, scrolled so the table fills the screen.',
  headline: ['Explore Every', 'Element'],
  sub: ['Browse the periodic table and open', 'any element for the full picture.'],
  copy: { top: 236, align: 'start' },
  device: { dx: 105, rot: -3.5 },
  light: [
    { x: 240, y: 1450, r: 1120, c: C.paleC, o: 0.62 },
    { x: 1120, y: 420, r: 980, c: C.paleB, o: 0.44 },
    { x: 300, y: 2740, r: 900, c: C.paleA, o: 0.46 },
  ],
  deco: (D) => [
    periodicFragment({ x: -62, y: 1146, cell: 56, gap: 9, opacity: 0.065 }),
    elementTile('C', { x: 24, y: 962, w: 182, variant: 'soft', opacity: 0.17, rot: -5 }),
    elementTile('O', { x: 20, y: 1560, w: 174, opacity: 0.11, rot: 3 }),
    elementTile('Fe', { x: 16, y: 1890, w: 170, opacity: 0.095, rot: -3 }),
    orbits({ cx: 96, cy: 2440, r: 238, opacity: 0.075 }),
    formula('C6H6', { x: 96, y: 2820, size: 72, opacity: 0.12 }),
    molecule(D, 'dioxygen', { cx: 1236, cy: 300, scale: 92, rx: 0, ry: 22, rz: -20 }),
  ].join('\n'),
};
