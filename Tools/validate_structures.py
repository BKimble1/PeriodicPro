#!/usr/bin/env python3
"""Validates PeriodicPro/Data/structures.json against the element dataset.

Mirrors PeriodicProTests/StructureProfileTests.swift so a wrong or missing
structure profile fails CI in seconds, on any machine, without a Mac.

    python3 Tools/validate_structures.py

The rules it enforces are the scientific promises the 3D feature makes:

* every one of the 118 elements has exactly one entry, and no entry names an
  element that does not exist;
* an element is either experimentally established with a source, or is
  explicitly `unknown` with a note saying so — never a guessed lattice;
* the profile's phase agrees with elements.json;
* the examples that must differ correctly do: gold, copper and silver are
  face-centered cubic; iron is body-centered cubic; magnesium is hexagonal
  close-packed; silicon is diamond cubic; carbon is graphite with diamond as
  an allotrope; nitrogen has a triple bond and oxygen a double; the noble
  gases are monatomic, never diatomic; mercury and bromine are liquids; the
  synthetic superheavies are unknown;
* lattice parameters, where given, are physically plausible.
"""
from __future__ import annotations

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STRUCTURES = os.path.join(ROOT, "PeriodicPro", "Data", "structures.json")
ELEMENTS = os.path.join(ROOT, "PeriodicPro", "Data", "elements.json")

KINDS = {
    "monatomicGas", "diatomicMolecule", "polyatomicMolecule", "molecularCrystal",
    "molecularLiquid", "liquidMetal", "fcc", "bcc", "hcp", "dhcp", "simpleCubic",
    "diamondCubic", "graphite", "rhombohedral", "orthorhombic", "tetragonal",
    "helicalChain", "complexCrystal", "unknown",
}
CRYSTAL_KINDS = {
    "fcc", "bcc", "hcp", "dhcp", "simpleCubic", "diamondCubic", "graphite",
    "rhombohedral", "orthorhombic", "tetragonal", "helicalChain", "complexCrystal",
}
TEMPLATES = {
    "diatomic", "monatomicGas", "tetrahedron", "crownRing", "helicalChain", "icosahedron",
    "puckeredLayer", "graphite", "fcc", "bcc", "simpleCubic", "diamondCubic", "hcp", "dhcp",
    "lattice", "closePackedCluster", "liquidMetal", "molecularLiquid", "atom",
}
KIND_TEMPLATES = {
    "fcc": {"fcc"}, "bcc": {"bcc"}, "hcp": {"hcp"}, "dhcp": {"dhcp"},
    "simpleCubic": {"simpleCubic"}, "diamondCubic": {"diamondCubic"}, "graphite": {"graphite"},
    "diatomicMolecule": {"diatomic"}, "monatomicGas": {"monatomicGas"},
    "molecularLiquid": {"molecularLiquid"}, "liquidMetal": {"liquidMetal"},
    "unknown": {"atom"}, "helicalChain": {"helicalChain"},
}

EXPECTED_KINDS = {
    "Au": "fcc", "Cu": "fcc", "Ag": "fcc", "Al": "fcc", "Pt": "fcc", "Pb": "fcc", "Ni": "fcc",
    "Fe": "bcc", "Na": "bcc", "K": "bcc", "Cr": "bcc", "W": "bcc",
    "Mg": "hcp", "Ti": "hcp", "Zn": "hcp", "Co": "hcp",
    "Si": "diamondCubic", "Ge": "diamondCubic",
    "C": "graphite", "Po": "simpleCubic", "Mn": "complexCrystal",
    "As": "rhombohedral", "Sb": "rhombohedral", "Bi": "rhombohedral",
    "Se": "helicalChain", "Te": "helicalChain",
    "Ga": "orthorhombic", "U": "orthorhombic", "In": "tetragonal", "Sn": "tetragonal",
    "P": "molecularCrystal", "S": "molecularCrystal", "I": "molecularCrystal",
    "Hg": "liquidMetal", "Br": "molecularLiquid",
    "H": "diatomicMolecule", "N": "diatomicMolecule", "O": "diatomicMolecule",
    "F": "diatomicMolecule", "Cl": "diatomicMolecule",
    "He": "monatomicGas", "Ne": "monatomicGas", "Ar": "monatomicGas",
    "Kr": "monatomicGas", "Xe": "monatomicGas", "Rn": "monatomicGas",
    "At": "unknown", "Fr": "unknown", "Og": "unknown",
}
EXPECTED_BOND_ORDERS = {"H": 1, "N": 3, "O": 2, "F": 1, "Cl": 1, "Br": 1, "I": 1}
EXPECTED_ALLOTROPES = {
    "C": ["Diamond"],
    "P": ["Black phosphorus"],
    "Fe": ["γ-iron (austenite)"],
    "Sn": ["Gray (α) tin"],
}


