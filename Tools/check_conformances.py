#!/usr/bin/env python3
"""Catches a protocol conformance that cannot be synthesized.

Swift derives Equatable, Hashable, Codable and Sendable for a type only when
every stored property already has the conformance. When one does not, the
error arrives forty minutes into a CI run and names the outer type rather than
the property that caused it:

    type 'ScanCandidate' does not conform to protocol 'Hashable'

This answers the same question in a second. For every type in this project
that declares one of those four protocols, it checks each stored property's
type: a standard-library type that has the conformance, or one of this
project's own types that also declares it. A property whose type is a project
type without the conformance is the failure, and it is named.

Deliberately conservative — a type it cannot resolve is skipped rather than
reported, so this never blocks a build over something it does not understand.

    python3 Tools/check_conformances.py
"""
from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIRS = ["PeriodicPro", "PeriodicProTests", "PeriodicProUITests", "ElemoraWidgets"]

CHECKED = ["Equatable", "Hashable", "Codable", "Decodable", "Encodable", "Sendable"]
# Hashable implies Equatable; Codable implies both halves.
IMPLIES = {
    "Hashable": {"Equatable", "Hashable"},
    "Equatable": {"Equatable"},
    "Codable": {"Codable", "Decodable", "Encodable"},
    "Decodable": {"Decodable"},
    "Encodable": {"Encodable"},
    "Sendable": {"Sendable"},
    "Identifiable": set(),
    "Comparable": {"Equatable"},
    "CaseIterable": set(),
}

TYPE_DECL = re.compile(
    r"^(?:@\w+(?:\([^)]*\))?\s*)*(?:public |internal |private |fileprivate )?"
    r"(?:final )?(struct|class|enum|actor) ([A-Z]\w*)\s*(?::\s*([^{]+))?\{"
)
STORED_PROPERTY = re.compile(
    r"^(\s+)(?:@\w+(?:\([^)]*\))?\s+)*(?:private\(set\)\s+)?"
    r"(?:public |internal |private |fileprivate )?(let|var)\s+(\w+)\s*:\s*([^=\n{]+?)\s*(?:=|$)"
)
COMPUTED = re.compile(r"^\s+(?:@\w+(?:\([^)]*\))?\s+)*(?:private\(set\)\s+)?"
                      r"(?:public |internal |private |fileprivate )?"
                      r"(?:static )?var\s+\w+\s*:\s*[^=\n]+\{")

# Standard-library and framework types that have all four conformances for
# the purposes of synthesis.
UNIVERSAL = {
    "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
    "Double", "Float", "CGFloat", "Bool", "String", "Character", "Substring",
    "Date", "URL", "UUID", "Data", "TimeInterval", "CGPoint", "CGSize", "CGRect", "CGVector",
    "Duration", "Decimal", "IndexPath", "Locale", "TimeZone", "Calendar", "DateComponents",
    "SIMD2", "SIMD3", "SIMD4", "Float16",
}
# Types that are Equatable/Hashable/Sendable but not Codable.
NOT_CODABLE = {"CGRect", "CGPoint", "CGSize", "Duration", "AnyHashable"}
# Anything matching these is skipped rather than judged.
OPAQUE = re.compile(r"\b(any|some|->|@escaping|\(\)|Task|Binding|Namespace|Environment)\b")


def swift_files() -> list[str]:
    found = []
    for directory in SOURCE_DIRS:
        for base, _, names in os.walk(os.path.join(ROOT, directory)):
            for name in names:
                if name.endswith(".swift"):
                    found.append(os.path.relpath(os.path.join(base, name), ROOT))
    return sorted(found)


def split_conformances(text: str) -> list[str]:
    """Top-level comma-separated names, ignoring generic brackets."""
    found, depth, current = [], 0, ""
    for character in text:
        if character in "<([":
            depth += 1
        elif character in ">)]":
            depth -= 1
        if character == "," and depth == 0:
            found.append(current.strip())
            current = ""
        else:
            current += character
    if current.strip():
        found.append(current.strip())
    return [name.split(".")[-1].split("<")[0].strip() for name in found if name.strip()]


