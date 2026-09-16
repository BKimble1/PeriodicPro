#!/usr/bin/env python3
"""Validates PeriodicPro/Data/compounds.json.

Mirrors PeriodicProTests/CompoundTests.swift so a bad compound record fails
CI in seconds, without a Mac.

    python3 Tools/validate_compounds.py

Every bundled compound must be: uniquely identified by a positive PubChem CID;
neutral; consistent — the Hill formula, the structure's atoms and the molar
mass all agree, and the molar mass equals the sum of the IUPAC weights in
elements.json; conservatively classified — an acid tag only on a compound
that carries hydrogen, organic only on a carbon compound, salt only on an
ionic one; and honestly described — a structure says what it is, a network
solid draws nothing, and no summary contains hype.
"""
from __future__ import annotations

import json
import math
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COMPOUNDS = os.path.join(ROOT, "PeriodicPro", "Data", "compounds.json")
ELEMENTS = os.path.join(ROOT, "PeriodicPro", "Data", "elements.json")

BONDING = {"molecular", "ionic", "networkSolid", "coordination", "unknown"}
TAGS = {"acid", "base", "salt", "organic", "inorganic"}
STRUCTURE_SOURCES = {"computedConformer", "curatedLattice", "pubChem3D", "pubChem2D"}
EXPECTED_MINIMUM = 30
EXPECTED_MAXIMUM = 60

# The formula collisions the app's honesty depends on.
EXPECTED_SHARED = {"C2H6O": {"Ethanol", "Dimethyl ether"}}
EXPECTED_PRESENT = [
    "Water", "Carbon dioxide", "Sodium chloride", "Ammonia", "Methane", "Hydrogen chloride",
    "Sulfuric acid", "Nitric acid", "Sodium hydroxide", "Calcium carbonate", "Sodium bicarbonate",
    "Glucose", "Sucrose", "Ethanol", "Methanol", "Acetone", "Acetic acid", "Hydrogen peroxide",
    "Caffeine", "Aspirin", "Dimethyl ether",
]


def parse_formula(formula: str) -> dict[str, int]:
    counts: dict[str, int] = {}
    for symbol, number in re.findall(r"([A-Z][a-z]?)(\d*)", formula):
        counts[symbol] = counts.get(symbol, 0) + (int(number) if number else 1)
    return counts


def hill(counts: dict[str, int]) -> str:
    symbols = sorted(counts)
    if "C" in counts:
        ordered = ["C"] + (["H"] if "H" in counts else []) + [s for s in symbols if s not in ("C", "H")]
    else:
        ordered = symbols
    return "".join(f"{s}{counts[s] if counts[s] > 1 else ''}" for s in ordered)


