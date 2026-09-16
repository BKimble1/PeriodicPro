#!/usr/bin/env python3
"""Writes PubChem PUG REST-shaped fixtures for the parser tests.

The unit tests never touch the network. These files have the exact JSON shape
PubChem's PUG REST service returns — the PropertyTable, IdentifierList,
PC_Compounds record and Fault envelopes — populated from the bundled catalog
so the numbers inside are real. They are synthetic in one respect: they were
written from the documented schema rather than captured from the live service,
which was not reachable from the machine that authored them. COMPOUND_SOURCES.md
says so too. If a live capture ever disagrees with a shape here, the capture
wins; update the fixture and the parser together.

    python3 Tools/build_pubchem_fixtures.py
"""
from __future__ import annotations

import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "PeriodicPro", "Data", "compounds.json")
OUT = os.path.join(ROOT, "PeriodicProTests", "Fixtures")


def property_row(record: dict) -> dict:
    return {
        "CID": record["pubChemCID"],
        "MolecularFormula": record["hillFormula"],
        # PUG REST returns MolecularWeight as a string.
        "MolecularWeight": f"{record['molarMass']:.2f}",
        "IUPACName": record["iupacName"],
        "Title": record["preferredName"],
        "Charge": record["charge"],
    }


def property_table(records: list[dict]) -> dict:
    return {"PropertyTable": {"Properties": [property_row(r) for r in records]}}


def identifier_list(cids: list[int]) -> dict:
    return {"IdentifierList": {"CID": cids}}


def compound_record(record: dict, three_d: bool) -> dict:
    structure = record["structure"]
    atoms = structure["atoms"]
    bonds = structure["bonds"]
    aids = [a["id"] + 1 for a in atoms]
    body = {
        "id": {"id": {"cid": record["pubChemCID"]}},
        "atoms": {"aid": aids, "element": [a["atomicNumber"] for a in atoms]},
        "charge": record["charge"],
        "props": [
            {"urn": {"label": "IUPAC Name", "name": "Preferred"}, "value": {"sval": record["iupacName"]}},
            {"urn": {"label": "Molecular Formula"}, "value": {"sval": record["hillFormula"]}},
        ],
    }
    charges = [{"aid": a["id"] + 1, "value": a["formalCharge"]} for a in atoms if a["formalCharge"]]
    if charges:
        body["atoms"]["charge"] = charges
    if bonds:
        body["bonds"] = {
            "aid1": [b["from"] + 1 for b in bonds],
            "aid2": [b["to"] + 1 for b in bonds],
            "order": [b["order"] for b in bonds],
        }
    conformer = {"x": [a["x"] for a in atoms], "y": [a["y"] for a in atoms]}
    coord_types = [1, 5] if not three_d else [2, 5, 10]
    if three_d:
        conformer["z"] = [a["z"] for a in atoms]
        conformer["data"] = [{"urn": {"label": "Conformer", "name": "ID"}, "value": {"sval": "0000000000000001"}}]
    body["coords"] = [{"type": coord_types, "aid": aids, "conformers": [conformer]}]
    return {"PC_Compounds": [body]}


def fault(code: str, message: str, details: list[str]) -> dict:
    return {"Fault": {"Code": code, "Message": message, "Details": details}}


def main() -> int:
    records = {r["preferredName"]: r for r in json.load(open(CATALOG, encoding="utf-8"))}
    os.makedirs(OUT, exist_ok=True)
    files = {
        "pubchem-name-water-properties.json": property_table([records["Water"]]),
        "pubchem-name-water-cids.json": identifier_list([962]),
        "pubchem-cid-962-3d.json": compound_record(records["Water"], True),
        "pubchem-cid-280-3d.json": compound_record(records["Carbon dioxide"], True),
        "pubchem-cid-702-3d.json": compound_record(records["Ethanol"], True),
        "pubchem-cid-8254-3d.json": compound_record(records["Dimethyl ether"], True),
        "pubchem-cid-2519-3d.json": compound_record(records["Caffeine"], True),
        # Sodium chloride has no conformer in PubChem: the 3D request faults
        # and the 2D record is what a client gets.
        "pubchem-cid-5234-2d.json": compound_record(records["Sodium chloride"], False),
        "pubchem-formula-C2H6O-cids.json": identifier_list([702, 8254]),
        "pubchem-cids-702-8254-properties.json": property_table([records["Ethanol"], records["Dimethyl ether"]]),
        "pubchem-formula-ClNa-cids.json": identifier_list([5234]),
        "pubchem-cids-5234-properties.json": property_table([records["Sodium chloride"]]),
        "pubchem-cids-2519-properties.json": property_table([records["Caffeine"]]),
        "pubchem-fault-notfound.json": fault(
            "PUGREST.NotFound", "No CID found", ["No CID found that matches the given name"]),
        "pubchem-fault-no-3d.json": fault(
            "PUGREST.NotFound", "Record not found",
            ["No 3D conformer information available for the requested record"]),
        "pubchem-fault-busy.json": fault(
            "PUGREST.ServerBusy", "Too many requests or server too busy", ["Please retry later"]),
        "pubchem-fault-timeout.json": fault(
            "PUGREST.Timeout", "Request timed out", ["Try a more specific query"]),
        # A record with atoms but neither bonds nor coordinates: legal for a
        # single atom, and the parser has to cope rather than crash.
        "pubchem-cid-missing-fields.json": {"PC_Compounds": [{
            "id": {"id": {"cid": 5462222}}, "atoms": {"aid": [1], "element": [18]}, "charge": 0}]},
    }
    for name, payload in files.items():
        with open(os.path.join(OUT, name), "w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=1)
            handle.write("\n")
    # Cut mid-record, which is what a dropped connection produces.
    full = json.dumps(compound_record(records["Water"], True))
    with open(os.path.join(OUT, "pubchem-malformed.json"), "w", encoding="utf-8") as handle:
        handle.write(full[: len(full) // 2])
    print(f"wrote {len(files) + 1} fixtures to {os.path.relpath(OUT, ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
