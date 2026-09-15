#!/usr/bin/env python3
"""Measures the app's colour pairings against WCAG contrast ratios.

Reads the real values out of AppColor.swift and CategoryPalette.swift so the
numbers can never drift from the code, and checks every pairing the UI actually
draws, in both appearances.

    python3 Tools/check_contrast.py

Thresholds follow WCAG 2.1 AA: 4.5:1 for normal text, 3:1 for large text
(>=18pt regular or >=14pt bold) and for meaningful graphics.
"""
from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP_COLOR = os.path.join(ROOT, "PeriodicPro", "DesignSystem", "AppColor.swift")
PALETTE = os.path.join(ROOT, "PeriodicPro", "DesignSystem", "CategoryPalette.swift")

NORMAL_TEXT = 4.5
LARGE_TEXT = 3.0

Color = tuple  # (r, g, b) in sRGB 0...1


def luminance(color: Color) -> float:
    def channel(value: float) -> float:
        return value / 12.92 if value <= 0.03928 else ((value + 0.055) / 1.055) ** 2.4
    r, g, b = (channel(c) for c in color)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a: Color, b: Color) -> float:
    high, low = sorted((luminance(a), luminance(b)), reverse=True)
    return (high + 0.05) / (low + 0.05)


def composite(foreground: Color, alpha: float, background: Color) -> Color:
    """Flattens a translucent colour onto its background."""
    return tuple(foreground[i] * alpha + background[i] * (1 - alpha) for i in range(3))


SHORTHAND = {".white": (1.0, 1.0, 1.0), ".black": (0.0, 0.0, 0.0)}


def parse_color_literal(text: str) -> Color:
    """Accepts `Color(red: r, green: g, blue: b)` and `.white` / `.black`."""
    text = text.strip()
    if text in SHORTHAND:
        return SHORTHAND[text]
    match = re.match(r"Color\(red: ([\d.]+), green: ([\d.]+), blue: ([\d.]+)\)", text)
    if not match:
        raise ValueError(f"unrecognised color literal: {text}")
    return tuple(float(match.group(i)) for i in (1, 2, 3))


def parse_app_colors() -> dict[str, tuple[Color, Color]]:
    """`static let name = Color(light: <literal>, dark: <literal>)`."""
    source = open(APP_COLOR, encoding="utf-8").read()
    # Matched as a block, then line by line: a colour literal contains its own
    # parentheses, so a single non-greedy pattern stops in the wrong place.
    block = re.compile(r"static let (\w+) = Color\(\n(.*?)\n    \)", re.S)
    line = re.compile(r"^\s*(light|dark): (.+?),?$", re.M)

    colors = {}
    for match in block.finditer(source):
        parts = {key: value for key, value in line.findall(match.group(2))}
        if "light" not in parts or "dark" not in parts:
            continue
        try:
            colors[match.group(1)] = (
                parse_color_literal(parts["light"]),
                parse_color_literal(parts["dark"]),
            )
        except ValueError:
            continue
    return colors


def parse_families() -> dict[str, dict]:
    """The `make(...)` call for each family in the palette table."""
    source = open(PALETTE, encoding="utf-8").read()
    triple = r"\(([\d.]+), ([\d.]+), ([\d.]+)\)"
    pattern = re.compile(
        r"\.(\w+): make\(\s*"
        rf"accentLight: {triple}, accentDark: {triple},\s*"
        rf"fillLight: {triple}, fillDark: {triple},\s*"
        rf"inkLight: {triple}"
        r"(,\s*darkTextOnAccent: true)?",
        re.S,
    )
    families = {}
    for match in pattern.finditer(source):
        values = [float(v) for v in match.groups()[1:16]]
        families[match.group(1)] = {
            "accentLight": tuple(values[0:3]),
            "accentDark": tuple(values[3:6]),
            "fillLight": tuple(values[6:9]),
            "fillDark": tuple(values[9:12]),
            "inkLight": tuple(values[12:15]),
            "darkTextOnAccent": match.group(17) is not None,
        }
    ink = re.search(r"accentInk = Color\(red: ([\d.]+), green: ([\d.]+), blue: ([\d.]+)\)", source)
    families["_accentInk"] = tuple(float(ink.group(i)) for i in (1, 2, 3)) if ink else (0, 0, 0)
    return families