def check_profile(label: str, profile: dict, element: dict, errors: list[str]) -> None:
    kind = profile.get("representationKind")
    if kind not in KINDS:
        errors.append(f"{label}: unknown representationKind {kind!r}")
        return
    template = (profile.get("geometry") or {}).get("template")
    if template not in TEMPLATES:
        errors.append(f"{label}: unknown geometry template {template!r}")
    elif kind in KIND_TEMPLATES and template not in KIND_TEMPLATES[kind]:
        errors.append(f"{label}: kind {kind} cannot be drawn with template {template}")

    established = profile.get("isExperimentallyEstablished")
    if kind == "unknown":
        if established is not False:
            errors.append(f"{label}: an unknown structure must not claim to be established")
        if "not established" not in (profile.get("notes") or "").lower():
            errors.append(f"{label}: an unknown structure must say so in its notes")
        if profile.get("phase") != "unknown":
            errors.append(f"{label}: an unknown structure has no phase to claim")
    else:
        if established is not True:
            errors.append(f"{label}: a drawn structure must be experimentally established, "
                          "or be marked unknown")
        if not (profile.get("source") or "").strip():
            errors.append(f"{label}: every established structure needs a source")
        if not profile.get("temperatureContext"):
            errors.append(f"{label}: missing temperatureContext")

    if kind in CRYSTAL_KINDS or kind == "molecularCrystal":
        parameters = profile.get("latticeParameters") or {}
        a = parameters.get("a")
        if a is None:
            errors.append(f"{label}: a crystal needs at least a lattice parameter a")
        else:
            for key in ("a", "b", "c"):
                value = parameters.get(key)
                if value is not None and not 1.5 <= value <= 30:
                    errors.append(f"{label}: lattice parameter {key} = {value} Å is implausible")
            for key in ("alpha", "beta", "gamma"):
                value = parameters.get(key)
                if value is not None and not 30 <= value <= 150:
                    errors.append(f"{label}: cell angle {key} = {value}° is implausible")
        if not profile.get("latticeType"):
            errors.append(f"{label}: a crystal needs a latticeType")

    if template == "lattice":
        basis = (profile.get("geometry") or {}).get("basis")
        if not basis or any(len(row) != 3 for row in basis):
            errors.append(f"{label}: an explicit lattice needs a 3-column basis")
        else:
            for row in basis:
                if any(not 0 <= value <= 1 for value in row):
                    errors.append(f"{label}: basis coordinates must be fractional, in [0, 1]")
    if template == "hcp" or template == "dhcp":
        ratio = (profile.get("geometry") or {}).get("cOverA")
        if ratio is None or not 1.4 <= ratio <= 3.6:
            errors.append(f"{label}: c/a = {ratio} is not a close-packed ratio")

    if kind in ("diatomicMolecule", "molecularLiquid"):
        orders = profile.get("bondOrders") or []
        if len(orders) != 1 or orders[0] not in (1, 2, 3):
            errors.append(f"{label}: a diatomic needs exactly one bond order of 1, 2 or 3")
        length = profile.get("bondLengthAngstrom")
        if length is None or not 0.5 <= length <= 3.2:
            errors.append(f"{label}: bond length {length} Å is implausible")

    if kind == "monatomicGas" and profile.get("bondOrders"):
        errors.append(f"{label}: a monatomic gas must not declare bonds")

    # The profile's phase describes the same conditions as elements.json.
    if kind != "unknown" and profile.get("temperatureContext") == "298 K, 1 atm":
        if profile.get("phase") != element["phase"]:
            errors.append(f"{label}: phase {profile.get('phase')} disagrees with elements.json "
                          f"({element['phase']})")


