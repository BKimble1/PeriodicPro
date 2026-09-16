# Element structure sources and assumptions

`PeriodicPro/Data/structures.json` holds one **structure profile** per element:
the representative physical form of the pure element at ordinary conditions,
its crystal system and lattice, the lattice parameters, the coordination
number, and whether that structure is experimentally established at all. It is
generated from the table in `Tools/build_structures.py`, validated by
`Tools/validate_structures.py` on every push and by
`PeriodicProTests/StructureProfileTests.swift` in the app's own test bundle,
and rendered by `StructureSceneBuilder`, which the element detail preview and
the 3D explorer both call with the same arguments.

This document records where every number comes from, which conventions were
chosen where the literature offers more than one, and every simplification the
renderer makes. **Nothing shown in the app is a photograph or a measurement of
a particular sample.** Every scene carries one of these labels:

| Label | Meaning |
| --- | --- |
| Representative crystal unit cell | A conventional unit cell drawn whole, from the cited lattice parameters |
| Representative crystal fragment | A finite fragment of an infinite structure (a chain, a layer, one icosahedron) |
| Simplified crystal fragment | A close-packed stand-in for a cell too complex to draw (α-Mn, α-Pu, Sm, α-Np) |
| Representative molecular structure | One molecule, with real bond orders and geometry |
| Single atoms, no bonds | A noble gas |
| Representative liquid arrangement | Mercury or bromine: no lattice exists to draw |
| Simplified atomic model | Nucleus and electron shells; electrons are spread over a sphere, never on orbits |
| Bulk structure not established | Only individual atoms have ever been made; the app shows the atom and says so |

## Reference sources

| Data | Source |
| --- | --- |
| Crystal systems, space groups, lattice parameters of the metals and covalent solids | *CRC Handbook of Chemistry and Physics*, 104th ed. (2023), "Crystal Structures of the Elements" (room-temperature values, ångströms) |
| Structures of the awkward elements — gallium, white tin, α-uranium, α-neptunium, black phosphorus, iodine, sulfur, white phosphorus — and the atom positions in their cells | J. Donohue, *The Structures of the Elements* (Wiley, 1974); fractional coordinates as tabulated there and in Villars & Calvert, *Pearson's Handbook of Crystallographic Data* |
| Diatomic bond lengths and bond orders (H₂, N₂, O₂, F₂, Cl₂, Br₂, I₂) | K. P. Huber & G. Herzberg, *Constants of Diatomic Molecules*, via the NIST Chemistry WebBook |
| Which elements are liquid at 298 K, which are gases | Same as `DATA_SOURCES.md` (CRC; only Br and Hg are liquid) |
| The fact that no bulk sample exists for At, Fr and Z ≥ 100, and the predicted structures for them | IUPAC; the predictions are from relativistic calculations reported in the review literature and are stated in the app only as predictions |

## Conventions

**Room temperature, one atmosphere.** Every primary profile describes the
element at 298 K and 1 atm unless its `temperatureContext` says otherwise. The
one exception offered as an allotrope with a different context is γ-iron
(912–1394 °C), because the α → γ change is the whole story of steel and a
learner will meet it.

**The reference allotrope is the standard state, not the prettiest form.**
Carbon is graphite (its standard state), with diamond available on the picker.
Phosphorus is white P₄, the reference allotrope, with black phosphorus (the
stable one) available; red phosphorus is amorphous and cannot be drawn as a
structure, and the note says so. Tin is white β-tin, with gray α-tin available.
Sulfur is orthorhombic α-S₈. Selenium is the gray trigonal chain form. Arsenic,
antimony and bismuth are the rhombohedral A7 layered form.

**Close packing.** Face-centered cubic (A1), hexagonal close-packed (A3) and
double hexagonal close-packed (A3′, ABAC) are kept distinct: a lanthanum cell
is not a magnesium cell. Samarium's nine-layer rhombohedral stacking is drawn
as a twelve-coordinated fragment and labeled simplified, because the full
repeat is 26 Å tall and communicates nothing at phone size.

**Complex cells.** α-Manganese (58 atoms per cell), α-plutonium (16 atoms,
monoclinic), α-neptunium (8 atoms, two distinct sites) and β-rhombohedral boron
(105 atoms) are not drawn as cells. Manganese, plutonium and neptunium get a
close-packed fragment labeled "Simplified crystal fragment" with a note giving
the real atom count; boron gets one B₁₂ icosahedron, which is the real building
block of its network.

**What the struts mean.** In a metallic lattice the struts join nearest
neighbors and are marked `isDiscreteBond: false`; the inspector calls them
contacts and explains that a metal's electrons are shared across the whole
lattice. In diamond, graphite, the A7 layers, the selenium chains, P₄, S₈ and
I₂ the struts are real two-electron bonds and are marked as such. Gallium is
the interesting case: the cell is drawn with only the Ga₂ pair at 2.44 Å joined
(contact factor 1.03), because that pair is what makes gallium gallium, and the
six longer contacts would hide it.

