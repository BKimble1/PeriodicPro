#!/usr/bin/env python3
"""Normalises prose to US English.

The app ships US element names (Aluminum, Cesium, Sulfur), so the surrounding
copy has to match. This pass is explicit word-for-word rather than rule-based:
a blanket "-ise -> -ize" rule would happily wreck "precise" and "surprise".

    python3 Tools/normalize_spelling.py PeriodicPro/Data/elements.json [more files...]
"""
from __future__ import annotations

import re
import sys

REPLACEMENTS = {
    # -our -> -or
    "colour": "color", "colours": "colors", "coloured": "colored",
    "colourless": "colorless", "colourful": "colorful",
    "behaviour": "behavior", "behaviours": "behaviors",
    "favour": "favor", "favours": "favors", "favoured": "favored",
    "favourite": "favorite", "favourites": "favorites",
    "flavour": "flavor", "flavours": "flavors",
    "harbour": "harbor", "honour": "honor", "humour": "humor",
    "labour": "labor", "neighbour": "neighbor", "neighbouring": "neighboring",
    "odour": "odor", "odours": "odors", "odourless": "odorless",
    "rumour": "rumor", "savour": "savor", "splendour": "splendor",
    "vapour": "vapor", "vapours": "vapors", "vapourises": "vaporizes",
    "vigour": "vigor", "armour": "armor", "armoured": "armored",
    "endeavour": "endeavor", "parlour": "parlor", "valour": "valor",
    # -re -> -er
    "centre": "center", "centres": "centers", "centred": "centered",
    "fibre": "fiber", "fibres": "fibers", "fibreglass": "fiberglass",
    "litre": "liter", "litres": "liters",
    "metre": "meter", "metres": "meters",
    "kilometre": "kilometer", "kilometres": "kilometers",
    "centimetre": "centimeter", "centimetres": "centimeters",
    "millimetre": "millimeter", "millimetres": "millimeters",
    "micrometre": "micrometer", "micrometres": "micrometers",
    "nanometre": "nanometer", "nanometres": "nanometers",
    "picometre": "picometer", "picometres": "picometers",
    "theatre": "theater", "calibre": "caliber",
    "lustre": "luster", "lustrous": "lustrous", "sombre": "somber",
    "spectre": "specter", "sabre": "saber", "titre": "titer",
    "manoeuvre": "maneuver", "manoeuvres": "maneuvers",
    # -ise / -isation -> -ize / -ization (explicit list only)
    "organise": "organize", "organised": "organized", "organising": "organizing",
    "organisation": "organization", "organisations": "organizations",
    "recognise": "recognize", "recognised": "recognized", "recognising": "recognizing",
    "realise": "realize", "realised": "realized",
    "utilise": "utilize", "utilised": "utilized",
    "stabilise": "stabilize", "stabilised": "stabilized", "stabiliser": "stabilizer",
    "stabilisers": "stabilizers", "stabilising": "stabilizing",
    "standardise": "standardize", "standardised": "standardized",
    "sterilise": "sterilize", "sterilised": "sterilized",
    "vulcanise": "vulcanize", "vulcanised": "vulcanized",
    "galvanise": "galvanize", "galvanised": "galvanized", "galvanising": "galvanizing",
    "ionise": "ionize", "ionised": "ionized", "ionising": "ionizing",
    "ionisation": "ionization",
    "oxidise": "oxidize", "oxidised": "oxidized", "oxidising": "oxidizing",
    "oxidiser": "oxidizer", "oxidisers": "oxidizers",
    "polarise": "polarize", "polarised": "polarized", "polariser": "polarizer",
    "crystallise": "crystallize", "crystallised": "crystallized",
    "crystallisation": "crystallization",
    "catalyse": "catalyze", "catalysed": "catalyzed", "catalysing": "catalyzing",
    "analyse": "analyze", "analysed": "analyzed", "analysing": "analyzing",
    "paralyse": "paralyze", "paralysed": "paralyzed",
    "hydrolyse": "hydrolyze", "electrolyse": "electrolyze",
    "magnetise": "magnetize", "magnetised": "magnetized",
    "industrialise": "industrialize", "industrialised": "industrialized",
    "specialise": "specialize", "specialised": "specialized",
    "characterise": "characterize", "characterised": "characterized",
    "minimise": "minimize", "minimised": "minimized",
    "maximise": "maximize", "maximised": "maximized",
    "emphasise": "emphasize", "emphasised": "emphasized",
    "synthesise": "synthesize", "synthesised": "synthesized",
    "sensitise": "sensitize", "sensitised": "sensitized",
    "immunise": "immunize", "immunised": "immunized",
    "pasteurise": "pasteurize", "pasteurised": "pasteurized",
    "apologise": "apologize", "sterilisation": "sterilization",
    "hospitalised": "hospitalized", "prioritise": "prioritize",
    "summarise": "summarize", "summarised": "summarized",
    "normalise": "normalize", "normalised": "normalized", "normalising": "normalizing",
    "vaporise": "vaporize", "vaporised": "vaporized", "vaporising": "vaporizing",
    # doubled consonants
    "travelled": "traveled", "travelling": "traveling", "traveller": "travelers",
    "modelling": "modeling", "modelled": "modeled",
    "labelled": "labeled", "labelling": "labeling",
    "signalling": "signaling", "signalled": "signaled",
    "fuelled": "fueled", "fuelling": "fueling",
    "jewellery": "jewelry", "jeweller": "jeweler", "jewellers": "jewelers",
    "marvellous": "marvelous", "cancelled": "canceled", "cancelling": "canceling",
    "channelled": "channeled", "levelled": "leveled", "chiselled": "chiseled",
    # miscellaneous
    "programme": "program", "programmes": "programs",
    "ageing": "aging", "artefact": "artifact", "artefacts": "artifacts",
    "mould": "mold", "moulds": "molds", "moulded": "molded", "moulding": "molding",
    "smoulder": "smolder", "smouldering": "smoldering",
    "plough": "plow", "draught": "draft", "draughts": "drafts",
    "grey": "gray", "greyish": "grayish",
    "tyre": "tire", "tyres": "tires", "kerb": "curb",
    "aeroplane": "airplane", "aluminium": "aluminum",
    "caesium": "cesium", "sulphur": "sulfur", "sulphide": "sulfide",
    "sulphides": "sulfides", "sulphate": "sulfate", "sulphates": "sulfates",
    "sulphuric": "sulfuric", "sulphide": "sulfide",
    "haemoglobin": "hemoglobin", "haematite": "hematite", "anaemia": "anemia",
    "anaemic": "anemic", "oesophagus": "esophagus",
    "sceptical": "skeptical", "scepticism": "skepticism",
    "defence": "defense", "defences": "defenses", "offence": "offense",
    "practise": "practice", "practises": "practices", "practised": "practiced",
    "practising": "practicing",
    "licence": "license", "licences": "licenses",
    "enquiry": "inquiry", "enquiries": "inquiries",
    "whilst": "while", "storey": "story", "storeys": "stories",
    "catalogue": "catalog", "catalogues": "catalogs",
    "analogue": "analog", "analogues": "analogs",
    "cheque": "check", "gaol": "jail", "speciality": "specialty",
    "specialities": "specialties", "aluminised": "aluminized",
    "moustache": "mustache", "pyjamas": "pajamas",
}

PATTERN = re.compile(
    r"\b(" + "|".join(sorted(REPLACEMENTS, key=len, reverse=True)) + r")\b",
    re.IGNORECASE,
)


def match_case(source: str, replacement: str) -> str:
    if source.isupper():
        return replacement.upper()
    if source[:1].isupper():
        return replacement[:1].upper() + replacement[1:]
    return replacement


def normalize(text: str) -> str:
    return PATTERN.sub(lambda m: match_case(m.group(0), REPLACEMENTS[m.group(0).lower()]), text)


def main() -> int:
    if len(sys.argv) < 2:
        raise SystemExit(f"usage: {sys.argv[0]} <file> [file...]")

    changed_files = 0
    for path in sys.argv[1:]:
        with open(path, encoding="utf-8") as handle:
            original = handle.read()
        updated = normalize(original)
        if updated != original:
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(updated)
            changed = sum(1 for a, b in zip(original.split("\n"), updated.split("\n")) if a != b)
            print(f"{path}: normalized {changed} line(s)")
            changed_files += 1
    if changed_files == 0:
        print("Nothing to normalize.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
