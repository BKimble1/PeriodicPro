/* 05  STUDY.  Composition: TWO OVERLAPPING DEVICES, MIRRORED FROM 03. Here the
   rear phone enters from the LEFT edge and the front phone sits right and low,
   so the pair leans the opposite way to frame 03 and the two multi-device
   frames do not read as the same picture twice. Two study surfaces communicate
   that Study is more than one activity. */
import { C } from '../system.mjs';
import { skeletal, elementTile, orbits, formula, EQUATIONS } from '../chemistry.mjs';

export default {
  id: '05', slug: 'study',
  title: 'Elemora 05 Study',
  headline: ['Study Smarter'],
  sub: ['Practice with focused tools that', 'make chemistry stick.'],
  copy: { top: 296, align: 'start' },
  devices: [
    {
      role: 'back', label: 'Quiz or flashcard', screenW: 800, x: -70, y: 800, rot: 4, labelDX: -200,
      need: 'The second strongest study surface: a quiz mid-question, or a flashcard. Cropped by the left edge, so keep the subject right of centre.',
    },
    {
      role: 'front', label: 'Study overview', screenW: 904, x: 392, y: 910, rot: -4,
      need: 'The Study home or dashboard, with real progress on it. This is the dominant device.',
    },
  ],
  light: [
    { x: 1120, y: 700, r: 1080, c: C.lavender, o: 0.66 },
    { x: 220, y: 1760, r: 1060, c: C.paleC, o: 0.48 },
    { x: 700, y: 2800, r: 900, c: C.paleA, o: 0.46 },
  ],
  deco: () => [
    elementTile('N', { x: 1122, y: 596, w: 162, opacity: 0.06, rot: 5 }),
    formula(EQUATIONS.haber, { x: 96, y: 2842, size: 48, opacity: 0.09 }),
    orbits({ cx: 86, cy: 2764, r: 212, opacity: 0.05 }),
    skeletal('naphthalene', { cx: 1196, cy: 330, scale: 74, rot: 16, opacity: 0.055, width: 7 }),
  ].join('\n'),
};
