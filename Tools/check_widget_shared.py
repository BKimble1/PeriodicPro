#!/usr/bin/env python3
"""The app and the widget agree about the data they share.

The serialization contract between Elemora and its Home Screen widget lives in
one file that is compiled into both targets. Because the project uses
file-system synchronized groups — a folder belongs to a target — that file
exists twice on disk. Two copies of a wire format is exactly the arrangement
that rots: the app starts writing a field the widget does not decode, nothing
fails to build, and the widget silently shows a placeholder forever.

So the copies are compared byte for byte, and the identifiers that have to
match the signed entitlements are checked against the entitlements themselves.

    python3 Tools/check_widget_shared.py
"""
from __future__ import annotations

import os
import plistlib
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (app copy, widget copy)
SHARED_PAIRS = [
    (
        os.path.join("PeriodicPro", "WidgetShared", "ElemoraSharedStore.swift"),
        os.path.join("ElemoraWidgets", "Shared", "ElemoraSharedStore.swift"),
    ),
]

APP_ENTITLEMENTS = os.path.join("Config", "Elemora.entitlements")
WIDGET_ENTITLEMENTS = os.path.join("Config", "ElemoraWidgets.entitlements")
WIDGET_INFO = os.path.join("Config", "ElemoraWidgets-Info.plist")
APP_GROUP_KEY = "com.apple.security.application-groups"

# The widget extension's bundle identifier is derived from the app's, which
# must not change. Build 5 of the specification names it explicitly.
BUNDLE_BASE = "com.idlery.periodicpro"
EXPECTED_GROUP = f"group.{BUNDLE_BASE}"


def read_bytes(path: str) -> bytes | None:
    full = os.path.join(ROOT, path)
    if not os.path.exists(full):
        return None
    with open(full, "rb") as handle:
        return handle.read()


def read_plist(path: str) -> dict | None:
    full = os.path.join(ROOT, path)
    if not os.path.exists(full):
        return None
    with open(full, "rb") as handle:
        return plistlib.load(handle)


def first_difference(left: bytes, right: bytes) -> str:
    """Where the two copies stop agreeing, as a line number and the two lines."""
    left_lines = left.decode("utf-8", "replace").splitlines()
    right_lines = right.decode("utf-8", "replace").splitlines()
    for index, (one, other) in enumerate(zip(left_lines, right_lines), start=1):
        if one != other:
            return f"line {index}:\n    app:    {one.strip()}\n    widget: {other.strip()}"
    shorter, longer = sorted((len(left_lines), len(right_lines)))
    return f"identical for {shorter} lines; one copy has {longer - shorter} more"


ICON_SOURCE = os.path.join("PeriodicPro", "App", "ElemoraAppIcon.swift")
WIDGET_PALETTE = os.path.join("ElemoraWidgets", "WidgetPalette.swift")
# (name in ElemoraIconPalette, name in WidgetPalette)
SHARED_COLORS = [("teal", "accent"), ("gold", "gold"), ("field", "canvas")]

COLOR_PAIR = re.compile(
    r"static let (\w+) = Color\(\s*"
    r"light: Color\(red: ([\d./ ]+), green: ([\d./ ]+), blue: ([\d./ ]+)\),\s*"
    r"dark: Color\(red: ([\d./ ]+), green: ([\d./ ]+), blue: ([\d./ ]+)\)"
)


def colors(path: str) -> dict[str, tuple[str, ...]]:
    """Every `static let name = Color(light:dark:)` in a file, as raw literals."""
    raw = read_bytes(path)
    if raw is None:
        return {}
    text = raw.decode("utf-8")
    found = {}
    for match in COLOR_PAIR.finditer(text):
        name = match.group(1)
        found[name] = tuple(part.replace(" ", "") for part in match.groups()[1:])
    return found


