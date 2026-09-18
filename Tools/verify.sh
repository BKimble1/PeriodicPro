#!/usr/bin/env bash
#
# Every check that can run without a Mac. CI runs the same three in its
# validate-data job; this is the local shorthand.
#
#   ./Tools/verify.sh
#
# The Xcode build, unit tests and UI tests need macOS — see README.md.

set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
run() {
  printf '\n\033[1m==> %s\033[0m\n' "$1"
  shift
  if "$@"; then :; else fail=1; fi
}

run "Element dataset"        python3 Tools/validate_elements.py
run "Structure profiles"     python3 Tools/validate_structures.py
run "Compound catalog"       python3 Tools/validate_compounds.py
run "Swift source hygiene"   python3 Tools/lint_sources.py
run "Swift syntax (tree-sitter, skipped if not installed)" python3 Tools/check_swift_syntax.py
run "Xcode project structure" python3 Tools/validate_project.py
run "Initializer call sites"  python3 Tools/check_initializers.py
run "Synthesized conformances" python3 Tools/check_conformances.py
run "Undeclared identifiers"  python3 Tools/check_undeclared.py
run "Colour contrast"        python3 Tools/check_contrast.py
run "StoreKit configuration" python3 Tools/check_storekit.py
run "Branding (Elemora)"     python3 Tools/check_branding.py
run "App icon"               python3 Tools/check_app_icon.py
run "Artwork and structure routing" python3 Tools/check_visual_routing.py
run "Website and universal links" python3 Tools/check_website.py
run "The whole table fits"     python3 Tools/check_table_fit.py
run "Table layout at three device widths" python3 Tools/preview_table.py
run "Study layout at three device widths" python3 Tools/preview_study.py

printf '\n\033[1m==> US English spelling\033[0m\n'
before=$(git status --porcelain)
python3 Tools/normalize_spelling.py \
  PeriodicPro/Data/elements.json \
  $(find PeriodicPro PeriodicProTests PeriodicProUITests -name '*.swift') \
  $(find . -maxdepth 2 -name '*.md' -not -path './.git/*') >/dev/null
after=$(git status --porcelain)
if [ "$before" != "$after" ]; then
  echo "Sources contained British spellings and have been normalized. Review and commit."
  fail=1
else
  echo "OK — spelling already normalized"
fi

printf '\n'
if [ "$fail" -eq 0 ]; then
  printf '\033[32mAll local checks passed.\033[0m\n'
else
  printf '\033[31mSome checks failed.\033[0m\n'
fi
exit "$fail"
