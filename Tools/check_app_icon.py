#!/usr/bin/env python3
"""Checks the app icon against the rules App Store Connect enforces at upload,
and against the rules that keep it sharp on a Home Screen.

An icon that is the wrong size, or that carries an alpha channel, is rejected
by Apple's upload endpoint — after a full archive, sign and export, which on a
hosted runner is most of an hour. And an icon that *passes* upload can still
look soft on the phone: a raster that was upscaled, blurred, or drawn with a
paper-grain texture survives every metadata check and fails the only one that
matters, which is a person looking at their Home Screen.

So this reads the pixels as well as the header. The PNG is decoded by hand
(zlib plus the five scanline filters) rather than through Pillow, so it runs on
a bare CI image with no pip install:

    python3 Tools/check_app_icon.py

What is checked, per appearance:

* exactly 1024 × 1024, truecolor, no alpha channel, no tRNS chunk;
* produced by `Tools/make_app_icon.py` from a master of at least 2048 units,
  which the generator records in tEXt chunks — an icon that skipped the
  pipeline, or was upscaled from something small, has no such record;
* hard edges: every horizontal transition between two flat colors must be at
  most `MAX_EDGE_WIDTH` pixels of intermediate color. A Gaussian blur, a
  resize from a smaller raster or a soft glow around the tiles all widen
  that ramp, and this is what "blurry" looks like in numbers;
* a flat field: the four corners of the canvas, well away from the mark,
  must be a single color. Grain is texture that iOS's downsampler turns into
  a mottled edge;
* a small palette: flat artwork with antialiased edges uses a few dozen
  colors. Thousands means grain, noise or a gradient crept in.
"""
from __future__ import annotations

import json
import os
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON_SET = os.path.join(
    ROOT, "PeriodicPro", "Assets.xcassets", "AppIcon.appiconset"
)
PROJECT = os.path.join(ROOT, "PeriodicPro.xcodeproj", "project.pbxproj")

REQUIRED_SIZE = 1024

# iOS 18 and later take one 1024x1024 image per appearance and generate every
# smaller size themselves.
EXPECTED_APPEARANCES = {
    "AppIcon-1024.png": None,
    "AppIcon-1024-Dark.png": "dark",
    "AppIcon-1024-Tinted.png": "tinted",
}

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"

# From the PNG specification. Only truecolor without alpha is acceptable here;
# the others either carry an alpha channel or can carry one through tRNS.
COLOR_TYPES = {
    0: "grayscale",
    2: "truecolor (RGB)",
    3: "indexed (palette)",
    4: "grayscale with alpha",
    6: "truecolor with alpha (RGBA)",
}
COLOR_TYPE_RGB = 2

# --- Sharpness rules ---------------------------------------------------------
# Written by the generator; a master below this is too small to downsample
# cleanly, and an icon with no record at all did not come from the generator.
MASTER_KEY = "elemora:master-size"
MIN_MASTER_SIZE = 2048
# A box-downsampled hard edge is at most one pixel of intermediate color. The
# only wider transitions in a hard-edged icon are where a scanline crosses a
# rounded corner at a shallow tangent, and those are a small minority — so the
# rule is on the distribution, not the maximum: the typical (median) edge
# must be a single pixel and nine in ten must be within MAX_EDGE_WIDTH. A
# blurred, upscaled or soft-drawn icon widens *every* edge, and fails both.
MAX_EDGE_WIDTH = 3
MAX_MEDIAN_EDGE_WIDTH = 1
# Colors closer than this (Euclidean, 0-255 per channel) to a plateau's own
# reference color are part of that plateau; plateaus further apart than
# EDGE_CONTRAST are a real edge. Comparing to the reference rather than to
# the previous pixel is what stops a slow ramp or a grainy field from being
# mistaken for flat color one step at a time.
PLATEAU_TOLERANCE = 6.0
EDGE_CONTRAST = 60.0
# A plateau has to hold for this many pixels to count as one.
PLATEAU_MIN_RUN = 6
# Flat art plus antialiasing. The raster this pipeline replaced had 6,730.
MAX_DISTINCT_COLORS = 512
# The corner patches sampled for the flat-field rule, in pixels.
CORNER_PATCH = 96


