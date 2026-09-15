"""Authoritative structural backbone for the 118 confirmed chemical elements.

This file encodes only the facts that are structurally verifiable and
non-controversial: atomic number, IUPAC symbol, name (US English spellings),
period, group, block, category and the (x, y) coordinates used to lay the
element out on a standard 18-column periodic table.

Numeric/physical properties and editorial copy live in
`PeriodicPro/Data/elements.json` and are produced by `build_elements.py`.
"""

NAMES = [
    ("H", "Hydrogen"), ("He", "Helium"), ("Li", "Lithium"), ("Be", "Beryllium"),
    ("B", "Boron"), ("C", "Carbon"), ("N", "Nitrogen"), ("O", "Oxygen"),
    ("F", "Fluorine"), ("Ne", "Neon"), ("Na", "Sodium"), ("Mg", "Magnesium"),
    ("Al", "Aluminum"), ("Si", "Silicon"), ("P", "Phosphorus"), ("S", "Sulfur"),
    ("Cl", "Chlorine"), ("Ar", "Argon"), ("K", "Potassium"), ("Ca", "Calcium"),
    ("Sc", "Scandium"), ("Ti", "Titanium"), ("V", "Vanadium"), ("Cr", "Chromium"),
    ("Mn", "Manganese"), ("Fe", "Iron"), ("Co", "Cobalt"), ("Ni", "Nickel"),
    ("Cu", "Copper"), ("Zn", "Zinc"), ("Ga", "Gallium"), ("Ge", "Germanium"),
    ("As", "Arsenic"), ("Se", "Selenium"), ("Br", "Bromine"), ("Kr", "Krypton"),
    ("Rb", "Rubidium"), ("Sr", "Strontium"), ("Y", "Yttrium"), ("Zr", "Zirconium"),
    ("Nb", "Niobium"), ("Mo", "Molybdenum"), ("Tc", "Technetium"), ("Ru", "Ruthenium"),
    ("Rh", "Rhodium"), ("Pd", "Palladium"), ("Ag", "Silver"), ("Cd", "Cadmium"),
    ("In", "Indium"), ("Sn", "Tin"), ("Sb", "Antimony"), ("Te", "Tellurium"),
    ("I", "Iodine"), ("Xe", "Xenon"), ("Cs", "Cesium"), ("Ba", "Barium"),
    ("La", "Lanthanum"), ("Ce", "Cerium"), ("Pr", "Praseodymium"), ("Nd", "Neodymium"),
    ("Pm", "Promethium"), ("Sm", "Samarium"), ("Eu", "Europium"), ("Gd", "Gadolinium"),
    ("Tb", "Terbium"), ("Dy", "Dysprosium"), ("Ho", "Holmium"), ("Er", "Erbium"),
    ("Tm", "Thulium"), ("Yb", "Ytterbium"), ("Lu", "Lutetium"), ("Hf", "Hafnium"),
    ("Ta", "Tantalum"), ("W", "Tungsten"), ("Re", "Rhenium"), ("Os", "Osmium"),
    ("Ir", "Iridium"), ("Pt", "Platinum"), ("Au", "Gold"), ("Hg", "Mercury"),
    ("Tl", "Thallium"), ("Pb", "Lead"), ("Bi", "Bismuth"), ("Po", "Polonium"),
    ("At", "Astatine"), ("Rn", "Radon"), ("Fr", "Francium"), ("Ra", "Radium"),
    ("Ac", "Actinium"), ("Th", "Thorium"), ("Pa", "Protactinium"), ("U", "Uranium"),
    ("Np", "Neptunium"), ("Pu", "Plutonium"), ("Am", "Americium"), ("Cm", "Curium"),
    ("Bk", "Berkelium"), ("Cf", "Californium"), ("Es", "Einsteinium"), ("Fm", "Fermium"),
    ("Md", "Mendelevium"), ("No", "Nobelium"), ("Lr", "Lawrencium"),
    ("Rf", "Rutherfordium"), ("Db", "Dubnium"), ("Sg", "Seaborgium"), ("Bh", "Bohrium"),
    ("Hs", "Hassium"), ("Mt", "Meitnerium"), ("Ds", "Darmstadtium"),
    ("Rg", "Roentgenium"), ("Cn", "Copernicium"), ("Nh", "Nihonium"),
    ("Fl", "Flerovium"), ("Mc", "Moscovium"), ("Lv", "Livermorium"),
    ("Ts", "Tennessine"), ("Og", "Oganesson"),
]

