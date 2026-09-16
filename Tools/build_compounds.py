#!/usr/bin/env python3
"""Writes PeriodicPro/Data/compounds.json: the bundled starter catalog.

Fifty common educational compounds, each identified by its PubChem CID and
described with a curated name, conventional formula, Hill formula, IUPAC name,
molar mass, canonical SMILES, a conservative classification and one short
sentence. The record also carries a structure — atoms, bonds with orders,
formal charges and 3D coordinates — so the app can show it offline.

Where the numbers come from:

* **Identity** (CID, names, SMILES): PubChem, transcribed by hand for each
  entry and cross-checked here — RDKit parses the SMILES and the resulting
  Hill formula must equal the one expected for the compound, or the build
  fails.
* **Molar mass**: computed from the Hill formula with the IUPAC 2021 standard
  atomic weights the app already ships in elements.json — the same numbers
  the app shows on element pages — not typed in.
* **Structure, molecular compounds**: an RDKit ETKDGv3 conformer, optimized
  with MMFF94, from the SMILES. This is a *computed* geometry with the right
  connectivity and bond orders and realistic bond lengths and angles; it is
  not an experimental structure, and the record says so.
* **Structure, rock-salt ionic solids** (NaCl, KCl, MgO, CaO): a conventional
  cell generated from the tabulated lattice parameter, with the ions on their
  real sites and nearest-neighbor contacts marked as contacts, not bonds.
* **Structure, other ionic compounds**: the ions of one formula unit — the
  polyatomic ion as a computed conformer, the cations placed beside it — with
  a note that the solid is a lattice of many such ions.
* **Network solids** (SiO₂): no structure is drawn, because there is no
  molecule to draw.

    python3 -m pip install rdkit
    python3 Tools/build_compounds.py
    python3 Tools/validate_compounds.py

COMPOUND_SOURCES.md documents the sources, the classification rules and the
limits of the computed geometry.
"""
from __future__ import annotations

import json
import math
import os
import re
from datetime import date

from rdkit import Chem
from rdkit.Chem import AllChem

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "PeriodicPro", "Data", "compounds.json")
ELEMENTS = os.path.join(ROOT, "PeriodicPro", "Data", "elements.json")

CONFORMER_NOTE = ("Computed conformer (RDKit ETKDGv3, MMFF94-optimized). Real connectivity and "
                  "bond orders; the geometry is calculated, not measured.")
IONS_NOTE = ("The ions of one formula unit. In the solid these ions pack into a lattice of "
             "many such units; no bond is drawn between the ions.")
LATTICE_NOTE = "A conventional unit cell of the rock-salt structure; the struts are ionic contacts."
CLASSIFICATION_SOURCE = (
    "Curated: ionic versus molecular from the constituents (metal + nonmetal or polyatomic ion "
    "versus nonmetals only); acid and base in the Brønsted sense in water, for compounds "
    "textbooks list as such; organic for carbon compounds with C–H bonds, plus urea."
)
TODAY = date.today().isoformat()