def main() -> int:
    errors: list[str] = []
    elements = json.load(open(ELEMENTS, encoding="utf-8"))
    weights = {e["symbol"]: e["atomicMass"] for e in elements}
    symbols = {e["atomicNumber"]: e["symbol"] for e in elements}
    metals = {e["symbol"] for e in elements
              if e["category"] in ("alkaliMetal", "alkalineEarthMetal", "transitionMetal",
                                   "postTransitionMetal", "lanthanide", "actinide")}
    records = json.load(open(COMPOUNDS, encoding="utf-8"))

    if not EXPECTED_MINIMUM <= len(records) <= EXPECTED_MAXIMUM:
        errors.append(f"expected {EXPECTED_MINIMUM}–{EXPECTED_MAXIMUM} compounds, found {len(records)}")

    ids: set[str] = set()
    cids: set[int] = set()
    names: dict[str, dict] = {}
    by_hill: dict[str, set[str]] = {}
    for record in records:
        name = record.get("preferredName") or "?"
        label = f"{name} ({record.get('id')})"
        for key in ("id", "pubChemCID", "preferredName", "formula", "hillFormula", "molarMass",
                    "bondingClass", "tags", "alternateNames", "summary", "dataSource",
                    "isLocalCurated", "lastUpdated", "classificationSource"):
            if key not in record:
                errors.append(f"{label}: missing {key}")
        if record.get("id") in ids:
            errors.append(f"{label}: duplicate id")
        ids.add(record.get("id"))
        cid = record.get("pubChemCID")
        if not isinstance(cid, int) or cid <= 0:
            errors.append(f"{label}: every bundled compound needs a positive PubChem CID")
        elif cid in cids:
            errors.append(f"{label}: duplicate CID {cid}")
        else:
            cids.add(cid)
        if record.get("id") != f"pubchem-{cid}":
            errors.append(f"{label}: id must be pubchem-<cid>")
        if record.get("dataSource") != "curated" or record.get("isLocalCurated") is not True:
            errors.append(f"{label}: bundled compounds are curated")
        if record.get("charge") != 0:
            errors.append(f"{label}: bundled compounds are neutral")
        names[name] = record

        formula = record.get("formula") or ""
        hill_formula = record.get("hillFormula") or ""
        counts = parse_formula(formula)
        if hill(counts) != hill_formula:
            errors.append(f"{label}: formula {formula} and Hill formula {hill_formula} disagree")
        by_hill.setdefault(hill_formula, set()).add(name)
        unknown = [s for s in counts if s not in weights]
        if unknown:
            errors.append(f"{label}: unknown element symbols {unknown}")
        else:
            computed = sum(weights[s] * n for s, n in counts.items())
            if abs(computed - float(record.get("molarMass") or 0)) > 0.01:
                errors.append(f"{label}: molar mass {record.get('molarMass')} but the IUPAC "
                              f"weights give {computed:.3f}")

        bonding = record.get("bondingClass")
        if bonding not in BONDING:
            errors.append(f"{label}: unknown bondingClass {bonding}")
        tags = record.get("tags") or []
        for tag in tags:
            if tag not in TAGS:
                errors.append(f"{label}: unknown tag {tag}")
        if len(set(tags)) != len(tags):
            errors.append(f"{label}: duplicate tags")
        if "acid" in tags and "H" not in counts:
            errors.append(f"{label}: tagged acid without hydrogen")
        if "acid" in tags and "base" in tags:
            errors.append(f"{label}: tagged both acid and base")
        if "organic" in tags and "C" not in counts:
            errors.append(f"{label}: tagged organic without carbon")
        if "organic" in tags and "inorganic" in tags:
            errors.append(f"{label}: tagged both organic and inorganic")
        if not ({"organic", "inorganic"} & set(tags)):
            errors.append(f"{label}: needs organic or inorganic")
        if "salt" in tags and bonding != "ionic":
            errors.append(f"{label}: a salt must be ionic")
        if bonding == "ionic" and not (set(counts) & metals or ("N" in counts and "H" in counts)):
            errors.append(f"{label}: ionic but contains no metal and no ammonium")
        if bonding == "molecular" and set(counts) & metals:
            errors.append(f"{label}: molecular but contains a metal")

        summary = record.get("summary") or ""
        if not 20 <= len(summary) <= 260:
            errors.append(f"{label}: summary is {len(summary)} characters (20–260)")
        if "!" in summary or "did you know" in summary.lower():
            errors.append(f"{label}: summary reads as hype")

        structure = record.get("structure")
        if bonding == "networkSolid":
            if structure is not None:
                errors.append(f"{label}: a network solid has no molecule to draw")
            continue
        if structure is None:
            errors.append(f"{label}: missing structure")
            continue
        if structure.get("source") not in STRUCTURE_SOURCES:
            errors.append(f"{label}: unknown structure source {structure.get('source')}")
        if not (structure.get("note") or "").strip():
            errors.append(f"{label}: a structure must say what it is")
        atoms = structure.get("atoms") or []
        bonds = structure.get("bonds") or []
        if not atoms:
            errors.append(f"{label}: structure has no atoms")
            continue
        ids_in_structure = [a["id"] for a in atoms]
        if ids_in_structure != list(range(len(atoms))):
            errors.append(f"{label}: atom ids must be 0..n-1 in order")
        atom_counts: dict[str, int] = {}
        for atom in atoms:
            symbol = symbols.get(atom.get("atomicNumber"))
            if symbol is None:
                errors.append(f"{label}: atom with unknown atomic number {atom.get('atomicNumber')}")
                continue
            atom_counts[symbol] = atom_counts.get(symbol, 0) + 1
            for axis in ("x", "y", "z"):
                value = atom.get(axis)
                if not isinstance(value, (int, float)) or not math.isfinite(value) or abs(value) > 60:
                    errors.append(f"{label}: atom {atom.get('id')} has a bad {axis}")
        if structure.get("source") == "curatedLattice":
            # A conventional cell is cut at its boundary, so the two sublattices
            # hold 14 and 13 sites; only the element set must agree.
            if set(atom_counts) != set(counts):
                errors.append(f"{label}: lattice elements {sorted(atom_counts)} differ from {sorted(counts)}")
            if any(atom_counts.get(s, 0) < 4 for s in counts):
                errors.append(f"{label}: lattice cell is too small to show the packing")
        elif atom_counts != counts:
            errors.append(f"{label}: structure atoms {atom_counts} do not match formula {counts}")
        if sum(a.get("formalCharge", 0) for a in atoms) != 0 and structure.get("source") != "curatedLattice":
            errors.append(f"{label}: formal charges do not sum to zero")
        for bond in bonds:
            if bond.get("from") == bond.get("to"):
                errors.append(f"{label}: a bond from an atom to itself")
            if not (0 <= bond.get("from", -1) < len(atoms) and 0 <= bond.get("to", -1) < len(atoms)):
                errors.append(f"{label}: bond references a missing atom")
            if bond.get("order") not in (1, 2, 3):
                errors.append(f"{label}: bond order {bond.get('order')} is not 1, 2 or 3")
            if bond.get("isContact") and structure.get("source") != "curatedLattice":
                errors.append(f"{label}: only a lattice has contacts")
        if len(atoms) > 1 and structure.get("is3D"):
            # Planar molecules (water, CO2, ozone) legitimately sit in one plane;
            # only a set of coincident atoms is wrong.
            points = {(round(a["x"], 2), round(a["y"], 2), round(a["z"], 2)) for a in atoms}
            if len(points) != len(atoms):
                errors.append(f"{label}: two atoms share the same position")

    for name in EXPECTED_PRESENT:
        if name not in names:
            errors.append(f"missing the expected compound {name}")
    for formula, expected in EXPECTED_SHARED.items():
        found = by_hill.get(formula, set())
        if not expected <= found:
            errors.append(f"{formula} should be shared by {sorted(expected)}, found {sorted(found)}")
    if names.get("Sodium chloride", {}).get("hillFormula") != "ClNa":
        errors.append("sodium chloride's Hill formula must be ClNa (that is what PubChem indexes)")
    if names.get("Silicon dioxide", {}).get("bondingClass") != "networkSolid":
        errors.append("silicon dioxide is a network solid")

    if errors:
        for error in errors:
            print(f"error: {error}")
        print(f"\n{len(errors)} problem(s) in compounds.json")
        return 1
    with_structure = sum(1 for r in records if r.get("structure"))
    print(f"OK — {len(records)} bundled compounds, {with_structure} with structures, "
          f"{len([r for r in records if r['bondingClass'] == 'ionic'])} ionic, molar masses match IUPAC 2021")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
