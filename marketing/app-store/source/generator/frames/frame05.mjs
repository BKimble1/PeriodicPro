/* 05 — STUDY.  Centre, tilted slightly left. The study surfaces in Elemora lean
   lavender, so this frame's light does too. One balanced equation, nothing more. */
import { C } from '../system.mjs';
import { molecule, elementTile, formula, EQUATIONS } from '../chemistry.mjs';

export default {
  id: '05', slug: 'study',
  title: 'Elemora — 05 Study',
  label: 'Study',
  need: 'The strongest single study surface — the Study home, a quiz in progress, or a flashcard. One mode only.',
  headline: ['Study Smarter'],
  sub: ['Practice with focused tools that', 'make chemistry stick.'],
  copy: { top: 296, align: 'start' },
  device: { rot: -3 },
  light: [
    { x: 1140, y: 700, r: 1080, c: C.lavender, o: 0.70 },
    { x: 200, y: 1720, r: 1060, c: C.paleC, o: 0.50 },
    { x: 700, y: 2780, r: 900, c: C.paleA, o: 0.48 },
  ],
  deco: (D) => [
    elementTile('N', { x: -26, y: 1010, w: 190, opacity: 0.095, rot: -5 }),
    formula(EQUATIONS.haber, { x: 96, y: 2820, size: 58, opacity: 0.13 }),
    formula('NH3', { x: 1224, y: 640, size: 78, opacity: 0.11, anchor: 'end' }),
    molecule(D, 'ammonia', { cx: 1300, cy: 1560, scale: 150, rx: -24, ry: 20, rz: -8 }),
    molecule(D, 'dinitrogen', { cx: 16, cy: 2240, scale: 132, rx: 0, ry: 18, rz: 22 }),
  ].join('\n'),
};