# (cid, preferred name, display formula, IUPAC name, SMILES, bonding, tags,
#  alternate names, summary, structure kind)
#
# structure kinds: "conformer" (RDKit), "rocksalt:<a Å>" (lattice), "ions"
# (polyatomic ion conformer plus placed cations), "none" (network solid).
COMPOUNDS = [
    (962, "Water", "H2O", "oxidane", "O", "molecular", ["inorganic"],
     ["Dihydrogen monoxide"], "Bent molecule of two hydrogen atoms bonded to one oxygen; the solvent "
     "of life and the reference for the Celsius scale.", "conformer"),
    (280, "Carbon dioxide", "CO2", "carbon dioxide", "O=C=O", "molecular", ["inorganic"],
     ["Carbonic anhydride"], "Linear molecule with two C=O double bonds; the gas plants fix and "
     "combustion releases.", "conformer"),
    (5234, "Sodium chloride", "NaCl", "sodium chloride", "[Na+].[Cl-]", "ionic", ["salt", "inorganic"],
     ["Table salt", "Halite"], "Sodium and chloride ions in a rock-salt lattice, each ion surrounded "
     "by six of the other.", "rocksalt:5.640"),
    (222, "Ammonia", "NH3", "azane", "N", "molecular", ["base", "inorganic"],
     ["Azane"], "Trigonal pyramidal molecule; a weak base in water and the feedstock for most "
     "nitrogen fertilizer.", "conformer"),
    (297, "Methane", "CH4", "methane", "C", "molecular", ["organic"],
     ["Natural gas (main component)"], "Tetrahedral, the simplest hydrocarbon and the main component "
     "of natural gas.", "conformer"),
    (313, "Hydrogen chloride", "HCl", "chlorane", "Cl", "molecular", ["acid", "inorganic"],
     ["Hydrochloric acid (in water)"], "Diatomic gas; dissolved in water it is hydrochloric acid, a "
     "strong acid.", "conformer"),
    (1118, "Sulfuric acid", "H2SO4", "sulfuric acid", "OS(=O)(=O)O", "molecular", ["acid", "inorganic"],
     ["Oil of vitriol"], "Tetrahedral sulfur bonded to four oxygens, two carrying hydrogen; a strong "
     "diprotic acid made in larger quantities than any other chemical.", "conformer"),
    (944, "Nitric acid", "HNO3", "nitric acid", "O[N+](=O)[O-]", "molecular", ["acid", "inorganic"],
     ["Aqua fortis"], "Planar nitrogen bonded to three oxygens; a strong acid and an oxidizer.",
     "conformer"),
    (14798, "Sodium hydroxide", "NaOH", "sodium hydroxide", "[Na+].[OH-]", "ionic",
     ["base", "inorganic"], ["Caustic soda", "Lye"], "Sodium and hydroxide ions; a strong base used "
     "in soap and paper making.", "ions"),
    (10112, "Calcium carbonate", "CaCO3", "calcium carbonate", "[Ca+2].[O-]C([O-])=O", "ionic",
     ["salt", "inorganic"], ["Limestone", "Calcite", "Chalk"], "Calcium ions and flat carbonate "
     "ions; limestone, marble, chalk and seashells.", "ions"),
    (516892, "Sodium bicarbonate", "NaHCO3", "sodium hydrogen carbonate", "[Na+].OC([O-])=O", "ionic",
     ["salt", "inorganic"], ["Baking soda", "Sodium hydrogen carbonate"], "Sodium and hydrogen "
     "carbonate ions; releases carbon dioxide when heated or acidified, which is what makes "
     "baking soda rise.", "ions"),
    (5793, "Glucose", "C6H12O6", "6-(hydroxymethyl)oxane-2,3,4,5-tetrol",
     "OC[C@H]1OC(O)[C@H](O)[C@@H](O)[C@@H]1O", "molecular", ["organic"],
     ["D-Glucose", "Dextrose", "Blood sugar"], "A six-carbon sugar, shown in its six-membered ring "
     "form; the sugar cells burn for energy.", "conformer"),
    (5988, "Sucrose", "C12H22O11",
     "2-[3,4-dihydroxy-2,5-bis(hydroxymethyl)oxolan-2-yl]oxy-6-(hydroxymethyl)oxane-3,4,5-triol",
     "OC[C@H]1O[C@@](CO)(O[C@H]2O[C@H](CO)[C@@H](O)[C@H](O)[C@H]2O)[C@@H](O)[C@@H]1O",
     "molecular", ["organic"], ["Table sugar", "Cane sugar"], "Glucose and fructose joined through "
     "an oxygen; ordinary table sugar.", "conformer"),
    (702, "Ethanol", "C2H6O", "ethanol", "CCO", "molecular", ["organic"],
     ["Ethyl alcohol", "Grain alcohol"], "Two carbons and a hydroxyl group; the alcohol in drinks "
     "and a common fuel and solvent. Shares its formula with dimethyl ether.", "conformer"),
    (887, "Methanol", "CH4O", "methanol", "CO", "molecular", ["organic"],
     ["Methyl alcohol", "Wood alcohol"], "The simplest alcohol, one carbon bearing a hydroxyl "
     "group; toxic, and a widely used solvent and feedstock.", "conformer"),
    (180, "Acetone", "C3H6O", "propan-2-one", "CC(C)=O", "molecular", ["organic"],
     ["Propanone", "2-Propanone"], "The simplest ketone, a C=O flanked by two methyl groups; the "
     "solvent in nail polish remover.", "conformer"),
    (176, "Acetic acid", "C2H4O2", "acetic acid", "CC(O)=O", "molecular", ["acid", "organic"],
     ["Ethanoic acid", "Vinegar (in water)"], "A carboxylic acid; vinegar is a few percent of it in "
     "water.", "conformer"),
    (784, "Hydrogen peroxide", "H2O2", "hydrogen peroxide", "OO", "molecular", ["inorganic"],
     ["Dioxidane"], "Two oxygens singly bonded, each carrying a hydrogen, in a twisted open-book "
     "shape; a bleach and disinfectant that decomposes to water and oxygen.", "conformer"),
    (2519, "Caffeine", "C8H10N4O2", "1,3,7-trimethylpurine-2,6-dione",
     "Cn1cnc2c1c(=O)n(C)c(=O)n2C", "molecular", ["organic"],
     ["1,3,7-Trimethylxanthine"], "A fused two-ring purine with three methyl groups; the stimulant "
     "in coffee and tea.", "conformer"),
    (2244, "Aspirin", "C9H8O4", "2-acetyloxybenzoic acid", "CC(=O)Oc1ccccc1C(O)=O", "molecular",
     ["acid", "organic"], ["Acetylsalicylic acid"], "A benzene ring carrying a carboxylic acid and an "
     "acetyl ester; the original synthetic painkiller.", "conformer"),
    (8254, "Dimethyl ether", "C2H6O", "methoxymethane", "COC", "molecular", ["organic"],
     ["Methoxymethane"], "Two methyl groups on one oxygen. The same atoms as ethanol, joined "
     "differently — a gas rather than a liquid.", "conformer"),
    (241, "Benzene", "C6H6", "benzene", "c1ccccc1", "molecular", ["organic"],
     ["Benzol"], "A flat six-carbon ring with delocalized bonding, drawn here with alternating "
     "double bonds; the parent of the aromatic compounds.", "conformer"),
    (6325, "Ethylene", "C2H4", "ethene", "C=C", "molecular", ["organic"],
     ["Ethene"], "Two carbons joined by a double bond; a plant hormone and the feedstock for "
     "polyethylene.", "conformer"),
    (6334, "Propane", "C3H8", "propane", "CCC", "molecular", ["organic"],
     [], "A three-carbon alkane; bottled fuel gas.", "conformer"),
    (24823, "Ozone", "O3", "trioxidane", "[O-][O+]=O", "molecular", ["inorganic"],
     ["Trioxygen"], "Three oxygen atoms in a bent molecule; an allotrope of oxygen that absorbs "
     "ultraviolet light in the stratosphere.", "conformer"),
    (281, "Carbon monoxide", "CO", "carbon monoxide", "[C-]#[O+]", "molecular", ["inorganic"],
     [], "One carbon and one oxygen joined by a triple bond; a colorless, odorless and toxic "
     "gas from incomplete combustion.", "conformer"),
    (1119, "Sulfur dioxide", "SO2", "sulfur dioxide", "O=S=O", "molecular", ["inorganic"],
     [], "Bent molecule of sulfur and two oxygens; a preservative, and the source of acid rain "
     "when it forms from burning sulfur-rich fuel.", "conformer"),
    (402, "Hydrogen sulfide", "H2S", "sulfane", "S", "molecular", ["inorganic"],
     ["Sulfane"], "Bent like water, with sulfur in place of oxygen; the smell of rotten eggs.",
     "conformer"),
    (1176, "Urea", "CH4N2O", "urea", "NC(N)=O", "molecular", ["organic"],
     ["Carbamide"], "A carbonyl flanked by two amino groups; the main nitrogen waste in urine and "
     "the first organic compound made from inorganic starting materials.", "conformer"),
    (712, "Formaldehyde", "CH2O", "formaldehyde", "C=O", "molecular", ["organic"],
     ["Methanal"], "The simplest aldehyde, a single carbon double-bonded to oxygen.", "conformer"),
    (174, "Ethylene glycol", "C2H6O2", "ethane-1,2-diol", "OCCO", "molecular", ["organic"],
     ["Ethane-1,2-diol"], "Two carbons each carrying a hydroxyl group; automotive antifreeze.",
     "conformer"),
    (753, "Glycerol", "C3H8O3", "propane-1,2,3-triol", "OCC(O)CO", "molecular", ["organic"],
     ["Glycerin", "Glycerine"], "Three carbons each with a hydroxyl group; the backbone of fats.",
     "conformer"),
    (311, "Citric acid", "C6H8O7", "2-hydroxypropane-1,2,3-tricarboxylic acid",
     "OC(=O)CC(O)(CC(O)=O)C(O)=O", "molecular", ["acid", "organic"],
     [], "Three carboxylic acid groups on a small carbon skeleton; the sourness of citrus fruit.",
     "conformer"),
    (3672, "Ibuprofen", "C13H18O2", "2-[4-(2-methylpropyl)phenyl]propanoic acid",
     "CC(C)Cc1ccc(cc1)C(C)C(O)=O", "molecular", ["acid", "organic"],
     [], "A benzene ring with an isobutyl group on one side and a propanoic acid on the other; a "
     "common anti-inflammatory painkiller.", "conformer"),
    (1983, "Acetaminophen", "C8H9NO2", "N-(4-hydroxyphenyl)acetamide", "CC(=O)Nc1ccc(O)cc1",
     "molecular", ["organic"], ["Paracetamol", "Tylenol (brand)"], "A benzene ring carrying a hydroxyl "
     "group and an acetamide; a common painkiller and fever reducer.", "conformer"),
    (4873, "Potassium chloride", "KCl", "potassium chloride", "[K+].[Cl-]", "ionic",
     ["salt", "inorganic"], ["Sylvite"], "Potassium and chloride ions in the rock-salt lattice; "
     "a fertilizer and a salt substitute.", "rocksalt:6.293"),
    (14792, "Magnesium oxide", "MgO", "oxomagnesium", "[Mg+2].[O-2]", "ionic", ["inorganic"],
     ["Magnesia", "Periclase"], "Magnesium and oxide ions in the rock-salt lattice; a refractory "
     "material that withstands very high temperatures.", "rocksalt:4.212"),
    (14778, "Calcium oxide", "CaO", "oxocalcium", "[Ca+2].[O-2]", "ionic", ["inorganic"],
     ["Quicklime", "Lime"], "Calcium and oxide ions in the rock-salt lattice; quicklime, made by "
     "heating limestone.", "rocksalt:4.811"),
    (24261, "Silicon dioxide", "SiO2", "dioxosilane", "O=[Si]=O", "networkSolid", ["inorganic"],
     ["Silica", "Quartz", "Sand"], "Not a molecule: every silicon is bonded to four oxygens and every "
     "oxygen to two silicons in an endless network. Quartz, sand and glass.", "none"),
    (25517, "Ammonium chloride", "NH4Cl", "azanium chloride", "[NH4+].[Cl-]", "ionic",
     ["salt", "inorganic"], ["Sal ammoniac"], "Ammonium and chloride ions; used in dry cells and "
     "as a flux for soldering.", "ions"),
    (10340, "Sodium carbonate", "Na2CO3", "disodium carbonate", "[Na+].[Na+].[O-]C([O-])=O",
     "ionic", ["salt", "inorganic"], ["Washing soda", "Soda ash"], "Two sodium ions and a carbonate "
     "ion; washing soda, used in glass making.", "ions"),
    (24434, "Potassium nitrate", "KNO3", "potassium nitrate", "[K+].[O-][N+](=O)[O-]", "ionic",
     ["salt", "inorganic"], ["Saltpeter", "Niter"], "Potassium and nitrate ions; the oxidizer in "
     "black powder and a fertilizer.", "ions"),
    (8857, "Ethyl acetate", "C4H8O2", "ethyl acetate", "CCOC(C)=O", "molecular", ["organic"],
     ["Ethyl ethanoate"], "The ester of ethanol and acetic acid; the fruity smell of nail polish "
     "and a common solvent.", "conformer"),
    (3776, "Isopropyl alcohol", "C3H8O", "propan-2-ol", "CC(C)O", "molecular", ["organic"],
     ["Isopropanol", "2-Propanol", "Rubbing alcohol"], "A three-carbon alcohol with the hydroxyl "
     "on the middle carbon; rubbing alcohol.", "conformer"),
    (6326, "Acetylene", "C2H2", "ethyne", "C#C", "molecular", ["organic"],
     ["Ethyne"], "Two carbons joined by a triple bond in a linear molecule; the fuel in welding "
     "torches.", "conformer"),
    (22985, "Ammonium nitrate", "NH4NO3", "azanium nitrate", "[NH4+].[O-][N+](=O)[O-]", "ionic",
     ["salt", "inorganic"], [], "Ammonium and nitrate ions; a nitrogen fertilizer.", "ions"),
    (54670067, "Ascorbic acid", "C6H8O6",
     "(2R)-2-[(1S)-1,2-dihydroxyethyl]-3,4-dihydroxy-2H-furan-5-one",
     "OC[C@H](O)[C@H]1OC(=O)C(O)=C1O", "molecular", ["acid", "organic"],
     ["Vitamin C", "L-Ascorbic acid"], "A five-membered ring lactone with an enediol; vitamin C, "
     "which humans cannot make.", "conformer"),
    (24462, "Copper(II) sulfate", "CuSO4", "copper;sulfate", "[Cu+2].[O-]S([O-])(=O)=O", "ionic",
     ["salt", "inorganic"], ["Cupric sulfate", "Blue vitriol (hydrate)"], "Copper(II) and sulfate "
     "ions; the anhydrous salt is white, and the familiar blue is the pentahydrate.", "ions"),
    (6212, "Chloroform", "CHCl3", "chloroform", "ClC(Cl)Cl", "molecular", ["organic"],
     ["Trichloromethane"], "Methane with three hydrogens replaced by chlorine; once an anesthetic, "
     "now a solvent.", "conformer"),
    (14917, "Hydrogen fluoride", "HF", "fluorane", "F", "molecular", ["acid", "inorganic"],
     ["Hydrofluoric acid (in water)"], "Diatomic, strongly hydrogen-bonded; its solution etches "
     "glass.", "conformer"),
]

