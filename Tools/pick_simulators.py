#!/usr/bin/env python3
"""Chooses iPhone and iPad simulators from whatever the machine actually has.

GitHub rotates the device set in its macOS images, so a hard-coded
`name=iPhone 17 Pro` destination fails the whole pipeline the day that device
goes away. This reads `xcrun simctl list devices available --json` and picks a
default, a small and a large iPhone, plus an iPad, from what is there.

    xcrun simctl list devices available --json | python3 Tools/pick_simulators.py

Writes `KEY=udid` lines suitable for appending to $GITHUB_ENV, and a readable
summary on stderr.
"""
from __future__ import annotations

import json
import re
import sys

SMALL_HINTS = ("SE", "mini", "16e", "13 mini", "12 mini")
LARGE_HINTS = ("Pro Max", "Plus")


def device_rank(name: str) -> tuple:
    """Newer model numbers sort last."""
    numbers = [int(part) for part in re.findall(r"\d+", name)]
    return (numbers[0] if numbers else 0, name)


def main() -> int:
    raw = sys.stdin.read()
    if not raw.strip():
        print("error: no simulator JSON on stdin", file=sys.stderr)
        return 2

    devices = []
    ipads = []
    for runtime, entries in json.loads(raw).get("devices", {}).items():
        if "iOS" not in runtime:
            continue
        for entry in entries:
            if not entry.get("isAvailable", False):
                continue
            name = entry.get("name", "")
            if "iPhone" in name:
                devices.append(entry)
            elif "iPad" in name:
                ipads.append(entry)

    if not devices:
        print("error: no available iPhone simulators", file=sys.stderr)
        return 1

    devices.sort(key=lambda d: device_rank(d["name"]))

    def first(hints, fallback):
        for device in devices:
            if any(hint.lower() in device["name"].lower() for hint in hints):
                return device
        return fallback

    newest = devices[-1]
    large = first(LARGE_HINTS, newest)
    small = first(SMALL_HINTS, devices[0])
    default = next(
        (d for d in reversed(devices)
         if "pro" in d["name"].lower() and "max" not in d["name"].lower()),
        newest,
    )

    chosen = {"SIM_DEFAULT": default, "SIM_SMALL": small, "SIM_LARGE": large}

    # The app ships for iPhone and iPad, so CI needs one of each. A plain iPad
    # or an Air is preferred over a Pro: the narrower screen is where a layout
    # built for a phone is likeliest to look stretched, and it is the one more
    # people own.
    if ipads:
        ipads.sort(key=lambda d: device_rank(d["name"]))
        chosen["SIM_IPAD"] = next(
            (d for d in ipads if "pro" not in d["name"].lower()), ipads[-1]
        )
    else:
        print("warning: no available iPad simulators", file=sys.stderr)
    for key, device in chosen.items():
        print(f"{key}={device['udid']}")
        print(f"{key}_NAME={device['name']}")
        print(f"{key:12} -> {device['name']}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