def palette_errors() -> list[str]:
    icon = colors(ICON_SOURCE)
    widget = colors(WIDGET_PALETTE)
    if not icon:
        return [f"no Color(light:dark:) pairs found in {ICON_SOURCE}"]
    if not widget:
        return [f"no Color(light:dark:) pairs found in {WIDGET_PALETTE}"]

    problems = []
    for icon_name, widget_name in SHARED_COLORS:
        if icon_name not in icon:
            problems.append(f"{ICON_SOURCE} no longer defines {icon_name}")
            continue
        if widget_name not in widget:
            problems.append(f"{WIDGET_PALETTE} no longer defines {widget_name}")
            continue
        if icon[icon_name] != widget[widget_name]:
            problems.append(
                f"WidgetPalette.{widget_name} does not match ElemoraIconPalette.{icon_name}:\n"
                f"    icon:   {icon[icon_name]}\n"
                f"    widget: {widget[widget_name]}"
            )
    return problems


def main() -> int:
    errors: list[str] = []

    # --- the shared sources are the same file --------------------------------
    for app_path, widget_path in SHARED_PAIRS:
        app_copy = read_bytes(app_path)
        widget_copy = read_bytes(widget_path)
        if app_copy is None:
            errors.append(f"{app_path} is missing")
            continue
        if widget_copy is None:
            errors.append(f"{widget_path} is missing")
            continue
        if app_copy != widget_copy:
            errors.append(
                f"{app_path} and {widget_path} have diverged.\n  "
                + first_difference(app_copy, widget_copy)
                + f"\n  Fix with: cp {app_path} {widget_path}"
            )

    # --- the App Group in the source is the App Group that is signed ---------
    source = read_bytes(SHARED_PAIRS[0][0])
    if source is not None:
        text = source.decode("utf-8")
        match = re.search(r'static let identifier = "([^"]+)"', text)
        if not match:
            errors.append("ElemoraAppGroup.identifier could not be found in the shared source")
        elif match.group(1) != EXPECTED_GROUP:
            errors.append(
                f"ElemoraAppGroup.identifier is {match.group(1)!r}; "
                f"expected {EXPECTED_GROUP!r}, derived from the bundle identifier"
            )

    for label, path in (("app", APP_ENTITLEMENTS), ("widget", WIDGET_ENTITLEMENTS)):
        plist = read_plist(path)
        if plist is None:
            errors.append(f"{path} is missing")
            continue
        groups = plist.get(APP_GROUP_KEY)
        if not groups:
            errors.append(f"{path} declares no App Group; the {label} cannot open the container")
        elif EXPECTED_GROUP not in groups:
            errors.append(f"{path} does not declare {EXPECTED_GROUP!r}, it declares {groups!r}")

    # --- the widget is an extension iOS will actually load -------------------
    info = read_plist(WIDGET_INFO)
    if info is None:
        errors.append(f"{WIDGET_INFO} is missing")
    else:
        point = info.get("NSExtension", {}).get("NSExtensionPointIdentifier")
        if point != "com.apple.widgetkit-extension":
            errors.append(
                f"{WIDGET_INFO} has NSExtensionPointIdentifier {point!r}; a widget "
                "extension must be com.apple.widgetkit-extension or it never appears "
                "in the gallery"
            )

    # --- the widget's palette is the app's palette ----------------------------
    # The widget extension cannot read the app's asset catalog, so its colors
    # are written out. That is a second copy of the brand, and a second copy
    # drifts. These three are the ones a learner would notice.
    errors.extend(palette_errors())

    # --- the app never carries a capability it does not use ------------------
    app_plist = read_plist(APP_ENTITLEMENTS) or {}
    for key in app_plist:
        if key not in (APP_GROUP_KEY, "com.apple.developer.associated-domains"):
            errors.append(
                f"{APP_ENTITLEMENTS} declares {key}, which is not one of the two "
                "capabilities this app is meant to request"
            )

    for error in errors:
        print(f"error: {error}")
    if errors:
        print(f"\n{len(errors)} problem(s) in the widget's shared layer")
        return 1
    print("OK — the app and the widget share one file and one App Group")
    return 0


if __name__ == "__main__":
    sys.exit(main())
