#!/usr/bin/env python3
"""Asserts the fitted periodic table is the whole periodic table.

Build 5's claim about the Table screen is that opening it puts all 118
elements on screen at once: eighteen columns, seven periods, the lanthanides
and the actinides, with no scroll of its own to hide a row behind.

This mirrors `TableZoomLayout`'s arithmetic — the same terms, in the same
order — and checks it against the screens the app ships for, so a change that
quietly stops the table fitting fails in seconds on a Linux runner rather than
forty minutes later in the simulator. The Swift suite `FittedTableTests`
asserts the same thing against the real implementation; this is the Mac-free
half of that pair, and the two are meant to disagree loudly if the layout
constants drift apart.

    python3 Tools/check_table_fit.py
"""
from __future__ import annotations

import math
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LAYOUT = os.path.join(ROOT, "PeriodicPro", "Views", "Table", "TableZoomLayout.swift")

COLUMNS = 18
MAIN_ROWS = 7
DETACHED_ROWS = 2
FITTED_SPACING = 1.5
LARGEST_SPACING = 4.0
SPACING_S = 8.0                 # Theme.Spacing.s
SPACING_M = 12.0                # Theme.Spacing.m
SPACING_L = 16.0                # Theme.Spacing.l
SMALLEST_TILE = 13.0
SMALLEST_REGION = 170.0
BREATHING_ROOM = SPACING_S

# The screens the app ships for: display width, display height, and the
# chrome above and below the table on that device — the window's own safe
# areas, the navigation bar with its large title, the search field and the
# tab bar. Real per-device numbers, not the single allowance the app uses.
#
# The app cannot measure these without reintroducing the bug this gate now
# guards: the large title and the search field collapse as the page scrolls,
# so anything derived from a live safe-area inset changes size under the
# learner's thumb. The app therefore budgets one constant,
# TableZoomLayout.pageChromeAllowance, and this gate checks that constant
# against what each device really gives up.
DEVICES = [
    ("iPhone SE (3rd generation)", 375, 667, 217),
    ("iPhone 16e",                 390, 844, 304),
    ("iPhone 17",                  393, 852, 290),
    ("iPhone 17 Pro",              402, 874, 304),
    ("iPhone 17 Pro Max",          440, 956, 290),
    ("iPad (A16) portrait",        820, 1180, 230),
    ("iPad Pro 11 portrait",       834, 1210, 242),
    ("iPad Pro 13 portrait",      1024, 1366, 186),
    ("iPad Pro 11 landscape",     1210, 834, 242),
    ("iPad Pro 13 landscape",     1366, 1024, 242),
]

# The hint line and the families filter bar, at their tallest (375 points,
# where the hint wraps to two lines), plus the constants the screen adds.
HEADER = 110.0


def swift_rounded(value: float) -> float:
    """Swift's `.rounded()`: half away from zero, not Python's half-to-even."""
    return math.floor(value + 0.5) if value >= 0 else math.ceil(value - 0.5)


def spacing(tile: float) -> float:
    return min(LARGEST_SPACING, max(FITTED_SPACING, tile * 0.075))


def block_gap(tile: float) -> float:
    return max(SPACING_S, tile * 0.45)


def caption_gap(tile: float) -> float:
    return max(4.0, tile * 0.2)


def caption_height(tile: float) -> float:
    return max(12.0, min(18.0, swift_rounded(tile * 0.5)))


def grid_height(tile: float) -> float:
    gap = spacing(tile)
    main = MAIN_ROWS * tile + (MAIN_ROWS - 1) * gap
    f_block = DETACHED_ROWS * (caption_height(tile) + tile) + 3 * caption_gap(tile)
    return main + block_gap(tile) + f_block


def content_height(tile: float) -> float:
    return grid_height(tile) + SPACING_M * 2


def content_width(tile: float) -> float:
    return COLUMNS * tile + (COLUMNS - 1) * spacing(tile) + SPACING_L * 2


def fitted_tile(width: float, available: float = math.inf) -> float:
    usable = max(width - SPACING_L * 2, 260)
    gaps = FITTED_SPACING * (COLUMNS - 1)
    tile = max(SMALLEST_TILE, math.floor((usable - gaps) / COLUMNS))
    while tile > SMALLEST_TILE and COLUMNS * tile + (COLUMNS - 1) * spacing(tile) > usable:
        tile -= 1
    if not math.isfinite(available) or available <= 0:
        return tile
    width_fitted = tile
    while tile > SMALLEST_TILE and content_height(tile) > available:
        tile -= 1
    return tile if content_height(tile) <= available else width_fitted


def available_height(screen_height: float, allowance: float) -> float:
    """What the app budgets: a function of the window height alone."""
    if screen_height <= 0:
        return math.inf
    return max(SMALLEST_REGION, screen_height - allowance - BREATHING_ROOM)


