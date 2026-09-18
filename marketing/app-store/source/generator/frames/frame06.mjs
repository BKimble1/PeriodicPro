/* 06  PROGRESS.  Composition: SINGLE DEVICE, HARD OFFSET. The closing image
   returns to one phone but places it nothing like frame 01: rising out of the
   lower left corner, cropped on two sides, with the whole right of the canvas
   left deliberately empty. An ethanol chain and a hexane chain drift in from
   that empty side at watermark strength. */
import { C } from '../system.mjs';
import { skeletal, elementTile, periodicFragment, formula, EQUATIONS } from '../chemistry.mjs';

export default {
  id: '06', slug: 'progress',
  title: 'Elemora 06 Progress',
  headline: ['See Your', 'Progress'],
  sub: ['Track mastery, activity, and what', 'to review next.'],
  copy: { top: 236, align: 'start' },
  devices: [{
    role: 'hero', label: 'Progress', screenW: 960, x: -46, y: 940, rot: 5,
    need: 'The progress or mastery view, with enough real activity on it to look earned. Cropped on the left and bottom, so keep the headline numbers high and right.',
  }],
  light: [
    { x: 420, y: 1720, r: 1160, c: C.paleC, o: 0.56 },
    { x: 1140, y: 520, r: 1000, c: C.paleB, o: 0.46 },
    { x: 1160, y: 2620, r: 900, c: C.paleA, o: 0.50 },
  ],
  deco: () => [
    periodicFragment({ x: 704, y: 88, cell: 30, gap: 5, opacity: 0.065 }),
    formula(EQUATIONS.combustionH2, { x: 1224, y: 790, size: 50, opacity: 0.09, anchor: 'end' }),
    elementTile('Fe', { x: 1158, y: 2276, w: 184, opacity: 0.07, rot: 4 }),
    skeletal('hexane', { cx: 1272, cy: 1452, scale: 134, rot: -14, opacity: 0.075, width: 10 }),
    skeletal('ethanol', { cx: 1252, cy: 1872, scale: 122, rot: 8, opacity: 0.065, width: 10 }),
  ].join('\n'),
};