def collect() -> tuple[dict[str, set[str]], dict[str, list[tuple[str, str, int]]]]:
    """Declared conformances per type, and each type's stored properties."""
    conformances: dict[str, set[str]] = {}
    properties: dict[str, list[tuple[str, str, int]]] = {}
    # Enum name -> (has at least one case, every case is payload-free). An
    # enum of payload-free cases is Equatable and Hashable whether it says so
    # or not; a caseless enum is a namespace and is never held by anything.
    enum_shape: dict[str, list[bool]] = {}

    for path in swift_files():
        with open(os.path.join(ROOT, path), encoding="utf-8") as handle:
            lines = handle.readlines()

        # (type name, indent of its declaration)
        stack: list[tuple[str, int]] = []
        for number, line in enumerate(lines, start=1):
            if line.strip().startswith("//"):
                continue
            declaration = TYPE_DECL.match(line)
            if declaration:
                name = declaration.group(2)
                declared = set(split_conformances(declaration.group(3) or ""))
                resolved: set[str] = set()
                for item in declared:
                    resolved |= IMPLIES.get(item, {item})
                conformances.setdefault(name, set()).update(resolved)
                properties.setdefault(name, [])
                if declaration.group(1) == "enum":
                    enum_shape.setdefault(name, [False, True])
                stack.append((name, len(line) - len(line.lstrip())))
                continue

            if stack and stack[-1][0] in enum_shape and re.match(r"^\s+case\s", line):
                shape = enum_shape[stack[-1][0]]
                shape[0] = True
                if "(" in line.split("//")[0]:
                    shape[1] = False
                continue
            # An extension can add a conformance.
            extension = re.match(r"^extension ([A-Z]\w*)\s*:\s*([^{]+)\{", line)
            if extension:
                declared = set(split_conformances(extension.group(2)))
                resolved = set()
                for item in declared:
                    resolved |= IMPLIES.get(item, {item})
                conformances.setdefault(extension.group(1), set()).update(resolved)
                continue

            if not stack:
                continue
            if COMPUTED.match(line):
                continue
            stored = STORED_PROPERTY.match(line)
            if not stored:
                continue
            indent = len(stored.group(1))
            while stack and indent <= stack[-1][1]:
                stack.pop()
            if not stack:
                continue
            # Exactly one level in. Anything deeper is a local variable inside
            # a method, which is not a stored property and does not affect
            # what can be synthesized.
            if indent != stack[-1][1] + 4:
                continue
            if "static " in line or "class " in line.split(":")[0]:
                continue
            properties[stack[-1][0]].append((stored.group(3), stored.group(4).strip(), number))

    # An enum whose cases carry no associated values is Equatable and Hashable
    # without declaring it, so a type holding one can still synthesize.
    for name, (hasCase, payloadFree) in enum_shape.items():
        if hasCase and payloadFree:
            conformances.setdefault(name, set()).update({"Equatable", "Hashable"})
    return conformances, properties


def element_types(declared: str) -> list[str]:
    """The types a declaration ultimately depends on, unwrapped."""
    text = declared.strip()
    if OPAQUE.search(text):
        return []
    text = text.rstrip("?!")
    if text.startswith("[") and text.endswith("]"):
        inner = text[1:-1]
        if ":" in inner:
            key, _, value = inner.partition(":")
            return element_types(key) + element_types(value)
        return element_types(inner)
    generic = re.match(r"^(Set|Array|Optional|Result)<(.+)>$", text)
    if generic:
        return [part for chunk in split_conformances(generic.group(2))
                for part in element_types(chunk)]
    if "<" in text or "(" in text or " " in text:
        return []
    # A nested type is named by its last component: `ElementSearch.Entry` is
    # judged as `Entry`, which is what is declared.
    return [text.split(".")[-1]]


def main() -> int:
    conformances, properties = collect()
    failures: list[str] = []
    checked = 0

    for name, declared in sorted(conformances.items()):
        wanted = [item for item in CHECKED if item in declared]
        if not wanted:
            continue
        checked += 1
        for propertyName, declaredType, number in properties.get(name, []):
            for dependency in element_types(declaredType):
                if dependency in UNIVERSAL:
                    if "Codable" in wanted and dependency in NOT_CODABLE:
                        failures.append(
                            f"{name} declares Codable but its property "
                            f"'{propertyName}' is {dependency}, which is not")
                    continue
                if dependency not in conformances:
                    continue  # Not one of ours, or not resolvable: not judged.
                for protocol in wanted:
                    if protocol in ("Decodable", "Encodable") and "Codable" in conformances[dependency]:
                        continue
                    if protocol not in conformances[dependency]:
                        failures.append(
                            f"{name} declares {protocol}, but its stored property "
                            f"'{propertyName}: {declaredType}' is {dependency}, which does not "
                            f"(line {number}). Swift cannot synthesize {protocol} for {name}.")

    if failures:
        for failure in sorted(set(failures)):
            print(f"error: {failure}", file=sys.stderr)
        print(f"\n{len(set(failures))} conformance(s) cannot be synthesized", file=sys.stderr)
        return 1
    print(f"OK — every synthesized conformance is satisfiable ({checked} types checked)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