def real_room(screen_height: float, chrome: float) -> float:
    """What the device actually leaves for the table, chrome and header off."""
    return screen_height - chrome - HEADER - BREATHING_ROOM


def swift_constants() -> dict[str, float]:
    """Reads the constants back out of the Swift, so the two cannot drift."""
    with open(LAYOUT, encoding="utf-8") as handle:
        source = handle.read()
    found: dict[str, float] = {}
    for name in ("fittedSpacing", "largestSpacing", "smallestFittedTile",
                 "smallestTableRegion", "pageChromeAllowance"):
        match = re.search(rf"static let {name}: CGFloat = ([0-9.]+)", source)
        if match:
            found[name] = float(match.group(1))
    for name, value in (("columns", COLUMNS), ("mainRows", MAIN_ROWS),
                        ("detachedRows", DETACHED_ROWS)):
        match = re.search(rf"static let {name} = (\d+)", source)
        if match:
            found[name] = float(match.group(1))
    return found


def main() -> int:
    failures: list[str] = []

    expected = {
        "fittedSpacing": FITTED_SPACING, "largestSpacing": LARGEST_SPACING,
        "smallestFittedTile": SMALLEST_TILE, "smallestTableRegion": SMALLEST_REGION,
        "columns": COLUMNS, "mainRows": MAIN_ROWS, "detachedRows": DETACHED_ROWS,
    }
    # Read from the Swift rather than duplicated here: this is the number
    # under test, so the gate has to use whatever the app actually ships.
    actual = swift_constants()
    for name, value in expected.items():
        if name not in actual:
            failures.append(f"TableZoomLayout no longer declares {name}")
        elif actual[name] != value:
            failures.append(
                f"{name} is {actual[name]} in TableZoomLayout.swift and {value} here")

    allowance = actual.get("pageChromeAllowance", 0.0)

    print(f"{'device':28}{'width':>7}{'budget':>8}{'real':>7}{'tile':>6}"
          f"{'table w':>9}{'table h':>9}{'spare':>8}  fits")
    for name, width, screen_height, chrome in DEVICES:
        room = available_height(screen_height, allowance)
        tile = fitted_tile(width, room)
        height = content_height(tile)
        wide = content_width(tile)
        # Two questions, not one. The budget is what the app fits the table
        # into; the real room is what the device actually has. The table must
        # fit the budget (or the app has miscounted its own layout) and the
        # budget must fit the device (or a row falls off the bottom).
        actual_room = real_room(screen_height, chrome)
        fits_width = wide <= width + 0.5
        fits_height = height <= room + 0.001
        on_screen = height <= actual_room + 0.001
        verdict = "yes" if (fits_width and fits_height and on_screen) else "NO"
        print(f"{name:28}{width:>7}{room:>8.0f}{actual_room:>7.0f}{tile:>6.0f}"
              f"{wide:>9.1f}{height:>9.1f}{actual_room - height:>8.1f}  {verdict}")
        if not fits_width:
            failures.append(f"{name}: the table is {wide:.1f} points wide in {width}")
        if not fits_height:
            failures.append(f"{name}: the table needs {height:.1f} points and has {room:.0f}")
        if not on_screen:
            failures.append(
                f"{name}: pageChromeAllowance {allowance:.0f} claims {room:.0f} points but the "
                f"device leaves {actual_room:.0f}, so the table would run {height - actual_room:.1f} "
                "points past the bottom")
        if tile < SMALLEST_TILE:
            failures.append(f"{name}: tile shrank to {tile}")
        # Held upright, the eighteen columns are what decides the fitted size.
        # If the height budget decides it instead, the table is smaller than
        # the screen can hold and sits in the middle of the page with the
        # margins around it — which is what a too-large allowance looks like,
        # and it fits everything, so none of the checks above would say a word.
        # Landscape is excluded on purpose: sideways there is genuinely not
        # room for ten rows at the width-fitted size, and shrinking is the
        # right answer there.
        #
        # This pins the constant. What the *app* feeds the constant is a
        # different question and not one a Linux runner can answer;
        # `PeriodicProLaunchTests` asserts that on the simulator.
        if screen_height > width and tile != fitted_tile(width):
            failures.append(
                f"{name}: the width fits a {fitted_tile(width):.0f}-point tile and the "
                f"{allowance:.0f}-point chrome allowance cuts it to {tile:.0f}, so the "
                "table would open smaller than the screen it is on")

    # Ten rows of tiles are really in the height, whatever else is.
    for tile in range(int(SMALLEST_TILE), 113):
        rows = (MAIN_ROWS + DETACHED_ROWS) * tile
        if grid_height(float(tile)) <= rows:
            failures.append(f"a {tile}-point tile leaves no room for all ten rows")

    print()
    if failures:
        for failure in failures:
            print(f"FAIL — {failure}", file=sys.stderr)
        return 1
    print(f"OK — all 118 elements fit at fitted zoom on {len(DEVICES)} screens, "
          "with no scroll range in either direction")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
