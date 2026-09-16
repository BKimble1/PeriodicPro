#!/usr/bin/env bash
#
# Pulls the attachments ElemoraScreenshotTests left in a result bundle out into
# plain files.
#
#   ./Tools/export_screenshots.sh build/Screenshots-light.xcresult Screenshots
#
# The screenshots are named in the test (`01-table-light` and friends), and
# xcresulttool preserves those names, so the output is a folder a person can
# look at in order rather than a pile of UUIDs. XCTest also attaches its own
# diagnostics when a query fails — those come out too, because when the tour
# fails they are the most useful thing in the bundle.
#
# `xcresulttool export attachments` is the Xcode 16+ spelling. Older Xcodes only
# had the deprecated `--format json --id` graph walk; this script does not try
# to support both, because the whole pipeline is pinned to Xcode 26.

set -euo pipefail

RESULT_BUNDLE="${1:?usage: export_screenshots.sh <result.xcresult> <output-dir>}"
OUTPUT_DIR="${2:?usage: export_screenshots.sh <result.xcresult> <output-dir>}"

if [ ! -d "$RESULT_BUNDLE" ]; then
  echo "error: $RESULT_BUNDLE does not exist" >&2
  exit 1
fi

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

# Silenced: it prints a "File: <uuid>, suggested name: <name>" line for every
# attachment, and XCTest attaches a snapshot per query and an image per tap, so
# this alone ran to a hundred lines a bundle.
xcrun xcresulttool export attachments \
  --path "$RESULT_BUNDLE" \
  --output-path "$STAGING" >/dev/null

mkdir -p "$OUTPUT_DIR"

# The export writes a manifest describing which file is which attachment. Use
# it to restore the names, and fall back to the on-disk names if the manifest
# shape ever changes — a screenshot with an ugly name still beats no screenshot.
MANIFEST="$STAGING/manifest.json"
if [ -f "$MANIFEST" ]; then
  python3 Tools/rename_attachments.py "$MANIFEST" "$STAGING" "$OUTPUT_DIR"
else
  echo "warning: no manifest.json in the export; copying PNGs verbatim" >&2
  find "$STAGING" -name '*.png' -exec cp {} "$OUTPUT_DIR/" \;
fi

# A count and the tour's own frames, not the whole folder. XCTest adds its own
# snapshots, synthesized-event images and a screen recording on failure, and
# listing all of them three times over buried the failure this script was run
# to help diagnose.
echo "screenshots so far: $(ls -1 "$OUTPUT_DIR" | wc -l | tr -d ' ') file(s)"
ls -1 "$OUTPUT_DIR" | grep -E '^[0-9]{2}-' || true

# When the tour fails, XCTest attaches a full description of the failure. Print
# it. It is the one thing in the bundle worth reading from CI, and the
# alternative is downloading a fifty-megabyte artifact to see one paragraph —
# which is not possible at all from an environment whose egress policy blocks
# the artifact host.
find "$OUTPUT_DIR" -maxdepth 1 -name 'Complete Issue Description*' -print0 2>/dev/null |
  while IFS= read -r -d '' issue; do
    echo "--- $(basename "$issue") ---"
    cat "$issue"
    echo "--- end ---"
  done
