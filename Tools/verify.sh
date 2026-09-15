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
run "Swift source hygiene"   python3 Tools/lint_sources.py
run "Xcode project structure" python3 Tools/validate_project.py
run "Table layout at three device widths" python3 Tools/preview_table.py

printf '\n\033[1m==> US English spelling\033[0m\n'
before=$(git status --porcelain)
python3 Tools/normalize_spelling.py \
  PeriodicPro/Data/elements.json \
  $(find PeriodicPro PeriodicProTests PeriodicProUITests -name '*.swift') >/dev/null
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