assert len(NAMES) == 118, len(NAMES)


def _span(*ranges):
    out = set()
    for lo, hi in ranges:
        out.update(range(lo, hi + 1))
    return out


CATEGORY_MEMBERS = {
    "alkaliMetal": {3, 11, 19, 37, 55, 87},
    "alkalineEarthMetal": {4, 12, 20, 38, 56, 88},
    "transitionMetal": _span((21, 30), (39, 48), (72, 80), (104, 112)),
    "postTransitionMetal": {13, 31, 49, 50, 81, 82, 83, 84, 113, 114, 115, 116},
    "metalloid": {5, 14, 32, 33, 51, 52},
    "reactiveNonmetal": {1, 6, 7, 8, 15, 16, 34},
    "halogen": {9, 17, 35, 53, 85, 117},
    "nobleGas": {2, 10, 18, 36, 54, 86, 118},
    "lanthanide": _span((57, 71)),
    "actinide": _span((89, 103)),
}


def category_for(z):
    for name, members in CATEGORY_MEMBERS.items():
        if z in members:
            return name
    raise ValueError(f"no category for Z={z}")


# --- Table geometry ---------------------------------------------------------
# x: 1...18 columns. y: 1...7 main rows; 9 = lanthanide row, 10 = actinide row.

def position_for(z):
    if z == 1:
        return 1, 1
    if z == 2:
        return 18, 1
    if 3 <= z <= 4:
        return z - 2, 2
    if 5 <= z <= 10:
        return z + 8, 2
    if 11 <= z <= 12:
        return z - 10, 3
    if 13 <= z <= 18:
        return z, 3
    if 19 <= z <= 36:
        return z - 18, 4
    if 37 <= z <= 54:
        return z - 36, 5
    if 55 <= z <= 56:
        return z - 54, 6
    if 57 <= z <= 71:
        return z - 54, 9          # La(57) -> x=3 ... Lu(71) -> x=17
    if 72 <= z <= 86:
        return z - 68, 6          # Hf(72) -> x=4 ... Rn(86) -> x=18
    if 87 <= z <= 88:
        return z - 86, 7
    if 89 <= z <= 103:
        return z - 86, 10         # Ac(89) -> x=3 ... Lr(103) -> x=17
    if 104 <= z <= 118:
        return z - 100, 7         # Rf(104) -> x=4 ... Og(118) -> x=18
    raise ValueError(z)


def period_for(z):
    for period, hi in enumerate([2, 10, 18, 36, 54, 86, 118], start=1):
        if z <= hi:
            return period
    raise ValueError(z)


def group_for(z):
    """IUPAC group 1-18, or None for the f-block (lanthanides/actinides).

    The membership of group 3 is still disputed (La/Ac vs. Lu/Lr), so the
    f-block rows are deliberately left without a group number rather than
    asserting a contested answer.
    """
    if 57 <= z <= 71 or 89 <= z <= 103:
        return None
    x, _ = position_for(z)
    return x


def block_for(z):
    if 57 <= z <= 71 or 89 <= z <= 103:
        return "f"
    g = group_for(z)
    if z in (1, 2):
        return "s"
    if g in (1, 2):
        return "s"
    if 3 <= g <= 12:
        return "d"
    return "p"


def backbone():
    rows = []
    for index, (symbol, name) in enumerate(NAMES):
        z = index + 1
        x, y = position_for(z)
        rows.append({
            "atomicNumber": z,
            "symbol": symbol,
            "name": name,
            "category": category_for(z),
            "group": group_for(z),
            "period": period_for(z),
            "block": block_for(z),
            "gridX": x,
            "gridY": y,
        })
    return rows


if __name__ == "__main__":
    import json
    import sys

    rows = backbone()

    # --- self checks --------------------------------------------------------
    assert len({r["atomicNumber"] for r in rows}) == 118
    assert len({r["symbol"] for r in rows}) == 118
    assert len({r["name"] for r in rows}) == 118
    assert len({(r["gridX"], r["gridY"]) for r in rows}) == 118
    assert sum(len(v) for v in CATEGORY_MEMBERS.values()) == 118
    for r in rows:
        assert 1 <= r["gridX"] <= 18, r
        assert r["gridY"] in range(1, 8) or r["gridY"] in (9, 10), r
    print(json.dumps(rows, indent=2), file=sys.stdout)
