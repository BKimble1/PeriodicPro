/* 05  STUDY.  Two complete overlapping devices, proportioned after the
   CoreCredit two-phone frame: the rear phone about 60 percent of the canvas
   width and the front about 65, both wholly on canvas, the rear higher and
   left with a small negative tilt, the front lower and right with a small
   positive one. Neither is cropped; the overlap alone carries the depth.

   Background hierarchy
     anchor     a naphthalene ring system entering top right and passing behind
                both devices
     secondary  an acetone skeleton at the lower left, a formula bottom right
     ambient    the Haber equation in the gap above the devices               */
import { C } from '../system.mjs';
import { skeletal, formula, EQUATIONS } from '../chemistry.mjs';

export default {
  id: '05', slug: 'study',
  title: 'Elemora 05 Study',
  headline: ['Study Smarter'],
  sub: ['Practice with focused tools that', 'make chemistry stick.'],
  copy: { top: 296, align: 'start' },
  devices: [
    {
      role: 'back', label: 'Quiz or flashcard', screenW: 740, x: 96, y: 700, rot: -2,
      need: 'A DIFFERENT study surface from the front device: a quiz mid-question, or a flashcard. The two phones must show two distinct states, otherwise the composition says nothing. Fully visible, so nothing is cropped.',
    },
    {
      role: 'front', label: 'Study overview', screenW: 810, x: 380, y: 900, rot: 2,
      need: 'The Study home or dashboard, with real progress on it. Must be visibly different from the rear device. The dominant device, fully visible.',
    },
  ],
  light: [
    { x: 1100, y: 760, r: 1080, c: C.lavender, o: 0.64 },
    { x: 260, y: 1820, r: 1060, c: C.paleC, o: 0.48 },
    { x: 760, y: 2800, r: 900, c: C.paleA, o: 0.46 },
  ],
  deco: () => [
    skeletal('naphthalene', { cx: 1280, cy: 980, scale: 165, rot: -14, opacity: 0.10, width: 9 }),
    skeletal('acetone', { cx: 120, cy: 2680, scale: 96, opacity: 0.04, width: 7 }),
    formula('C10H8', { x: 1224, y: 2840, size: 52, opacity: 0.045, anchor: 'end' }),
    formula(EQUATIONS.haber, { x: 96, y: 624, size: 40, opacity: 0.028 }),
  ],
};
