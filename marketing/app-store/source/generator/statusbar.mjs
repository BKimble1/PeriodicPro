/* The iOS status bar, reconstructed at capture resolution.

   The shipped captures were taken across a 36 minute window, so they carried
   seven different clocks, weak-signal bars and yellow Low Power Mode batteries.
   Rather than keep a mismatched set or fake something approximate, the strip is
   rebuilt once, here, and composited onto every capture by prepare.py.

   Every number below was measured off the real captures (all seven agree to
   within a few pixels), so the reconstruction lands exactly where the device
   drew it and reads as native rather than pasted on. What changes is only the
   state: the canonical 9:41, full signal, full Wi-Fi and a full battery, which
   is the treatment Apple ships on its own App Store screenshots.

   Coordinates are capture pixels on a 1170 x 2532 screen.                     */

import { fontFace } from './system.mjs';

export const STRIP = { w: 1170, h: 132 };

/* Measured from the captures. */
const INK = '#000000';
const BASELINE = 96;          // digits sit on y = 96, ink top 60, bottom 95
const DIGIT_H = 36;           // cap height of the clock
const CAP = 1490 / 2048;      // Inter cap-height / em
const TIME_CX = 190;          // iOS centres the clock in the left ear

const BARS = { x: 856, w: 10, pitch: 16, bottom: 96, h: [14, 21, 29, 37] };
const WIFI = { cx: 961, cy: 89.5, r1: 14.5, r2: 27, dot: 6.2, stroke: 7.5, span: 55 };
const BATT = { x: 1009, y: 57, w: 75.5, h: 41, rx: 12, stroke: 3, nubX: 1086.5 };

const n = (v) => Number(v.toFixed(2));

/* An arc of `r` about the Wi-Fi origin, spanning +/- `span` degrees from
   straight up, drawn left to right over the top. */
function arc(r) {
  const t = (WIFI.span * Math.PI) / 180;
  const dx = Math.sin(t) * r, dy = Math.cos(t) * r;
  return `M ${n(WIFI.cx - dx)} ${n(WIFI.cy - dy)} A ${n(r)} ${n(r)} 0 0 1 ${n(WIFI.cx + dx)} ${n(WIFI.cy - dy)}`;
}

export function statusBarSVG({ time = '9:41' } = {}) {
  const bars = BARS.h.map((h, i) =>
    `<rect x="${BARS.x + i * BARS.pitch}" y="${BARS.bottom - h}" width="${BARS.w}" height="${h}" rx="3" fill="${INK}"/>`
  ).join('\n      ');

  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${STRIP.w}" height="${STRIP.h}"
     viewBox="0 0 ${STRIP.w} ${STRIP.h}">
  <style>${fontFace()}
    text { font-family:'Inter','Segoe UI',Arial,sans-serif; -webkit-font-smoothing:antialiased; }
  </style>
  <g id="Status-Bar">
    <text id="Time" x="${TIME_CX}" y="${BASELINE}" text-anchor="middle" fill="${INK}"
          style="font-weight:600;font-size:${n(DIGIT_H / CAP)}px;letter-spacing:-0.2px">${time}</text>
    <g id="Cellular">
      ${bars}
    </g>
    <g id="Wi-Fi" fill="none" stroke="${INK}" stroke-width="${WIFI.stroke}" stroke-linecap="round">
      <path d="${arc(WIFI.r2)}"/>
      <path d="${arc(WIFI.r1)}"/>
    </g>
    <circle cx="${WIFI.cx}" cy="${WIFI.cy}" r="${WIFI.dot}" fill="${INK}"/>
    <g id="Battery">
      <rect x="${n(BATT.x + BATT.stroke / 2)}" y="${n(BATT.y + BATT.stroke / 2)}"
            width="${n(BATT.w - BATT.stroke)}" height="${n(BATT.h - BATT.stroke)}"
            rx="${BATT.rx}" fill="none" stroke="${INK}" stroke-opacity="0.35" stroke-width="${BATT.stroke}"/>
      <rect x="${n(BATT.x + 6)}" y="${n(BATT.y + 6)}"
            width="${n(BATT.w - 12)}" height="${n(BATT.h - 12)}" rx="7.5" fill="${INK}"/>
      <rect x="${BATT.nubX}" y="72" width="4.5" height="11" rx="2.2" fill="${INK}" fill-opacity="0.35"/>
    </g>
  </g>
</svg>`;
}
