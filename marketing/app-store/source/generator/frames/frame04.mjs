/* 04  ELEMENT DETAIL.  Composition: EXTREME SCALE, NEAR UPRIGHT. The largest
   device in the set, almost square to the canvas and wide enough to run edge to
   edge, bleeding off the bottom. That deliberately separates it from the two
   other single-device frames, which both lean: 02 enters at an angle from the
   right and 06 from the left, while this one simply fills the frame. Only one
   phone here, because a second view of an element would be decoration rather
   than information. A large carbon shell diagram sits in the only clear space
   left, the top right beside the headline. */
import { C } from '../system.mjs';
import { skeletal, elementTile, bohr } from '../chemistry.mjs';

export default {
  id: '04', slug: 'element-detail',
  title: 'Elemora 04 Element detail',
  headline: ['See More Than', 'Symbols'],
  sub: ['Explore properties, structures, uses,', 'and facts worth remembering.'],
  copy: { top: 236, align: 'start' },
  devices: [{
    role: 'hero', label: 'Element Detail', screenW: 1105, x: 112, y: 800, rot: 1.5,
    need: 'One element detail screen, the most visually complete you have. Carbon or Iron usually read best. The lower sixth is cropped by the canvas, so keep the tile, name and key properties high.',
  }],
  light: [
    { x: 1080, y: 400, r: 1080, c: C.paleC, o: 0.56 },
    { x: 160, y: 1560, r: 1060, c: C.paleB, o: 0.44 },
    { x: 700, y: 2800, r: 880, c: C.paleA, o: 0.44 },
  ],
  deco: () => [
    bohr('C', { cx: 1262, cy: 356, r: 284, opacity: 0.075 }),
    elementTile('C', { x: 1148, y: 636, w: 156, variant: 'soft', opacity: 0.10, rot: 5 }),
    skeletal('phenol', { cx: 176, cy: 60, scale: 74, rot: 12, opacity: 0.055, width: 7 }),
  ].join('\n'),
};
