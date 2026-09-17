#!/usr/bin/env python3
"""Finds identifiers the project uses but declares nowhere.

    error: cannot find 'prefixes' in scope

is a one-word mistake that costs a full macOS CI cycle to hear about, because
nothing short of a compiler notices it. This is not a compiler and does not
try to be: it does no scope analysis at all. It asks a much weaker question
that is still enough to catch that class of bug —

    is this lowercase identifier declared ANYWHERE in the project, as a
    property, a parameter, a binding, a function, a case or a label?

Anything declared anywhere passes, so the check can never be confused by
scope, shadowing, extensions, protocol witnesses or generics. What it catches
is a name that exists in no declaration at all: a reference to something that
was renamed, deleted, or — as here — described in a comment and never written.

Names from outside the project (Foundation, SwiftUI, the standard library)
cannot be found by definition, so they live in an allowlist below.

    python3 -m pip install tree-sitter tree-sitter-swift
    python3 Tools/check_undeclared.py

Skips itself, with a note, when the grammar is not installed.
"""
from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIRS = ["PeriodicPro", "PeriodicProTests", "PeriodicProUITests", "ElemoraWidgets"]

# Node types whose DIRECT identifier children are declarations rather than
# uses. Deliberately direct only: a `let x = prefixes.first` is one
# `property_declaration` containing both a binding and a use, and treating the
# whole subtree as declaring would quietly declare `prefixes` — which is the
# exact bug this file exists to catch.
DECLARING = {
    "pattern",                      # every `let`/`var`/`case let` binding
    "parameter",
    "lambda_parameter",
    "function_declaration",
    "init_declaration",
    "enum_entry",
    "typealias_declaration",
    "associatedtype_declaration",
    "type_parameter",
    "external_parameter_name",
    "macro_declaration",
    "protocol_function_declaration",
    "subscript_declaration",
}

# Positions that are never a value reference to a project symbol.
#
# Anything after a dot is skipped, which covers both halves of the problem:
# the `bar` in `foo.bar`, whose meaning depends on the type of `foo`, and the
# `atomic` in `.atomic`, which is an implicit member of a type the compiler
# infers. Neither is resolvable without types, and neither is the bug this
# looks for.
SKIP_PARENT = {
    "value_argument_label",    # the `label:` in `f(label: x)`
    "type_identifier",
    "user_type",
}

# Names that come from outside this project and so are declared nowhere in it.
# Every entry is a standard-library, Foundation, SwiftUI, Observation,
# SwiftData, StoreKit, WidgetKit, AppIntents, XCTest or swift-testing symbol.
FOREIGN = {
    # Keywords and expression forms the grammar reports as identifiers
    "self", "Self", "super", "nil", "true", "false", "type", "some", "any",
    "defer", "case", "let", "var", "func", "return", "if", "else", "for",
    "get", "set", "willSet", "didSet", "newValue", "oldValue", "in", "where",
    "async", "await", "throws", "rethrows", "init", "deinit", "subscript",
    "each", "borrowing", "consuming", "sending", "package", "unsafe",
    # Protocol members this project's own types inherit and use without
    # `self.`: CaseIterable.allCases, RawRepresentable.rawValue.
    "allCases", "rawValue", "hashValue", "description", "debugDescription",
    "rawRepresentable", "pi", "infinity", "nan", "zero", "one",
    # simd / CoreGraphics / UIKit C-level entry points
    "simd_quatf", "simd_float3", "getRed", "getWhite",
    # Standard library free functions and globals
    "print", "min", "max", "abs", "zip", "stride", "swap", "assert",
    "precondition", "fatalError", "assertionFailure", "preconditionFailure",
    "dump", "repeatElement", "sequence", "withUnsafeBytes", "autoreleasepool",
    "withTaskGroup", "withThrowingTaskGroup", "withCheckedContinuation",
    "withCheckedThrowingContinuation", "withAnimation", "withObservationTracking",
    "numericCast", "unsafeBitCast", "isKnownUniquelyReferenced", "readLine",
    "abs", "pow", "sqrt", "round", "floor", "ceil", "log", "exp", "sin", "cos",
    "tan", "atan2", "hypot", "fmod", "trunc", "cbrt", "log2", "log10",
    "Double", "Float", "CGFloat", "Int", "UInt", "UInt64", "Int64", "String",
    # SwiftUI / WidgetKit / AppIntents environment-style globals
    "body", "content", "label", "value", "id", "placeholder",
    # swift-testing / XCTest
    "expect", "require", "continueAfterFailure",
    # Members this project's own extensions inherit and call without `self.`
    # — `View.modifier`, `View.shadow`, `View.matchedTransitionSource`,
    # `Path.applying`. Resolving these needs the conformance, which needs
    # types, which is exactly what this check does not have.
    "modifier", "shadow", "matchedTransitionSource", "applying",
    # The simd module's free functions.
    "simd_normalize", "simd_length", "simd_cross", "simd_dot",
}


