#!/usr/bin/env python3
"""Checks that every element resolves to artwork and to a 3D structure.

The artwork routes an element to a treatment by rule, with a short list of
named exceptions; the 3D structure routes through the profile in
structures.json. The failure they share is a silent gap: an element that falls
through to nothing, a named exception that points at a symbol whose data has
since changed, or a profile whose geometry template the scene builder does not
implement.

Neither can be caught by reading the Swift alone, and the Swift unit tests that
assert the same properties cannot run without a Mac. This mirrors the routing
rules against the real datasets instead.

    python3 Tools/check_visual_routing.py
"""
from __future__ import annotations

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ELEMENTS = os.path.join(ROOT, "PeriodicPro", "Data", "elements.json")
STRUCTURES = os.path.join(ROOT, "PeriodicPro", "Data", "structures.json")
ARTWORK = os.path.join(ROOT, "PeriodicPro", "Artwork", "ElementArtwork.swift")
BUILDER = os.path.join(ROOT, "PeriodicPro", "Structure3D", "StructureSceneBuilder.swift")

# Mirrors ElementArtwork.kind(for:). Ordered exactly as the Swift is.
METAL_LATTICE_BY_CATEGORY = {
    "alkaliMetal": "metallicSheen",
    "alkalineEarthMetal": "metallicSheen",
    "lanthanide": "metallicSheen",
    "actinide": "metallicSheen",
    "postTransitionMetal": "nuggets",
    "transitionMetal": "lattice",
    "metalloid": "facetedGems",
    "reactiveNonmetal": "hexPlates",
    "halogen": "hexPlates",
    "nobleGas": "hexPlates",
}
STRUCTURE_TO_KIND = {
    "monatomicGas": "luminousGas",
    "diatomic": "pairedSpheres",
    "polyatomicMolecule": "crystalShards",
    "covalentNetwork": "facetedGems",
    "atom": "orbitalArcs",
}

# Mirrors StructureSceneBuilder.formScene: every template the builder
# implements, with the atom count it draws. A profile that names anything
# else would fall through to the atom model — silently, which is what this
# check exists to prevent.
GENERATOR_ATOM_COUNTS = {
    "diatomic": 2,
    "monatomicGas": 6,
    "tetrahedron": 4,
    "crownRing": 8,
    "helicalChain": 7,
    "icosahedron": 12,
    "puckeredLayer": 12,
    "graphite": 24,
    "fcc": 14,
    "bcc": 9,
    "simpleCubic": 8,
    "diamondCubic": 18,
    "hcp": 17,
    "dhcp": 27,
    "lattice": None,       # depends on the basis
    "closePackedCluster": 13,
    "liquidMetal": 19,
    "molecularLiquid": 8,
    "atom": None,          # the atom model
}


def named_artwork_symbols() -> set[str]:
    """The symbols listed in ElementArtwork.namedKinds."""
    source = open(ARTWORK, encoding="utf-8").read()
    block = re.search(
        r"private static let namedKinds: \[String: ElementArtworkKind\] = \[(.*?)\n    \]",
        source,
        re.S,
    )
    if not block:
        return set()
    return set(re.findall(r'"([A-Z][a-z]?)"\s*:', block.group(1)))


def named_tint_symbols() -> set[str]:
    source = open(ARTWORK, encoding="utf-8").read()
    block = re.search(
        r"private static let namedTints: \[String: UInt32\] = \[(.*?)\n    \]", source, re.S
    )
    if not block:
        return set()
    return set(re.findall(r'"([A-Z][a-z]?)"\s*:', block.group(1)))


def artwork_kind(element: dict, named: set[str]) -> str:
    if element["symbol"] in named:
        return "named"
    if element["phase"] == "unknown":
        return "orbitalArcs"
    if element["phase"] == "liquid":
        return "droplets"
    structure = element["structure"]
    if structure in STRUCTURE_TO_KIND:
        return STRUCTURE_TO_KIND[structure]
    if structure == "metallicLattice":
        return METAL_LATTICE_BY_CATEGORY.get(element["category"], "")
    return ""


