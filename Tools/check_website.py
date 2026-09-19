#!/usr/bin/env python3
"""Checks the Elemora website against what the app actually links to.

The app and the site are two halves of one thing: `ElemoraLinks` in the app
names four destinations and a quiz base, Settings and the paywall open them,
and the App Store listing points at two of them. A path that exists in one half
and not the other is a dead legal link, which is a review rejection rather than
a visual bug — so this asserts that every address the app ships resolves to a
file in `website/site`, and that the Universal Link plumbing is the shape iOS
requires.

It also holds the site to the promise its own privacy policy makes: no
cookies, no analytics, and nothing loaded from a third-party domain.

    python3 Tools/check_website.py
"""
from __future__ import annotations

import io
import os
import re
import struct
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SITE = os.path.join(ROOT, "website", "site")
LINKS = os.path.join(ROOT, "PeriodicPro", "Utilities", "ElemoraLinks.swift")

HOST = "elemora.idlery.com"
BUNDLE_ID = "com.idlery.periodicpro"
CARD = "assets/img/og-quiz.png"
STYLESHEET = "assets/css/site.css"

# The pages the app links to, and the file each one must be served from.
REQUIRED_PAGES = {
    "": "index.html",
    "/privacy": "privacy/index.html",
    "/terms": "terms/index.html",
    "/support": "support/index.html",
}

# Hosts an <a href> may point at. Anything else in a page — a script, a style,
# a font, an image — must be same-origin, which is the whole of "no third
# parties" as a rule a checker can enforce.
ALLOWED_LINK_HOSTS = {
    HOST,
    "idlery.com",             # the publisher
    "pubchem.ncbi.nlm.nih.gov",   # the compound lookups the policy discloses
    "apps.apple.com",         # the listing, and subscription management
    "reportaproblem.apple.com",
    "www.apple.com",
    "www.nlm.nih.gov",
}

# The one <script> the site is allowed: JSON-LD is data a crawler reads, not
# code a browser runs, and `_headers` sets script-src 'none' over the whole
# site so nothing on the page can execute either way.
LD_JSON = '<script type="application/ld+json">'

RESOURCE_ATTRIBUTE = re.compile(
    r"""<(?:script|link|img|iframe|source|video|audio|embed|object)\b[^>]*?"""
    r"""\b(?:src|href|data)\s*=\s*["']([^"']+)["']""",
    re.IGNORECASE | re.DOTALL,
)
ANCHOR = re.compile(r"""<a\b[^>]*?\bhref\s*=\s*["']([^"']+)["']""", re.IGNORECASE | re.DOTALL)
META = re.compile(
    r"""<meta\b[^>]*?\bproperty\s*=\s*["']([^"']+)["'][^>]*?\bcontent\s*=\s*["']([^"']*)["']""",
    re.IGNORECASE | re.DOTALL,
)
STYLESHEET_URL = re.compile(r"url\(\s*['\"]?([^'\")]+)")
SRCSET = re.compile(r"""\bsrcset\s*=\s*["']([^"']+)["']""", re.IGNORECASE)


def read(path: str) -> str:
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def png_size(path: str) -> tuple[int, int]:
    with open(path, "rb") as handle:
        header = handle.read(24)
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    width, height = struct.unpack(">II", header[16:24])
    return width, height


def html_files() -> list[str]:
    found = []
    for base, _, names in os.walk(SITE):
        for name in names:
            if name.endswith(".html"):
                found.append(os.path.relpath(os.path.join(base, name), SITE))
    return sorted(found)


def check_links_agree(errors: list[str]) -> None:
    """Every address in ElemoraLinks.swift is served by a file in the site."""
    source = read(LINKS)
    declared = dict(re.findall(r'static let (\w+String) = "([^"]+)"', source))
    expected = {
        "websiteString": f"https://{HOST}",
        "privacyString": f"https://{HOST}/privacy",
        "termsString": f"https://{HOST}/terms",
        "supportString": f"https://{HOST}/support",
        "quizBaseString": f"https://{HOST}/quiz/",
    }
    for name, value in expected.items():
        if declared.get(name) != value:
            errors.append(
                f"ElemoraLinks.{name} is {declared.get(name)!r}, expected {value!r}"
            )
    if f'static let host = "{HOST}"' not in source:
        errors.append(f"ElemoraLinks.host is not {HOST!r}")
    if 'static let supportEmailAddress = "support@idlery.com"' not in source:
        errors.append("ElemoraLinks.supportEmailAddress is not support@idlery.com")

    for path, file in REQUIRED_PAGES.items():
        full = os.path.join(SITE, file)
        if not os.path.exists(full):
            errors.append(f"https://{HOST}{path} has no file at website/site/{file}")

    if not os.path.exists(os.path.join(SITE, "quiz", "index.html")):
        errors.append("the shared-quiz landing page website/site/quiz/index.html is missing")


