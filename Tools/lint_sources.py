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
    # `Font.system(_:design:weight:)` takes the design first. Written the other
    # way round the compiler tries `system(size:weight:design:)` instead and
    # reports "type 'CGFloat' has no member 'body'", which is a forty-minute
    # round trip to a Mac for a transposition.
    (re.compile(r"\.system\(\s*\.\w+\s*,\s*weight:[^)]*design:"),
     "Font.system text style with weight before design"),
    # Every `Date` this project encodes is also read back and compared, so it
    # has to survive the round trip exactly. Only the default strategy does:
    # ISO 8601 carries whole seconds (milliseconds at best), and
    # `.secondsSince1970` adds an epoch offset and subtracts it again, which
    # changes the value about half the time. Measured, not assumed.
    (re.compile(r"date(?:En|De)codingStrategy\s*=\s*\.(?:iso8601|secondsSince1970|millisecondsSince1970)"),
     "a lossy JSON date strategy; the default round-trips exactly"),
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


# A call whose function argument is a key path: `xs.allSatisfy(\.isContact)`.
KEY_PATH_CALL = re.compile(r"^!?\s*[a-z]\w*(?:\.\w+(?:\([^()]*\))?)*\.(\w+)\(\s*\\\.")


def check_key_path_expectations(path: str, raw: str, errors: list[str]) -> None:
    """A key path cannot be the function argument of a bare `#expect` call.

        #expect(bonds.allSatisfy(\.isContact))     // does not compile
        #expect(bonds.allSatisfy { $0.isContact }) // compiles
        #expect(xs.map(\.id) == ys.map(\.id))      // compiles

    When the whole expectation is a single call, the macro rewrites it so it
    can name the receiver in a failure message. A closure literal keeps its
    non-throwing type through that rewrite; a key path has to be converted to
    a function inside it, and the conversion lands on the throwing overload of
    whatever `rethrows` method it was passed to — so the call wants a `try`
    nobody wrote, reported against a synthesized line.

    Inside a comparison there is no rewrite and no problem, which is why every
    `map(\.id) == …` in the suite is fine.
    """
    for match in MACRO_CALL.finditer(raw):
        arguments = balanced_argument_text(raw, match.end() - 1)
        argument = first_argument(arguments).strip()
        call = KEY_PATH_CALL.match(argument)
        if not call:
            continue
        # Only when the call is the whole expectation: anything trailing its
        # closing parenthesis is a comparison, which takes the value path.
        opening = argument.index("(", call.start(1))
        inner = balanced_argument_text(argument, opening)
        if argument[opening + len(inner) + 2:].strip():
            continue
        line = raw.count("\n", 0, match.start()) + 1
        errors.append(
            f"{path}:{line}: '{call.group(1)}' is given a key path and is the "
            "whole of an #expect/#require, where the macro's rewrite converts "
            "it to a throwing function; write it as a closure"
        )


def check_accessibility_order(path: str, raw: str, errors: list[str]) -> None:
    """An element has to exist before it can be identified.

        .accessibilityIdentifier("launch.screen")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Elemora")

    `accessibilityElement(children: .ignore)` *creates* an element. Anything
    applied above it describes the view underneath instead, so the identifier
    and the label end up on two different elements: VoiceOver reads an
    unnamed control, and a test that finds the element by identifier reads an
    empty label. Nothing fails to build and nothing looks wrong on screen.

    Put `accessibilityElement` first, then identify and describe it.
    """
    lines = raw.split("\n")
    for index, line in enumerate(lines):
        if ".accessibilityElement(children: .ignore)" not in line:
            continue
        back = index - 1
        while back >= 0 and lines[back].strip().startswith("."):
            if ".accessibilityIdentifier(" in lines[back]:
                errors.append(
                    f"{path}:{back + 1}: accessibilityIdentifier is applied above "
                    f"accessibilityElement(children: .ignore) on line {index + 1}, so it "
                    "lands on a different element than the label; create the element first"
                )
                break
            back -= 1


# `.alert("Title", isPresented: $flag) { ... }` and the fields inside it.
ALERT_MODIFIER = re.compile(r"\.alert\s*\(")
ALERT_FIELD = re.compile(r"\b(?:TextField|SecureField)\s*\(")


