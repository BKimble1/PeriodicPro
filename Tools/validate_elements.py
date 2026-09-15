#!/usr/bin/env python3
"""Structural and scientific validation of PeriodicPro/Data/elements.json.

Mirrors the Swift unit tests in PeriodicProTests/ElementDataTests.swift so a
bad dataset fails CI in seconds, on any machine, without a Mac.

    python3 Tools/validate_elements.py [path/to/elements.json]

Exits non-zero and prints every problem it finds.
"""
from __future__ import annotations

import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from backbone import backbone, CATEGORY_MEMBERS  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_PATH = os.path.join(ROOT, "PeriodicPro", "Data", "elements.json")
ALLOWLIST_PATH = os.path.join(
    ROOT, "PeriodicPro", "Utilities", "SFSymbolAllowlist.swift"
)

REQUIRED_FIELDS = [
    "atomicNumber", "symbol", "name", "category", "group", "period", "block",
    "gridX", "gridY", "atomicMass", "atomicMassIsMassNumber",
    "electronConfiguration", "shellElectrons", "phase", "meltingPointK",
    "boilingPointK", "densityGramsPerCm3", "electronegativity", "discoveryYear",
    "discoveredBy", "tagline", "about", "memoryHook", "structure",
    "elementalForm", "uses",
]

PHASES = {"solid", "liquid", "gas", "unknown"}
STRUCTURES = {
    "atom", "diatomic", "polyatomicMolecule", "metallicLattice",
    "covalentNetwork", "monatomicGas",
}
SUBSHELL_CAPACITY = {"s": 2, "p": 6, "d": 10, "f": 14}
NOBLE_GASES = {"He": 2, "Ne": 10, "Ar": 18, "Kr": 36, "Xe": 54, "Rn": 86}

LIQUIDS = {"Br", "Hg"}
GASES = {"H", "He", "N", "O", "F", "Ne", "Cl", "Ar", "Kr", "Xe", "Rn"}
DIATOMIC = {"H", "N", "O", "F", "Cl", "Br", "I"}
NO_STABLE_ISOTOPE = set(range(84, 119)) | {43, 61}
RADIOGENIC_BUT_WEIGHTED = {90, 91, 92}
MASS_INVERSIONS = {18, 27, 52}

ANOMALOUS_CONFIGURATIONS = {
    "Cr": "[Ar] 3d5 4s1",
    "Cu": "[Ar] 3d10 4s1",
    "Nb": "[Kr] 4d4 5s1",
    "Mo": "[Kr] 4d5 5s1",
    "Ru": "[Kr] 4d7 5s1",
    "Rh": "[Kr] 4d8 5s1",
    "Pd": "[Kr] 4d10",
    "Ag": "[Kr] 4d10 5s1",
    "La": "[Xe] 5d1 6s2",
    "Ce": "[Xe] 4f1 5d1 6s2",
    "Gd": "[Xe] 4f7 5d1 6s2",
    "Pt": "[Xe] 4f14 5d9 6s1",
    "Au": "[Xe] 4f14 5d10 6s1",
    "Ac": "[Rn] 6d1 7s2",
    "Th": "[Rn] 6d2 7s2",
    "Pa": "[Rn] 5f2 6d1 7s2",
    "U": "[Rn] 5f3 6d1 7s2",
    "Np": "[Rn] 5f4 6d1 7s2",
    "Cm": "[Rn] 5f7 6d1 7s2",
    "Lr": "[Rn] 5f14 7s2 7p1",
}

BANNED_PHRASES = ["orbits the nucleus", "orbit the nucleus", "did you know", "!"]


class Report:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []
        self.notes: list[str] = []

    def note(self, message: str) -> None:
        self.notes.append(message)

    def error(self, message: str) -> None:
        self.errors.append(message)

    def warn(self, message: str) -> None:
        self.warnings.append(message)


