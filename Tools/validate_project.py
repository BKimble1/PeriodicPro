#!/usr/bin/env python3
"""Structural checks on the hand-maintained Xcode project file.

Does not replace opening the project in Xcode, but catches the mistakes that
are easy to make and hard to spot: a dangling object reference, an object
nothing points at, a target missing a build phase, a build configuration with
no name.

    python3 Tools/validate_project.py
"""
from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PBXPROJ = os.path.join(ROOT, "PeriodicPro.xcodeproj", "project.pbxproj")
SCHEME = os.path.join(ROOT, "PeriodicPro.xcodeproj", "xcshareddata", "xcschemes",
                      "PeriodicPro.xcscheme")

OBJECT_ID = re.compile(r"\b([0-9A-F]{24})\b")
# Matches both the multi-line form (`ID /* x */ = {`) and the single-line
# form Xcode uses for file references (`ID /* x */ = {isa = ...; };`).
DEFINITION = re.compile(r"^\t\t([0-9A-F]{24})\b[^=]*= \{", re.MULTILINE)
ISA = re.compile(r"isa = (\w+);")

REQUIRED_TARGET_KEYS = [
    "buildConfigurationList", "buildPhases", "buildRules", "dependencies",
    "name", "productName", "productReference", "productType",
]


def main() -> int:
    errors: list[str] = []

    with open(PBXPROJ, encoding="utf-8") as handle:
        source = handle.read()

    # --- balanced containers -------------------------------------------------
    for opener, closer, label in (("{", "}", "braces"), ("(", ")", "parentheses")):
        if source.count(opener) != source.count(closer):
            errors.append(f"unbalanced {label}")

    # --- header --------------------------------------------------------------
    if not source.startswith("// !$*UTF8*$!"):
        errors.append("missing the UTF-8 marker Xcode writes as the first line")
    object_version = re.search(r"objectVersion = (\d+);", source)
    if not object_version:
        errors.append("no objectVersion")
    elif int(object_version.group(1)) < 77:
        errors.append(
            f"objectVersion {object_version.group(1)} predates file-system "
            "synchronized groups, which this project relies on"
        )

    # --- every referenced id is defined, and vice versa ----------------------
    defined = set(DEFINITION.findall(source))
    referenced = set(OBJECT_ID.findall(source)) - defined
    # The rootObject line references a definition, so subtract definitions first
    # and then check what is left really is defined somewhere.
    for identifier in sorted(referenced):
        errors.append(f"reference to undefined object {identifier}")

    body = source
    for identifier in sorted(defined):
        # One definition plus at least one reference (the root object is
        # referenced by the rootObject line).
        if len(re.findall(rf"\b{identifier}\b", body)) < 2:
            errors.append(f"object {identifier} is defined but never referenced")

    # --- section coverage ----------------------------------------------------
    counts: dict[str, int] = {}
    for match in ISA.finditer(source):
        counts[match.group(1)] = counts.get(match.group(1), 0) + 1

    expected = {
        "PBXProject": 1,
        "PBXNativeTarget": 3,
        "PBXFileSystemSynchronizedRootGroup": 3,
        "PBXSourcesBuildPhase": 3,
        "PBXFrameworksBuildPhase": 3,
        "PBXResourcesBuildPhase": 3,
        "PBXTargetDependency": 2,
        "PBXContainerItemProxy": 2,
        "XCConfigurationList": 4,
        "XCBuildConfiguration": 8,
    }
    for isa, count in expected.items():
        if counts.get(isa, 0) != count:
            errors.append(f"expected {count} {isa} objects, found {counts.get(isa, 0)}")

    # --- targets are complete ------------------------------------------------
    for block in re.findall(r"isa = PBXNativeTarget;(.*?)\n\t\t\};", source, re.S):
        name = re.search(r"name = (\w+);", block)
        label = name.group(1) if name else "?"
        for key in REQUIRED_TARGET_KEYS:
            if f"{key} = " not in block:
                errors.append(f"target {label} is missing {key}")
        if "fileSystemSynchronizedGroups" not in block:
            errors.append(f"target {label} has no synchronized source group")

    # --- build configurations ------------------------------------------------
    for block in re.findall(r"isa = XCBuildConfiguration;(.*?)\n\t\t\};", source, re.S):
        if not re.search(r"name = (Debug|Release);", block):
            errors.append("a build configuration has no Debug/Release name")

    # --- the xcconfigs the project points at exist ---------------------------
    for name in ("Shared.xcconfig", "Debug.xcconfig", "Release.xcconfig", "Info.plist"):
        if not os.path.exists(os.path.join(ROOT, "Config", name)):
            errors.append(f"Config/{name} is referenced by the project but missing")

    # --- synchronized folders exist ------------------------------------------
    for folder in ("PeriodicPro", "PeriodicProTests", "PeriodicProUITests"):
        if not os.path.isdir(os.path.join(ROOT, folder)):
            errors.append(f"synchronized group {folder}/ does not exist on disk")

    # --- shared scheme -------------------------------------------------------
    if not os.path.exists(SCHEME):
        errors.append("no shared scheme; `xcodebuild -scheme PeriodicPro` would fail")
    else:
        with open(SCHEME, encoding="utf-8") as handle:
            scheme = handle.read()
        for identifier in re.findall(r'BlueprintIdentifier = "([^"]+)"', scheme):
            if identifier not in defined:
                errors.append(f"scheme points at unknown target {identifier}")
        for required in ("BuildAction", "TestAction", "LaunchAction", "ArchiveAction"):
            if f"<{required}" not in scheme:
                errors.append(f"scheme has no {required}")
        for bundle in ("PeriodicProTests.xctest", "PeriodicProUITests.xctest"):
            if bundle not in scheme:
                errors.append(f"scheme does not run {bundle}")

    for error in errors:
        print(f"error: {error}")
    if errors:
        print(f"\n{len(errors)} problem(s) in the Xcode project")
        return 1
    print(f"OK — project structure is consistent "
          f"({len(defined)} objects, {counts.get('PBXNativeTarget', 0)} targets)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
