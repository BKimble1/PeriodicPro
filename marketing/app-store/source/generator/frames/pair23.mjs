/* ============================================================================
   The slide 2 + slide 3 master composition.

   Slides 2 and 3 are designed together on one 2640 x 2868 master canvas and
   then sliced at x = 1320. Everything that crosses the seam is defined HERE, in
   master coordinates, and each slide derives its own placement by subtracting
   its panel origin. That makes the slice exact by construction rather than by
   eye: the two slides carry the same screen width, the same rotation and the
   same y, and their x differs by exactly one panel width. The QA pass asserts
   all four.

   The Build device is the hero of slide 3. It is sized and angled after
   CoreCredit's own spanning device: 74 percent of a panel's width at 5 degrees,
   and seated so its BOTTOM sits on the canvas rather than running off it, which
   means slide 2 shows a real corner of the phone rather than an open-ended edge.

   Its TOP left corner clears the seam, so what reaches slide 2 is a wedge
   starting a little under a fifth of the way down and widening to 167px at the
   bottom left corner: 14.5 percent of the device. Only 5.2 percent of the Build
   SCREEN area falls on slide 2, and it is the bottom left corner of it, so
   nothing worth reading is split.
   ========================================================================== */

export const MASTER = { W: 2640, H: 2868 };
export const SEAM = 1320;                    // slide 2 is 0..1320, slide 3 is 1320..2640

/* The device that spans the seam, in MASTER coordinates. */
export const BUILD = {
  screenW: 900,           // 976px device, 74% of a panel, CoreCredit's proportion
  masterX: 1239.59,
  y: 759.36,
  rot: 5,
};

/** Placement for a given panel: 0 for slide 2, 1 for slide 3. */
export function buildOn(panel) {
  return { screenW: BUILD.screenW, x: BUILD.masterX - panel * SEAM, y: BUILD.y, rot: BUILD.rot };
}
