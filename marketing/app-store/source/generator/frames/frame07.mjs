/* 07 — FAVOURITES.  Right-biased and tilted right, mirroring 02 so the set
   closes symmetrically. A small saved-looking cluster of molecules sits in the
   left margin. */
import { C } from '../system.mjs';
import { molecule, elementTile, formula } from '../chemistry.mjs';

export default {
  id: '07', slug: 'favorites',
  title: 'Elemora — 07 Favourites',
  label: 'Favourites',
  need: 'Favourites / saved items, populated with several elements and compounds.',
  headline: ['Keep What', 'Matters Close'],
  sub: ['Save the elements and compounds', 'you come back to.'],
  copy: { top: 236, align: 'start' },
  device: { dx: 100, rot: 4 },
  light: [
    { x: 260, y: 1300, r: 1120, c: C.paleC, o: 0.58 },
    { x: 1140, y: 480, r: 940, c: C.mint, o: 0.40 },
    { x: 420, y: 2760, r: 900, c: C.paleA, o: 0.48 },
  ],
  deco: (D) => [
    elementTile('Na', { x: -28, y: 2320, w: 184, opacity: 0.095, rot: -6 }),
    formula('H2O', { x: 96, y: 1024, size: 74, opacity: 0.12 }),
    molecule(D, 'water', { cx: 92, cy: 1272, scale: 124, rx: -10, ry: 22, rz: -6 }),
    molecule(D, 'methane', { cx: 66, cy: 1782, scale: 146, rx: -18, ry: 32, rz: 14 }),
    molecule(D, 'dioxygen', { cx: 1298, cy: 366, scale: 86, rx: 0, ry: 18, rz: -24 }),
  ].join('\n'),
};
