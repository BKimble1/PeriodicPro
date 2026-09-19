#!/usr/bin/env python3
"""Exercises the shared-quiz wire format outside Swift.

    python3 Tools/check_share_link.py

`QuizShareLink` is the one piece of Elemora that two different programs have to
agree about: the app writes the link, and — once a recipient installs the app —
the app reads it back, possibly a version later. `PeriodicProTests/SavedQuizTests.swift`
covers it properly, but those tests need macOS. This file re-implements the same
format from the Swift source's own rules so the format can be exercised anywhere,
including in a Linux CI job, and so a change to the Swift constants that is not
matched here fails loudly.

What it does NOT do: run Swift. It proves the format is self-consistent and that
every documented refusal fires. Whether Apple's `Data.compressed(using: .zlib)`
agrees byte-for-byte with Python's raw DEFLATE is asserted, not observed — it is
raw DEFLATE (RFC 1951) on both sides, with no zlib header and no Adler-32 — and
the Swift round-trip test is what actually proves it on a Mac.

The constants below are READ FROM THE SWIFT SOURCE rather than copied, so this
file cannot quietly drift away from the app.
"""

from __future__ import annotations

import base64
import json
import re
import sys
import zlib
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent.parent
SHARE_LINK = ROOT / "PeriodicPro" / "StudyEngine" / "QuizShareLink.swift"
CONFIGURATION = ROOT / "PeriodicPro" / "StudyEngine" / "QuizConfiguration.swift"
LINKS = ROOT / "PeriodicPro" / "Utilities" / "ElemoraLinks.swift"


# --------------------------------------------------------------- constants --

def swift_int(source: str, name: str) -> int:
    """`static let name = 1_600` -> 1600."""
    match = re.search(rf"static let {name}\s*=\s*([0-9_ *]+)", source)
    if not match:
        raise SystemExit(f"could not find {name} in the Swift source")
    return int(eval(match.group(1).replace("_", ""), {"__builtins__": {}}))  # noqa: S307


SHARE_SRC = SHARE_LINK.read_text()
CONFIG_SRC = CONFIGURATION.read_text()
LINKS_SRC = LINKS.read_text()

SCHEMA_VERSION = swift_int(SHARE_SRC, "schemaVersion")
MAX_ENCODED = swift_int(SHARE_SRC, "maximumEncodedLength")
MAX_DECODED = swift_int(SHARE_SRC, "maximumDecodedBytes")
MAX_CUSTOM = swift_int(CONFIG_SRC, "maximumCustomItems")
MIN_QUESTIONS = swift_int(CONFIG_SRC, "minimumQuestions")
MAX_QUESTIONS = swift_int(CONFIG_SRC, "maximumQuestions")
MAX_NAME = swift_int(ROOT.joinpath("PeriodicPro/StudyEngine/SavedQuiz.swift").read_text(),
                     "maximumNameLength")

MARKER = re.search(r'static let formatMarker: Character = "(.)"', SHARE_SRC).group(1)
HOST = re.search(r'static let host = "([^"]+)"', LINKS_SRC).group(1)
QUIZ_PREFIX = re.search(r'static let quizPathPrefix = "([^"]+)"', LINKS_SRC).group(1)
QUIZ_BASE = re.search(r'static let quizBaseString = "([^"]+)"', LINKS_SRC).group(1)
COMPOUND_RE = re.compile(re.search(r'id\.range\(of: "\^(.+?)\$"', SHARE_SRC).group(1).join("^$"))


class Refused(Exception):
    """Whatever `QuizLinkError` case the Swift decoder would have thrown."""

    def __init__(self, kind: str, detail: object = None):
        super().__init__(f"{kind}{'' if detail is None else f'({detail})'}")
        self.kind = kind
        self.detail = detail


# ----------------------------------------------------------------- the wire --

