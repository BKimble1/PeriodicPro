#!/usr/bin/env python3
"""Checks the app icon against the rules App Store Connect enforces at upload.

An icon that is the wrong size, or that carries an alpha channel, is rejected
by Apple's upload endpoint — after a full archive, sign and export, which on a
hosted runner is most of an hour. Every rule below is cheap to check here and
expensive to discover there.

The PNG header is read by hand rather than through Pillow, so this runs on a
bare CI image with no pip install:

    python3 Tools/check_app_icon.py
"""
from __future__ import annotations

import json
import os
import struct
import sys

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


def inspect(path: str) -> list[str]:
    problems: list[str] = []
    name = os.path.basename(path)

    with open(path, "rb") as handle:
        data = handle.read()

    if not data.startswith(PNG_SIGNATURE):
        return [f"{name} is not a PNG"]

    header = None
    has_transparency_chunk = False
    for kind, payload in png_chunks(data):
        if kind == b"IHDR":
            header = payload
        elif kind == b"tRNS":
            has_transparency_chunk = True

    if header is None or len(header) < 10:
        return [f"{name} has no readable IHDR header"]

    width, height, _bit_depth, color_type = struct.unpack(">IIBB", header[:10])

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
        f"{REQUIRED_SIZE}x{REQUIRED_SIZE} truecolor with no alpha"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