def load_allowlist() -> set[str]:
    """Reads the SF Symbol allowlist straight out of the Swift source so the
    two can never drift apart."""
    with open(ALLOWLIST_PATH, encoding="utf-8") as handle:
        source = handle.read()
    start = source.index("static let names: Set<String> = [")
    end = source.index("]", start)
    body = source[start:end]
    return set(re.findall(r'"([^"]+)"', body))


def check_configuration(element: dict, report: Report) -> None:
    symbol = element["symbol"]
    configuration = element["electronConfiguration"]
    if not configuration:
        report.error(f"{symbol}: empty electron configuration")
        return

    total = 0
    core = re.match(r"\[([A-Z][a-z]?)\]", configuration)
    rest = configuration
    if core:
        noble = core.group(1)
        if noble not in NOBLE_GASES:
            report.error(f"{symbol}: configuration core [{noble}] is not a noble gas")
            return
        if NOBLE_GASES[noble] >= element["atomicNumber"]:
            report.error(f"{symbol}: core [{noble}] is not lighter than the element")
        total += NOBLE_GASES[noble]
        rest = configuration[core.end():]

    for token in rest.split():
        match = re.fullmatch(r"(\d)([spdf])(\d{1,2})", token)
        if not match:
            report.error(f"{symbol}: malformed configuration token '{token}'")
            return
        shell, subshell, count = int(match.group(1)), match.group(2), int(match.group(3))
        if not 1 <= count <= SUBSHELL_CAPACITY[subshell]:
            report.error(f"{symbol}: token '{token}' exceeds {subshell} capacity")
        if shell < 1 or shell > 7:
            report.error(f"{symbol}: token '{token}' has an impossible shell number")
        total += count

    if total != element["atomicNumber"]:
        report.error(
            f"{symbol}: configuration '{configuration}' accounts for {total} electrons, "
            f"expected {element['atomicNumber']}"
        )


SWIFT_PROPERTY = re.compile(r"^\s+let (\w+): ([\w\[\]?]+)$")


def swift_model_shape() -> dict[str, str]:
    """Reads the stored properties of `ChemicalElement` out of the Swift source.

    JSONDecoder tolerates extra keys but fails the whole launch on a missing
    non-optional key or a type mismatch, so the shape is worth checking here
    rather than discovering it on a device.
    """
    source = open(
        os.path.join(ROOT, "PeriodicPro", "Models", "ChemicalElement.swift"),
        encoding="utf-8",
    ).read()
    start = source.index("struct ChemicalElement")
    end = source.index("\n}", start)
    shape: dict[str, str] = {}
    for line in source[start:end].split("\n"):
        match = SWIFT_PROPERTY.match(line)
        if match:
            shape[match.group(1)] = match.group(2)
    return shape


def json_matches_swift(value, base: str) -> bool:
    """Python's bool is a subclass of int, so each Swift type is checked
    explicitly rather than with a lookup table."""
    if base == "Bool":
        return isinstance(value, bool)
    if base == "Int":
        return isinstance(value, int) and not isinstance(value, bool)
    if base == "Double":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if base in ("String", "ElementCategory", "MatterPhase", "ElementStructure"):
        return isinstance(value, str)
    if base in ("[Int]", "[ElementUse]"):
        return isinstance(value, list)
    return True


