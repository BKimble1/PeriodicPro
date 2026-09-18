/* 02  PERIODIC TABLE.  The primary device is straight, full and large, because
   the real periodic table screen carries plenty of visual information on its
   own and the frame around it should stay calm.

   A much smaller secondary device sits at the right edge and is the only thing
   in this frame allowed to leave the canvas. It is the first half of the
   handoff into frame 03: same screen width, same rotation, same y, and it shows
   its LEFT side here because it is on its way out to the right. Frame 03 picks
   the same device up at its left edge showing its RIGHT side. The two frames
   still read correctly on their own.

   Background hierarchy
     anchor     a period 1-4 table fragment sliding under the phone and out
                both sides
     secondary  an orbit diagram off the top right, one oversized carbon tile
                half hidden behind the phone
     ambient    a balanced equation along the bottom                          */
import { C } from '../system.mjs';
import { elementTile, periodicFragment, orbits, formula, EQUATIONS } from '../chemistry.mjs';

/* shared with frame 03: the handoff device must match on all three */
export const HANDOFF = { screenW: 620, rot: 0, y: 1180 };

export default {
  id: '02', slug: 'elements',
  title: 'Elemora 02 Periodic table',
  headline: ['Explore Every', 'Element'],
  sub: ['Browse the periodic table and open', 'any element for the full picture.'],
  copy: { top: 236, align: 'start' },
  devices: [
    {
      role: 'handoff', label: 'Element detail',
      screenW: HANDOFF.screenW, x: 1150, y: HANDOFF.y, rot: HANDOFF.rot,
      need: 'An element detail screen, the same capture used at the left edge of frame 03 and as frame 04. Only its left side shows here, so keep the element tile and name in the left half.',
    },
    {
      role: 'main', label: 'Periodic Table', screenW: 900, x: 120, y: 740, rot: 0,
      need: 'The full periodic table, scrolled so the grid fills the screen. Fully visible and straight on, so nothing is cropped.',
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
