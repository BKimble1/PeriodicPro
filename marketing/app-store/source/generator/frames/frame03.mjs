/* 03  BUILD.  One device, and it is the biggest single statement in the set:
   the Build phone that began at the right edge of slide 02 arrives here and
   takes the whole lower two thirds of the canvas. No supporting phones, because
   the continuation is the idea and a second device would only dilute it.

   Its placement comes from the same master composition as slide 02 (pair23.mjs),
   so the two halves line up exactly.

   Background hierarchy
     anchor     a caffeine skeleton centred ON the device, so most of the ring
                system is hidden behind it and the rest surfaces in the open
                right margin
     secondary  its molecular formula, half occluded by the phone
     ambient    a nitrogen tile in the top band                               */
import { C } from '../system.mjs';
import { skeletal, elementTile, formula } from '../chemistry.mjs';
import { buildOn } from './pair23.mjs';

const build = buildOn(1);

export default {
  id: '03', slug: 'build',
  title: 'Elemora 03 Build',
  headline: ['Build Real', 'Molecules'],
  sub: ['Create compounds visually and see', 'how atoms connect.'],
  copy: { top: 236, align: 'start' },
  devices: [{
    role: 'build', label: 'Build canvas',
    screenW: build.screenW, x: build.x, y: build.y, rot: build.rot,
    bleed: true, masterX: build.x,
    need: 'The Build screen mid-assembly, with a molecule actually on the canvas, never an empty builder. The same capture continues off the right edge of frame 02. The leftmost seventh of the screen falls on that slide, so keep controls and the molecule itself away from the extreme left edge.',
  }],
  light: [
    { x: 1020, y: 1280, r: 1160, c: C.paleC, o: 0.56 },
    { x: 240, y: 460, r: 980, c: C.paleB, o: 0.44 },
    { x: 1120, y: 2740, r: 900, c: C.paleA, o: 0.46 },
  ],
  deco: () => [
    skeletal('caffeine', { cx: 930, cy: 1660, scale: 205, rot: -8, opacity: 0.10, width: 9 }),
    formula('C8H10N4O2', { x: 1224, y: 2788, size: 62, opacity: 0.055, anchor: 'end' }),
    elementTile('N', { x: 1140, y: 108, w: 168, opacity: 0.028, rot: 4 }),
  ],
};