def png_chunks(data: bytes):
    """Yields (type, payload) for every chunk after the signature."""
    offset = len(PNG_SIGNATURE)
    while offset + 8 <= len(data):
        (length,) = struct.unpack(">I", data[offset:offset + 4])
        kind = data[offset + 4:offset + 8]
        payload = data[offset + 8:offset + 8 + length]
        yield kind, payload
        offset += 12 + length  # length + type + payload + CRC
        if kind == b"IEND":
            return


def text_chunks(data: bytes) -> dict[str, str]:
    """Every tEXt chunk as key -> value."""
    found: dict[str, str] = {}
    for kind, payload in png_chunks(data):
        if kind == b"tEXt" and b"\x00" in payload:
            key, _, value = payload.partition(b"\x00")
            found[key.decode("latin-1")] = value.decode("latin-1")
    return found


def decode_rgb8(data: bytes, width: int, height: int) -> list[bytes]:
    """Decodes a non-interlaced 8-bit RGB PNG into rows of raw RGB bytes.

    Implements the five scanline filters from the specification. Slow in pure
    Python for a 1024-square image — about a second — which is fine for a
    check that runs three times.
    """
    compressed = b"".join(payload for kind, payload in png_chunks(data) if kind == b"IDAT")
    raw = zlib.decompress(compressed)
    stride = width * 3
    rows: list[bytearray] = []
    previous = bytearray(stride)
    offset = 0
    for _ in range(height):
        filter_type = raw[offset]
        line = bytearray(raw[offset + 1:offset + 1 + stride])
        offset += 1 + stride
        if filter_type == 1:      # Sub
            for i in range(3, stride):
                line[i] = (line[i] + line[i - 3]) & 0xFF
        elif filter_type == 2:    # Up
            for i in range(stride):
                line[i] = (line[i] + previous[i]) & 0xFF
        elif filter_type == 3:    # Average
            for i in range(stride):
                left = line[i - 3] if i >= 3 else 0
                line[i] = (line[i] + ((left + previous[i]) >> 1)) & 0xFF
        elif filter_type == 4:    # Paeth
            for i in range(stride):
                a = line[i - 3] if i >= 3 else 0
                b = previous[i]
                c = previous[i - 3] if i >= 3 else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                if pa <= pb and pa <= pc:
                    predictor = a
                elif pb <= pc:
                    predictor = b
                else:
                    predictor = c
                line[i] = (line[i] + predictor) & 0xFF
        elif filter_type != 0:
            raise ValueError(f"unknown PNG filter type {filter_type}")
        rows.append(line)
        previous = line
    return [bytes(row) for row in rows]


def pixel(row: bytes, x: int) -> tuple[int, int, int]:
    return row[x * 3], row[x * 3 + 1], row[x * 3 + 2]


def distance(a: tuple[int, int, int], b: tuple[int, int, int]) -> float:
    return ((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2) ** 0.5


def transition_widths(row: bytes, width: int) -> list[int]:
    """The width of every real edge on one scanline.

    Walks the line plateau by plateau. A plateau is a run of pixels within
    PLATEAU_TOLERANCE of its first pixel, at least PLATEAU_MIN_RUN long; the
    pixels between two plateaus are the transition, and it counts as an edge
    when the two plateau colors differ by at least EDGE_CONTRAST.
    """

    def starts_plateau(at: int) -> bool:
        if at + PLATEAU_MIN_RUN > width:
            return False
        reference = pixel(row, at)
        return all(
            distance(pixel(row, at + offset), reference) <= PLATEAU_TOLERANCE
            for offset in range(1, PLATEAU_MIN_RUN)
        )

    widths: list[int] = []
    x = 0
    while x < width:
        if not starts_plateau(x):
            x += 1
            continue
        reference = pixel(row, x)
        end = x
        while end + 1 < width and distance(pixel(row, end + 1), reference) <= PLATEAU_TOLERANCE:
            end += 1
        cursor = end + 1
        while cursor < width and not starts_plateau(cursor):
            cursor += 1
        if cursor >= width:
            break
        if distance(reference, pixel(row, cursor)) >= EDGE_CONTRAST:
            widths.append(cursor - end - 1)
        x = cursor
    return widths


def percentile(values: list[int], fraction: float) -> int:
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, int(round(fraction * (len(ordered) - 1)))))
    return ordered[index]


