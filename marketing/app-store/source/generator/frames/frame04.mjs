/* 04  ELEMENT DETAIL.  One full device, near upright and fully visible, because
   the real element detail screen is the densest in the app and readability
   beats drama here.

   The device sits left of centre, which together with frame 06's shift to the
   right keeps the three single-device frames from reading as one composition
   used three times.

   Background hierarchy
     anchor     an iron electron-shell diagram wider than the phone, centred on
                it, so its outer shells pass behind the device and surface again
                in the wide right-hand margin. This is the clearest statement of
                the layering idea in the set.
     secondary  one large iron tile, top right
     ambient    a phenol ring clipped by the top edge                         */
import { C } from '../system.mjs';
import { skeletal, elementTile, bohr } from '../chemistry.mjs';

export default {
  id: '04', slug: 'element-detail',
  title: 'Elemora 04 Element detail',
  headline: ['See More Than', 'Symbols'],
  sub: ['Explore properties, structures, uses,', 'and facts worth remembering.'],
  copy: { top: 236, align: 'start' },
  devices: [{
    role: 'hero', label: 'Element Detail', screenW: 930, x: 120, y: 720, rot: 0.75,
    need: 'One element detail screen, the most visually complete you have. Iron matches the shell diagram behind it; Carbon also reads well. Fully visible, so nothing is cropped.',
  }],
  light: [
    { x: 1060, y: 480, r: 1080, c: C.paleC, o: 0.54 },
    { x: 180, y: 1620, r: 1060, c: C.paleB, o: 0.44 },
    { x: 700, y: 2800, r: 880, c: C.paleA, o: 0.44 },
  ],
  deco: () => [
    bohr('Fe', { cx: 624.5, cy: 1810, r: 880, opacity: 0.10, width: 11, dotR: 33 }),
    elementTile('Fe', { x: 1112, y: 128, w: 208, variant: 'soft', opacity: 0.04, rot: 4 }),
    skeletal('phenol', { cx: 196, cy: 44, scale: 72, rot: 12, opacity: 0.028, width: 6 }),
  ],
};
