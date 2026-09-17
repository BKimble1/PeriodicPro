#!/usr/bin/env python3
"""Checks the Elemora website against what the app actually links to.

The app and the site are two halves of one thing: `ElemoraLinks` in the app
names four destinations and a quiz base, Settings and the paywall open them,
and the App Store listing points at two of them. A path that exists in one half
and not the other is a dead legal link, which is a review rejection rather than
a visual bug — so this asserts that every address the app ships resolves to a
file in `Website/site`, and that the Universal Link plumbing is the shape iOS
requires.

It also holds the site to the promise its own privacy policy makes: no
cookies, no analytics, and nothing loaded from a third-party domain.

    python3 Tools/check_website.py
"""
from __future__ import annotations

import os
import re
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SITE = os.path.join(ROOT, "Website", "site")
LINKS = os.path.join(ROOT, "PeriodicPro", "Utilities", "ElemoraLinks.swift")

HOST = "elemora.idlery.com"
BUNDLE_ID = "com.idlery.periodicpro"
CARD = "assets/elemora-quiz-card.png"

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
    "www.apple.com",
    "www.nlm.nih.gov",
}

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
            errors.append(f"https://{HOST}{path} has no file at Website/site/{file}")

    if not os.path.exists(os.path.join(SITE, "quiz", "index.html")):
        errors.append("the shared-quiz landing page Website/site/quiz/index.html is missing")


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

    headers = os.path.join(SITE, "_headers")
    if not os.path.exists(headers):
        errors.append("Website/site/_headers is missing")
    else:
        text = read(headers)
        if "/.well-known/apple-app-site-association" not in text:
            errors.append("_headers does not set a type for the association file")
        elif "Content-Type: application/json" not in text:
            errors.append("the association file must be served as application/json")

    redirects = os.path.join(SITE, "_redirects")
    if not os.path.exists(redirects):
        errors.append("Website/site/_redirects is missing")
    elif not re.search(r"^/quiz/\*\s+\S+\s+200", read(redirects), re.MULTILINE):
        errors.append("/quiz/* must be rewritten to the landing page with a 200, not redirected")

    entitlements = os.path.join(ROOT, "Config", "Elemora.entitlements")
    if not os.path.exists(entitlements):
        errors.append("Config/Elemora.entitlements is missing")
    elif f"applinks:{HOST}" not in read(entitlements):
        errors.append(f"the app does not claim applinks:{HOST}")


def check_share_card(errors: list[str]) -> None:
    card = os.path.join(SITE, CARD)
    if not os.path.exists(card):
        errors.append(f"the link-preview image Website/site/{CARD} is missing")
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
        errors.append("no HTML pages in Website/site")
        return
    for file in files:
        text = read(os.path.join(SITE, file))
        where = f"Website/site/{file}"

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
        for reference in RESOURCE_ATTRIBUTE.findall(text):
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
                       "document.cookie", "<script"):
            if banned in text.lower():
                errors.append(f"{where} contains {banned!r}; this site runs no scripts "
                              "and sets no cookies")

    stylesheet = os.path.join(SITE, "assets", "elemora.css")
    if not os.path.exists(stylesheet):
        errors.append("Website/site/assets/elemora.css is missing")
    else:
        for reference in STYLESHEET_URL.findall(read(stylesheet)):
            if not reference.startswith(("/", "data:")):
                errors.append(f"elemora.css loads {reference} from outside the site")


def main() -> int:
    if not os.path.isdir(SITE):
        print("error: Website/site does not exist")
        return 1

    errors: list[str] = []
    check_links_agree(errors)
    check_universal_links(errors)
    check_share_card(errors)
    check_pages(errors)

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
