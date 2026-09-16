#!/usr/bin/env python3
"""Gives exported xcresult attachments their human-readable names back.

`xcresulttool export attachments` writes UUID filenames plus a manifest that
says what each one was called. This restores the names, with two constraints
that are not obvious until they bite:

* GitHub's upload-artifact rejects a file whose name contains any of
  `" : < > | * ? \\r \\n`, and it fails the *whole* upload when it finds one.
  XCTest names its own automatic diagnostics things like
  ``Debug description for `"element.Au" Button` ``, so one failed query took
  down an upload of screenshots that had exported perfectly well.
* The extension has to come from the exported file, not be assumed. Those
  diagnostics are text; a .txt renamed to .png is a file nothing will open.

    python3 Tools/rename_attachments.py <manifest.json> <staging-dir> <output-dir>
"""
from __future__ import annotations

import json
import os
import re
import shutil
import sys

FORBIDDEN = re.compile(r'["*:<>?|\r\n\\/]+')


def safe(name: str) -> str:
    cleaned = FORBIDDEN.sub("-", name)
    cleaned = re.sub(r"\s+", " ", cleaned).strip().strip(".")
    return cleaned[:120] or "attachment"


def main() -> int:
    manifest_path, staging, output = sys.argv[1:4]
    with open(manifest_path, encoding="utf-8") as handle:
        manifest = json.load(handle)

    entries = manifest if isinstance(manifest, list) else [manifest]
    count = 0
    for entry in entries:
        for attachment in entry.get("attachments", []):
            exported = attachment.get("exportedFileName")
            if not exported:
                continue
            source = os.path.join(staging, exported)
            if not os.path.exists(source):
                continue

            # The extension comes from the exported file, never from the
            # human-readable name. Splitting the name is wrong whenever it
            # contains a dot of its own: `Debug description for "element.Au"
            # Button` splits at `.Au- Button`, and the name is truncated to
            # `Debug description for -element`.
            name = attachment.get("suggestedHumanReadableName") or exported
            suffix = os.path.splitext(exported)[1] or ".png"
            stem = safe(name)
            if stem.lower().endswith(suffix.lower()):
                stem = stem[: -len(suffix)]

            # Two attachments can share a human-readable name — the tour runs
            # once per appearance — so never silently drop one.
            destination = os.path.join(output, stem + suffix)
            index = 2
            while os.path.exists(destination):
                destination = os.path.join(output, f"{stem}-{index}{suffix}")
                index += 1

            shutil.copyfile(source, destination)
            count += 1

    print(f"exported {count} attachment(s) to {output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
