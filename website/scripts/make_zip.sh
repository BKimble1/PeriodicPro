#!/usr/bin/env bash
#
# Build elemora-netlify.zip from site/ — the exact artifact you drag onto Netlify.
#
#   APPLE_TEAM_ID=XXXXXXXXXX ./scripts/make_zip.sh            # -> ./elemora-netlify.zip
#   APPLE_TEAM_ID=XXXXXXXXXX ./scripts/make_zip.sh /some/path
#
# The contents of site/ land at the ZIP root, so index.html is at the top level
# with no wrapper folder. Netlify rejects nothing here, but it only reads
# _redirects and _headers when they sit at the publish root — which is exactly
# where this puts them.
#
# A drag-and-drop deploy runs no build command, so anything generated has to be
# generated HERE. That is one file: .well-known/apple-app-site-association,
# which carries the Apple Team ID and is therefore never committed. Without
# APPLE_TEAM_ID this script stops rather than shipping a ZIP whose Universal
# Links silently do not work.

set -euo pipefail

WEB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$WEB/.." && pwd)"
SITE="$WEB/site"
DEST="${1:-$ROOT}"   # the repository root, so the ZIP is easy to find
ZIP="$DEST/elemora-netlify.zip"

[ -f "$SITE/index.html" ] || { echo "no index.html in $SITE" >&2; exit 1; }

# The Apple app-site-association, generated from its template. build_aasa.py
# validates the Team ID and the JSON, and exits non-zero on anything it does
# not recognise, so `set -e` stops the packaging here rather than later.
python3 "$WEB/scripts/build_aasa.py"

# The site must also match website/config.json: the App Store call to action is
# generated markup, and a ZIP built from drifted HTML would ship a stale button.
python3 "$WEB/scripts/apply_config.py" --check

rm -f "$ZIP"
mkdir -p "$DEST"

# -r recurse, -q quiet, -X drop platform extras. The excludes are belt and
# braces: none of these exist under site/, but a stray one must never ship.
( cd "$SITE" && zip -r -q -X "$ZIP" . \
    -x '.DS_Store' '**/.DS_Store' '__MACOSX/*' \
       '*.map' '.env' '.env.*' \
       'node_modules/*' '**/node_modules/*' \
       '.git/*' '**/.git/*' )

# Prove the deployable artifact carries the four files a drag-and-drop deploy
# cannot regenerate, and that the association file inside it is the real one.
AASA=".well-known/apple-app-site-association"
for entry in "index.html" "quiz/index.html" "_redirects" "_headers" "$AASA"; do
  unzip -l "$ZIP" | grep -q " $entry\$" || { echo "$entry is missing from $ZIP" >&2; exit 1; }
done
if unzip -p "$ZIP" "$AASA" | grep -q "__APPLE_TEAM_ID__"; then
  echo "$ZIP contains an unsubstituted association file" >&2
  exit 1
fi
unzip -p "$ZIP" "$AASA" | python3 -c 'import json,sys; json.load(sys.stdin)' \
  || { echo "the association file in $ZIP is not valid JSON" >&2; exit 1; }

echo "$ZIP"
unzip -l "$ZIP" | tail -n 3
