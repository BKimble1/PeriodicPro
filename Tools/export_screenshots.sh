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

xcrun xcresulttool export attachments \
  --path "$RESULT_BUNDLE" \
  --output-path "$STAGING"

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

ls -la "$OUTPUT_DIR"
