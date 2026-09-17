#!/usr/bin/env python3
"""Asks the real PubChem the questions Elemora asks, and checks the answers.

The unit tests answer from fixtures, which is right: they must pass on a
machine with no network and must not depend on a public service being up. What
they cannot tell you is whether PubChem still answers the way this app expects
— whether an endpoint moved, a field was renamed, or a formula that used to
return eleven records now returns none.

This asks for real. It is not part of CI: it would make a green build depend
on somebody else's uptime, and a rate limit would make it flaky. Run it by
hand before a release, and after any change to PubChemClient.

    python3 Tools/smoke_pubchem.py
    python3 Tools/smoke_pubchem.py --verbose

Exit status is 0 when every check passed, 1 when a check failed, and 2 when
the network could not be reached at all — which is not the same thing as a
failure and is not reported as one.

Courtesy: PUG REST asks for no more than five requests a second. This sends
one at a time with a pause between, which is well inside that.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = "https://pubchem.ncbi.nlm.nih.gov/rest/pug"
AUTOCOMPLETE = "https://pubchem.ncbi.nlm.nih.gov/rest/autocomplete"
# PUG REST asks callers to identify themselves.
USER_AGENT = "Elemora-smoke-test/5.0 (+https://elemora.idlery.com)"
GAP_SECONDS = 0.25
TIMEOUT_SECONDS = 20

# Compounds whose identity is not going to change, with the facts Elemora
# shows about them. Molar masses are compared loosely: PubChem recomputes them
# when atomic weights are revised, and a third decimal place is not what this
# is testing.
KNOWN = [
    # (name, expected CID, Hill formula, molar mass, tolerance)
    ("water", 962, "H2O", 18.015, 0.05),
    ("ethanol", 702, "C2H6O", 46.07, 0.1),
    ("caffeine", 2519, "C8H10N4O2", 194.19, 0.1),
    ("aspirin", 2244, "C9H8O4", 180.16, 0.1),
    ("glucose", 5793, "C6H12O6", 180.16, 0.1),
    ("sodium chloride", 5234, "ClNa", 58.44, 0.1),
    ("sulfuric acid", 1118, "H2O4S", 98.08, 0.1),
    ("benzene", 241, "C6H6", 78.11, 0.1),
]

# Formulas that must return more than one compound, because that is the whole
# claim the builder makes: a formula is a composition, not a structure.
AMBIGUOUS_FORMULAS = [
    ("C2H6O", 2, ["ethanol", "dimethyl ether"]),
    ("C3H6O", 3, []),
    ("C6H12O6", 5, []),
]

failures: list[str] = []
checks = 0
verbose = False


def note(message: str) -> None:
    if verbose:
        print(f"    {message}")


def fetch(url: str) -> dict:
    """One GET, decoded. Raises urllib errors; 404 comes back as {}."""
    time.sleep(GAP_SECONDS)
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return {}
        raise


def check(label: str, condition: bool, detail: str = "") -> bool:
    global checks
    checks += 1
    if condition:
        print(f"  ok    {label}")
        return True
    print(f"  FAIL  {label}" + (f" — {detail}" if detail else ""))
    failures.append(label)
    return False


def escaped(term: str) -> str:
    return urllib.parse.quote(term, safe="")


def properties(cids: list[int]) -> list[dict]:
    listed = ",".join(str(cid) for cid in cids)
    url = (f"{BASE}/compound/cid/{listed}/property/"
           "MolecularFormula,MolecularWeight,IUPACName,Title,Charge/JSON")
    payload = fetch(url)
    return payload.get("PropertyTable", {}).get("Properties", [])


def check_names() -> None:
    print("\nName lookup — the endpoint the search field uses")
    for name, cid, formula, mass, tolerance in KNOWN:
        payload = fetch(f"{BASE}/compound/name/{escaped(name)}/cids/JSON")
        cids = payload.get("IdentifierList", {}).get("CID", [])
        if not check(f"{name!r} resolves to a CID", bool(cids), "no identifiers returned"):
            continue
        note(f"{name} -> {cids[:5]}")
        check(f"{name!r} is still CID {cid}", cids[0] == cid, f"got {cids[0]}")

        rows = properties([cids[0]])
        if not check(f"{name!r} has properties", bool(rows)):
            continue
        row = rows[0]
        check(f"{name!r} formula is {formula}", row.get("MolecularFormula") == formula,
              f"got {row.get('MolecularFormula')!r}")
        try:
            weight = float(row.get("MolecularWeight"))
        except (TypeError, ValueError):
            check(f"{name!r} molar mass is a number", False, repr(row.get("MolecularWeight")))
            continue
        check(f"{name!r} molar mass is {mass} ± {tolerance}", abs(weight - mass) <= tolerance,
              f"got {weight}")
        # Elemora shows Title as the compound's name; an empty one would give
        # a row reading "CID 962".
        check(f"{name!r} has a display title", bool(row.get("Title")),
              "PropertyTable row has no Title")


def check_formulas() -> None:
    print("\nFormula search — a formula is a composition, not a structure")
    for formula, minimum, expected_names in AMBIGUOUS_FORMULAS:
        payload = fetch(f"{BASE}/compound/fastformula/{escaped(formula)}/cids/JSON"
                        "?MaxRecords=250")
        cids = payload.get("IdentifierList", {}).get("CID", [])
        if not check(f"{formula} returns candidates", bool(cids)):
            continue
        note(f"{formula} -> {len(cids)} candidates")
        check(f"{formula} returns at least {minimum} compounds", len(cids) >= minimum,
              f"got {len(cids)}")

        rows = properties(cids[:40])
        titles = {(row.get("Title") or "").lower() for row in rows}
        for wanted in expected_names:
            check(f"{formula} includes {wanted!r}",
                  any(wanted in title for title in titles),
                  f"first 40 titles did not contain it")
        # Every row the app shows must actually have the formula asked for;
        # the index is broader than an exact match.
        exact = [row for row in rows if row.get("MolecularFormula") == formula]
        check(f"{formula} yields exact-formula rows to rank", bool(exact),
              "no row in the first batch had this exact formula")


def check_autocomplete() -> None:
    print("\nAuto-complete — terms offered while the learner is typing")
    payload = fetch(f"{AUTOCOMPLETE}/compound/{escaped('caffe')}/JSON?limit=12")
    terms = payload.get("dictionary_terms", {}).get("compound", [])
    check("a prefix returns suggestions", bool(terms), "no terms returned")
    note(f"caffe -> {terms[:5]}")
    check("'caffeine' is among them",
          any("caffeine" in term.lower() for term in terms), f"got {terms[:5]}")


def check_structures() -> None:
    print("\nStructures — 3D where it exists, honest 2D where it does not")
    # Caffeine has a computed conformer.
    payload = fetch(f"{BASE}/compound/cid/2519/JSON?record_type=3d")
    compounds = payload.get("PC_Compounds", [])
    if check("caffeine has a 3D record", bool(compounds)):
        conformers = compounds[0].get("coords", [{}])[0].get("conformers", [{}])[0]
        check("the 3D record carries z coordinates", "z" in conformers,
              "no z array, so this is a 2D depiction wearing a 3D label")
        atoms = compounds[0].get("atoms", {}).get("aid", [])
        check("caffeine has 24 atoms", len(atoms) == 24, f"got {len(atoms)}")

    # Sodium chloride is a lattice; PubChem's record is a two-ion pair, which
    # is why Elemora renders it from its own structure profile instead.
    payload = fetch(f"{BASE}/compound/cid/5234/JSON")
    compounds = payload.get("PC_Compounds", [])
    if check("sodium chloride has a 2D record", bool(compounds)):
        atoms = compounds[0].get("atoms", {}).get("aid", [])
        check("the record is the ion pair, not a lattice", len(atoms) == 2,
              f"got {len(atoms)} atoms")


def check_identifiers() -> None:
    print("\nStructure identifiers — what the scanner reads off a page")
    key = "RYYVLZVUVIJVGH-UHFFFAOYSA-N"          # caffeine
    payload = fetch(f"{BASE}/compound/inchikey/{escaped(key)}/cids/JSON")
    cids = payload.get("IdentifierList", {}).get("CID", [])
    check("an InChIKey resolves", bool(cids) and cids[0] == 2519,
          f"got {cids[:3]}")

    smiles = "CC(=O)OC1=CC=CC=C1C(=O)O"          # aspirin
    payload = fetch(f"{BASE}/compound/smiles/{escaped(smiles)}/cids/JSON")
    cids = payload.get("IdentifierList", {}).get("CID", [])
    check("a SMILES string resolves", bool(cids) and cids[0] == 2244,
          f"got {cids[:3]}")


def check_absence() -> None:
    print("\nAbsence — a database miss is a miss, not a discovery")
    # A formula no compound has. PubChem answers 404, which the app must read
    # as "not found" rather than as an error, and must never present as a new
    # substance.
    payload = fetch(f"{BASE}/compound/fastformula/{escaped('C2H400')}/cids/JSON")
    check("an impossible formula returns nothing", not payload.get("IdentifierList"),
          f"got {payload}")
    payload = fetch(f"{BASE}/compound/name/{escaped('zzqqxxnotacompound')}/cids/JSON")
    check("a nonsense name returns nothing", not payload.get("IdentifierList"),
          f"got {payload}")


def main() -> int:
    global verbose
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verbose", action="store_true", help="print what came back")
    verbose = parser.parse_args().verbose

    print("Asking PubChem the questions Elemora asks.")
    print(f"  {BASE}")
    try:
        for section in (check_names, check_formulas, check_autocomplete,
                        check_structures, check_identifiers, check_absence):
            section()
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        print(f"\nPubChem could not be reached: {error}")
        print("This is not a test failure — it is an unanswered question.")
        return 2

    print()
    if failures:
        print(f"{len(failures)} of {checks} checks failed:")
        for failure in failures:
            print(f"  - {failure}")
        return 1
    print(f"All {checks} checks passed against the live service.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