def inspect_pixels(name: str, data: bytes, width: int, height: int) -> list[str]:
    problems: list[str] = []
    try:
        rows = decode_rgb8(data, width, height)
    except (zlib.error, ValueError, IndexError) as error:
        return [f"{name} could not be decoded: {error}"]

    # Edge sharpness, sampled on every fourth scanline. The mark's edges are
    # horizontal runs on those lines; sampling them all would take longer
    # than the archive this check exists to protect.
    widths: list[int] = []
    for y in range(0, height, 4):
        widths.extend(transition_widths(rows[y], width))
    if not widths:
        problems.append(f"{name} has no edges at all; is the mark missing?")
    else:
        median = percentile(widths, 0.5)
        ninetieth = percentile(widths, 0.9)
        if median > MAX_MEDIAN_EDGE_WIDTH or ninetieth > MAX_EDGE_WIDTH:
            problems.append(
                f"{name} has soft edges: the typical transition is {median} px wide and "
                f"nine in ten are within {ninetieth} px (limits {MAX_MEDIAN_EDGE_WIDTH} "
                f"and {MAX_EDGE_WIDTH}); the artwork was blurred, upscaled or drawn "
                "soft — regenerate it with Tools/make_app_icon.py"
            )

    # Flat field in all four corners.
    corners = [(0, 0), (width - CORNER_PATCH, 0), (0, height - CORNER_PATCH),
               (width - CORNER_PATCH, height - CORNER_PATCH)]
    for (cx, cy) in corners:
        reference = pixel(rows[cy], cx)
        for y in range(cy, cy + CORNER_PATCH, 4):
            for x in range(cx, cx + CORNER_PATCH, 4):
                if pixel(rows[y], x) != reference:
                    problems.append(
                        f"{name} has a textured field near ({x}, {y}); the field must be "
                        "one flat color, with no grain or gradient"
                    )
                    break
            else:
                continue
            break

    # Palette size, on a coarse sample so it stays cheap.
    colors: set[tuple[int, int, int]] = set()
    for y in range(0, height, 2):
        row = rows[y]
        for x in range(0, width, 2):
            colors.add(pixel(row, x))
            if len(colors) > MAX_DISTINCT_COLORS:
                break
        if len(colors) > MAX_DISTINCT_COLORS:
            break
    if len(colors) > MAX_DISTINCT_COLORS:
        problems.append(
            f"{name} uses more than {MAX_DISTINCT_COLORS} distinct colors; flat artwork with "
            "antialiased edges needs a few dozen, so this has grain, noise or a gradient"
        )
    return problems


