# Element data sources and editorial decisions

`PeriodicPro/Data/elements.json` holds one record for each of the 118 confirmed
chemical elements. This document records where the numbers come from, which
conventions the app follows where sources legitimately disagree, and how the
file is regenerated and checked.

## Reference sources

| Field | Source |
| --- | --- |
| Symbols, names, atomic numbers | IUPAC, *Periodic Table of the Elements* (2022 release) |
| Standard atomic weights | IUPAC Commission on Isotopic Abundances and Atomic Weights, **Standard Atomic Weights 2021** (*Pure Appl. Chem.* 94(5), 573–600) |
| Mass numbers for elements with no stable isotope | Most stable / longest-lived known isotope, per the IUPAC 2021 table and the NUBASE2020 evaluation |
| Electron configurations | NIST Atomic Spectra Database, *Ground Levels and Ionization Energies for the Neutral Atoms* |
| Melting and boiling points, densities | CRC *Handbook of Chemistry and Physics*, 104th edition, and the Royal Society of Chemistry's *Periodic Table* |
| Electronegativity | Pauling scale, as tabulated by the Royal Society of Chemistry |
| Discovery years and discoverers | IUPAC element discovery records and the Royal Society of Chemistry element profiles |

These are all standard, publicly documented reference values. No dataset was
copied wholesale from a proprietary source; every record was assembled field by
field and then independently audited (see *How the file is produced* below).

## Conventions where sources disagree

Several choices below are genuine judgement calls. They are listed so that the
app's classification can be checked rather than guessed at.

**Element families.** The app uses ten families. The six universally agreed
metalloids — B, Si, Ge, As, Sb, Te — are classified as metalloids. Polonium is
grouped with the post-transition metals and astatine with the halogens; both are
sometimes shown as metalloids elsewhere. Elements 113–116 are shown as
post-transition metals and 117–118 as halogen and noble gas respectively, which
follows their group position; their actual chemistry is predicted, not measured.

**Group 3 and the f-block.** The membership of group 3 (La/Ac versus Lu/Lr) is
still formally unresolved by IUPAC. Rather than assert a contested answer, the
lanthanides (57–71) and actinides (89–103) carry **no** group number, and the
detail screen says so explicitly. All other elements have a group number equal
to their column, 1 through 18.

**Spelling.** US English throughout: Aluminum, Cesium, Sulfur. IUPAC's preferred
spellings are aluminium and caesium. `Tools/normalize_spelling.py` keeps the
prose consistent with the element names.

**Atomic mass.** Where IUPAC publishes a standard atomic weight, that value is
used and `atomicMassIsMassNumber` is `false`. Where an element has no stable
isotope and no standard weight, the whole-number mass of the most stable known
isotope is used and `atomicMassIsMassNumber` is `true`; the detail screen
footnotes this. Thorium, protactinium and uranium are radioactive but *do* have
standard atomic weights because they have a characteristic terrestrial isotopic
composition, so they keep their weighted values.

**Density units.** Stored in g/cm³ for every element, including gases (so
hydrogen is `0.00008988`). The detail screen converts gases to the conventional
g/L for display so the number stays readable.

**Temperatures.** Stored in kelvin. The detail screen shows kelvin and celsius
together. `null` means the value is genuinely unknown or predicted-only, which
is the case for most elements above fermium.

**Phase.** State of the pure element at 298.15 K and 1 atm. Only mercury and
bromine are liquid. Elements whose bulk state has never been established are
`unknown` rather than guessed.

**Elements 104–118.** Only a handful of atoms of each have ever been produced
and most live for milliseconds. Their properties are largely predicted. The
`about` text says so, and their "common uses" are honest — research and
accelerator chemistry, not invented commercial applications.

## Structure and diagrams

`structure` describes how the *pure element* exists, and drives the second
diagram on the detail screen:

| Value | Meaning | Examples |
| --- | --- | --- |
| `diatomic` | Two-atom molecule | H₂, N₂, O₂, F₂, Cl₂, Br₂, I₂ |
| `polyatomicMolecule` | Larger discrete molecule | P₄, S₈, Se₈ |
| `monatomicGas` | Separate atoms, no bonding | He, Ne, Ar, Kr, Xe, Rn |
| `covalentNetwork` | Extended covalent structure | B, C, Si, Ge, As, Sb, Te |
| `metallicLattice` | Metallic bonding | every metal |
| `atom` | Bulk form not established | Og |

The shell diagram on the detail screen is an **educational simplification**, and
is labelled as such in the app: rings stand for energy levels and how many
electrons occupy them. Electrons do not follow fixed circular paths. An atom is
never described as a molecule, and the elemental form is always shown separately
from the shell diagram.

## How the file is produced

```
Tools/backbone.py            # structural truth: Z, symbol, name, family, group,
                             # period, block, table coordinates — pure Python,
                             # self-checking, no external input
Tools/build_elements.py      # merges authored records onto the backbone
Tools/normalize_spelling.py  # US English pass
Tools/validate_elements.py   # the gate: run this before committing
```

The backbone always wins on structure, so an editing mistake in the authored
data can never move an element on the table or change its family.

Every record was authored, then audited twice — once against the numeric
reference values above, and once for scientific accuracy of the prose — before
being merged.

## Validation

`Tools/validate_elements.py` runs on every push (see `.github/workflows/ci.yml`)
and is mirrored by `PeriodicProTests/ElementDataTests.swift`, which runs in the
app's own test bundle. Between them they assert:

- exactly 118 elements, atomic numbers 1–118 with no gaps or duplicates
- unique symbols, unique names, unique table coordinates inside an 18-column grid
- family sizes match the expected partition and total 118
- group numbers equal the column, except on the f-block where they are absent
- shell electron counts sum to the atomic number and respect the 2n² capacity limit
- electron configurations parse, use a lighter noble-gas core, respect subshell
  capacities, and account for exactly Z electrons
- the twenty well-known configuration anomalies (Cr, Cu, Nb, Mo, Ru, Rh, Pd, Ag,
  La, Ce, Gd, Pt, Au, Ac, Th, Pa, U, Np, Cm, Lr) are preserved
- only Br and Hg are liquid; the eleven room-temperature gases are exactly right
- melting point ≤ boiling point, both in kelvin and physically plausible
- densities are in g/cm³ (a gas above 0.02 means someone stored g/L)
- electronegativity sits on the Pauling scale
- standard atomic weights rise with atomic number below bismuth, except at the
  three classic inversions Ar/K, Co/Ni and Te/I — which are asserted to *be*
  inversions
- every element has a tagline, 2–4 sentence description, memory hook, elemental
  form and 3–5 uses, each within its length budget
- every SF Symbol referenced by a "use" is on the app's allowlist
- prose contains no planetary-orbit language and no hype

## Corrections

If you find an error, please open an issue with the element, the field, the
value you expected and the reference you are using. Fix `elements.json`, run
`python3 Tools/validate_elements.py`, and add a regression assertion to
`PeriodicProTests/ElementDataTests.swift` if the mistake was a class of error
rather than a one-off typo.
