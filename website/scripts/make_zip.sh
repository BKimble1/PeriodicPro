#!/usr/bin/env bash
#
# Build elemora-netlify.zip from site/ — the exact artifact you drag onto Netlify.
#
#   APPLE_TEAM_ID=XXXXXXXXXX ./scripts/make_zip.sh            # -> ./elemora-netlify.zip
#   APPLE_TEAM_ID=XXXXXXXXXX ./scripts/make_zip.sh /some/path
#   ./scripts/make_zip.sh --without-universal-links           # see below
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
#
# --without-universal-links packages the site with no association file at all.
# That is a real, deployable state — every page works and a shared quiz opens
# the landing page — it simply means a shared link cannot open the app yet. It
# is deliberately a flag you have to type, and it is deliberately not the same
# as shipping a placeholder: a file that names a Team ID of __APPLE_TEAM_ID__
# is cached by Apple's CDN for hours and is worse than no file at all.

set -euo pipefail

WEB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$WEB/.." && pwd)"
SITE="$WEB/site"
AASA=".well-known/apple-app-site-association"

WITH_LINKS=1
ARGS=()
for argument in "$@"; do
  case "$argument" in
    --without-universal-links) WITH_LINKS=0 ;;
    *) ARGS+=("$argument") ;;
  esac
done

DEST="${ARGS[0]:-$ROOT}"   # the repository root, so the ZIP is easy to find
ZIP="$DEST/elemora-netlify.zip"

[ -f "$SITE/index.html" ] || { echo "no index.html in $SITE" >&2; exit 1; }

# The Apple app-site-association, generated from its template. build_aasa.py
# validates the Team ID and the JSON, and exits non-zero on anything it does
# not recognise, so `set -e` stops the packaging here rather than later.
if [ "$WITH_LINKS" -eq 1 ]; then
  python3 "$WEB/scripts/build_aasa.py"
else
  rm -f "$SITE/$AASA"
  echo "warning: packaging WITHOUT $AASA." >&2
  echo "         Every page works and /quiz/<payload> serves the landing page," >&2
  echo "         but a shared link cannot open Elemora until this file is" >&2
  echo "         served. Rebuild with APPLE_TEAM_ID set to fix that." >&2
fi

# The site must also match website/config.json: the App Store call to action is
# generated markup, and a ZIP built from drifted HTML would ship a stale button.
python3 "$WEB/scripts/apply_config.py" --check

rm -f "$ZIP"
mkdir -p "$DEST"

# -r recurse, -q quiet, -X drop platform extras. The template is source, not
# something to deploy: it is the file with __APPLE_TEAM_ID__ still in it, and
# nothing should ever be able to fetch that from the live site. The rest of the
# excludes are belt and braces — none of them exist under site/, but a stray one
# must never ship.
EXCLUDES=('.well-known/*.template'
          '.DS_Store' '**/.DS_Store' '__MACOSX/*'
          '*.map' '.env' '.env.*'
          'node_modules/*' '**/node_modules/*'
          '.git/*' '**/.git/*')
if [ "$WITH_LINKS" -eq 0 ]; then
  # Nothing is left to serve from there, so do not ship the empty folder.
  EXCLUDES+=('.well-known/' '.well-known/*')
fi

( cd "$SITE" && zip -r -q -X "$ZIP" . -x "${EXCLUDES[@]}" )

# Prove the deployable artifact carries the files a drag-and-drop deploy cannot
# regenerate, and that the association file inside it is the real one.
#
# The listing is read once into a variable rather than piped into grep per
# entry. `set -o pipefail` plus `grep -q` is a trap: grep stops at the first
# match, unzip takes SIGPIPE writing the rest, and the pipeline reports failure
# for a file that is right there — which is exactly what it did.
LISTING="$(unzip -Z1 "$ZIP")"

contains() {
  case $'\n'"$LISTING"$'\n' in
    *$'\n'"$1"$'\n'*) return 0 ;;
    *) return 1 ;;
  esac
}

REQUIRED=("index.html" "quiz/index.html" "404.html" "privacy/index.html"
          "support/index.html" "terms/index.html" "_redirects" "_headers")
if [ "$WITH_LINKS" -eq 1 ]; then
  REQUIRED+=("$AASA")
fi
for entry in "${REQUIRED[@]}"; do
  contains "$entry" || { echo "$entry is missing from $ZIP" >&2; exit 1; }
done

if contains "$AASA.template"; then
  echo "$ZIP ships the association template; only the generated file may go out" >&2
  exit 1
fi

if [ "$WITH_LINKS" -eq 1 ]; then
  ASSOCIATION="$(unzip -p "$ZIP" "$AASA")"
  case "$ASSOCIATION" in
    *__APPLE_TEAM_ID__*)
      echo "$ZIP contains an unsubstituted association file" >&2
      exit 1 ;;
  esac
  printf '%s' "$ASSOCIATION" | python3 -c 'import json,sys; json.load(sys.stdin)' \
    || { echo "the association file in $ZIP is not valid JSON" >&2; exit 1; }
  echo "association file: $(printf '%s' "$ASSOCIATION" | tr -d ' \n')"
elif contains "$AASA"; then
  echo "$ZIP still contains an association file" >&2
  exit 1
fi

echo "$ZIP"
unzip -l "$ZIP" | tail -n 3