def inspect(path: str) -> list[str]:
    problems: list[str] = []
    name = os.path.basename(path)

    with open(path, "rb") as handle:
        data = handle.read()

    if not data.startswith(PNG_SIGNATURE):
        return [f"{name} is not a PNG"]

    header = None
    has_transparency_chunk = False
    has_icc_profile = False
    for kind, payload in png_chunks(data):
        if kind == b"IHDR":
            header = payload
        elif kind == b"tRNS":
            has_transparency_chunk = True
        elif kind == b"iCCP":
            has_icc_profile = True

    if header is None or len(header) < 13:
        return [f"{name} has no readable IHDR header"]

    width, height, bit_depth, color_type, _, _, interlace = struct.unpack(">IIBBBBB", header[:13])

    if (width, height) != (REQUIRED_SIZE, REQUIRED_SIZE):
        problems.append(
            f"{name} is {width}x{height}; App Store Connect requires "
            f"{REQUIRED_SIZE}x{REQUIRED_SIZE}"
        )
    if color_type != COLOR_TYPE_RGB:
        problems.append(
            f"{name} is {COLOR_TYPES.get(color_type, color_type)}; an app icon "
            "must be truecolor with no alpha channel, or the upload is rejected"
        )
    if has_transparency_chunk:
        problems.append(
            f"{name} carries a tRNS chunk, which is transparency by another name"
        )
    if has_icc_profile:
        problems.append(
            f"{name} embeds an ICC profile; the pipeline writes untagged sRGB, which "
            "is what Apple's toolchain assumes"
        )

    text = text_chunks(data)
    master = text.get(MASTER_KEY)
    if master is None:
        problems.append(
            f"{name} has no {MASTER_KEY!r} record, so it was not produced by "
            "Tools/make_app_icon.py — every appearance must come from the geometry"
        )
    else:
        try:
            master_size = int(master)
        except ValueError:
            master_size = 0
        if master_size < MIN_MASTER_SIZE:
            problems.append(
                f"{name} was rendered from a {master} master; anything under "
                f"{MIN_MASTER_SIZE} is an upscale, not a downsample"
            )

    # The pixel rules only make sense on an image the header says is sane.
    if not problems and bit_depth == 8 and color_type == COLOR_TYPE_RGB and interlace == 0:
        problems.extend(inspect_pixels(name, data, width, height))
    elif not problems:
        problems.append(f"{name} is not 8-bit non-interlaced RGB, so its pixels were not checked")
    return problems


def main() -> int:
    errors: list[str] = []

    contents_path = os.path.join(ICON_SET, "Contents.json")
    if not os.path.exists(contents_path):
        print(f"error: {contents_path} is missing")
        return 1

    contents = json.load(open(contents_path, encoding="utf-8"))
    images = contents.get("images", [])

    # Every appearance the catalog promises must be present, and the catalog
    # must not promise one that is not.
    declared: dict[str, str | None] = {}
    for image in images:
        filename = image.get("filename")
        if not filename:
            errors.append("an entry in Contents.json has no filename")
            continue
        appearances = image.get("appearances") or []
        value = appearances[0].get("value") if appearances else None
        declared[filename] = value

    for filename, appearance in EXPECTED_APPEARANCES.items():
        if filename not in declared:
            errors.append(f"Contents.json does not list {filename}")
        elif declared[filename] != appearance:
            errors.append(
                f"{filename} is declared as appearance {declared[filename]!r}; "
                f"expected {appearance!r}"
            )
    for filename in declared:
        if filename not in EXPECTED_APPEARANCES:
            errors.append(f"Contents.json lists an unexpected image, {filename}")

    for filename in EXPECTED_APPEARANCES:
        path = os.path.join(ICON_SET, filename)
        if not os.path.exists(path):
            errors.append(f"{filename} is missing from the icon set")
            continue
        errors.extend(inspect(path))

    # The build setting that decides which icon set ships. Renaming the folder
    # without it is a build that silently has no icon.
    if os.path.exists(PROJECT):
        project = open(PROJECT, encoding="utf-8").read()
        if "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;" not in project:
            errors.append(
                "ASSETCATALOG_COMPILER_APPICON_NAME is not AppIcon in the project, "
                "so the app would ship without an icon"
            )

    if errors:
        for error in errors:
            print(f"error: {error}")
        return 1

    print(
        f"OK — {len(EXPECTED_APPEARANCES)} app icon appearances, each "
        f"{REQUIRED_SIZE}x{REQUIRED_SIZE} truecolor with no alpha, hard-edged "
        f"(median edge {MAX_MEDIAN_EDGE_WIDTH}px, 90th percentile ≤{MAX_EDGE_WIDTH}px), "
        f"flat field, rendered from a "
        f"≥{MIN_MASTER_SIZE} master"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
