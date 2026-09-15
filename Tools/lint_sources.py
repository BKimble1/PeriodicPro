#!/usr/bin/env python3
"""Cheap, Mac-free hygiene checks over the Swift sources.

Not a compiler — a guard against the things that quietly rot a codebase and
against the specific quality-gate items this project promised: no placeholder
copy, no unexplained TODOs, no stray debug printing, balanced delimiters.

    python3 Tools/lint_sources.py
"""
from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIRS = ["PeriodicPro", "PeriodicProTests", "PeriodicProUITests"]

MAX_LINE = 118
BANNED = [
    (re.compile(r"\bTODO\b"), "unexplained TODO"),
    (re.compile(r"\bFIXME\b"), "unexplained FIXME"),
    (re.compile(r"\bXXX\b"), "placeholder marker"),
    (re.compile(r"[Ll]orem [Ii]psum"), "placeholder copy"),
    (re.compile(r"^\s*print\("), "leftover debug print"),
    (re.compile(r"\bdump\("), "leftover debug dump"),
    (re.compile(r"\bfatalError\("), "fatalError on a shipping path"),
    (re.compile(r"\w\)?!\s*$"), "trailing force-unwrap"),
    (re.compile(r"\bas!\s"), "force cast"),
    (re.compile(r"\btry!\s"), "force try"),
]

# Files where a given check is legitimately allowed, with the reason.
ALLOWANCES = {
    "leftover debug print": {"Tools/"},
    "fatalError on a shipping path": {
        # Only reachable if the schema itself is invalid, which is a programmer
        # error, and only in test support / an unrecoverable container failure.
        "PeriodicPro/Persistence/PersistenceController.swift",
        "PeriodicProTests/TestSupport.swift",
    },
}

STRING_OR_COMMENT = re.compile(r'("(?:[^"\\]|\\.)*")|(//.*$)')

# `var app: XCUIApplication!` is an implicitly-unwrapped optional declaration,
# which is the idiomatic XCUITest fixture pattern, not a force-unwrap.
IUO_DECLARATION = re.compile(
    r"^\s*(?:private |public |internal |fileprivate )?(?:var|let)\s+\w+\s*:"
    r"\s*[\w<>\[\].,\s]+!\s*$"
)


def swift_files() -> list[str]:
    found = []
    for directory in SOURCE_DIRS:
        for base, _, names in os.walk(os.path.join(ROOT, directory)):
            for name in names:
                if name.endswith(".swift"):
                    found.append(os.path.relpath(os.path.join(base, name), ROOT))
    return sorted(found)


def strip_literals(line: str) -> str:
    """Blanks out string literals and line comments so delimiter counting and
    banned-token matching do not trip over prose."""
    return STRING_OR_COMMENT.sub(lambda m: " " * len(m.group(0)), line)


def check(path: str, errors: list[str]) -> None:
    with open(os.path.join(ROOT, path), encoding="utf-8") as handle:
        raw = handle.read()
    lines = raw.split("\n")

    if not raw.endswith("\n"):
        errors.append(f"{path}: file does not end with a newline")
    if "\r" in raw:
        errors.append(f"{path}: contains CRLF line endings")
    if "\t" in raw:
        errors.append(f"{path}: contains a tab character")

    depth_braces = depth_parens = depth_brackets = 0
    in_block_comment = False

    for number, line in enumerate(lines, start=1):
        if line.rstrip() != line:
            errors.append(f"{path}:{number}: trailing whitespace")
        if len(line) > MAX_LINE:
            errors.append(f"{path}:{number}: line is {len(line)} characters (max {MAX_LINE})")

        code = strip_literals(line)

        # Very small block-comment tracker; the sources use /* */ rarely.
        if in_block_comment:
            if "*/" in code:
                code = code.split("*/", 1)[1]
                in_block_comment = False
            else:
                continue
        while "/*" in code:
            before, _, after = code.partition("/*")
            if "*/" in after:
                code = before + after.split("*/", 1)[1]
            else:
                code = before
                in_block_comment = True
                break

        depth_braces += code.count("{") - code.count("}")
        depth_parens += code.count("(") - code.count(")")
        depth_brackets += code.count("[") - code.count("]")

        for pattern, label in BANNED:
            if not pattern.search(code):
                continue
            if label == "trailing force-unwrap" and IUO_DECLARATION.match(line):
                continue
            allowed = ALLOWANCES.get(label, set())
            if any(path.startswith(prefix) for prefix in allowed):
                continue
            errors.append(f"{path}:{number}: {label} -> {line.strip()[:80]}")

    for depth, name in ((depth_braces, "braces"), (depth_parens, "parentheses"),
                        (depth_brackets, "brackets")):
        if depth != 0:
            errors.append(f"{path}: unbalanced {name} (net {depth:+d})")

    # Every type and extension in the app target should carry documentation.
    if path.startswith("PeriodicPro/"):
        for number, line in enumerate(lines, start=1):
            match = re.match(r"^(?:public |internal |private |fileprivate )?"
                             r"(?:final )?(struct|enum|class|protocol) ([A-Z]\w+)", line)
            if not match:
                continue
            # Walk back past attributes (@main, @Model, @Observable, ...) and
            # blank lines to find the documentation comment.
            cursor = number - 2
            while cursor >= 0:
                previous = lines[cursor].strip()
                if previous.startswith("@") or previous == "":
                    cursor -= 1
                    continue
                break
            previous = lines[cursor].strip() if cursor >= 0 else ""
            if not previous.startswith("//"):
                errors.append(
                    f"{path}:{number}: {match.group(1)} {match.group(2)} has no doc comment"
                )


def main() -> int:
    errors: list[str] = []
    files = swift_files()
    for path in files:
        check(path, errors)

    for error in errors:
        print(f"error: {error}")

    if errors:
        print(f"\n{len(errors)} issue(s) across {len(files)} Swift files")
        return 1
    print(f"OK — {len(files)} Swift files passed hygiene checks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
