#!/usr/bin/env python3
"""Writes PeriodicPro/Data/structures.json: one structure profile per element.

This file *is* the science. Each entry says what representative physical form
the element takes at ordinary conditions (298 K, 1 atm unless stated), which
crystal system and lattice it has, the lattice parameters, the coordination,
and — just as important — whether that structure is experimentally established
at all. Elements whose bulk form has never been observed get an explicit
`unknown` profile rather than a guessed lattice. Nothing in the app can
silently fall back to a generic crystal: the Swift catalog, the unit tests and
`Tools/validate_structures.py` all fail on an element with no entry.

Sources are cited per entry; the reference list, conventions and every
simplification the renderer makes are in STRUCTURE_SOURCES.md.

    python3 Tools/build_structures.py        # regenerates the JSON
    python3 Tools/validate_structures.py     # checks it against elements.json

Numbers are the room-temperature values tabulated in the CRC Handbook of
Chemistry and Physics ("Crystal Structures of the Elements", 104th ed.) and
Donohue, *The Structures of the Elements* (Wiley, 1974), with diatomic bond
lengths from Huber & Herzberg via the NIST Chemistry WebBook. Values are in
ångströms and degrees.
"""
from __future__ import annotations

import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "PeriodicPro", "Data", "structures.json")

CRC = "CRC Handbook of Chemistry and Physics, 104th ed., Crystal Structures of the Elements"
DONOHUE = "Donohue, The Structures of the Elements (1974)"
NIST = "NIST Chemistry WebBook, Constants of Diatomic Molecules (Huber & Herzberg)"
STP = "298 K, 1 atm"


def profile(kind, **fields):
    base = {
        "representationKind": kind,
        "allotropeName": None,
        "phase": "solid",
        "crystalSystem": None,
        "latticeType": None,
        "spaceGroup": None,
        "latticeParameters": None,
        "molecularGeometry": None,
        "bondOrders": None,
        "bondLengthAngstrom": None,
        "coordination": None,
        "temperatureContext": STP,
        "isExperimentallyEstablished": True,
        "source": CRC,
        "notes": None,
        "geometry": None,
        "pickerTitle": None,
    }
    base.update(fields)
    return base


def cell(a=None, b=None, c=None, alpha=None, beta=None, gamma=None):
    return {"a": a, "b": b, "c": c, "alpha": alpha, "beta": beta, "gamma": gamma}


# --- Metallic and covalent crystals ----------------------------------------

def fcc(a, name=None, **extra):
    return profile("fcc", allotropeName=name, crystalSystem="cubic",
                   latticeType="face-centered cubic (A1, Cu-type)", spaceGroup="Fm-3m",
                   latticeParameters=cell(a=a), coordination=12,
                   geometry={"template": "fcc"}, **extra)


def bcc(a, name=None, **extra):
    return profile("bcc", allotropeName=name, crystalSystem="cubic",
                   latticeType="body-centered cubic (A2, W-type)", spaceGroup="Im-3m",
                   latticeParameters=cell(a=a), coordination=8,
                   geometry={"template": "bcc"}, **extra)


def hcp(a, c, name=None, **extra):
    return profile("hcp", allotropeName=name, crystalSystem="hexagonal",
                   latticeType="hexagonal close-packed (A3, Mg-type)", spaceGroup="P6_3/mmc",
                   latticeParameters=cell(a=a, c=c), coordination=12,
                   geometry={"template": "hcp", "cOverA": round(c / a, 4)}, **extra)


def dhcp(a, c, name=None, **extra):
    return profile("dhcp", allotropeName=name, crystalSystem="hexagonal",
                   latticeType="double hexagonal close-packed (A3', La-type, ABAC stacking)",
                   spaceGroup="P6_3/mmc", latticeParameters=cell(a=a, c=c), coordination=12,
                   geometry={"template": "dhcp", "cOverA": round(c / a, 4)}, **extra)


def simple_cubic(a, name=None, **extra):
    return profile("simpleCubic", allotropeName=name, crystalSystem="cubic",
                   latticeType="simple cubic (Ah, Po-type)", spaceGroup="Pm-3m",
                   latticeParameters=cell(a=a), coordination=6,
                   geometry={"template": "simpleCubic"}, **extra)