def swift_files() -> list[str]:
    found = []
    for directory in SOURCE_DIRS:
        for base, _, names in os.walk(os.path.join(ROOT, directory)):
            for name in names:
                if name.endswith(".swift"):
                    found.append(os.path.relpath(os.path.join(base, name), ROOT))
    return sorted(found)


def text(node, source: bytes) -> str:
    return source[node.start_byte:node.end_byte].decode("utf-8", "replace")


def collect(node, source: bytes, declared: set[str], used: list[tuple]) -> None:
    """One pass: every declared name into `declared`, every use into `used`."""
    stack = [(node, False)]
    while stack:
        current, ignored = stack.pop()
        # Two subtrees say nothing about scope. An ERROR node is a shape the
        # grammar could not parse — `switch try await` is one this project
        # really uses — and every identifier under it is guesswork. An import
        # names a module, not a value.
        ignored = ignored or current.type in ("ERROR", "import_declaration")
        for child in current.children:
            if child.type == "simple_identifier":
                name = text(child, source)
                previous = child.prev_sibling
                if current.type in DECLARING:
                    declared.add(name)
                elif previous is not None and previous.type in (
                    "let", "var", "value_binding_pattern"
                ):
                    # `if let boiling`, `guard let bare`, `case .success(let
                    # verification)` — bindings the grammar hangs directly off
                    # the statement rather than off a `pattern`.
                    declared.add(name)
                elif ignored or current.type in SKIP_PARENT:
                    pass
                elif child.next_sibling is not None and child.next_sibling.type == ":":
                    # A label, not a use: a tuple element (`area: CGFloat`), a
                    # property-wrapper argument (`relativeTo: .title`), a
                    # dictionary key. Skipping the occasional real use on the
                    # left of a ternary is a cost this check can afford; a
                    # false alarm is not.
                    pass
                elif previous is not None and previous.type == ".":
                    pass
                else:
                    used.append((name, child.start_point[0] + 1))
                continue
            stack.append((child, ignored))


def main() -> int:
    try:
        import tree_sitter_swift
        from tree_sitter import Language, Parser
    except ImportError:
        print("skipped — pip install tree-sitter tree-sitter-swift to enable")
        return 0

    parser = Parser(Language(tree_sitter_swift.language()))
    files = swift_files()

    declared: set[str] = set()
    uses: dict[str, list[tuple[str, int]]] = {}

    for path in files:
        with open(os.path.join(ROOT, path), "rb") as handle:
            source = handle.read()
        tree = parser.parse(source)
        found: list[tuple] = []
        collect(tree.root_node, source, declared, found)
        for name, line in found:
            uses.setdefault(name, []).append((path, line))

    errors = []
    for name in sorted(uses):
        if name in declared or name in FOREIGN:
            continue
        # Type-like and enum-case-like names are reached through other syntax
        # and are checked by the compiler in ways this cannot improve on.
        if not name[:1].islower():
            continue
        if name.startswith("_") or name.startswith("$"):
            continue
        for path, line in uses[name][:3]:
            errors.append(f"{path}:{line}: '{name}' is used but declared nowhere in the project")

    for error in errors:
        print(f"error: {error}")
    if errors:
        print(f"\n{len(errors)} undeclared identifier(s)")
        return 1
    print(f"OK — every identifier used in {len(files)} files is declared somewhere")
    return 0


if __name__ == "__main__":
    sys.exit(main())
