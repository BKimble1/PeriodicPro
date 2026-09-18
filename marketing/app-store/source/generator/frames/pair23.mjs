/* ============================================================================
   The slide 2 + slide 3 master composition.

   Slides 2 and 3 are designed together on one 2640 x 2868 master canvas and
   then sliced at x = 1320. Everything that crosses the seam is defined HERE, in
   master coordinates, and each slide derives its own placement by subtracting
   its panel origin. That makes the slice exact by construction rather than by
   eye: the two slides carry the same screen width, the same rotation and the
   same y, and their x differs by exactly one panel width. The QA pass asserts
   all four.

   The Build device is the hero of slide 3. Its TOP left corner clears the seam,
   so what reaches slide 2 is a wedge that starts at a point about a third of
   the way down and widens to roughly 105px at the bottom: a lower left corner
   arriving, not a second phone. Its screen begins only 5px before the seam, so
   essentially no Build UI is split; the continuation is carried by the device
   body, which is exactly what section 7 of the brief asks for.
   ========================================================================== */

export const MASTER = { W: 2640, H: 2868 };
export const SEAM = 1320;                    // slide 2 is 0..1320, slide 3 is 1320..2640

/* The device that spans the seam, in MASTER coordinates. */
export const BUILD = {
  screenW: 1000,
  masterX: 1272.5,
  y: 700,
  rot: 3,
};

/** Placement for a given panel: 0 for slide 2, 1 for slide 3. */
export function buildOn(panel) {
  return { screenW: BUILD.screenW, x: BUILD.masterX - panel * SEAM, y: BUILD.y, rot: BUILD.rot };
}
