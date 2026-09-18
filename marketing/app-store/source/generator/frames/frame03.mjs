/* 03 — BUILD.  Left-biased, tilted the other way from 02 so the pair reads as a
   spread. Benzene anchors the right-hand negative space in both its 3D and
   skeletal forms. */
import { C } from '../system.mjs';
import { molecule, elementTile, skeletalBenzene, lattice, formula, EQUATIONS } from '../chemistry.mjs';

export default {
  id: '03', slug: 'build',
  title: 'Elemora — 03 Build',
  label: 'Build',
  need: 'The Build screen showing a molecule that has actually been assembled.',
  headline: ['Build Real', 'Molecules'],
  sub: ['Create compounds visually and see', 'how atoms connect.'],
  copy: { top: 236, align: 'start' },
  device: { dx: -105, rot: 3.5 },
  light: [
    { x: 1080, y: 1380, r: 1140, c: C.paleC, o: 0.60 },
    { x: 220, y: 460, r: 980, c: C.paleB, o: 0.42 },
    { x: 1020, y: 2760, r: 900, c: C.paleA, o: 0.48 },
  ],
  deco: (D) => [
    skeletalBenzene({ cx: 1222, cy: 1746, r: 262, opacity: 0.075, width: 9, mode: 'kekule' }),
    lattice({ x: -70, y: 2404, cols: 4, rows: 3, a: 74, opacity: 0.055, width: 5 }),
    elementTile('N', { x: 1176, y: 1046, w: 178, opacity: 0.10, rot: 4 }),
    formula(EQUATIONS.combustionCH4, { x: 96, y: 2822, size: 54, opacity: 0.12 }),
    molecule(D, 'benzene', { cx: 1214, cy: 332, scale: 88, rx: -56, ry: 16, rz: 12 }),
    molecule(D, 'methane', { cx: 1298, cy: 2350, scale: 150, rx: -14, ry: 34, rz: -10 }),
  ].join('\n'),
};