def b64url_encode(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def b64url_decode(text: str) -> bytes | None:
    if not text:
        return None
    padded = text + "=" * (-len(text) % 4)
    try:
        # Swift's Data(base64Encoded:) rejects anything outside the alphabet.
        return base64.b64decode(padded.replace("-", "+").replace("_", "/"), validate=True)
    except Exception:
        return None


def deflate(raw: bytes) -> bytes:
    """Apple's `.zlib` is raw DEFLATE: no 2-byte header, no Adler-32 trailer."""
    compressor = zlib.compressobj(5, zlib.DEFLATED, -zlib.MAX_WBITS)
    return compressor.compress(raw) + compressor.flush()


def inflate(raw: bytes) -> bytes:
    try:
        return zlib.decompress(raw, -zlib.MAX_WBITS)
    except zlib.error as error:
        raise Refused("notAQuiz", error) from error


def clean_name(raw: str, fallback: str = "Untitled quiz") -> str:
    one_line = raw.replace("\n", " ").strip()
    return one_line[:MAX_NAME] if one_line else fallback


def configuration(**overrides) -> dict:
    """The Swift defaults, as the synthesized encoder writes them."""
    base = {
        "content": "elements",
        "scope": "all",
        "elementFilters": {"categories": [], "phases": [], "periods": [], "groups": []},
        "compoundFilters": {"bondingClasses": [], "tags": [], "onlySaved": False},
        "customElementIDs": [],
        "customCompoundIDs": [],
        "difficulty": "mixed",
        "questionCount": 10,
        "shuffles": True,
        # timerSeconds is Optional, so `encodeIfPresent` omits it when nil.
    }
    base.update(overrides)
    return base


def sanitized(config: dict) -> dict:
    """`QuizConfiguration.sanitized()`, rule for rule."""
    out = json.loads(json.dumps(config))
    out["questionCount"] = min(max(out.get("questionCount", 10), MIN_QUESTIONS), MAX_QUESTIONS)
    out["customElementIDs"] = [n for n in out.get("customElementIDs", []) if 1 <= n <= 118][:MAX_CUSTOM]
    out["customCompoundIDs"] = out.get("customCompoundIDs", [])[:MAX_CUSTOM]
    if "timerSeconds" in out and out["timerSeconds"] is not None and not 5 <= out["timerSeconds"] <= 300:
        del out["timerSeconds"]
    filters = out.get("elementFilters", {})
    low, high = filters.get("minimumAtomicNumber"), filters.get("maximumAtomicNumber")
    if low is not None and high is not None and low > high:
        filters["minimumAtomicNumber"], filters["maximumAtomicNumber"] = high, low
    return out


def encode(name: str, config: dict) -> str:
    payload = {"v": SCHEMA_VERSION, "n": clean_name(name), "c": sanitized(config)}
    body = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    encoded = MARKER + b64url_encode(deflate(body))
    if len(encoded) > MAX_ENCODED:
        raise Refused("tooLarge")
    return encoded


def encode_unsanitized(name: str, config: dict) -> str:
    """A hostile link: skips the sender-side cleanup the app applies."""
    payload = {"v": SCHEMA_VERSION, "n": name, "c": config}
    body = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return MARKER + b64url_encode(deflate(body))


def decode(encoded: str, elements: range = range(1, 119)) -> dict:
    """`QuizShareLink.decode`, check for check and in the same order."""
    if len(encoded) > MAX_ENCODED:
        raise Refused("tooLarge")
    if not encoded:
        raise Refused("notAQuiz")
    marker = encoded[0]
    if marker != MARKER:
        if marker.isdigit() and int(marker) > SCHEMA_VERSION:
            raise Refused("unsupportedVersion", int(marker))
        raise Refused("notAQuiz")
    compressed = b64url_decode(encoded[1:])
    if compressed is None:
        raise Refused("notAQuiz")
    body = inflate(compressed)
    if len(body) > MAX_DECODED:
        raise Refused("tooLarge")
    try:
        payload = json.loads(body)
    except ValueError as error:
        raise Refused("notAQuiz", error) from error
    if not isinstance(payload, dict) or set(payload) != {"v", "n", "c"}:
        raise Refused("notAQuiz")
    if payload["v"] != SCHEMA_VERSION:
        raise Refused("unsupportedVersion", payload["v"])
    name = str(payload["n"]).strip()
    if not name:
        raise Refused("invalidName")
    config = payload["c"]
    if (len(config.get("customElementIDs", [])) > MAX_CUSTOM
            or len(config.get("customCompoundIDs", [])) > MAX_CUSTOM):
        raise Refused("tooManyItems")
    for number in config.get("customElementIDs", []):
        if number not in elements:
            raise Refused("unknownElement", number)
    for identifier in config.get("customCompoundIDs", []):
        if not COMPOUND_RE.match(identifier):
            raise Refused("invalidCompoundReference", identifier)
    return {"v": payload["v"], "n": clean_name(name), "c": sanitized(config)}


def quiz_payload(url: str) -> str | None:
    """`ElemoraLinks.quizPayload(from:)`, rule for rule."""
    parts = urlsplit(url)
    if parts.scheme.lower() != "https":
        return None
    if (parts.hostname or "").lower() != HOST:
        return None
    if not parts.path.startswith(QUIZ_PREFIX):
        return None
    payload = parts.path[len(QUIZ_PREFIX):]
    if not payload or "/" in payload:
        return None
    return payload


# --------------------------------------------------------------- the cases --

FAILURES: list[str] = []
CHECKS = 0


def check(label: str, condition: bool) -> None:
    global CHECKS
    CHECKS += 1
    if condition:
        print(f"  ok    {label}")
    else:
        FAILURES.append(label)
        print(f"  FAIL  {label}")


def refuses(label: str, kind: str, thunk) -> None:
    global CHECKS
    CHECKS += 1
    try:
        thunk()
    except Refused as error:
        if error.kind == kind:
            print(f"  ok    {label} -> {kind}")
            return
        FAILURES.append(f"{label}: refused with {error.kind}, expected {kind}")
        print(f"  FAIL  {label}: refused with {error.kind}, expected {kind}")
        return
    FAILURES.append(f"{label}: was accepted, expected {kind}")
    print(f"  FAIL  {label}: was accepted, expected {kind}")


def round_trip(label: str, name: str, config: dict) -> None:
    link = QUIZ_BASE + encode(name, config)
    payload = quiz_payload(link)
    check(f"{label}: the URL routes", payload is not None)
    decoded = decode(payload)
    check(f"{label}: the name survives", decoded["n"] == clean_name(name))
    check(f"{label}: the configuration survives exactly", decoded["c"] == sanitized(config))
    check(f"{label}: no quiz text is visible in the URL",
          "{" not in link and "customElementIDs" not in link
          and (len(name) < 4 or name.split()[0] not in link))


def main() -> int:
    print(f"wire format v{SCHEMA_VERSION}, marker {MARKER!r}, "
          f"<= {MAX_ENCODED} chars, <= {MAX_CUSTOM} custom items\n")

    print("round trips")
    round_trip("normal quiz", "Halogens", configuration())
    round_trip("custom quiz", "Water and salt", configuration(
        content="both", scope="custom",
        customElementIDs=[1, 8, 79], customCompoundIDs=["pubchem-962", "pubchem-5234"],
        difficulty="medium"))
    round_trip("elements only", "First twenty", configuration(
        content="elements", scope="custom", customElementIDs=list(range(1, 21))))
    round_trip("compounds only", "Acids", configuration(
        content="compounds", scope="custom",
        customCompoundIDs=["pubchem-962", "pubchem-1118", "pubchem-24261"],
        compoundFilters={"bondingClasses": ["ionic"], "tags": ["acid"], "onlySaved": False}))
    round_trip("filters and a timer", "Gases of period 2", configuration(
        elementFilters={"categories": ["nobleGas", "halogen"], "phases": ["gas"],
                        "periods": [2], "groups": [17, 18],
                        "minimumAtomicNumber": 1, "maximumAtomicNumber": 54},
        timerSeconds=30, difficulty="hard", questionCount=20, shuffles=False))
    round_trip("the largest quiz a learner can build", "A" * MAX_NAME, configuration(
        content="both", scope="custom", questionCount=MAX_QUESTIONS,
        customElementIDs=list(range(1, 119)),
        customCompoundIDs=[f"pubchem-{962 + n}" for n in range(MAX_CUSTOM)]))

    print("\nrefusals")
    good = encode("Halogens", configuration())
    refuses("an oversized quiz", "tooLarge", lambda: encode("A" * MAX_NAME, configuration(
        content="both", scope="custom", customElementIDs=list(range(1, 119)),
        customCompoundIDs=[f"pubchem-{100_000_000 + n * 4_177_777}" for n in range(MAX_CUSTOM)])))
    refuses("a payload past the length limit", "tooLarge",
            lambda: decode("A" * (MAX_ENCODED + 1)))
    refuses("an empty payload", "notAQuiz", lambda: decode(""))
    refuses("a payload that is not base64", "notAQuiz", lambda: decode("1not-a-payload!!"))
    refuses("base64 that is not deflated JSON", "notAQuiz",
            lambda: decode(MARKER + b64url_encode(b"hello")))
    refuses("a truncated payload", "notAQuiz", lambda: decode(good[: len(good) // 2]))
    refuses("a payload with its last character dropped", "notAQuiz",
            lambda: decode(good[:-1]))
    refuses("a newer schema version in the marker", "unsupportedVersion",
            lambda: decode("9" + good[1:]))
    refuses("a newer schema version inside the payload", "unsupportedVersion",
            lambda: decode(MARKER + b64url_encode(deflate(json.dumps(
                {"v": SCHEMA_VERSION + 1, "n": "x", "c": configuration()}).encode()))))
    refuses("a blank name", "invalidName",
            lambda: decode(encode_unsanitized("   ", configuration())))
    refuses("an element that does not exist", "unknownElement",
            lambda: decode(encode_unsanitized("x", configuration(customElementIDs=[200]))))
    refuses("a compound that is private to one device", "invalidCompoundReference",
            lambda: decode(encode_unsanitized("x", configuration(
                customCompoundIDs=["hypothetical-abc"]))))
    refuses("more items than a quiz can hold", "tooManyItems",
            lambda: decode(encode_unsanitized("x", configuration(
                customElementIDs=[1] * (MAX_CUSTOM + 1)))))

    print("\nURL routing")
    check("a real quiz link routes", quiz_payload(QUIZ_BASE + good) == good)
    for text in [
        f"https://{HOST}/",
        f"https://{HOST}/privacy",
        f"https://{HOST}/support",
        f"https://{HOST}/terms",
        f"https://{HOST}/quiz/",
        f"https://{HOST}/quiz/a/b",
        "https://example.com/quiz/1abc",
        f"https://evil.{HOST}.attacker.test/quiz/1abc",
        f"http://{HOST}/quiz/1abc",
        "elemora://quiz/1abc",
        f"https://{HOST}/.well-known/apple-app-site-association",
    ]:
        check(f"{text} is not a quiz link", quiz_payload(text) is None)

    print("\nwhat travels")
    link = encode("Halogens and noble gases", configuration(
        content="both", scope="custom", customElementIDs=[9, 17, 35],
        customCompoundIDs=["pubchem-962"]))
    body = inflate(b64url_decode(link[1:]))
    text = body.decode("utf-8").lower()
    check("the payload carries exactly v, n and c", set(json.loads(body)) == {"v", "n", "c"})
    for forbidden in ("favorite", "streak", "mastery", "device", "progress",
                      "answered", "uuid", "identifier"):
        check(f"{forbidden!r} never travels", forbidden not in text)

    print("\nrepeated imports")
    first = encode("Halogens", configuration())
    check("encoding is deterministic, so the same quiz is the same link",
          all(encode("Halogens", configuration()) == first for _ in range(5)))
    check("a different configuration is a different link",
          encode("Halogens", configuration(difficulty="hard")) != first)
    # Swift encodes a Set in whatever order it happens to hold, so two shares of
    # the same filtered quiz can be different strings. What has to hold is that
    # they decode to the same quiz -- that is what SavedQuizStore.save(shared:)
    # compares, and it is why forwarding a link twice cannot pile up copies.
    ordered = configuration(elementFilters={"categories": ["halogen", "nobleGas"],
                                            "phases": [], "periods": [], "groups": []})
    reversed_ = configuration(elementFilters={"categories": ["nobleGas", "halogen"],
                                              "phases": [], "periods": [], "groups": []})
    a, b = encode("Filtered", ordered), encode("Filtered", reversed_)
    check("a set written in a different order is still the same quiz",
          sorted(decode(a)["c"]["elementFilters"]["categories"])
          == sorted(decode(b)["c"]["elementFilters"]["categories"])
          and decode(a)["n"] == decode(b)["n"])

    print("\nthe website serves it")
    redirects = (ROOT / "website" / "site" / "_redirects").read_text()
    check("/quiz/* is rewritten with a 200",
          re.search(r"^/quiz/\*\s+/quiz/index\.html\s+200", redirects, re.MULTILINE) is not None)
    check("the landing page exists",
          (ROOT / "website" / "site" / "quiz" / "index.html").exists())
    longest = QUIZ_BASE + "1" * (MAX_ENCODED - 1)
    check(f"the longest possible link is {len(longest)} characters, under 2000",
          len(longest) < 2000)

    print(f"\n{CHECKS} checks, {len(FAILURES)} failure(s)")
    for failure in FAILURES:
        print(f"  {failure}")
    return 1 if FAILURES else 0


if __name__ == "__main__":
    raise SystemExit(main())