def builder_templates() -> set[str]:
    """The template strings StructureSceneBuilder.formScene switches on."""
    source = open(BUILDER, encoding="utf-8").read()
    body = source[source.index("private static func formScene"):source.index("private static func caption")]
    return set(re.findall(r'case "([a-zA-Z]+)":', body))


def structure_generator(entry: dict) -> str:
    return ((entry.get("primary") or {}).get("geometry") or {}).get("template") or ""


def main() -> int:
    elements = json.load(open(ELEMENTS, encoding="utf-8"))
    errors: list[str] = []
    named = named_artwork_symbols()
    tints = named_tint_symbols()

    # --- every element resolves to artwork ----------------------------------
    for element in elements:
        kind = artwork_kind(element, named)
        if not kind:
            errors.append(
                f"{element['symbol']} ({element['structure']}/{element['category']}) "
                "resolves to no artwork treatment"
            )

    # --- every element's profile resolves to a generator the builder has ----
    structures = {e["atomicNumber"]: e for e in json.load(open(STRUCTURES, encoding="utf-8"))}
    implemented = builder_templates()
    for template in GENERATOR_ATOM_COUNTS:
        if template != "atom" and template not in implemented:
            errors.append(f"this check lists template {template}, but StructureSceneBuilder "
                          "no longer implements it")
    for template in implemented:
        if template not in GENERATOR_ATOM_COUNTS:
            errors.append(f"StructureSceneBuilder implements template {template}, which this "
                          "check does not know; add its atom count")
    for element in elements:
        entry = structures.get(element["atomicNumber"])
        if entry is None:
            errors.append(f"{element['symbol']} has no entry in structures.json")
            continue
        profiles = [entry["primary"]] + list(entry.get("alternatives") or [])
        for profile in profiles:
            template = (profile.get("geometry") or {}).get("template") or ""
            if template == "atom":
                if profile.get("representationKind") != "unknown":
                    errors.append(f"{element['symbol']} draws the atom for a structure it "
                                  "claims to know")
                if not element.get("shellElectrons"):
                    errors.append(f"{element['symbol']} has no shellElectrons for its atom model")
                continue
            if template not in implemented:
                errors.append(
                    f"{element['symbol']} names geometry template {template!r}, which "
                    "StructureSceneBuilder does not implement — it would silently draw the atom"
                )
                continue
            count = GENERATOR_ATOM_COUNTS.get(template)
            if count is None and template != "lattice":
                errors.append(f"{element['symbol']} routes to {template}, whose atom count is unknown")
            if template == "lattice":
                basis = (profile.get("geometry") or {}).get("basis") or []
                if not basis:
                    errors.append(f"{element['symbol']} has an explicit lattice with no basis")

    by_symbol = {element["symbol"]: element for element in elements}
    for symbol in sorted(named | tints):
        if symbol not in by_symbol:
            errors.append(f"artwork names {symbol}, which is not in the dataset")

    # --- diatomic bond orders must be chemically right ----------------------
    expected_orders = {"H": 1, "N": 3, "O": 2, "F": 1, "Cl": 1, "Br": 1, "I": 1}
    diatomics = {e["symbol"] for e in elements if e["structure"] == "diatomic"}
    if diatomics != set(expected_orders):
        errors.append(
            f"the diatomic set changed: dataset has {sorted(diatomics)}, "
            f"bond orders are declared for {sorted(expected_orders)}"
        )

    if errors:
        for error in errors:
            print(f"error: {error}")
        print(f"\n{len(errors)} issue(s) across {len(elements)} elements")
        return 1

    templates_used = {
        (p.get("geometry") or {}).get("template")
        for e in structures.values()
        for p in [e["primary"]] + list(e.get("alternatives") or [])
    }
    print(
        f"OK — all {len(elements)} elements resolve to artwork and to a structure "
        f"({len(named)} named artwork treatments, {len(templates_used)} geometry templates in use)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