HILL_ORDER_CACHE: dict[str, int] = {}


def atomic_weights() -> dict[str, float]:
    elements = json.load(open(ELEMENTS, encoding="utf-8"))
    return {e["symbol"]: e["atomicMass"] for e in elements}


def symbol_table() -> dict[int, str]:
    elements = json.load(open(ELEMENTS, encoding="utf-8"))
    return {e["atomicNumber"]: e["symbol"] for e in elements}


def hill_formula(counts: dict[str, int]) -> str:
    """C first, H second, then alphabetical; alphabetical throughout if no C."""
    symbols = sorted(counts)
    if "C" in counts:
        ordered = ["C"] + (["H"] if "H" in counts else []) + [s for s in symbols if s not in ("C", "H")]
    else:
        ordered = symbols
    return "".join(f"{s}{counts[s] if counts[s] > 1 else ''}" for s in ordered)


def parse_formula(formula: str) -> dict[str, int]:
    counts: dict[str, int] = {}
    for symbol, number in re.findall(r"([A-Z][a-z]?)(\d*)", formula):
        counts[symbol] = counts.get(symbol, 0) + (int(number) if number else 1)
    return counts


def molar_mass(counts: dict[str, int], weights: dict[str, float]) -> float:
    return round(sum(weights[s] * n for s, n in counts.items()), 3)


