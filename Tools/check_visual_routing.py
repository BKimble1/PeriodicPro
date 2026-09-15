#!/usr/bin/env python3
"""Checks that every element resolves to artwork and to a 3D structure.

Both systems route an element to a treatment by rule, with a short list of
named exceptions. The failure they share is a silent gap: an element that falls
through to nothing, or a named exception that points at a symbol whose data has
since changed, so the exception is dead and the element quietly gets the wrong
picture.

Neither can be caught by reading the Swift alone, and the Swift unit tests that
assert the same properties cannot run without a Mac. This mirrors the routing
rules against the real dataset instead.

    python3 Tools/check_visual_routing.py
"""
from __future__ import annotations

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ELEMENTS = os.path.join(ROOT, "PeriodicPro", "Data", "elements.json")
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

# Mirrors StructureSceneBuilder: how many atoms each generator produces.
GENERATOR_ATOM_COUNTS = {
    "diatomic": 2,
    "tetrahedron": 4,
    "crownRing": 8,
    "helicalChain": 7,
    "icosahedron": 12,
    "diamondNetwork": 8,
    "puckeredLayer": 6,
    "closePackedCluster": 13,
}
# Named routing inside StructureSceneBuilder.elementalFormScene.
NAMED_STRUCTURE_ROUTES = {
    "P": ("polyatomicMolecule", "tetrahedron"),
    "Se": ("polyatomicMolecule", "helicalChain"),
    "B": ("covalentNetwork", "icosahedron"),
    "As": ("covalentNetwork", "puckeredLayer"),
    "Sb": ("covalentNetwork", "puckeredLayer"),
    "Te": ("covalentNetwork", "helicalChain"),
}
DEFAULT_STRUCTURE_ROUTES = {
    "diatomic": "diatomic",
    "polyatomicMolecule": "crownRing",
    "covalentNetwork": "diamondNetwork",
    "metallicLattice": "closePackedCluster",
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


def structure_generator(element: dict) -> str:
    structure = element["structure"]
    if structure in ("monatomicGas", "atom"):
        return "atomModel"
    route = NAMED_STRUCTURE_ROUTES.get(element["symbol"])
    if route and route[0] == structure:
        return route[1]
    return DEFAULT_STRUCTURE_ROUTES.get(structure, "")


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

    # --- every element resolves to a structure generator --------------------
    for element in elements:
        generator = structure_generator(element)
        if not generator:
            errors.append(
                f"{element['symbol']} ({element['structure']}) resolves to no structure generator"
            )
            continue
        if generator == "atomModel":
            if not element.get("shellElectrons"):
                errors.append(f"{element['symbol']} has no shellElectrons for its atom model")
            continue
        count = GENERATOR_ATOM_COUNTS.get(generator, 0)
        if count < 1:
            errors.append(f"{element['symbol']} routes to {generator}, which draws no atoms")

    # --- named exceptions must still match the data -------------------------
    by_symbol = {element["symbol"]: element for element in elements}
    for symbol, (structure, generator) in sorted(NAMED_STRUCTURE_ROUTES.items()):
        element = by_symbol.get(symbol)
        if element is None:
            errors.append(f"structure route names {symbol}, which is not in the dataset")
        elif element["structure"] != structure:
            errors.append(
                f"structure route for {symbol} expects {structure} but the dataset says "
                f"{element['structure']}, so the {generator} case is dead"
            )

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

    print(
        f"OK — all {len(elements)} elements resolve to artwork and to a structure "
        f"({len(named)} named artwork treatments, {len(NAMED_STRUCTURE_ROUTES)} named structures)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