def diamond(a, name=None, **extra):
    return profile("diamondCubic", allotropeName=name, crystalSystem="cubic",
                   latticeType="diamond cubic (A4)", spaceGroup="Fd-3m",
                   latticeParameters=cell(a=a), coordination=4, bondOrders=[1],
                   geometry={"template": "diamondCubic"}, **extra)


def graphite(a, c, **extra):
    return profile("graphite", allotropeName="Graphite", crystalSystem="hexagonal",
                   latticeType="hexagonal layered (A9, graphite)", spaceGroup="P6_3/mmc",
                   latticeParameters=cell(a=a, c=c), coordination=3, bondOrders=[1],
                   bondLengthAngstrom=1.42,
                   geometry={"template": "graphite"}, **extra)


def layered_rhombohedral(a, c, **extra):
    """The gray arsenic (A7) structure: puckered six-membered layers."""
    return profile("rhombohedral", crystalSystem="trigonal (rhombohedral)",
                   latticeType="rhombohedral layered (A7, As-type)", spaceGroup="R-3m",
                   latticeParameters=cell(a=a, c=c), coordination=3, bondOrders=[1],
                   notes="Each atom has three near neighbors in its own puckered layer and "
                         "three more distant ones in the next; the layers are shown as one "
                         "fragment.",
                   geometry={"template": "puckeredLayer"}, **extra)


def helical_chains(a, c, **extra):
    return profile("helicalChain", crystalSystem="trigonal", latticeType="helical chains (A8, Se-type)",
                   spaceGroup="P3_121", latticeParameters=cell(a=a, c=c), coordination=2,
                   bondOrders=[1],
                   geometry={"template": "helicalChain"}, **extra)


def lattice(kind, system, lattice_type, space_group, params, basis, contact_factor,
            coordination, discrete=False, name=None, **extra):
    """An explicit conventional cell: fractional basis, nearest-neighbor contacts."""
    return profile(kind, allotropeName=name, crystalSystem=system, latticeType=lattice_type,
                   spaceGroup=space_group, latticeParameters=params, coordination=coordination,
                   geometry={"template": "lattice", "basis": basis,
                             "contactFactor": contact_factor, "discreteBonds": discrete},
                   **extra)


def complex_crystal(system, lattice_type, space_group, params, atoms_per_cell, **extra):
    return profile("complexCrystal", crystalSystem=system, latticeType=lattice_type,
                   spaceGroup=space_group, latticeParameters=params,
                   notes=f"{atoms_per_cell} atoms per unit cell in several distinct "
                         "environments — too complex to draw as a cell. A close-packed "
                         "fragment stands in for the metallic packing, and is labeled "
                         "simplified.",
                   geometry={"template": "closePackedCluster"}, **extra)


# --- Molecules, gases and liquids ------------------------------------------

def diatomic(length, order, phase="gas", **extra):
    return profile("diatomicMolecule", phase=phase, molecularGeometry="linear",
                   bondOrders=[order], bondLengthAngstrom=length, coordination=1,
                   source=NIST, geometry={"template": "diatomic"}, **extra)


def monatomic(**extra):
    return profile("monatomicGas", phase="gas", molecularGeometry="single atoms",
                   coordination=0, source=CRC,
                   notes="A noble gas: closed-shell atoms that do not bond to each other. "
                         "Several are shown to convey a gas, not a molecule.",
                   geometry={"template": "monatomicGas"}, **extra)


def unknown(predicted, **extra):
    return profile("unknown", phase="unknown", isExperimentallyEstablished=False,
                   temperatureContext="not established",
                   source="No bulk sample has ever been produced; " + predicted,
                   notes="Bulk crystal structure not established. Only individual atoms "
                         "have been made, so the app shows the atom and says so rather "
                         "than drawing a lattice nobody has observed.",
                   geometry={"template": "atom"}, **extra)


# --- The table --------------------------------------------------------------
# Keyed by atomic number: (primary profile, [alternative profiles]).