def check_model_shape(elements: list, report: Report) -> None:
    shape = swift_model_shape()
    if not shape:
        report.error("could not read ChemicalElement's properties from the Swift source")
        return
    report.note(f"checked against {len(shape)} properties declared on ChemicalElement")

    for element in elements:
        label = element.get("symbol", element.get("atomicNumber", "?"))
        for name, swift_type in shape.items():
            optional = swift_type.endswith("?")
            base = swift_type.rstrip("?")
            if name not in element:
                report.error(f"{label}: JSON is missing '{name}', which decoding requires")
                continue
            value = element[name]
            if value is None:
                if not optional:
                    report.error(f"{label}: '{name}' is null but Swift declares it non-optional")
                continue
            if not json_matches_swift(value, base):
                report.error(
                    f"{label}: '{name}' is {type(value).__name__}, Swift expects {base}"
                )
                continue
            if base == "[Int]" and not all(
                isinstance(item, int) and not isinstance(item, bool) for item in value
            ):
                report.error(f"{label}: '{name}' contains a non-integer")
            if base == "[ElementUse]":
                for item in value:
                    if not isinstance(item, dict):
                        report.error(f"{label}: '{name}' contains a non-object")
                        continue
                    for key in ("title", "detail", "symbolName"):
                        if not isinstance(item.get(key), str):
                            report.error(f"{label}: a use has a non-string '{key}'")

        for name in element:
            if name not in shape:
                report.warn(f"{label}: JSON key '{name}' is not read by the Swift model")


