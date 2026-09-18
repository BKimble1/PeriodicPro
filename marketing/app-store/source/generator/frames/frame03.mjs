/* 03  BUILD.  The strongest composition of the six, and the second half of the
   handoff that starts in frame 02.

   Three devices, back to front:
     handoff   the same element detail capture frame 02 pushes off its right
               edge, arriving here at the left edge showing its RIGHT side.
               Matched to frame 02 on screen width, rotation and y, so the two
               read as one device continuing across the gallery. It is the only
               device in the frame allowed off canvas.
     back      the finished compound, a complete phone, higher and to the right
     front     the Build canvas, a complete phone, dominant, low and left

   Both Build devices are whole: the depth comes from scale, overlap, opposed
   tilt and the front device's shadow, not from cropping.

   Background hierarchy
     anchor     a caffeine skeleton in the lower right, running behind both
                Build devices and off the bottom
     secondary  a nitrogen tile, and the methane combustion equation
     ambient    a benzene ring at the upper left                              */
import { C } from '../system.mjs';
import { skeletal, elementTile, formula, EQUATIONS } from '../chemistry.mjs';
import { HANDOFF } from './frame02.mjs';

/* frame 02 shows this device's left 170px; here we show its right 170px */
const HANDOFF_W = HANDOFF.screenW * 1.085;

export default {
  id: '03', slug: 'build',
  title: 'Elemora 03 Build',
  headline: ['Build Real', 'Molecules'],
  sub: ['Create compounds visually and see', 'how atoms connect.'],
  copy: { top: 236, align: 'start' },
  devices: [
    {
      role: 'handoff', label: 'Element detail',
      screenW: HANDOFF.screenW, x: 170 - HANDOFF_W, y: HANDOFF.y, rot: HANDOFF.rot,
      need: 'The SAME element detail capture used at the right edge of frame 02. Only its right side shows here, which is what makes the two frames read as one continuous device.',
    },
    {
      role: 'back', label: 'Finished compound', screenW: 700, x: 480, y: 760, rot: -3,
      need: 'The result of a build: a completed compound sheet, or the 3D viewer if the app has one. Fully visible, so nothing is cropped.',
    },
    {
      role: 'front', label: 'Build canvas', screenW: 800, x: 250, y: 940, rot: 2,
      need: 'The Build screen mid-assembly, with a molecule actually on the canvas. Never an empty builder. Fully visible and dominant.',
    },
  ],
  light: [
    { x: 1020, y: 1280, r: 1160, c: C.paleC, o: 0.56 },
    { x: 240, y: 460, r: 980, c: C.paleB, o: 0.44 },
    { x: 940, y: 2780, r: 900, c: C.paleA, o: 0.46 },
  ],
  deco: () => [
    skeletal('caffeine', { cx: 1170, cy: 2540, scale: 145, rot: -8, opacity: 0.10, width: 8 }),
    elementTile('N', { x: 1140, y: 108, w: 168, opacity: 0.055, rot: 4 }),
    formula(EQUATIONS.combustionCH4, { x: 96, y: 2842, size: 46, opacity: 0.05 }),
    skeletal('benzene', { cx: 40, cy: 780, scale: 118, opacity: 0.032, width: 8 }),
  ],
};
