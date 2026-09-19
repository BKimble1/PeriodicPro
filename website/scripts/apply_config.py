#!/usr/bin/env python3
"""
Switch the site between its pre-release and its on-sale state.

    python3 website/scripts/apply_config.py          # apply website/config.json
    python3 website/scripts/apply_config.py --check  # verify, change nothing

Everything about the App Store listing lives in website/config.json. This script
is what turns that one setting into markup. It rewrites the regions marked

    <!-- APPSTORE:CTA:START -->  ...  <!-- APPSTORE:CTA:END -->      in site/*.html
    # APPSTORE:REDIRECT:START    ...  # APPSTORE:REDIRECT:END        in _redirects

and nothing else. Running it twice in a row changes nothing the second time, so
it is safe to run from a build or a hook.

When appStoreUrl is null the site shows a 'Coming to the App Store' pill next to
a working mailto link -- a real destination rather than a dead button. Set
appStoreUrl (and appStoreId) and run this again to swap in Apple's official
download badge, linked to the listing.
"""

import argparse
import json
import re
import shutil
import sys
from pathlib import Path

WEB = Path(__file__).resolve().parents[1]
SITE = WEB / "site"
CONFIG = WEB / "config.json"
BADGE_SRC = WEB / "src-assets" / "brand" / "apple-download-badge-us-uk-black.svg"
BADGE_DST = SITE / "assets" / "img" / "apple-download-badge.svg"

CTA_RE = re.compile(
    r"(?P<open><!-- APPSTORE:CTA:START -->)(?P<body>.*?)(?P<close><!-- APPSTORE:CTA:END -->)",
    re.DOTALL,
)
REDIRECT_RE = re.compile(
    r"(?P<open># APPSTORE:REDIRECT:START\n)(?P<body>.*?)(?P<close># APPSTORE:REDIRECT:END)",
    re.DOTALL,
)

MAILTO = "mailto:support@idlery.com?subject=Tell%20me%20when%20Elemora%20is%20available"

# The secondary button differs per page, so it is keyed by file. Keeping the
# variants here means the pre-release and on-sale markup stay in step.
SECONDARY = {
    "index.html":     ('<a class="btn btn-secondary" href="#explore">See what it does</a>', 0),
    "index.html#get": ('<a class="btn btn-secondary" href="/support/">Contact support</a>', 1),
}


def cta_prerelease(secondary: str, closing: bool) -> str:
    note = (
        "            Elemora is not on the App Store yet. Email\n"
        f'            <a href="{MAILTO}">support@idlery.com</a>\n'
        "            and we will tell you when it is.\n"
        if closing else
        "            Want to know the moment it lands? Email\n"
        f'            <a href="{MAILTO}">support@idlery.com</a>.\n'
    )
    return (
        "\n"
        '          <div class="cta-row">\n'
        '            <span class="status-pill"><span class="dot" aria-hidden="true"></span>'
        "Coming to the App Store</span>\n"
        f"            {secondary}\n"
        "          </div>\n"
        '          <p class="cta-note">\n'
        f"{note}"
        "          </p>\n"
        "          "
    )


def cta_released(url: str, secondary: str) -> str:
    """Apple's badge, used unmodified and at its documented minimum height."""
    return (
        "\n"
        '          <div class="cta-row">\n'
        f'            <a class="appstore-badge" href="{url}">\n'
        '              <img src="/assets/img/apple-download-badge.svg" width="156" height="52"\n'
        '                   alt="Download Elemora on the App Store">\n'
        "            </a>\n"
        f"            {secondary}\n"
        "          </div>\n"
        '          <p class="cta-note">\n'
        "            Elemora is free to download. Any subscription is shown in the App Store\n"
        "            and inside the app for your storefront.\n"
        "          </p>\n"
        "          "
    )


def apply(check: bool) -> int:
    cfg = json.loads(CONFIG.read_text())
    url = cfg.get("appStoreUrl")
    app_id = cfg.get("appStoreId")

    if url and app_id and str(app_id) not in url:
        print(f"warning: appStoreId {app_id} does not appear in appStoreUrl {url}", file=sys.stderr)

    changed = []

    for path in sorted(SITE.rglob("*.html")):
        text = original = path.read_text()
        blocks = list(CTA_RE.finditer(text))
        if not blocks:
            continue
        # Rebuild back to front so earlier spans stay valid.
        for i, m in reversed(list(enumerate(blocks))):
            key = f"{path.name}#get" if i else path.name
            secondary = SECONDARY.get(key, SECONDARY.get(path.name, ("", 0)))[0]
            body = cta_released(url, secondary) if url else cta_prerelease(secondary, bool(i))
            text = text[: m.start("body")] + body + text[m.end("body") :]
        if text != original:
            changed.append(path)
            if not check:
                path.write_text(text)

    redirects = SITE / "_redirects"
    if redirects.exists():
        text = original = redirects.read_text()
        body = (
            f"/download        {url}   302\n/app             {url}   302\n"
            if url else
            "/download        /#get       302\n/app             /#get       302\n"
        )
        text = REDIRECT_RE.sub(lambda m: m.group("open") + body + m.group("close"), text)
        if text != original:
            changed.append(redirects)
            if not check:
                redirects.write_text(text)

    if url and not BADGE_DST.exists():
        changed.append(BADGE_DST)
        if not check:
            BADGE_DST.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(BADGE_SRC, BADGE_DST)

    state = "on sale" if url else "pre-release"
    if check:
        if changed:
            print(f"out of date with config.json ({state}):")
            for p in changed:
                print(f"  {p.relative_to(WEB)}")
            return 1
        print(f"site matches config.json ({state})")
        return 0

    if changed:
        print(f"applied {state} state:")
        for p in changed:
            print(f"  {p.relative_to(WEB)}")
    else:
        print(f"already {state}; nothing to change")
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true", help="report drift, write nothing")
    sys.exit(apply(ap.parse_args().check))