def conformer_structure(smiles: str, seed: int) -> tuple[list[dict], list[dict]]:
    mol = Chem.MolFromSmiles(smiles)
    if mol is None:
        raise SystemExit(f"RDKit could not parse {smiles}")
    mol = Chem.AddHs(mol)
    params = AllChem.ETKDGv3()
    params.randomSeed = seed
    if AllChem.EmbedMolecule(mol, params) != 0:
        raise SystemExit(f"embedding failed for {smiles}")
    try:
        AllChem.MMFFOptimizeMolecule(mol, maxIters=2000)
    except Exception:  # noqa: BLE001 — MMFF lacks parameters for a few ions
        AllChem.UFFOptimizeMolecule(mol, maxIters=2000)
    Chem.Kekulize(mol, clearAromaticFlags=True)
    conformer = mol.GetConformer()
    atoms = []
    for atom in mol.GetAtoms():
        position = conformer.GetAtomPosition(atom.GetIdx())
        atoms.append({
            "id": atom.GetIdx(),
            "atomicNumber": atom.GetAtomicNum(),
            "x": round(position.x, 3), "y": round(position.y, 3), "z": round(position.z, 3),
            "formalCharge": atom.GetFormalCharge(),
        })
    bonds = []
    for bond in mol.GetBonds():
        order = {Chem.BondType.SINGLE: 1, Chem.BondType.DOUBLE: 2, Chem.BondType.TRIPLE: 3}.get(
            bond.GetBondType(), 1)
        bonds.append({
            "id": bond.GetIdx(), "from": bond.GetBeginAtomIdx(), "to": bond.GetEndAtomIdx(),
            "order": order, "isContact": False,
        })
    return atoms, bonds


