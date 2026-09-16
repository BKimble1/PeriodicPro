# Compound data sources

Where every compound in `PeriodicPro/Data/compounds.json` comes from, how the
records were built, what the structures are, and what the app promises about
compounds it fetches at runtime.

## The bundled catalog

Fifty compounds ship inside the app. Each record carries:

| Field | Source |
| --- | --- |
| `pubChemCID`, `preferredName`, `iupacName`, `canonicalSMILES`, `charge` | The PubChem compound record for that CID. Names are PubChem's title and IUPAC name as of the authoring date. |
| `formula` | The conventional written formula (NaCl, H₂O); curated. |
| `hillFormula` | Hill order, as PubChem indexes it (ClNa, H2O); generated from the composition. |
| `molarMass` | Computed from the IUPAC 2021 standard atomic weights in `elements.json`, which `Tools/validate_compounds.py` re-checks. |
| `bondingClass`, `tags`, `classificationSource` | Curated, and applied only where the constituents make the class unambiguous. The `classificationSource` sentence says why. PubChem does not classify bonding, so runtime records are `unknown`. |
| `summary` | One curated sentence. Never copied from a third-party description. |
| `structure` | See below. |

The generator is `Tools/build_compounds.py`; the validator is
`Tools/validate_compounds.py`, which CI runs. The validator checks the count,
the expected compounds, the formula collisions the app depends on (ethanol and
dimethyl ether both answer to C₂H₆O), every molar mass against the element
weights, every structure's atom counts against its formula, and that no ionic
record carries a covalent bond.

## Structures

Three kinds, and every picture in the app says which it is.

- **Computed conformer** (`computedConformer`). A 3D geometry generated with
  RDKit (ETKDGv3 embedding, MMFF94 minimization) from the compound's SMILES.
  The connectivity and bond orders are real; the coordinates are a calculation,
  not a measurement, and the viewer's label says "Representative molecular
  structure". Planar molecules — water, carbon dioxide, ozone — come out
  planar, as they should.
- **Ions as a formula unit** (`computedConformer` with formal charges). Salts
  whose lattice is not generated (sodium hydroxide, calcium carbonate,
  ammonium chloride…) are drawn as their ions, each ion a computed conformer
  with its formal charge, with no bond drawn between the ions.
- **Representative unit cell** (`curatedLattice`). Rock-salt cells for NaCl,
  KCl, MgO and CaO from the tabulated cubic lattice parameters, with
  nearest-neighbor contacts marked as contacts and never as bonds.
- **No structure.** Silicon dioxide is a network solid: there is no molecule
  to draw, and the app says so rather than drawing one.

`PeriodicPro/Compounds/Models/CompoundStructureScene.swift` converts a record
into the same `StructureScene` the element explorer renders, so the preview on
the detail page, the builder's result card and the 3D explorer are one
picture.

## PubChem at runtime

The app talks to PubChem's PUG REST API directly over HTTPS, with no key and no
server of its own. Requests are user-driven and short:

- a name typed into the table's search field (after a pause, and never for a
  bare number or a one- or two-letter symbol);
- a Hill formula the learner built in the Compound Builder and asked to look
  up;
- one compound record by CID, when a page needs the full record.

Nothing else is sent. The client keeps requests at least 220 ms apart, retries
a busy or failed request at most twice with backoff, and never crawls.
Fetched records are cached on the device so a compound works offline after
its first lookup. Names, formulas and structures from PubChem are shown with
"Data source: PubChem" and the CID on the compound page.

A formula lookup returns **every** neutral compound with that exact formula.
Several compounds sharing a formula is the normal case, so the builder makes
the learner choose rather than picking the first hit. A formula that matches
nothing is reported as "No known PubChem match found" with the reminder that a
database miss is not evidence of a discovery; it can be kept only as a
*hypothetical composition*, which carries its formula and molar mass and
nothing invented.

## Test fixtures

`PeriodicProTests/Fixtures/` holds PubChem responses in the PUG REST JSON
shapes the client parses: property tables, identifier lists, 2D and 3D
records, and the Fault envelopes for not-found, busy and timeout. PubChem was
not reachable from the environment in which this beta was authored, so the
fixtures were generated from the bundled catalog by
`Tools/build_pubchem_fixtures.py` in PubChem's exact schema rather than
captured live. The unit tests run entirely against these fixtures through an
injected transport; no unit test touches the network.

## What is not claimed

- Bonding classes and acid/base/salt tags exist only for the bundled records
  that carry a stated basis.
- A computed conformer is not an experimental geometry.
- A unit cell is a representative cell from tabulated parameters, not a
  measured crystal.
- Absence from PubChem means absence from PubChem.

_Last updated for the compound beta._