def matching_delimiter(source: str, open_index: int, opener: str, closer: str) -> int:
    """The index of the delimiter closing the one at `open_index`."""
    depth = 0
    for index in range(open_index, len(source)):
        if source[index] == opener:
            depth += 1
        elif source[index] == closer:
            depth -= 1
            if depth == 0:
                return index
    return len(source) - 1


def check_alert_field_identifiers(path: str, raw: str, errors: list[str]) -> None:
    """An alert's text field cannot carry an accessibility identifier.

        .alert("How many atoms?", isPresented: $editing) {
            TextField("Count", text: $typed)
                .accessibilityIdentifier("build.countField")
            Button("Set") { commit() }
                .accessibilityIdentifier("build.countConfirm")
        }

    SwiftUI hands an alert's contents to a UIAlertController, which builds its
    own text field. The buttons' identifiers survive that — `build.countConfirm`
    arrives — and a field's does not, so the modifier compiles, reads as if it
    works, and the identifier never reaches the accessibility tree. A UI test
    then waits ten seconds for a control that is on screen and typed into.

    An alert holds one or two fields at most, so a test names one by being the
    alert's: `app.alerts.textFields.firstMatch`.

    Only the trailing-closure spelling is checked, which is the one that
    occurs; a closure passed as `actions:` is left alone rather than guessed at.
    """
    blank = "\n".join(strip_literals(line) for line in raw.split("\n"))
    blank_lines = blank.split("\n")
    for match in ALERT_MODIFIER.finditer(blank):
        open_paren = match.end() - 1
        close_paren = matching_delimiter(blank, open_paren, "(", ")")
        brace = blank.find("{", close_paren)
        if brace == -1 or blank[close_paren + 1:brace].strip():
            continue
        end = matching_delimiter(blank, brace, "{", "}")
        alert_line = blank.count("\n", 0, match.start()) + 1
        first_line = blank.count("\n", 0, brace) + 1
        last_line = blank.count("\n", 0, end) + 1
        for number in range(first_line, last_line + 1):
            if not ALERT_FIELD.search(blank_lines[number - 1]):
                continue
            ahead = number
            while ahead < last_line and blank_lines[ahead].strip().startswith("."):
                if ".accessibilityIdentifier(" in blank_lines[ahead]:
                    errors.append(
                        f"{path}:{ahead + 1}: an accessibility identifier on a text "
                        f"field inside the alert on line {alert_line} is dropped by the "
                        "UIAlertController underneath; find the field with "
                        "app.alerts.textFields instead"
                    )
                    break
                ahead += 1


def check_expectation_comments(path: str, raw: str, errors: list[str]) -> None:
    """An expectation's message is a literal, not a String expression.

        #expect(a == b,
                "the diagram draws \\(x) "
                    + "and the scene models \\(y)")

    `#expect`'s second parameter is a `Comment`, which a string *literal*
    becomes implicitly and a `String` does not — so joining two literals with
    `+` produces `cannot convert value of type 'String' to expected argument
    type 'Comment?'`. Worse, the failed conversion takes the rest of the call
    down with it: the first argument is reported as needing a `try` it does
    not need, which sends you looking in entirely the wrong place.

    The same mistake as concatenating an os_log message, for the same reason,
    and it happens for the same innocent motive: the line was too long.
    Interpolate into one literal, or use a multi-line string.
    """
    for match in MACRO_CALL.finditer(raw):
        arguments = balanced_argument_text(raw, match.end() - 1)
        first = first_argument(arguments)
        # Only the comment argument. `#expect("a" + "b" == "ab")` is a
        # perfectly good expectation about string concatenation.
        comment = arguments[len(first):]
        if not JOINED_LITERALS.search(comment):
            continue
        line = raw.count("\n", 0, match.start()) + 1
        errors.append(
            f"{path}:{line}: the message given to #expect/#require is two "
            "string literals joined with '+', but the parameter is a Comment, "
            "which only a literal becomes — interpolate into one literal or "
            "use a multi-line string"
        )


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
    check_expectation_comments(path, raw, errors)
    check_accessibility_order(path, raw, errors)
    check_alert_field_identifiers(path, raw, errors)
    check_key_path_expectations(path, raw, errors)

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