STRUCTURES = {
    1: (diatomic(0.741, 1, notes="H₂ is the free element at every ordinary temperature."), []),
    2: (monatomic(), []),
    3: (bcc(3.510, notes="Body-centered cubic at room temperature; a martensitic transformation "
                         "below about 78 K gives a close-packed form."), []),
    4: (hcp(2.286, 3.584), []),
    5: (profile("complexCrystal", allotropeName="β-rhombohedral boron", crystalSystem="trigonal",
                latticeType="B₁₂ icosahedra linked into a network", spaceGroup="R-3m",
                latticeParameters=cell(a=10.93, c=23.82), coordination=5,
                notes="The stable form has 105 atoms per cell built from B₁₂ icosahedra. One "
                      "icosahedron is shown; the network continues between them.",
                geometry={"template": "icosahedron"}), []),
    6: (graphite(2.461, 6.708, pickerTitle="Graphite",
                 notes="Graphite is the standard state of carbon. Each layer is a sheet of "
                       "hexagons with three bonds per atom; the layers 3.35 Å apart are held "
                       "only by weak forces, which is why graphite is soft and flakes."),
        [diamond(3.567, name="Diamond", pickerTitle="Diamond",
                 notes="Diamond is metastable at ordinary conditions: every atom bonded to "
                       "four neighbors in a continuous network, which is why it is so hard.")]),
    7: (diatomic(1.098, 3, notes="The N≡N triple bond is one of the strongest known, which is why "
                                 "nitrogen gas is so unreactive."), []),
    8: (diatomic(1.208, 2, notes="O₂ has a double bond. Ozone, O₃, is a separate allotrope."), []),
    9: (diatomic(1.412, 1), []),
    10: (monatomic(), []),
    11: (bcc(4.291), []),
    12: (hcp(3.209, 5.211), []),
    13: (fcc(4.050), []),
    14: (diamond(5.431), []),
    15: (profile("molecularCrystal", allotropeName="White phosphorus (P₄)", crystalSystem="cubic",
                 latticeType="molecular crystal of P₄ tetrahedra", spaceGroup="I-43m",
                 latticeParameters=cell(a=18.51), molecularGeometry="tetrahedral", pickerTitle="White",
                 bondOrders=[1], bondLengthAngstrom=2.21, coordination=3, source=DONOHUE,
                 notes="White phosphorus is the reference allotrope but not the most stable "
                       "one; red phosphorus is amorphous polymeric chains and black "
                       "phosphorus is a layered crystal.",
                 geometry={"template": "tetrahedron"}),
         [lattice("orthorhombic", "orthorhombic", "puckered layers (A17, black phosphorus)",
                  "Cmce", cell(a=3.314, b=10.478, c=4.376),
                  [[0, 0.1017, 0.0806], [0, 0.3983, 0.5806], [0, 0.6017, 0.4194],
                   [0, 0.8983, 0.9194], [0.5, 0.6017, 0.0806], [0.5, 0.8983, 0.5806],
                   [0.5, 0.1017, 0.4194], [0.5, 0.3983, 0.9194]],
                  1.06, 3, discrete=True, name="Black phosphorus", source=DONOHUE, pickerTitle="Black",
                  notes="The thermodynamically stable allotrope: puckered layers in which "
                        "every atom is bonded to three neighbors.")]),
    16: (profile("molecularCrystal", allotropeName="α-sulfur (S₈)", crystalSystem="orthorhombic",
                 latticeType="molecular crystal of S₈ crown rings", spaceGroup="Fddd",
                 latticeParameters=cell(a=10.465, b=12.866, c=24.486),
                 molecularGeometry="puckered eight-membered ring (crown)", bondOrders=[1],
                 bondLengthAngstrom=2.05, coordination=2, source=DONOHUE,
                 notes="128 atoms — sixteen S₈ rings — per unit cell. One ring is shown.",
                 geometry={"template": "crownRing"}), []),
    17: (diatomic(1.988, 1), []),
    18: (monatomic(), []),
    19: (bcc(5.328), []),
    20: (fcc(5.588), []),
    21: (hcp(3.309, 5.268), []),
    22: (hcp(2.951, 4.686, name="α-titanium"), []),
    23: (bcc(3.024), []),
    24: (bcc(2.885), []),
    25: (complex_crystal("cubic", "α-manganese (A12)", "I-43m", cell(a=8.913), 58), []),
    26: (bcc(2.867, name="α-iron (ferrite)", pickerTitle="α (BCC)",
             notes="Body-centered cubic up to 912 °C. Steel's heat treatment turns on the "
                   "change to face-centered γ-iron above that temperature."),
         [fcc(3.65, name="γ-iron (austenite)", temperatureContext="912–1394 °C", pickerTitle="γ (FCC)",
              notes="The face-centered cubic form stable between 912 and 1394 °C, in "
                    "which carbon dissolves far more readily than in ferrite.")]),
    27: (hcp(2.507, 4.070, name="ε-cobalt"), []),
    28: (fcc(3.524), []),
    29: (fcc(3.615), []),
    30: (hcp(2.665, 4.947, notes="Noticeably stretched along c (c/a = 1.86 against the ideal "
                                 "1.63), so the six neighbors in the layer are closer than "
                                 "the six above and below."), []),
    31: (lattice("orthorhombic", "orthorhombic", "α-gallium (A11): Ga₂ dimers in a buckled network",
                 "Cmce", cell(a=4.520, b=7.663, c=4.526),
                 [[0, 0.1549, 0.0810], [0, 0.3451, 0.5810], [0, 0.6549, 0.4190],
                  [0, 0.8451, 0.9190], [0.5, 0.6549, 0.0810], [0.5, 0.8451, 0.5810],
                  [0.5, 0.1549, 0.4190], [0.5, 0.3451, 0.9190]],
                 1.03, 1, discrete=False, name="α-gallium", source=DONOHUE,
                 notes="Each atom has one neighbor at 2.44 Å — the Ga₂ pair drawn here — and "
                       "six more between 2.7 and 2.8 Å. The pairs are why gallium melts in "
                       "the hand."), []),
    32: (diamond(5.658), []),
    33: (layered_rhombohedral(3.760, 10.548, allotropeName="Gray arsenic"), []),
    34: (helical_chains(4.366, 4.954, allotropeName="Gray (trigonal) selenium",
                        notes="Infinite helical chains, three atoms per turn, shown as one "
                              "open fragment. Red selenium is Se₈ rings."), []),
    35: (profile("molecularLiquid", phase="liquid", molecularGeometry="linear", bondOrders=[1],
                 bondLengthAngstrom=2.281, coordination=1, source=NIST,
                 notes="One of two elements liquid at room temperature: Br₂ molecules in "
                       "close contact with no long-range order.",
                 geometry={"template": "molecularLiquid"}), []),
    36: (monatomic(), []),
    37: (bcc(5.585), []),
    38: (fcc(6.085), []),
    39: (hcp(3.647, 5.731), []),
    40: (hcp(3.232, 5.147, name="α-zirconium"), []),
    41: (bcc(3.301), []),
    42: (bcc(3.147), []),
    43: (hcp(2.735, 4.388), []),
    44: (hcp(2.706, 4.282), []),
    45: (fcc(3.803), []),
    46: (fcc(3.890), []),
    47: (fcc(4.086), []),
    48: (hcp(2.979, 5.619, notes="Like zinc, stretched along c (c/a = 1.89)."), []),
    49: (lattice("tetragonal", "tetragonal", "body-centered tetragonal (A6, In-type)", "I4/mmm",
                 cell(a=3.253, c=4.946), [[0, 0, 0], [0.5, 0.5, 0.5]], 1.06, 12,
                 notes="A face-centered cubic lattice stretched 8% along one axis: four "
                       "neighbors at 3.25 Å and eight at 3.38 Å."), []),
    50: (lattice("tetragonal", "tetragonal", "β-tin (A5): body-centered tetragonal, four atoms per cell",
                 "I4_1/amd", cell(a=5.831, c=3.182),
                 [[0, 0, 0], [0, 0.5, 0.25], [0.5, 0.5, 0.5], [0.5, 0, 0.75]], 1.06, 6,
                 name="White (β) tin", source=DONOHUE, pickerTitle="White",
                 notes="Four neighbors at 3.02 Å and two at 3.18 Å. Below 13.2 °C it slowly "
                       "converts to gray tin — the 'tin pest' — with a different structure."),
         [diamond(6.489, name="Gray (α) tin", temperatureContext="below 13.2 °C", pickerTitle="Gray",
                  notes="The diamond-cubic form, a brittle semimetal rather than a metal.")]),
    51: (layered_rhombohedral(4.307, 11.273), []),
    52: (helical_chains(4.457, 5.929), []),
    53: (lattice("molecularCrystal", "orthorhombic", "molecular crystal of I₂ (A14)", "Cmce",
                 cell(a=7.18, b=4.71, c=9.81),
                 [[0, 0.1543, 0.1174], [0, 0.3457, 0.6174], [0, 0.6543, 0.3826],
                  [0, 0.8457, 0.8826], [0.5, 0.6543, 0.1174], [0.5, 0.8457, 0.6174],
                  [0.5, 0.1543, 0.3826], [0.5, 0.3457, 0.8826]],
                 1.05, 1, discrete=True, source=DONOHUE, bondOrders=[1], bondLengthAngstrom=2.72,
                 molecularGeometry="linear I₂ molecules",
                 notes="The bond drawn is the I–I bond within each molecule; molecules sit "
                       "3.5 Å and more apart."), []),
    54: (monatomic(), []),
    55: (bcc(6.141), []),
    56: (bcc(5.028), []),
    57: (dhcp(3.774, 12.171, name="α-lanthanum"), []),
    58: (fcc(5.161, name="γ-cerium",
             notes="Room-temperature cerium is mostly γ (face-centered cubic) with some β "
                   "(double hexagonal) present; the two interconvert slowly."), []),
    59: (dhcp(3.672, 11.833), []),
    60: (dhcp(3.658, 11.797), []),
    61: (dhcp(3.65, 11.65, notes="Determined on milligram-scale samples of the radioactive metal."), []),
    62: (profile("rhombohedral", allotropeName="α-samarium", crystalSystem="trigonal (rhombohedral)",
                 latticeType="Sm-type close packing (nine-layer ABABCBCAC stacking)",
                 spaceGroup="R-3m", latticeParameters=cell(a=3.629, c=26.207), coordination=12,
                 notes="A close-packed metal whose stacking repeats only every nine layers. "
                       "A 12-coordinated fragment is shown; the full repeat is not.",
                 geometry={"template": "closePackedCluster"}), []),
    63: (bcc(4.581), []),
    64: (hcp(3.636, 5.783), []),
    65: (hcp(3.601, 5.694), []),
    66: (hcp(3.593, 5.654), []),
    67: (hcp(3.578, 5.618), []),
    68: (hcp(3.559, 5.585), []),
    69: (hcp(3.538, 5.554), []),
    70: (fcc(5.485, name="β-ytterbium"), []),
    71: (hcp(3.505, 5.549), []),
    72: (hcp(3.195, 5.051), []),
    73: (bcc(3.303), []),
    74: (bcc(3.165), []),
    75: (hcp(2.761, 4.456), []),
    76: (hcp(2.734, 4.320), []),
    77: (fcc(3.839), []),
    78: (fcc(3.924), []),
    79: (fcc(4.078), []),
    80: (profile("liquidMetal", phase="liquid", coordination=None, source=CRC,
                 notes="The only metal liquid at room temperature: atoms in close contact "
                       "with no fixed lattice. Solid mercury (below −38.8 °C) is rhombohedral.",
                 geometry={"template": "liquidMetal"}), []),
    81: (hcp(3.457, 5.525, name="α-thallium"), []),
    82: (fcc(4.950), []),
    83: (layered_rhombohedral(4.546, 11.862), []),
    84: (simple_cubic(3.359, name="α-polonium",
                      notes="The only element with a simple cubic structure at ordinary "
                            "conditions, determined on small radioactive samples."), []),
    85: (unknown("its metallic structure is predicted, not measured."), []),
    86: (monatomic(), []),
    87: (unknown("a body-centered cubic metal is predicted from its group."), []),
    88: (bcc(5.148), []),
    89: (fcc(5.311), []),
    90: (fcc(5.084), []),
    91: (lattice("tetragonal", "tetragonal", "body-centered tetragonal (Pa-type)", "I4/mmm",
                 cell(a=3.925, c=3.238), [[0, 0, 0], [0.5, 0.5, 0.5]], 1.06, 10,
                 notes="A body-centered tetragonal cell squashed along c."), []),
    92: (lattice("orthorhombic", "orthorhombic", "α-uranium (A20): corrugated layers", "Cmcm",
                 cell(a=2.854, b=5.870, c=4.955),
                 [[0, 0.1025, 0.25], [0, 0.8975, 0.75], [0.5, 0.6025, 0.25], [0.5, 0.3975, 0.75]],
                 1.06, 4, name="α-uranium", source=DONOHUE,
                 notes="Each atom has two neighbors at 2.75 Å and two at 2.85 Å, in "
                       "corrugated sheets; four more sit at 3.26 Å."), []),
    93: (profile("orthorhombic", allotropeName="α-neptunium", crystalSystem="orthorhombic",
                 latticeType="orthorhombic, eight atoms per cell", spaceGroup="Pnma",
                 latticeParameters=cell(a=6.663, b=4.723, c=4.887), source=DONOHUE,
                 notes="Two crystallographically distinct atom sites with irregular "
                       "coordination. A close-packed fragment stands in, labeled simplified.",
                 geometry={"template": "closePackedCluster"}), []),
    94: (complex_crystal("monoclinic", "α-plutonium", "P2_1/m",
                         cell(a=6.183, b=4.822, c=10.963, beta=101.79), 16,
                         allotropeName="α-plutonium"), []),
    95: (dhcp(3.468, 11.241), []),
    96: (dhcp(3.496, 11.331), []),
    97: (dhcp(3.416, 11.069), []),
    98: (dhcp(3.38, 11.03, notes="Determined on microgram-scale samples."), []),
    99: (fcc(5.75, notes="A single determination on microgram-scale samples "
                         "(Haire & Baybarz, 1979); treat the value as approximate."), []),
}