def validate(path: str) -> Report:
    report = Report()

    with open(path, encoding="utf-8") as handle:
        elements = json.load(handle)

    if not isinstance(elements, list):
        report.error("elements.json must contain a JSON array")
        return report

    if len(elements) != 118:
        report.error(f"expected 118 elements, found {len(elements)}")

    # Shape first: if a field has the wrong Swift type the value checks below
    # cannot run meaningfully, and the app would fail to decode at launch.
    check_model_shape(elements, report)
    if report.errors:
        report.error("stopping: fix the decoding problems above before the value checks can run")
        return report

    expected = {row["atomicNumber"]: row for row in backbone()}
    allowlist = load_allowlist()

    numbers, symbols, names, positions = [], [], [], []

    for element in elements:
        for field in REQUIRED_FIELDS:
            if field not in element:
                report.error(f"Z={element.get('atomicNumber', '?')}: missing '{field}'")
        if any(field not in element for field in REQUIRED_FIELDS):
            continue

        z = element["atomicNumber"]
        symbol = element["symbol"]
        numbers.append(z)
        symbols.append(symbol)
        names.append(element["name"])
        positions.append((element["gridX"], element["gridY"]))

        # --- backbone agreement -------------------------------------------
        reference = expected.get(z)
        if reference is None:
            report.error(f"Z={z}: not a confirmed element")
            continue
        for field in ("symbol", "name", "category", "group", "period", "block",
                      "gridX", "gridY"):
            if element[field] != reference[field]:
                report.error(
                    f"{symbol}: {field} is {element[field]!r}, expected {reference[field]!r}"
                )

        # --- shells --------------------------------------------------------
        shells = element["shellElectrons"]
        if sum(shells) != z:
            report.error(f"{symbol}: shells {shells} sum to {sum(shells)}, expected {z}")
        if any(count <= 0 for count in shells):
            report.error(f"{symbol}: shells {shells} contain an empty level")
        for index, count in enumerate(shells):
            capacity = 2 * (index + 1) ** 2
            if count > capacity:
                report.error(
                    f"{symbol}: shell {index + 1} holds {count}, capacity {capacity}"
                )
        expected_shells = 4 if symbol == "Pd" else reference["period"]
        if len(shells) != expected_shells:
            report.error(
                f"{symbol}: occupies {len(shells)} shells, expected {expected_shells}"
            )

        # --- configuration --------------------------------------------------
        check_configuration(element, report)
        if symbol in ANOMALOUS_CONFIGURATIONS:
            if element["electronConfiguration"] != ANOMALOUS_CONFIGURATIONS[symbol]:
                report.error(
                    f"{symbol}: configuration is '{element['electronConfiguration']}', "
                    f"expected '{ANOMALOUS_CONFIGURATIONS[symbol]}'"
                )

        # --- phase ----------------------------------------------------------
        phase = element["phase"]
        if phase not in PHASES:
            report.error(f"{symbol}: unknown phase '{phase}'")
        if symbol in LIQUIDS and phase != "liquid":
            report.error(f"{symbol}: should be liquid at room temperature")
        if symbol in GASES and phase != "gas":
            report.error(f"{symbol}: should be a gas at room temperature")
        if phase == "liquid" and symbol not in LIQUIDS:
            report.error(f"{symbol}: only Br and Hg are liquid at room temperature")
        if phase == "gas" and symbol not in GASES:
            report.error(f"{symbol}: is not a gas at room temperature")

        # --- numeric ranges ---------------------------------------------------
        mass = element["atomicMass"]
        if mass < z or mass > z * 3.1:
            report.error(f"{symbol}: atomic mass {mass} is implausible for Z={z}")
        if element["atomicMassIsMassNumber"] and mass != round(mass):
            report.error(f"{symbol}: mass number {mass} should be a whole number")
        must_use_mass_number = z in NO_STABLE_ISOTOPE and z not in RADIOGENIC_BUT_WEIGHTED
        if must_use_mass_number and not element["atomicMassIsMassNumber"]:
            report.error(f"{symbol}: has no stable isotope, so should use a mass number")
        if (not element["atomicMassIsMassNumber"]
                and z >= 84 and z not in RADIOGENIC_BUT_WEIGHTED):
            report.error(f"{symbol}: should not claim a standard atomic weight")

        melting, boiling = element["meltingPointK"], element["boilingPointK"]
        for label, value, ceiling in (("melting", melting, 4500), ("boiling", boiling, 6500)):
            if value is None:
                continue
            if not 0 < value < ceiling:
                report.error(f"{symbol}: {label} point {value} K is out of range")
        if melting is not None and boiling is not None and melting > boiling:
            report.error(f"{symbol}: melts at {melting} K but boils at {boiling} K")

        density = element["densityGramsPerCm3"]
        if density is not None:
            if not 0 < density < 41:
                report.error(f"{symbol}: density {density} g/cm3 is out of range")
            elif phase == "gas" and density > 0.02:
                report.error(
                    f"{symbol}: gas density {density} looks like g/L, not g/cm3"
                )
            elif phase in ("solid", "liquid") and density < 0.05:
                report.error(f"{symbol}: condensed-matter density {density} is too low")

        electronegativity = element["electronegativity"]
        if electronegativity is not None and not 0.7 <= electronegativity <= 3.98:
            report.error(
                f"{symbol}: electronegativity {electronegativity} is off the Pauling scale"
            )

        year = element["discoveryYear"]
        if year is not None and not 1250 <= year <= 2025:
            report.error(f"{symbol}: discovery year {year} is implausible")

        # --- structure --------------------------------------------------------
        structure = element["structure"]
        if structure not in STRUCTURES:
            report.error(f"{symbol}: unknown structure '{structure}'")
        if symbol in DIATOMIC and structure != "diatomic":
            report.error(f"{symbol}: should be diatomic, not '{structure}'")
        if symbol in NOBLE_GASES and phase == "gas" and structure != "monatomicGas":
            report.error(f"{symbol}: should be a monatomic gas, not '{structure}'")
        if (reference["category"] in ("alkaliMetal", "alkalineEarthMetal",
                                      "transitionMetal", "postTransitionMetal",
                                      "lanthanide", "actinide")
                and z <= 103 and structure != "metallicLattice"):
            report.error(f"{symbol}: metals should form a metallic lattice, got '{structure}'")

        # --- editorial --------------------------------------------------------
        if not 0 < len(element["tagline"]) <= 72:
            report.error(f"{symbol}: tagline is {len(element['tagline'])} characters")
        if not 120 <= len(element["about"]) <= 460:
            report.error(f"{symbol}: about text is {len(element['about'])} characters")
        if not 0 < len(element["memoryHook"]) <= 190:
            report.error(f"{symbol}: memory hook is {len(element['memoryHook'])} characters")
        if not 0 < len(element["elementalForm"]) <= 52:
            report.error(
                f"{symbol}: elemental form is {len(element['elementalForm'])} characters"
            )

        prose = " ".join([element["about"], element["memoryHook"], element["tagline"]]).lower()
        for phrase in BANNED_PHRASES:
            if phrase in prose:
                report.error(f"{symbol}: copy contains '{phrase}'")

        uses = element["uses"]
        if not 3 <= len(uses) <= 5:
            report.error(f"{symbol}: has {len(uses)} uses, expected 3-5")
        seen_titles = set()
        for use in uses:
            for key in ("title", "detail", "symbolName"):
                if key not in use:
                    report.error(f"{symbol}: a use is missing '{key}'")
            if any(key not in use for key in ("title", "detail", "symbolName")):
                continue
            if not 0 < len(use["title"]) <= 20:
                report.error(f"{symbol}: use title '{use['title']}' is too long")
            if not 0 < len(use["detail"]) <= 30:
                report.error(f"{symbol}: use detail '{use['detail']}' is too long")
            if use["symbolName"] not in allowlist:
                report.error(
                    f"{symbol}: use '{use['title']}' has unlisted SF Symbol "
                    f"'{use['symbolName']}'"
                )
            if use["title"] in seen_titles:
                report.error(f"{symbol}: repeats the use '{use['title']}'")
            seen_titles.add(use["title"])

    # --- global uniqueness ---------------------------------------------------
    for label, values in (("atomic number", numbers), ("symbol", symbols),
                          ("name", names), ("grid position", positions)):
        if len(set(values)) != len(values):
            duplicates = {v for v in values if values.count(v) > 1}
            report.error(f"duplicate {label}s: {sorted(map(str, duplicates))}")
    if sorted(numbers) != list(range(1, 119)):
        report.error("atomic numbers are not exactly 1 through 118")

    # --- family sizes --------------------------------------------------------
    by_category: dict[str, int] = {}
    for element in elements:
        by_category[element.get("category", "?")] = by_category.get(element.get("category", "?"), 0) + 1
    for category, members in CATEGORY_MEMBERS.items():
        if by_category.get(category, 0) != len(members):
            report.error(
                f"family {category} has {by_category.get(category, 0)} members, "
                f"expected {len(members)}"
            )

    # --- mass ordering below bismuth ----------------------------------------
    ordered = sorted((e for e in elements if e.get("atomicNumber", 999) <= 83),
                     key=lambda e: e["atomicNumber"])
    for lighter, heavier in zip(ordered, ordered[1:]):
        if lighter["atomicNumber"] in MASS_INVERSIONS:
            if lighter["atomicMass"] <= heavier["atomicMass"]:
                report.error(
                    f"{lighter['symbol']} should outweigh {heavier['symbol']}"
                )
            continue
        if lighter["atomicMass"] >= heavier["atomicMass"]:
            report.error(
                f"{lighter['symbol']} ({lighter['atomicMass']}) should be lighter than "
                f"{heavier['symbol']} ({heavier['atomicMass']})"
            )

    # --- taglines should not all read the same ------------------------------
    taglines = [e.get("tagline", "") for e in elements]
    if len(set(taglines)) < len(taglines):
        duplicates = {t for t in taglines if taglines.count(t) > 1}
        report.warn(f"repeated taglines: {sorted(duplicates)[:5]}")

    return report


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_PATH
    if not os.path.exists(path):
        print(f"error: {path} does not exist", file=sys.stderr)
        return 2

    report = validate(path)

    for note in report.notes:
        print(f"note: {note}")
    for warning in report.warnings:
        print(f"warning: {warning}")
    for error in report.errors:
        print(f"error: {error}")

    if report.errors:
        print(f"\n{len(report.errors)} problem(s) found in {os.path.relpath(path, ROOT)}")
        return 1

    print(f"OK — {os.path.relpath(path, ROOT)} passed every check "
          f"({len(report.warnings)} warning(s))")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