def ions_structure(smiles: str, seed: int) -> tuple[list[dict], list[dict]]:
    """The polyatomic ion(s) as conformers, the monatomic ions placed beside them."""
    fragments = smiles.split(".")
    atoms: list[dict] = []
    bonds: list[dict] = []
    monatomic: list[str] = []
    offset_x = 0.0
    for fragment in fragments:
        mol = Chem.MolFromSmiles(fragment)
        # Monatomic means one atom *with hydrogens counted*: hydroxide has one
        # heavy atom but is a two-atom ion.
        if Chem.AddHs(mol).GetNumAtoms() == 1:
            monatomic.append(fragment)
            continue
        fragment_atoms, fragment_bonds = conformer_structure(fragment, seed)
        base = len(atoms)
        for atom in fragment_atoms:
            atom = dict(atom)
            atom["id"] = atom["id"] + base
            atom["x"] = round(atom["x"] + offset_x, 3)
            atoms.append(atom)
        for bond in fragment_bonds:
            bond = dict(bond)
            bond["id"] = len(bonds)
            bond["from"] += base
            bond["to"] += base
            bonds.append(bond)
        offset_x += 6.0
    # Cations sit 3 Å beyond the anion's extent on alternating sides: close
    # enough to read as the same formula unit, far enough not to look bonded.
    if atoms:
        xs = [a["x"] for a in atoms]
        left, right = min(xs) - 3.0, max(xs) + 3.0
    else:
        left, right = -1.5, 1.5
    for index, fragment in enumerate(monatomic):
        mol = Chem.MolFromSmiles(fragment)
        atom = mol.GetAtomWithIdx(0)
        atoms.append({
            "id": len(atoms), "atomicNumber": atom.GetAtomicNum(),
            "x": round(right if index % 2 == 0 else left, 3),
            "y": round(0.0 + 0.6 * (index // 2), 3), "z": 0.0,
            "formalCharge": atom.GetFormalCharge(),
        })
    return atoms, bonds


def rocksalt_structure(cation: int, anion: int, a: float,
                       cation_charge: int, anion_charge: int) -> tuple[list[dict], list[dict]]:
    """A conventional rock-salt cell: cations on the FCC sites, anions offset by a/2."""
    fcc = [(0, 0, 0), (0.5, 0.5, 0), (0.5, 0, 0.5), (0, 0.5, 0.5)]
    sites: list[tuple[int, int, tuple[float, float, float]]] = []
    for element, charge, shift in ((cation, cation_charge, 0.0), (anion, anion_charge, 0.5)):
        for base in fcc:
            for i in (-1, 0, 1):
                for j in (-1, 0, 1):
                    for k in (-1, 0, 1):
                        f = (base[0] + shift + i, base[1] + j, base[2] + k)
                        f = (round(f[0], 6), round(f[1], 6), round(f[2], 6))
                        if all(-1e-6 <= c <= 1 + 1e-6 for c in f):
                            if not any(s[0] == element and s[2] == f for s in sites):
                                sites.append((element, charge, f))
    atoms = []
    for index, (element, charge, f) in enumerate(sites):
        atoms.append({
            "id": index, "atomicNumber": element,
            "x": round((f[0] - 0.5) * a, 3), "y": round((f[1] - 0.5) * a, 3), "z": round((f[2] - 0.5) * a, 3),
            "formalCharge": charge,
        })
    bonds = []
    for i, first in enumerate(atoms):
        for j in range(i + 1, len(atoms)):
            second = atoms[j]
            if first["atomicNumber"] == second["atomicNumber"]:
                continue
            d = math.dist((first["x"], first["y"], first["z"]), (second["x"], second["y"], second["z"]))
            if abs(d - a / 2) < 0.01:
                bonds.append({"id": len(bonds), "from": i, "to": j, "order": 1, "isContact": True})
    return atoms, bonds


def main() -> int:
    weights = atomic_weights()
    symbols = symbol_table()
    records = []
    seen_cids: set[int] = set()
    for index, entry in enumerate(COMPOUNDS):
        (cid, name, formula, iupac, smiles, bonding, tags, aliases, summary, kind) = entry
        if cid in seen_cids:
            raise SystemExit(f"duplicate CID {cid}")
        seen_cids.add(cid)

        mol = Chem.MolFromSmiles(smiles)
        if mol is None:
            raise SystemExit(f"{name}: RDKit could not parse {smiles}")
        with_h = Chem.AddHs(mol)
        counts: dict[str, int] = {}
        charge = 0
        for atom in with_h.GetAtoms():
            symbol = symbols[atom.GetAtomicNum()]
            counts[symbol] = counts.get(symbol, 0) + 1
            charge += atom.GetFormalCharge()
        hill = hill_formula(counts)
        expected = hill_formula(parse_formula(formula))
        if hill != expected:
            raise SystemExit(f"{name}: SMILES gives {hill} but the display formula {formula} is {expected}")
        if charge != 0:
            raise SystemExit(f"{name}: net charge {charge}; every bundled compound is neutral")

        structure = None
        if kind == "conformer":
            atoms, bonds = conformer_structure(smiles, seed=1000 + index)
            structure = {"is3D": True, "source": "computedConformer", "note": CONFORMER_NOTE,
                         "atoms": atoms, "bonds": bonds}
        elif kind == "ions":
            atoms, bonds = ions_structure(smiles, seed=1000 + index)
            structure = {"is3D": True, "source": "computedConformer", "note": IONS_NOTE,
                         "atoms": atoms, "bonds": bonds}
        elif kind.startswith("rocksalt:"):
            a = float(kind.split(":")[1])
            fragments = [Chem.MolFromSmiles(f).GetAtomWithIdx(0) for f in smiles.split(".")]
            cation = next(f for f in fragments if f.GetFormalCharge() > 0)
            anion = next(f for f in fragments if f.GetFormalCharge() < 0)
            atoms, bonds = rocksalt_structure(cation.GetAtomicNum(), anion.GetAtomicNum(), a,
                                              cation.GetFormalCharge(), anion.GetFormalCharge())
            structure = {"is3D": True, "source": "curatedLattice",
                         "note": f"{LATTICE_NOTE} a = {a} Å (CRC Handbook).",
                         "atoms": atoms, "bonds": bonds}
        elif kind == "none":
            structure = None
        else:
            raise SystemExit(f"{name}: unknown structure kind {kind}")

        records.append({
            "id": f"pubchem-{cid}",
            "pubChemCID": cid,
            "preferredName": name,
            "formula": formula,
            "hillFormula": hill,
            "iupacName": iupac,
            "molarMass": molar_mass(counts, weights),
            "canonicalSMILES": smiles,
            "charge": charge,
            "bondingClass": bonding,
            "tags": tags,
            "alternateNames": aliases,
            "summary": summary,
            "classificationSource": CLASSIFICATION_SOURCE,
            "dataSource": "curated",
            "isLocalCurated": True,
            "lastUpdated": TODAY,
            "structure": structure,
        })

    with open(OUT, "w", encoding="utf-8") as handle:
        json.dump(records, handle, indent=1, ensure_ascii=False)
        handle.write("\n")
    print(f"wrote {os.path.relpath(OUT, ROOT)}: {len(records)} compounds, "
          f"{sum(1 for r in records if r['structure'])} with structures")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