**Contact factor.** For an explicit cell, every pair of atoms closer than
`contactFactor × (nearest-neighbor distance)` is joined. 1.06 draws exactly the
first coordination shell for the cubic and tetragonal metals; 1.10 for diamond;
1.03 for gallium; 1.05 for iodine, so only the intramolecular I–I bond appears.

**Coordination numbers** are the nearest-neighbor counts of the real
structure (12 for close packing, 8 for BCC, 6 for simple cubic, 4 for diamond,
3 for graphite and the A7 layers, 2 for chains and rings, 1 for a diatomic),
not counts of struts in the fragment drawn — a corner atom of a drawn cell
shows fewer struts than its coordination number, and the inspector reports
both separately.

**Colors.** Atoms carry the color of the element: the conventional CPK-style
colors for the molecular nonmetals, and for metals the color of the metal
itself — gold, copper, silver, the straw of cesium, the blue cast of osmium —
or a neutral steel where the metal has no color worth showing. Metallic scenes
are rendered with a metallic physically based material; structure, not color,
is what distinguishes gold from iron from magnesium.

## Simplifications, stated

- **Lattice parameters are rounded to three decimals** and are room-temperature
  values; thermal expansion and sample-to-sample variation are ignored.
- **Cells are drawn at unit scale.** The picture is normalized to fit the
  view; relative geometry within one scene (c/a ratios, the 4 + 2 neighbors of
  white tin, the buckling of α-uranium) is real, but nothing about the absolute
  size survives normalization.
- **Fragments are finite.** A graphite sheet, a selenium chain or an arsenic
  layer continues beyond the atoms shown. The caption says so, and the edge
  atoms of every fragment show fewer bonds than the interior ones.
- **Graphite's bonds are drawn single.** They are aromatic, of order about
  1.5; the app does not draw fractional orders. The layers are 3.35 Å apart
  and joined by nothing, which is drawn as nothing.
- **Liquids are a picture, not a model.** The mercury and bromine scenes are
  seeded random arrangements chosen to look like a liquid. They do not come
  from a simulation and claim nothing about the real radial distribution.
- **The noble-gas scene shows six atoms** to communicate "a gas of separate
  atoms"; the number is not meaningful.
- **The atom model** shows electrons at representative positions spread over
  a sphere for each shell, never on a ring, and a nucleus of at most 44 drawn
  nucleons with a note when it is a sample. It is labeled a simplification on
  every screen it appears.
- **Element 61 (promethium), 98 (californium) and 99 (einsteinium)** are
  established from milligram- or microgram-scale samples, in einsteinium's
  case from a single determination (Haire & Baybarz, 1979). The notes say so.

## What is *not* claimed

- No structure is claimed for astatine, francium or any element from fermium
  (100) to oganesson (118). Predicted structures are named in the source
  field as predictions and are not drawn.
- No pressure- or low-temperature phases are shown except the two allotropes
  offered on pickers (diamond, gray tin) and γ-iron, each with its temperature
  context stated.
- Amorphous forms (red phosphorus, amorphous boron, glassy selenium) are not
  drawn, because they have no structure to draw.

## Validation

`Tools/validate_structures.py` fails the build if any of the following is not
true; `StructureProfileTests.swift` asserts the same inside the app:

- exactly 118 entries, atomic numbers 1–118, no more;
- every entry is either experimentally established with a source, or explicitly
  `unknown` with a note containing "not established" — never a guessed lattice;
- the profile's phase agrees with `elements.json`;
- gold, copper and silver are FCC; iron BCC with γ-iron FCC as an allotrope;
  magnesium HCP; silicon and germanium diamond cubic; carbon graphite with
  diamond as an allotrope; nitrogen's bond order is 3 and oxygen's 2; the six
  noble gases are monatomic with no bonds; mercury and bromine are liquids;
  polonium is the only simple cubic element; every element from 100 up is
  unknown;
- every geometry template a profile names is one `StructureSceneBuilder`
  implements (`Tools/check_visual_routing.py`), so no profile can silently fall
  through to the atom model;
- lattice parameters lie between 1.5 and 30 Å and cell angles between 30° and
  150°; explicit bases are fractional; close-packed c/a ratios are plausible.

The Swift tests go further and check the geometry the generators produce: an
FCC cell has 14 atoms and a BCC cell 9, the HCP prism's central atom shows
twelve contacts, diamond's four interior atoms each show four bonds, graphite's
bonds never cross between layers, gallium's cell shows dimers, and the
detail-page preview and the explorer build identical scenes.

## Corrections

If a value here is wrong, change it in `Tools/build_structures.py`, regenerate
with `python3 Tools/build_structures.py`, run `python3 Tools/validate_structures.py`,
and add the reference to the table above.
