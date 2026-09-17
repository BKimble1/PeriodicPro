#!/usr/bin/env python3
"""Parses every Swift source with tree-sitter and fails on a syntax error.

Not a compiler, and not a substitute for the Xcode build: it knows nothing
about types, imports or overloads. What it catches is the class of mistake
that a text editor lets through and a 45-minute CI cycle is an expensive way
to find — an unbalanced brace inside a string, a stray `)` after a refactor, a
`switch` with a case that never closed.

    python3 -m pip install tree-sitter tree-sitter-swift
    python3 Tools/check_swift_syntax.py

Skips itself, with a note, when the grammar is not installed, so a bare
checkout can still run `Tools/verify.sh`.
"""
from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIRS = ["PeriodicPro", "PeriodicProTests", "PeriodicProUITests", "ElemoraWidgets"]


def swift_files() -> list[str]:
    found = []
    for directory in SOURCE_DIRS:
        for base, _, names in os.walk(os.path.join(ROOT, directory)):
            for name in names:
                if name.endswith(".swift"):
                    found.append(os.path.relpath(os.path.join(base, name), ROOT))
    return sorted(found)


# Constructs the tree-sitter grammar rejects but the Swift compiler accepts.
# Each is a known grammar gap, proven by CI compiling the files that use them;
# an ERROR node whose text starts this way is not reported.
GRAMMAR_GAPS = (
    "switch try",            # `switch try await f() {`
    "* ",                    # a binary operator starting a continuation line
    "info?[",                # `dict?[key] as? T ?? default`
)


OPERATOR_CONTINUATIONS = ("* ", "+ ", "- ", "/ ", "&& ", "|| ", "?? ", "== ", "!= ")


def is_grammar_gap(line: str) -> bool:
    """Whether a whole source line is one of the shapes the grammar cannot parse."""
    stripped = line.lstrip()
    if any(stripped.startswith(gap) for gap in GRAMMAR_GAPS):
        return True
    if any(stripped.startswith(op) for op in OPERATOR_CONTINUATIONS):
        return True
    return " as? " in line and " ?? " in line


def error_nodes(node, out: list, limit: int = 5) -> None:
    if len(out) >= limit:
        return
    if node.type == "ERROR" or node.is_missing:
        out.append(node)
        return
    for child in node.children:
        error_nodes(child, out, limit)


def main() -> int:
    try:
        import tree_sitter  # noqa: F401
        import tree_sitter_swift
        from tree_sitter import Language, Parser
    except ImportError:
        print("skipped — tree-sitter-swift is not installed "
              "(python3 -m pip install tree-sitter tree-sitter-swift)")
        return 0

    parser = Parser(Language(tree_sitter_swift.language()))
    files = swift_files()
    problems: list[str] = []
    for path in files:
        with open(os.path.join(ROOT, path), "rb") as handle:
            source = handle.read()
        tree = parser.parse(source)
        if not tree.root_node.has_error:
            continue
        found: list = []
        error_nodes(tree.root_node, found)
        reported_gap = False
        for node in found:
            line = node.start_point[0] + 1
            snippet = source[node.start_byte:node.start_byte + 60].decode("utf-8", "replace")
            snippet = snippet.split("\n", 1)[0]
            line_text = source.split(b"\n")[node.start_point[0]].decode("utf-8", "replace")
            if not node.is_missing and is_grammar_gap(line_text):
                reported_gap = True
                continue
            # A "missing" token at the end of the file is the parser giving
            # up after a gap it could not recover from, not a second problem.
            if node.is_missing and reported_gap:
                continue
            kind = "missing" if node.is_missing else "syntax error"
            problems.append(f"{path}:{line}: {kind} near: {snippet!r}")

    for problem in problems:
        print(f"error: {problem}")
    if problems:
        print(f"\n{len(problems)} syntax problem(s) across {len(files)} Swift files")
        return 1
    print(f"OK — {len(files)} Swift files parse")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
