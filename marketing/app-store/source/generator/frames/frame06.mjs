/* 06  PROGRESS.  The closing image: one complete device, a small tilt, shifted well
   right of centre, opening a wide left margin, so the frame closes the set
   asymmetrically without cropping anything. After
   frame 01 this is the cleanest background in the set.

   Background hierarchy
     anchor     a period 1-4 table fragment running behind the device and out
                both sides, the scientific grid the headline is talking about
     secondary  one balanced equation along the bottom
     ambient    a single iron tile half hidden by the device                  */
import { C } from '../system.mjs';
import { elementTile, periodicFragment, formula, EQUATIONS } from '../chemistry.mjs';

export default {
  id: '06', slug: 'progress',
  title: 'Elemora 06 Progress',
  headline: ['See Your', 'Progress'],
  sub: ['Track mastery, activity, and what', 'to review next.'],
  copy: { top: 236, align: 'start' },
  devices: [{
    role: 'hero', label: 'Progress', screenW: 960, x: 403.4, y: 680, rot: 0, bleed: true,
    need: 'The progress or mastery view, with enough real activity on it to look earned. The rightmost ninth of the screen runs off the canvas, so keep headline numbers and labels left of centre.',
  }],
  light: [
    { x: 420, y: 1700, r: 1160, c: C.paleC, o: 0.54 },
    { x: 1160, y: 540, r: 1000, c: C.paleB, o: 0.46 },
    { x: 180, y: 2680, r: 900, c: C.paleA, o: 0.48 },
  ],
  deco: () => [
    periodicFragment({ x: -160, y: 1500, cell: 72, gap: 11, opacity: 0.10 }),
    formula(EQUATIONS.combustionH2, { x: 96, y: 2846, size: 48, opacity: 0.05 }),
    elementTile('Fe', { x: 44, y: 912, w: 182, opacity: 0.03, rot: -5 }),
  ],
};
