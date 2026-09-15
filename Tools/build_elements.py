#!/usr/bin/env python3
"""Merges the authored element records with the structural backbone and writes
PeriodicPro/Data/elements.json.

The backbone (atomic number, symbol, name, family, group, period, block and the
table coordinates) always wins: it is deterministic and independently checked,
so a stray edit in the authored data can never move an element on the table.

    python3 Tools/build_elements.py authored.json
"""
from __future__ import annotations

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from backbone import backbone  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_PATH = os.path.join(ROOT, "PeriodicPro", "Data", "elements.json")

AUTHORED_FIELDS = [
    "atomicMass", "atomicMassIsMassNumber", "electronConfiguration",
    "shellElectrons", "phase", "meltingPointK", "boilingPointK",
    "densityGramsPerCm3", "electronegativity", "discoveryYear", "discoveredBy",
    "tagline", "about", "memoryHook", "structure", "elementalForm", "uses",
]

# Field order in the emitted JSON, chosen to read top-down like the model.
FIELD_ORDER = [
    "atomicNumber", "symbol", "name", "category", "group", "period", "block",
    "gridX", "gridY",
] + AUTHORED_FIELDS


def extract_records(payload) -> list[dict]:
    """Accepts either a bare list, {"elements": [...]} or a task-output wrapper."""
    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict):
        if "elements" in payload:
            return payload["elements"]
        if "result" in payload:
            return extract_records(payload["result"])
    raise SystemExit("Could not find an element list in the input file")


def main() -> int:
    if len(sys.argv) < 2:
        raise SystemExit(f"usage: {sys.argv[0]} <authored.json>")

    with open(sys.argv[1], encoding="utf-8") as handle:
        authored = {record["atomicNumber"]: record
                    for record in extract_records(json.load(handle))}

    merged = []
    problems = []
    for row in backbone():
        z = row["atomicNumber"]
        record = authored.get(z)
        if record is None:
            problems.append(f"Z={z} ({row['symbol']}) has no authored record")
            continue
        if record.get("symbol") != row["symbol"]:
            problems.append(
                f"Z={z}: authored symbol {record.get('symbol')!r} != {row['symbol']!r}"
            )
        entry = dict(row)
        for field in AUTHORED_FIELDS:
            if field not in record:
                problems.append(f"{row['symbol']}: authored record is missing {field}")
            entry[field] = record.get(field)
        merged.append({key: entry[key] for key in FIELD_ORDER})

    if problems:
        for problem in problems:
            print(f"error: {problem}", file=sys.stderr)
        return 1

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as handle:
        json.dump(merged, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    print(f"wrote {len(merged)} elements to {os.path.relpath(OUT_PATH, ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