def check_universal_links(errors: list[str]) -> None:
    template = os.path.join(SITE, ".well-known", "apple-app-site-association.template")
    if not os.path.exists(template):
        errors.append("the apple-app-site-association template is missing")
        return
    text = read(template)
    if "__APPLE_TEAM_ID__" not in text:
        errors.append(
            "the association template has no __APPLE_TEAM_ID__ placeholder — a Team ID "
            "must never be committed"
        )
    if re.search(r"\b[A-Z0-9]{10}\.com\.idlery", text):
        errors.append("the association template appears to contain a real Team ID")
    if f".{BUNDLE_ID}" not in text:
        errors.append(f"the association file does not name {BUNDLE_ID}")
    if '"/": "/quiz/*"' not in text:
        errors.append("the association file should match /quiz/* and nothing else")
    for path in ("/privacy", "/terms", "/support"):
        if f'"{path}' in text:
            errors.append(f"{path} must not be an app link; it belongs in a browser")

    generated = os.path.join(SITE, ".well-known", "apple-app-site-association")
    if os.path.exists(generated):
        # Generated at package time by website/scripts/build_aasa.py and
        # git-ignored. If a working copy has one, it must be the real thing.
        text = read(generated)
        if "__APPLE_TEAM_ID__" in text:
            errors.append("the generated association file still holds the placeholder")
        elif not re.search(r'"[A-Z0-9]{10}\.' + re.escape(BUNDLE_ID) + r'"', text):
            errors.append(
                f"the generated association file does not name <TeamID>.{BUNDLE_ID}"
            )

    headers = os.path.join(SITE, "_headers")
    if not os.path.exists(headers):
        errors.append("website/site/_headers is missing")
    else:
        text = read(headers)
        if "/.well-known/apple-app-site-association" not in text:
            errors.append("_headers does not set a type for the association file")
        elif "Content-Type: application/json" not in text:
            errors.append("the association file must be served as application/json")

    redirects = os.path.join(SITE, "_redirects")
    if not os.path.exists(redirects):
        errors.append("website/site/_redirects is missing")
    else:
        rules = read(redirects)
        if not re.search(r"^/quiz/\*\s+\S+\s+200", rules, re.MULTILINE):
            errors.append(
                "/quiz/* must be rewritten to the landing page with a 200, not redirected"
            )
        for line in rules.splitlines():
            line = line.strip()
            if line.startswith("/quiz") and not line.startswith("/quiz/*"):
                errors.append(f"an extra /quiz rule would compete with the rewrite: {line}")
            if line.startswith("/.well-known"):
                errors.append(
                    f"the association endpoint must not be redirected: {line}"
                )

    entitlements = os.path.join(ROOT, "Config", "Elemora.entitlements")
    if not os.path.exists(entitlements):
        errors.append("Config/Elemora.entitlements is missing")
    elif f"applinks:{HOST}" not in read(entitlements):
        errors.append(f"the app does not claim applinks:{HOST}")


def check_share_card(errors: list[str]) -> None:
    card = os.path.join(SITE, CARD)
    if not os.path.exists(card):
        errors.append(f"the link-preview image website/site/{CARD} is missing")
        return
    try:
        width, height = png_size(card)
    except (OSError, ValueError) as error:
        errors.append(f"{CARD} could not be read as a PNG: {error}")
        return
    if (width, height) != (1200, 630):
        errors.append(f"{CARD} is {width}x{height}; link previews want 1200x630")
    if os.path.getsize(card) > 500 * 1024:
        errors.append(f"{CARD} is over 500 KB, which is slow for a preview fetch")