def main() -> int:
    app = parse_app_colors()
    families = parse_families()
    accent_ink = families.pop("_accentInk")

    if len(families) != 10:
        print(f"error: parsed {len(families)} families, expected 10", file=sys.stderr)
        return 2

    failures: list[str] = []
    rows: list[tuple[str, str, float, float]] = []

    def check(label: str, appearance: str, fore: Color, back: Color, minimum: float) -> None:
        ratio = contrast(fore, back)
        rows.append((label, appearance, ratio, minimum))
        if ratio < minimum:
            failures.append(f"{label} ({appearance}): {ratio:.2f}:1, needs {minimum}:1")

    # --- semantic text on the surfaces it is actually drawn on ---------------
    # Only real pairings: surfaceMuted carries FactRow's label, value and
    # footnote and the session badge, but never the accent, so asserting that
    # combination would be inventing a requirement.
    text_on_surfaces = [
        ("primaryText", NORMAL_TEXT, ("canvas", "surface", "surfaceMuted")),
        ("secondaryText", NORMAL_TEXT, ("canvas", "surface", "surfaceMuted")),
        ("tertiaryText", LARGE_TEXT, ("canvas", "surface", "surfaceMuted")),
        ("accent", NORMAL_TEXT, ("canvas", "surface")),
        ("positive", LARGE_TEXT, ("canvas", "surface")),
        ("warning", LARGE_TEXT, ("canvas", "surface")),
    ]
    for name, minimum, surfaces in text_on_surfaces:
        for index, appearance in enumerate(("light", "dark")):
            for surface in surfaces:
                check(f"{name} on {surface}", appearance,
                      app[name][index], app[surface][index], minimum)

    # White button labels sit on the accent; 17pt semibold counts as large text.
    for index, appearance in enumerate(("light", "dark")):
        check("white label on accent", appearance, (1, 1, 1), app["accent"][index], LARGE_TEXT)
        check("hairline on surface", appearance,
              app["hairline"][index], app["surface"][index], 1.2)

    # --- per-family pairings -------------------------------------------------
    for family, values in sorted(families.items()):
        # The tile symbol goes as small as 8pt, so it is normal text.
        check(f"{family} symbol on tile", "light", values["inkLight"], values["fillLight"], NORMAL_TEXT)
        check(f"{family} symbol on tile", "dark",
              composite((1, 1, 1), 0.94, values["fillDark"]), values["fillDark"], NORMAL_TEXT)
        # The family accent is used for glyphs and rings: meaningful graphics.
        check(f"{family} accent on canvas", "light",
              values["accentLight"], app["canvas"][0], LARGE_TEXT)
        check(f"{family} accent on canvas", "dark",
              values["accentDark"], app["canvas"][1], LARGE_TEXT)
        # The nucleus symbol sits directly on the accent.
        on_accent_light = accent_ink if values["darkTextOnAccent"] else (1, 1, 1)
        check(f"{family} nucleus symbol", "light", on_accent_light, values["accentLight"], LARGE_TEXT)
        check(f"{family} nucleus symbol", "dark", accent_ink, values["accentDark"], LARGE_TEXT)

    width = max(len(r[0]) for r in rows) + 2
    print(f"{'pairing':{width}}{'mode':7}{'ratio':>8}  {'min':>5}")
    for label, appearance, ratio, minimum in rows:
        flag = "" if ratio >= minimum else "   <-- FAIL"
        print(f"{label:{width}}{appearance:7}{ratio:7.2f}:1  {minimum:5.1f}{flag}")

    print()
    if failures:
        for failure in failures:
            print(f"error: {failure}")
        print(f"\n{len(failures)} contrast failure(s) of {len(rows)} pairings")
        return 1
    print(f"OK — all {len(rows)} colour pairings meet their WCAG threshold")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
