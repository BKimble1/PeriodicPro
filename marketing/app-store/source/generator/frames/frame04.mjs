/* 04 — ELEMENT DETAIL.  The largest device in the set, straight on, so a dense
   information screen stays readable. A carbon Bohr diagram carries the idea of
   structure behind the symbol. */
import { C } from '../system.mjs';
import { molecule, elementTile, bohr, periodicFragment, formula } from '../chemistry.mjs';

export default {
  id: '04', slug: 'element-detail',
  title: 'Elemora — 04 Element detail',
  label: 'Element Detail',
  need: 'A single element detail screen — pick the most visually complete one (Carbon or Iron).',
  headline: ['See More Than', 'Symbols'],
  sub: ['Properties, structure, uses, and the', 'facts worth remembering.'],
  copy: { top: 236, align: 'start' },
  device: { screenW: 950, dy: -45, rot: 0 },
  light: [
    { x: 1100, y: 420, r: 1060, c: C.paleC, o: 0.58 },
    { x: 180, y: 1500, r: 1040, c: C.paleB, o: 0.42 },
    { x: 760, y: 2780, r: 860, c: C.paleA, o: 0.46 },
  ],
  deco: (D) => [
    bohr('C', { cx: 1214, cy: 322, r: 206, opacity: 0.155 }),
    elementTile('C', { x: -30, y: 300, w: 186, opacity: 0.095, rot: -7 }),
    periodicFragment({ x: 96, y: 2792, cell: 26, gap: 5, opacity: 0.075, rows: 3 }),
    formula('12.011', { x: 1224, y: 2828, size: 58, opacity: 0.11, anchor: 'end' }),
    molecule(D, 'carbonDioxide', { cx: 34, cy: 2080, scale: 116, rx: -12, ry: 26, rz: 16 }),
    molecule(D, 'water', { cx: 1294, cy: 1330, scale: 126, rx: -10, ry: -22, rz: 8 }),
  ].join('\n'),
};
