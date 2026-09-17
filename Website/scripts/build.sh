#!/usr/bin/env bash
#
# Writes site/.well-known/apple-app-site-association from its template.
#
# The only thing this substitutes is the Apple Developer Team ID, which is a
# signing identifier and is supplied by the host's environment rather than
# committed. Set APPLE_TEAM_ID in the Netlify site's environment variables (or
# export it locally) before deploying.
#
#     APPLE_TEAM_ID=XXXXXXXXXX bash scripts/build.sh

set -euo pipefail
cd "$(dirname "$0")/.."

TEMPLATE="site/.well-known/apple-app-site-association.template"
OUTPUT="site/.well-known/apple-app-site-association"

if [ -z "${APPLE_TEAM_ID:-}" ]; then
  echo "error: APPLE_TEAM_ID is not set." >&2
  echo "       Universal Links cannot work without it: iOS matches the app's" >&2
  echo "       signed <TeamID>.com.idlery.periodicpro against this file." >&2
  exit 1
fi

case "$APPLE_TEAM_ID" in
  [A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9]) ;;
  *)
    echo "error: APPLE_TEAM_ID should be the 10-character Team ID." >&2
    exit 1
    ;;
esac

sed "s/__APPLE_TEAM_ID__/$APPLE_TEAM_ID/" "$TEMPLATE" > "$OUTPUT"
# Never print the value; confirming the shape is enough.
echo "wrote $OUTPUT (app ID: <TeamID>.com.idlery.periodicpro)"

python3 -c "import json,sys; json.load(open('$OUTPUT'))" \
  && echo "apple-app-site-association is valid JSON"
