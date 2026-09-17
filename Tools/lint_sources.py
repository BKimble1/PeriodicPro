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
SOURCE_DIRS = ["PeriodicPro", "PeriodicProTests", "PeriodicProUITests", "ElemoraWidgets"]

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
    # `Font.system(_:design:weight:)` takes the design first. Written the other
    # way round the compiler tries `system(size:weight:design:)` instead and
    # reports "type 'CGFloat' has no member 'body'", which is a forty-minute
    # round trip to a Mac for a transposition.
    (re.compile(r"\.system\(\s*\.\w+\s*,\s*weight:[^)]*design:"),
     "Font.system text style with weight before design"),
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

LOG_CALL = re.compile(r"\.(?:debug|info|notice|warning|error|fault|critical|log)\s*\(")
# A closing quote, a `+`, an opening quote — the shape of two string literals
# joined. Ordinary Swift strings concatenate; an os_log message does not.
JOINED_LITERALS = re.compile(r'"\s*\+\s*"', re.S)

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


MUTATING_FUNC = re.compile(r"\bmutating\s+func\s+(\w+)")
MACRO_CALL = re.compile(r"#(?:expect|require)\s*\(")
# A value receiver (lowercase) calling a method, optionally negated. An
# uppercase receiver is a type, and a static method is never mutating.
BARE_CALL = re.compile(r"^!?\s*([a-z]\w*)\.(\w+)\(")
# `return Issue.record("...")` in a test: `record` returns a value, and a test
# function returns Void, so this is `unexpected non-void return value in void
# function`. It reads like an early exit and is not one.
RETURNS_A_VALUE = re.compile(r"\breturn\s+(Issue\.record|#expect|#require)\b")


def mutating_method_names() -> set[str]:
    """Every method declared `mutating` anywhere in the project."""
    names: set[str] = set()
    for path in swift_files():
        with open(os.path.join(ROOT, path), encoding="utf-8") as handle:
            names.update(MUTATING_FUNC.findall(handle.read()))
    return names


def first_argument(arguments: str) -> str:
    """The text up to the first top-level comma."""
    depth = 0
    in_string = False
    for index, character in enumerate(arguments):
        if character == '"':
            in_string = not in_string
        elif in_string:
            continue
        elif character in "([{":
            depth += 1
        elif character in ")]}":
            depth -= 1
        elif character == "," and depth == 0:
            return arguments[:index]
    return arguments


def check_mutating_in_expectations(path: str, raw: str, mutating: set[str],
                                   errors: list[str]) -> None:
    """A bare mutating call cannot be the whole of an `#expect`.

        #expect(ledger.markMerged(id))          // does not compile
        #expect(stabilizer.observe(x) == nil)   // compiles

    The difference is which path the macro takes. Given a comparison it
    evaluates each side and captures the values. Given a single call it
    rewrites the call itself, so it can name the receiver and the arguments
    when the expectation fails — and the receiver in that rewrite is a `let`,
    so a mutating method is rejected. The error it produces names `$0` and a
    line nobody wrote, which is why this is worth catching here instead.

    Bind the result first and assert on the binding.
    """
    if not mutating:
        return
    for match in MACRO_CALL.finditer(raw):
        arguments = balanced_argument_text(raw, match.end() - 1)
        argument = first_argument(arguments).strip()
        call = BARE_CALL.match(argument)
        if not call or call.group(2) not in mutating:
            continue
        # Only when the call *is* the whole expectation: anything after its
        # closing parenthesis means a comparison, which compiles.
        remainder = balanced_argument_text(argument, call.end() - 1)
        if argument[call.end() - 1 + len(remainder) + 2:].strip():
            continue
        line = raw.count("\n", 0, match.start()) + 1
        errors.append(
            f"{path}:{line}: '{call.group(2)}' is a mutating method and is the "
            "whole of an #expect/#require, where the macro rewrites the call "
            "and makes its receiver immutable; bind the result first and "
            "assert on the binding"
        )


def balanced_argument_text(source: str, open_index: int) -> str:
    """The text between `(` at `open_index` and its matching `)`."""
    depth = 0
    for index in range(open_index, len(source)):
        if source[index] == "(":
            depth += 1
        elif source[index] == ")":
            depth -= 1
            if depth == 0:
                return source[open_index + 1:index]
    return source[open_index + 1:]


