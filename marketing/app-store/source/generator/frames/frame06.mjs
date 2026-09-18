/* 06  PROGRESS.  The closing image: one large device, perfectly vertical, pushed
   right so that about a seventh of its width runs off the right edge. The full
   left edge, the top left corner and most of the screen stay on the canvas; the
   asymmetric crop alone carries the composition, which is the CoreCredit closing
   move. After frame 01 this is the cleanest background in the set.

   Background hierarchy
     anchor     a period 1-4 table fragment low on the canvas, running behind
                the device and out the left margin
     secondary  one very large, very pale orbit diagram centred on the device,
                so only its left lobe surfaces in the open margin
     ambient    a balanced equation along the bottom                          */
import { C } from '../system.mjs';
import { periodicFragment, orbits, formula, EQUATIONS } from '../chemistry.mjs';

export default {
  id: '06', slug: 'progress',
  title: 'Elemora 06 Progress',
  headline: ['See Your', 'Progress'],
  sub: ['Track mastery, activity, and what', 'to review next.'],
  copy: { top: 236, align: 'start' },
  devices: [{
    role: 'hero', label: 'Progress', screenW: 960, x: 429.4, y: 680, rot: 0, bleed: true,
    need: 'The progress or mastery view, with enough real activity on it to look earned. The rightmost ninth of the screen runs off the canvas, so keep headline numbers and labels left of centre.',
  }],
  light: [
    { x: 380, y: 1700, r: 1160, c: C.paleC, o: 0.54 },
    { x: 1160, y: 540, r: 1000, c: C.paleB, o: 0.46 },
    { x: 180, y: 2680, r: 900, c: C.paleA, o: 0.48 },
  ],
  deco: () => [
    periodicFragment({ x: -180, y: 2360, cell: 72, gap: 11, opacity: 0.09 }),
    orbits({ cx: 950, cy: 1660, r: 820, opacity: 0.045, width: 6, flatten: 0.4 }),
    formula(EQUATIONS.combustionH2, { x: 96, y: 2846, size: 48, opacity: 0.04 }),
  ],
};
