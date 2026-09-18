/* 06 — PROGRESS.  Straight on. The decoration turns deliberately more
   structured here: a period 1-4 table strip above the copy reads as coverage,
   and the orbit motif supplies the only curve. */
import { C } from '../system.mjs';
import { molecule, bohr, periodicFragment, orbits, lattice } from '../chemistry.mjs';

export default {
  id: '06', slug: 'progress',
  title: 'Elemora — 06 Progress',
  label: 'Progress',
  need: 'The progress / mastery view, with enough real activity on it to look earned.',
  headline: ['See Your', 'Progress'],
  sub: ['Track mastery, activity, and what', 'to review next.'],
  copy: { top: 236, align: 'start' },
  device: { rot: 0 },
  light: [
    { x: 660, y: 520, r: 1120, c: C.paleC, o: 0.52 },
    { x: 1180, y: 1820, r: 1020, c: C.paleB, o: 0.44 },
    { x: 140, y: 2700, r: 900, c: C.paleA, o: 0.48 },
  ],
  deco: (D) => [
    periodicFragment({ x: 706, y: 58, cell: 30, gap: 5, opacity: 0.085 }),
    orbits({ cx: 52, cy: 1520, r: 250, opacity: 0.075 }),
    bohr('O', { cx: 1286, cy: 2260, r: 236, opacity: 0.085 }),
    lattice({ x: -66, y: 2500, cols: 3, rows: 3, a: 72, opacity: 0.05, width: 5 }),
    molecule(D, 'water', { cx: 1304, cy: 1150, scale: 128, rx: -12, ry: -26, rz: -6 }),
  ].join('\n'),
};