def check_pages(errors: list[str]) -> None:
    files = html_files()
    if not files:
        errors.append("no HTML pages in website/site")
        return
    for file in files:
        text = read(os.path.join(SITE, file))
        where = f"website/site/{file}"

        if "<title>" not in text:
            errors.append(f"{where} has no <title>")
        if 'name="viewport"' not in text:
            errors.append(f"{where} has no viewport meta, so it is unreadable on a phone")
        if 'name="color-scheme"' not in text:
            errors.append(f"{where} does not declare a color scheme, so dark mode is a guess")

        # Open Graph, so a shared link is a card rather than a bare URL.
        properties = dict(META.findall(text))
        if file != "404.html":
            for key in ("og:title", "og:description", "og:url", "og:image"):
                if not properties.get(key):
                    errors.append(f"{where} is missing {key}")
            image = properties.get("og:image", "")
            if image and not image.startswith(f"https://{HOST}/"):
                errors.append(f"{where} og:image must be an absolute URL on {HOST}")

        # No third-party resources anywhere, which is what the privacy policy
        # on this very site promises.
        references = RESOURCE_ATTRIBUTE.findall(text)
        for candidates in SRCSET.findall(text):
            references += [part.strip().split()[0]
                           for part in candidates.split(",") if part.strip()]
        for reference in references:
            if reference.startswith(("/", "#", "data:")):
                continue
            if reference.startswith(f"https://{HOST}/"):
                continue
            errors.append(f"{where} loads {reference} from outside the site")

        for href in ANCHOR.findall(text):
            if href.startswith(("/", "#", "mailto:")):
                continue
            match = re.match(r"https?://([^/]+)", href)
            if not match:
                errors.append(f"{where} links to {href!r}, which is neither relative nor https")
            elif match.group(1) not in ALLOWED_LINK_HOSTS:
                errors.append(f"{where} links to an unexpected host: {href}")

        # Analytics and cookies, by their mechanics rather than by the word:
        # the privacy page has to be allowed to *say* "cookie".
        for banned in ("googletagmanager", "google-analytics", "gtag(", "fbq(",
                       "document.cookie", "onclick=", "javascript:"):
            if banned in text.lower():
                errors.append(f"{where} contains {banned!r}; this site runs no scripts "
                              "and sets no cookies")
        # JSON-LD is the only <script> allowed, and it may not carry code.
        for opening in re.findall(r"<script\b[^>]*>", text, re.IGNORECASE):
            if opening != LD_JSON:
                errors.append(f"{where} contains {opening}; the only script this site "
                              "may carry is JSON-LD, which is data rather than code")

    stylesheet = os.path.join(SITE, STYLESHEET)
    if not os.path.exists(stylesheet):
        errors.append(f"website/site/{STYLESHEET} is missing")
    else:
        for reference in STYLESHEET_URL.findall(read(stylesheet)):
            if not reference.startswith(("/", "data:")):
                errors.append(f"{STYLESHEET} loads {reference} from outside the site")


def check_committed_zip(errors: list[str]) -> None:
    """The committed deployment ZIP must not smuggle in the Team ID.

    `website/site/.well-known/apple-app-site-association` is git-ignored and
    generated at package time, so the source tree never carries a signing
    identifier. A ZIP is a binary, and `git diff` shows nothing useful about
    one — which makes it exactly the place a Team ID would slip in unnoticed.

    This reads what is *committed* rather than what is on disk, so building
    the real ZIP to deploy it is fine; committing that build is not.
    """
    import subprocess

    try:
        blob = subprocess.run(
            ["git", "show", "HEAD:elemora-netlify.zip"],
            cwd=ROOT, capture_output=True, check=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError):
        return                       # no git, or no committed ZIP: nothing to say

    try:
        with zipfile.ZipFile(io.BytesIO(blob)) as archive:
            names = archive.namelist()
    except zipfile.BadZipFile as error:
        errors.append(f"the committed elemora-netlify.zip is not a ZIP: {error}")
        return

    for name in names:
        if name.endswith("apple-app-site-association"):
            errors.append(
                "the committed elemora-netlify.zip contains "
                f"{name}, which carries the Apple Team ID. Build it with "
                "--without-universal-links before committing; see website/README.md"
            )
    if not any(n == "index.html" for n in names):
        errors.append("the committed elemora-netlify.zip has no index.html at its root")


def check_quiz_page(errors: list[str]) -> None:
    """The shared-quiz landing page is the half of sharing a browser sees."""
    path = os.path.join(SITE, "quiz", "index.html")
    if not os.path.exists(path):
        return                       # already reported by check_links_agree
    text = read(path)
    where = "website/site/quiz/index.html"

    if "APPSTORE:CTA:START" not in text:
        errors.append(f"{where} has no marked App Store call to action, so "
                      "apply_config.py cannot keep it in step with config.json")
    if CARD.rsplit("/", 1)[-1] not in text:
        errors.append(f"{where} does not point og:image at {CARD}")
    for needed, why in (
        ("/privacy/", "the privacy link"),
        ("/support/", "the support link"),
        ("/terms/", "the terms link"),
        ("idlery.com", "the publisher"),
        ("noindex", "a quiz URL must not be indexed"),
    ):
        if needed not in text:
            errors.append(f"{where} is missing {why} ({needed!r})")

    # The page has to say what it says without running anything: a recipient
    # with scripts off still has to understand what they received.
    body = re.sub(r"<[^>]+>", " ", text.split("<main", 1)[-1])
    for phrase in ("Elemora", "shared", "App Store"):
        if phrase.lower() not in body.lower():
            errors.append(f"{where} does not say {phrase!r} in its rendered body")


def main() -> int:
    if not os.path.isdir(SITE):
        print("error: website/site does not exist")
        return 1

    errors: list[str] = []
    check_links_agree(errors)
    check_universal_links(errors)
    check_share_card(errors)
    check_pages(errors)
    check_quiz_page(errors)
    check_committed_zip(errors)

    for error in errors:
        print(f"error: {error}")
    if errors:
        print(f"\n{len(errors)} problem(s) in the website")
        return 1
    print(
        f"OK — {len(html_files())} pages on {HOST}, every app link served, "
        f"/quiz/* claimed for {BUNDLE_ID}, no third-party requests"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
