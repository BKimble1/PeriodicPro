#!/usr/bin/env bash
#
# Build elemora-netlify.zip from site/ — the exact artifact you drag onto Netlify.
#
#   ./scripts/make_zip.sh            # writes ./elemora-netlify.zip
#   ./scripts/make_zip.sh /some/path # writes /some/path/elemora-netlify.zip
#
# The contents of site/ land at the ZIP root, so index.html is at the top level
# with no wrapper folder. Netlify rejects nothing here, but it only reads
# _redirects and _headers when they sit at the publish root — which is exactly
# where this puts them.

set -euo pipefail

WEB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$WEB/.." && pwd)"
SITE="$WEB/site"
DEST="${1:-$ROOT}"   # the repository root, so the ZIP is easy to find
ZIP="$DEST/elemora-netlify.zip"

[ -f "$SITE/index.html" ] || { echo "no index.html in $SITE" >&2; exit 1; }

rm -f "$ZIP"
mkdir -p "$DEST"

# -r recurse, -q quiet, -X drop platform extras. The excludes are belt and
# braces: none of these exist under site/, but a stray one must never ship.
( cd "$SITE" && zip -r -q -X "$ZIP" . \
    -x '.DS_Store' '**/.DS_Store' '__MACOSX/*' \
       '*.map' '.env' '.env.*' \
       'node_modules/*' '**/node_modules/*' \
       '.git/*' '**/.git/*' )

echo "$ZIP"
unzip -l "$ZIP" | tail -n 3
