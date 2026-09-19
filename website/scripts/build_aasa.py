#!/usr/bin/env python3
"""
Generate site/.well-known/apple-app-site-association from its template.

    APPLE_TEAM_ID=XXXXXXXXXX python3 website/scripts/build_aasa.py
    python3 website/scripts/build_aasa.py --team-id XXXXXXXXXX
    python3 website/scripts/build_aasa.py --check        # verify, write nothing

The association file is what tells iOS that https://elemora.idlery.com/quiz/<payload>
belongs to Elemora, so tapping a shared quiz opens the app instead of Safari. It
names one application -- <TeamID>.com.idlery.periodicpro -- and one path,
/quiz/*, so the home page, /support, /privacy and /terms stay ordinary web pages.

The Team ID is a signing identifier and is never committed: the generated file is
git-ignored and produced here, from APPLE_TEAM_ID, at package or deploy time. A
placeholder is worse than nothing -- Apple's CDN caches this file for hours -- so
this script refuses to write one.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

WEB = Path(__file__).resolve().parents[1]
TEMPLATE = WEB / "site" / ".well-known" / "apple-app-site-association.template"
OUTPUT = WEB / "site" / ".well-known" / "apple-app-site-association"
PLACEHOLDER = "__APPLE_TEAM_ID__"
BUNDLE_ID = "com.idlery.periodicpro"

# Apple Team IDs are ten upper-case alphanumerics.
TEAM_ID_RE = re.compile(r"^[A-Z0-9]{10}$")


def resolve_team_id(explicit: str | None) -> str:
    team = (explicit or os.environ.get("APPLE_TEAM_ID") or "").strip()
    if not team:
        sys.exit(
            "error: no Apple Team ID.\n"
            "  Set APPLE_TEAM_ID, or pass --team-id. It is the ten-character\n"
            "  identifier under Membership details at developer.apple.com, and it\n"
            "  is the same value as the repository's APPLE_TEAM_ID secret."
        )
    if not TEAM_ID_RE.match(team):
        sys.exit(
            f"error: {team!r} is not an Apple Team ID.\n"
            "  It is exactly ten upper-case letters and digits, with no dot and no\n"
            "  bundle identifier after it."
        )
    return team


def render(team_id: str) -> str:
    text = TEMPLATE.read_text()
    if PLACEHOLDER not in text:
        sys.exit(f"error: {TEMPLATE} no longer contains {PLACEHOLDER}")
    rendered = text.replace(PLACEHOLDER, team_id)

    # Parse what we are about to serve. iOS rejects the whole file on a syntax
    # error, and a silent typo here is a Universal Link that never fires.
    data = json.loads(rendered)
    details = data["applinks"]["details"]
    app_ids = [app_id for detail in details for app_id in detail.get("appIDs", [])]
    if app_ids != [f"{team_id}.{BUNDLE_ID}"]:
        sys.exit(f"error: unexpected appIDs {app_ids}")
    paths = [
        component["/"]
        for detail in details
        for component in detail.get("components", [])
    ]
    if paths != ["/quiz/*"]:
        sys.exit(f"error: unexpected components {paths}")
    if PLACEHOLDER in rendered:
        sys.exit("error: the placeholder survived substitution")
    return rendered


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--team-id", help="ten-character Apple Team ID (else $APPLE_TEAM_ID)")
    ap.add_argument("--check", action="store_true",
                    help="verify an already-generated file, write nothing")
    args = ap.parse_args()

    if args.check:
        if not OUTPUT.exists():
            print(f"missing: {OUTPUT.relative_to(WEB)} — run this script to generate it",
                  file=sys.stderr)
            return 1
        text = OUTPUT.read_text()
        if PLACEHOLDER in text:
            print(f"error: {OUTPUT.relative_to(WEB)} still contains {PLACEHOLDER}",
                  file=sys.stderr)
            return 1
        data = json.loads(text)
        app_ids = [a for d in data["applinks"]["details"] for a in d.get("appIDs", [])]
        for app_id in app_ids:
            team, _, bundle = app_id.partition(".")
            if not TEAM_ID_RE.match(team) or bundle != BUNDLE_ID:
                print(f"error: {app_id!r} is not <TeamID>.{BUNDLE_ID}", file=sys.stderr)
                return 1
        print(f"ok: {OUTPUT.relative_to(WEB)} names {', '.join(app_ids)}")
        return 0

    team_id = resolve_team_id(args.team_id)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(render(team_id))
    print(f"wrote {OUTPUT.relative_to(WEB)} for {team_id}.{BUNDLE_ID} (/quiz/*)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