def check_log_messages(path: str, raw: str, errors: list[str]) -> None:
    """A log message is one compile-time literal, never two added together.

        Self.logger.error("Could not schedule \\(id): " + "\\(error)")

    reads as ordinary Swift and is not: an `OSLogMessage` has no `+`, so this
    is `binary operator '+' cannot be applied to two 'OSLogMessage' operands`
    — an error that only a Mac reports, forty minutes into a CI run. Wrapping
    a long log line is exactly when somebody reaches for it.
    """
    for match in LOG_CALL.finditer(raw):
        arguments = balanced_argument_text(raw, match.end() - 1)
        if not JOINED_LITERALS.search(arguments):
            continue
        # Only a message that interpolates is an OSLogMessage in practice;
        # two plain literals added together compile fine.
        if "\\(" not in arguments:
            continue
        line = raw.count("\n", 0, match.start()) + 1
        errors.append(
            f"{path}:{line}: a log message is built by adding two string "
            "literals; os_log takes one literal, so interpolate into a single "
            "string (hoist the parts into lets first if the line is long)"
        )


def check(path: str, errors: list[str], mutating: set[str] | None = None) -> None:
    with open(os.path.join(ROOT, path), encoding="utf-8") as handle:
        raw = handle.read()
    lines = raw.split("\n")
    check_mutating_in_expectations(path, raw, mutating or set(), errors)

    if not raw.endswith("\n"):
        errors.append(f"{path}: file does not end with a newline")
    if "\r" in raw:
        errors.append(f"{path}: contains CRLF line endings")
    if "\t" in raw:
        errors.append(f"{path}: contains a tab character")

    check_log_messages(path, raw, errors)

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

        # Anchored on the word, not the line: the shape that actually occurs
        # is `guard let x else { return Issue.record("...") }`, where the
        # `return` is mid-line and reads like an early exit.
        returning = RETURNS_A_VALUE.search(code)
        if returning:
            errors.append(
                f"{path}:{number}: returning the result of "
                f"{returning.group(1)} from a test, which returns Void — call "
                "it, then return on the next line"
            )

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


SYMBOL_LITERAL = re.compile(r'"([a-z0-9][a-z0-9.]*)"')
SYMBOL_PROPERTY = re.compile(r"var (symbolName|glyph): String \{")


def swift_symbol_allowlist() -> set[str]:
    """Reads both allowlists straight out of SFSymbolAllowlist.swift."""
    source = open(
        os.path.join(ROOT, "PeriodicPro", "Utilities", "SFSymbolAllowlist.swift"),
        encoding="utf-8",
    ).read()
    found: set[str] = set()
    for marker in ("static let names: Set<String> = [", "static let uiNames: Set<String> = ["):
        start = source.index(marker)
        end = source.index("]", start)
        found.update(re.findall(r'"([^"]+)"', source[start:end]))
    fallback = re.search(r'static let fallback = "([^"]+)"', source)
    if fallback:
        found.add(fallback.group(1))
    return found


def used_symbol_names() -> dict[str, list[str]]:
    """Every SF Symbol literal the app's own views can draw, with its location.

    Covers `Image(systemName:)` calls (including ternaries and calls wrapped
    onto a second line) and the bodies of `symbolName` / `glyph` properties.
    """
    used: dict[str, list[str]] = {}
    for path in swift_files():
        if not path.startswith("PeriodicPro/"):
            continue
        lines = open(os.path.join(ROOT, path), encoding="utf-8").read().split("\n")
        in_property = 0
        for number, line in enumerate(lines, start=1):
            harvest = False
            if "systemName" in line:
                harvest = True
            elif number >= 2 and "systemName" in lines[number - 2]:
                harvest = True
            if SYMBOL_PROPERTY.search(line):
                in_property = line.count("{") - line.count("}")
                continue
            if in_property > 0:
                in_property += line.count("{") - line.count("}")
                harvest = True
            if not harvest:
                continue
            for match in SYMBOL_LITERAL.finditer(line):
                name = match.group(1)
                if len(name) < 3 or name.endswith("."):
                    continue
                used.setdefault(name, []).append(f"{path}:{number}")
    return used


def check_symbols(errors: list[str]) -> None:
    allowlisted = swift_symbol_allowlist()
    for name, locations in sorted(used_symbol_names().items()):
        if name not in allowlisted:
            errors.append(
                f"{locations[0]}: SF Symbol '{name}' is not in SFSymbolAllowlist, "
                "so nothing proves it renders"
            )


def main() -> int:
    errors: list[str] = []
    files = swift_files()
    mutating = mutating_method_names()
    for path in files:
        check(path, errors, mutating)
    check_symbols(errors)

    for error in errors:
        print(f"error: {error}")

    if errors:
        print(f"\n{len(errors)} issue(s) across {len(files)} Swift files")
        return 1
    print(f"OK — {len(files)} Swift files passed hygiene checks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
