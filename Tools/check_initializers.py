#!/usr/bin/env python3
"""Cross-checks call sites against the types they construct.

Not a type checker. It answers one narrow question that refactoring gets wrong
constantly: does every argument label used when constructing one of this
project's own types actually exist on that type, either as a stored property
(so the memberwise initializer accepts it) or as a parameter of an explicit
initializer?

    python3 Tools/check_initializers.py
"""
from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIRS = ["PeriodicPro", "PeriodicProTests", "PeriodicProUITests"]

TYPE_DECL = re.compile(r"^(?:@\w+(?:\([^)]*\))?\s*)*(?:public |internal |private |fileprivate )?"
                       r"(?:final )?(struct|class|enum) ([A-Z]\w*)")
# `let x: T`, `var x = v`, `var x: T = v`, with or without a property wrapper.
STORED_PROPERTY = re.compile(
    r"^\s+(?:@\w+(?:\([^)]*\))?\s+)*(?:private\(set\)\s+)?(?:public |internal |private |fileprivate )?"
    r"(?:static )?(let|var) (\w+)\s*(?::|=)"
)
INIT_DECL = re.compile(r"^\s+(?:public |internal |private |fileprivate )?init\??\(")
# `enum Name: String, Codable, ...` — the first conformance is the raw type.
RAW_VALUE_ENUM = re.compile(
    r"^(?:@\w+(?:\([^)]*\))?\s*)*(?:public |internal |private |fileprivate )?"
    r"enum \w+\s*:\s*(String|Int|UInt|Int8|Int16|Int32|Int64|Double|Float|Character)\b"
)
PARAM_LABEL = re.compile(r"(?:^|[(,]\s*)(?:_\s+)?([a-z_]\w*)\s*:")


def swift_files() -> list[str]:
    found = []
    for directory in SOURCE_DIRS:
        for base, _, names in os.walk(os.path.join(ROOT, directory)):
            for name in names:
                if name.endswith(".swift"):
                    found.append(os.path.relpath(os.path.join(base, name), ROOT))
    return sorted(found)


def collect_types() -> dict[str, set[str]]:
    """Maps each declared type to every label it can accept when constructed."""
    accepted: dict[str, set[str]] = {}
    for path in swift_files():
        with open(os.path.join(ROOT, path), encoding="utf-8") as handle:
            lines = handle.read().split("\n")

        current: str | None = None
        depth = 0
        in_init = False
        init_buffer = ""

        for line in lines:
            stripped = line.strip()
            match = TYPE_DECL.match(line)
            if match and not line.startswith(" ") and not line.startswith("\t"):
                current = match.group(2)
                accepted.setdefault(current, set())
                # A raw-valued enum gets `init?(rawValue:)` for free. Without
                # this, an enum that also declares a `static let` looked like a
                # struct with one stored property, and every
                # `Appearance(rawValue:)` in the app read as a mismatch.
                if match.group(1) == "enum" and RAW_VALUE_ENUM.match(line):
                    accepted[current].add("rawValue")
                depth = line.count("{") - line.count("}")
                continue
            if current is None:
                continue

            if in_init:
                init_buffer += " " + stripped
                if ")" in stripped:
                    accepted[current].update(PARAM_LABEL.findall(init_buffer))
                    in_init = False
                    init_buffer = ""
            elif INIT_DECL.match(line):
                init_buffer = stripped
                if ")" in stripped.split("init", 1)[1]:
                    accepted[current].update(PARAM_LABEL.findall(init_buffer))
                else:
                    in_init = True
            else:
                prop = STORED_PROPERTY.match(line)
                # Computed properties open a brace on the same line; stored ones
                # do not (a trailing closure initializer is handled by the
                # "= {" check).
                if prop and ("{" not in line or "= {" in line or "{ get" not in line):
                    if "{" not in line.split("=")[0]:
                        accepted[current].add(prop.group(2))

            depth += line.count("{") - line.count("}")
            if depth <= 0 and (line.count("}") > 0):
                current = None
    return accepted


CALL = re.compile(r"\b([A-Z]\w*)\(")


def main() -> int:
    accepted = collect_types()
    # Enums are constructed through cases, not memberwise inits; skip anything
    # with no recorded labels to avoid false positives on those and on types
    # whose only initializer is inherited.
    checkable = {name: labels for name, labels in accepted.items() if labels}

    errors: list[str] = []
    for path in swift_files():
        with open(os.path.join(ROOT, path), encoding="utf-8") as handle:
            source = handle.read()
        lines = source.split("\n")

        for number, line in enumerate(lines, start=1):
            if line.lstrip().startswith("//") or line.lstrip().startswith("///"):
                continue
            for match in CALL.finditer(line):
                name = match.group(1)
                if name not in checkable:
                    continue
                # Gather the call's arguments, following continuation lines.
                chunk = line[match.end():]
                depth = 1
                index = number
                while depth > 0 and index < len(lines) and index - number < 24:
                    depth = 1 + chunk.count("(") - chunk.count(")")
                    if depth <= 0:
                        break
                    chunk += " " + lines[index].strip()
                    index += 1
                # Only top-level labels of this call.
                top: list[str] = []
                level = 0
                token = ""
                for character in chunk:
                    if character in "([{":
                        level += 1
                    elif character in ")]}":
                        if level == 0:
                            break
                        level -= 1
                    if level == 0:
                        token += character
                for label in PARAM_LABEL.findall("(" + token):
                    top.append(label)
                for label in top:
                    if label not in checkable[name]:
                        errors.append(
                            f"{path}:{number}: {name}(...) has no '{label}:' "
                            f"(accepts: {', '.join(sorted(checkable[name]))})"
                        )

    for error in sorted(set(errors)):
        print(f"error: {error}")
    if errors:
        print(f"\n{len(set(errors))} mismatched initializer label(s)")
        return 1
    print(f"OK — every call site matches its type ({len(checkable)} types checked)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