PREDICTIONS = {
    100: "a face-centered cubic metal is predicted.",
    101: "a face-centered cubic metal is predicted.",
    102: "a face-centered cubic metal is predicted.",
    103: "a hexagonal close-packed metal is predicted.",
    104: "a hexagonal close-packed metal is predicted.",
    105: "a body-centered cubic metal is predicted.",
    106: "a body-centered cubic metal is predicted.",
    107: "a hexagonal close-packed metal is predicted.",
    108: "a hexagonal close-packed metal is predicted.",
    109: "a face-centered cubic metal is predicted.",
    110: "a body-centered cubic metal is predicted.",
    111: "a body-centered cubic metal is predicted.",
    112: "calculations disagree on whether it is a metal or a volatile solid.",
    113: "a hexagonal close-packed metal is predicted.",
    114: "a face-centered cubic solid is predicted.",
    115: "a face-centered cubic metal is predicted.",
    116: "a face-centered cubic metal is predicted.",
    117: "a hexagonal close-packed solid is predicted.",
    118: "a face-centered cubic solid is predicted; it may be a gas.",
}
for number, prediction in PREDICTIONS.items():
    STRUCTURES[number] = (unknown(prediction), [])


def main() -> int:
    entries = []
    for number in sorted(STRUCTURES):
        primary, alternatives = STRUCTURES[number]
        entries.append({
            "atomicNumber": number,
            "primary": primary,
            "alternatives": alternatives,
        })
    assert len(entries) == 118, len(entries)
    with open(OUT, "w", encoding="utf-8") as handle:
        json.dump(entries, handle, indent=1, ensure_ascii=False)
        handle.write("\n")
    print(f"wrote {os.path.relpath(OUT, ROOT)} with {len(entries)} entries")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
