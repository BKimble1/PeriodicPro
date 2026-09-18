/* 03  BUILD.  Composition: TWO OVERLAPPING DEVICES. The front phone carries the
   Build canvas and stays dominant, low and left; the rear phone carries the
   finished compound and sits higher, tilted the other way, cropped by the right
   edge. Both hold real captures. A caffeine skeleton anchors the top right,
   which is the same idea the front screen is demonstrating. */
import { C } from '../system.mjs';
import { skeletal, elementTile, formula, EQUATIONS } from '../chemistry.mjs';

export default {
  id: '03', slug: 'build',
  title: 'Elemora 03 Build',
  headline: ['Build Real', 'Molecules'],
  sub: ['Create compounds visually and see', 'how atoms connect.'],
  copy: { top: 236, align: 'start' },
  devices: [
    {
      role: 'back', label: 'Finished compound', screenW: 730, x: 660, y: 740, rot: 5, labelDX: 70,
      need: 'The result of a build: a completed compound, its detail sheet, or the 3D viewer if the app has one. Cropped by the right edge, so keep the subject left of centre.',
    },
    {
      role: 'front', label: 'Build canvas', screenW: 840, x: 70, y: 920, rot: -3,
      need: 'The Build screen mid-assembly, with a molecule actually on the canvas. Never an empty builder.',
    },
  ],
  light: [
    { x: 1060, y: 1340, r: 1160, c: C.paleC, o: 0.58 },
    { x: 210, y: 420, r: 960, c: C.paleB, o: 0.42 },
    { x: 980, y: 2790, r: 900, c: C.paleA, o: 0.46 },
  ],
  deco: () => [
    elementTile('N', { x: 1148, y: 56, w: 166, opacity: 0.062, rot: 4 }),
    formula(EQUATIONS.combustionCH4, { x: 96, y: 2846, size: 46, opacity: 0.09 }),
    skeletal('caffeine', { cx: 1242, cy: 306, scale: 62, rot: -6, opacity: 0.055, width: 6 }),
    skeletal('naphthalene', { cx: 1286, cy: 2628, scale: 108, rot: 22, opacity: 0.06, width: 8 }),
  ].join('\n'),
};