def main() -> int:
    errors: list[str] = []
    elements = {e["atomicNumber"]: e for e in json.load(open(ELEMENTS, encoding="utf-8"))}
    entries = json.load(open(STRUCTURES, encoding="utf-8"))

    numbers = [entry.get("atomicNumber") for entry in entries]
    if sorted(numbers) != list(range(1, 119)):
        missing = sorted(set(range(1, 119)) - set(numbers))
        extra = sorted(set(numbers) - set(range(1, 119)))
        errors.append(f"structures.json must cover exactly 1–118; missing {missing}, extra {extra}")

    by_symbol: dict[str, dict] = {}
    for entry in entries:
        number = entry.get("atomicNumber")
        element = elements.get(number)
        if element is None:
            continue
        symbol = element["symbol"]
        by_symbol[symbol] = entry
        primary = entry.get("primary")
        if not isinstance(primary, dict):
            errors.append(f"{symbol}: no primary profile")
            continue
        check_profile(f"{symbol} primary", primary, element, errors)
        for index, alternative in enumerate(entry.get("alternatives") or []):
            check_profile(f"{symbol} alternative {index}", alternative, element, errors)
            if alternative.get("representationKind") == "unknown":
                errors.append(f"{symbol}: an alternative cannot be unknown")
            if not alternative.get("allotropeName"):
                errors.append(f"{symbol}: every alternative allotrope needs a name")
        if primary.get("representationKind") == "unknown" and entry.get("alternatives"):
            errors.append(f"{symbol}: an unknown element cannot offer allotropes")

    for symbol, kind in EXPECTED_KINDS.items():
        entry = by_symbol.get(symbol)
        found = entry and entry["primary"].get("representationKind")
        if found != kind:
            errors.append(f"{symbol} should be {kind}, found {found}")

    for symbol, order in EXPECTED_BOND_ORDERS.items():
        entry = by_symbol.get(symbol)
        found = entry and (entry["primary"].get("bondOrders") or [None])[0]
        if found != order:
            errors.append(f"{symbol} should have bond order {order}, found {found}")

    for symbol, names in EXPECTED_ALLOTROPES.items():
        entry = by_symbol.get(symbol)
        found = [a.get("allotropeName") for a in (entry or {}).get("alternatives", [])]
        if found != names:
            errors.append(f"{symbol} should offer allotropes {names}, found {found}")

    # Nobody has seen bulk fermium or anything heavier.
    for number in range(100, 119):
        entry = next((e for e in entries if e.get("atomicNumber") == number), None)
        if entry and entry["primary"].get("representationKind") != "unknown":
            errors.append(f"element {number} has never been made in bulk and must be unknown")

    # Metals below fermium that the dataset calls metallic lattices must be
    # drawn as a real metal structure, except the two never seen in bulk.
    for number, element in elements.items():
        entry = next((e for e in entries if e.get("atomicNumber") == number), None)
        if entry is None or element["structure"] != "metallicLattice" or number >= 100:
            continue
        kind = entry["primary"]["representationKind"]
        if element["symbol"] in ("Fr",):
            continue
        if kind not in CRYSTAL_KINDS | {"liquidMetal"}:
            errors.append(f"{element['symbol']} is a metal but its profile is {kind}")

    if errors:
        for error in errors:
            print(f"error: {error}")
        print(f"\n{len(errors)} problem(s) in structures.json")
        return 1

    kinds = {}
    for entry in entries:
        kind = entry["primary"]["representationKind"]
        kinds[kind] = kinds.get(kind, 0) + 1
    unknown = kinds.get("unknown", 0)
    print(f"OK — 118 structure profiles: {118 - unknown} established, {unknown} explicitly unknown, "
          f"{sum(len(e.get('alternatives') or []) for e in entries)} allotrope alternatives, "
          f"{len(kinds)} representation kinds")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
