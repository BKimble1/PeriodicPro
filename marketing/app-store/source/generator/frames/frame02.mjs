/* 02  PERIODIC TABLE.  The primary device is straight, full and large, because
   the real periodic table screen carries plenty of visual information on its
   own and the frame around it should stay calm.

   The second device is the Build phone, which lives almost entirely on slide 03
   and reaches back across the seam with its lower left corner only. See
   pair23.mjs: both slides derive it from one master composition, so the slice
   lines up exactly.

   Background hierarchy
     anchor     a period 1-4 table fragment sliding under the phone and out
                both sides
     secondary  an orbit diagram off the top right, partly hidden by the Build
                phone, and one oversized carbon tile half behind the main phone
     ambient    a balanced equation along the bottom                          */
import { C } from '../system.mjs';
import { elementTile, periodicFragment, orbits, formula, EQUATIONS } from '../chemistry.mjs';
import { buildOn } from './pair23.mjs';

const build = buildOn(0);

export default {
  id: '02', slug: 'elements',
  title: 'Elemora 02 Periodic table',
  headline: ['Explore Every', 'Element'],
  sub: ['Browse the periodic table and open', 'any element for the full picture.'],
  copy: { top: 236, align: 'start' },
  devices: [
    {
      role: 'main', label: 'Periodic Table', screenW: 900, x: 120, y: 740, rot: 0,
      need: 'The full periodic table, scrolled so the grid fills the screen. Straight on and fully visible, so nothing is cropped.',
    },
    {
      role: 'build', label: 'Build canvas',
      screenW: build.screenW, x: build.x, y: build.y, rot: build.rot,
      bleed: true, glow: true, masterX: build.x,
      hideLabel: true,
      need: 'The SAME Build capture used as the hero of frame 03. Only the lower left corner of the device reaches this slide, so almost no UI shows here; it is the device body that carries the eye into the next screenshot.',
    },
  ],
  light: [
    { x: 300, y: 1400, r: 1160, c: C.paleC, o: 0.58 },
    { x: 1140, y: 480, r: 980, c: C.paleB, o: 0.44 },
    { x: 520, y: 2740, r: 920, c: C.paleA, o: 0.48 },
  ],
  deco: () => [
    periodicFragment({ x: -100, y: 2560, cell: 72, gap: 11, opacity: 0.10 }),
    orbits({ cx: 1245, cy: 880, r: 215, opacity: 0.055 }),
    elementTile('C', { x: -46, y: 1320, w: 230, variant: 'soft', opacity: 0.06, rot: -4 }),
    formula(EQUATIONS.saltFormation, { x: 96, y: 2840, size: 44, opacity: 0.03 }),
  ],
};
