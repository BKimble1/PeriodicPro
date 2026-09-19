# elemora.idlery.com

The official website for **Elemora: Periodic Table**, published by **Idlery
Services LLC**. Plain static HTML and one stylesheet — no framework, no build
step for the pages themselves, no JavaScript on the deployed site, no web fonts,
and no third-party requests of any kind.

The deployable site is the `website/site/` folder. Nothing in here is read by
the Xcode project, and nothing here affects the iOS build, signing, schemes or
TestFlight.

```
website/
  site/                      <- everything that gets deployed; the publish root
    index.html               home: the product page
    support/index.html       support and contact
    privacy/index.html       privacy policy
    terms/index.html         terms of use
    404.html                 served by Netlify for unmatched paths
    _redirects               Netlify redirect rules
    _headers                 Netlify response headers (CSP and caching)
    robots.txt  sitemap.xml  favicon.ico
    assets/css/site.css      the entire stylesheet
    assets/img/              optimized images, all generated (see below)

  config.json                THE App Store URL lives here, and only here
  src-assets/                fonts and Apple's badge; never served directly
  scripts/build_assets.py    regenerates every file in site/assets/img
  scripts/apply_config.py    turns config.json into the call-to-action markup
  scripts/check_site.js      Chromium checks at eight widths, light and dark
  scripts/make_zip.sh        builds elemora-netlify.zip from site/
  CLAIMS-TO-VERIFY.md        every factual claim on the site, and its source
```

## Production URLs

| Purpose | URL |
|---|---|
| Marketing | `https://elemora.idlery.com` |
| Support | `https://elemora.idlery.com/support` |
| Privacy Policy | `https://elemora.idlery.com/privacy` |
| Terms of Use | `https://elemora.idlery.com/terms` |
| Support email | `support@idlery.com` |
| Publisher | `https://idlery.com` |

Netlify normalises trailing slashes, so `/support` and `/support/` both serve
`support/index.html`. Legacy and guessable paths (`/privacy.html`, `/help`,
`/contact`, `/tos`, `/eula`, `/periodicpro`, …) are redirected in
`site/_redirects`; anything unmatched falls through to `404.html`.

## Working on it

There is nothing to install and nothing to compile.

```sh
python3 -m http.server -d website/site 8000    # then open http://localhost:8000
```

### The App Store URL

**`website/config.json` is the only place the App Store listing is configured.**
No page hard-codes an App Store URL or ID.

While `appStoreUrl` is `null`, the site shows a *Coming to the App Store* status
pill beside a working `mailto:` link — a real destination, so there are no dead
buttons anywhere on the site.

When the listing goes live, this is the whole change:

```sh
# 1. edit website/config.json
#      "appStoreId":  "1234567890",
#      "appStoreUrl": "https://apps.apple.com/us/app/elemora-periodic-table/id1234567890"

python3 website/scripts/apply_config.py     # rewrites the marked CTA blocks
./website/scripts/make_zip.sh               # repackage
```

`apply_config.py` rewrites only the regions between `<!-- APPSTORE:CTA:START -->`
and `<!-- APPSTORE:CTA:END -->` in the HTML, and the marked block in
`_redirects`. It is idempotent, and `--check` reports drift without writing
anything — useful in CI. Going live also swaps the status pill for Apple's
official *Download on the App Store* badge, copied byte-for-byte from
`src-assets/brand/` and painted at 52 px tall.

### Regenerate the images

```sh
pip install Pillow
python3 website/scripts/build_assets.py
```

Everything under `site/assets/img/` is derived and should never be edited by
hand. The source artwork is the set of approved marketing images at the
**repository root**, which this script reads and never writes to:

| Repository root | Becomes | Shows |
|---|---|---|
| `ChatGPT Image Sep 15, 2026, 09_40_49 PM.png` | `elemora-icon-*.png`, `apple-touch-icon.png`, `favicon-32.png`, `favicon.ico` | the app icon |
| `IMG_2838.png` | `shot-table-*` | the periodic table screen |
| `IMG_2840.png` | `shot-oxygen-*` | the oxygen element page |
| `IMG_2845.png` | `shot-build-*` | the Build tab (caffeine) |
| `IMG_2849.png` | `shot-carbon-*` | the carbon element page |
| `IMG_2851.png` | `shot-identify-*` | an identification drill |
| `IMG_2852.png` | `shot-study-*` | the Study tab |
| `IMG_2853.png` | `shot-progress-*` | the Progress tab |

The script resizes and re-encodes, and that is all. **Nothing inside the app's
UI is retouched**, and the device status bars are left exactly as captured — so
the clock differs slightly from shot to shot, because these are genuine captures
from one evening's session. Unifying them would mean painting pixels the app
never drew. Each screenshot is emitted as WebP at 440 px and 880 px wide plus one
JPEG fallback at 880 px; the 1200×630 social card is composed from the icon, the
wordmark and the table screen.

**To replace a screenshot:** drop the new capture at the repository root, update
the `SCREENS` table at the top of `build_assets.py` to point at it, re-run the
script, and update the `alt` text in the page that uses it. The `alt` text
describes what is actually on screen, so it has to change with the picture.

### Check it

```sh
npm install playwright        # only dependency, and only for the checker
node scripts/check_site.js site .preview
```

Loads all four pages plus the 404 at 320, 390, 430, 820, 1180, 1280, 1440 and
1920 px, in light mode, plus dark mode at 390 px and 1440 px — under the same
`Content-Security-Policy` that `_headers` deploys. It fails on a console error,
a failed request, a broken image, horizontal overflow, a tap target under 44 px,
a dead internal link, an `<img>` with no `alt`, a `mailto:` that is not
`support@idlery.com`, or a `_redirects` rule that does not fire. Full-page
screenshots land in `.preview/`.

### Package it

```sh
./website/scripts/make_zip.sh          # writes ./elemora-netlify.zip at the repo root
```

The contents of `site/` go in at the **ZIP root**, so `index.html` is at the top
level with no wrapper folder. That is what Netlify's manual deploy expects, and
it is what makes `_redirects` and `_headers` take effect.

## Deploying

Nothing here deploys on its own.

1. Netlify → **Add new site** → **Deploy manually**, and drop in
   `elemora-netlify.zip` (or the folder it extracts to).
2. **Site configuration → Domain management → Add a domain** →
   `elemora.idlery.com`.
3. Add the DNS record Netlify shows you at whoever hosts DNS for `idlery.com` —
   a `CNAME` for the `elemora` subdomain pointing at the Netlify site's
   `*.netlify.app` hostname. Netlify then issues the TLS certificate
   automatically, usually within a few minutes.

The custom domain, DNS and certificate belong to the Netlify *site*, not to any
one deploy, so `elemora.idlery.com` stays connected and every earlier deploy
stays available to roll back to.

**DNS assumption:** `idlery.com` already resolves and is under your control, and
`elemora` is a free subdomain on it. This repository contains no DNS
configuration and cannot verify either.

A `netlify.toml` is included for the git-connected case (`publish =
"website/site"`, no build command). The ZIP workflow does not read it.

## Apple's badge

`src-assets/brand/apple-download-badge-us-uk-black.svg` is Apple's own artwork.
Per Apple's marketing guidelines it is used unmodified, painted at 52 px tall
(the onscreen minimum is 40), with clear space of at least a quarter of its
height, and every page carries Apple's trademark attribution in the footer. Do
not recreate, recolour, rotate, or animate it. It is only referenced once
`config.json` has a real `appStoreUrl` — a badge that links nowhere would breach
those guidelines.

## Universal Links

**Not configured, deliberately.** A `.well-known/apple-app-site-association`
file is not included, because publishing one requires facts this repository does
not contain: the app's Team ID, its bundle identifier, the Associated Domains
entitlement (`applinks:elemora.idlery.com`), and the paths the app can actually
route. Shipping an AASA that claims paths the app cannot handle breaks links
rather than enabling them.

To add it later you need, in one change:

1. In Xcode — the **Associated Domains** capability on the app target, with
   `applinks:elemora.idlery.com`.
2. In the app — a handler for `NSUserActivity` /
   `onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` that routes each
   claimed path.
3. Here — `site/.well-known/apple-app-site-association`, served as
   `application/json` with **no** `.json` extension, listing
   `TEAMID.bundle.identifier` and only the paths step 2 handles. Add a
   `/.well-known/*` block to `_headers` setting
   `Content-Type: application/json`.

## Content rules

Every product claim on these pages is limited to behaviour visible in the
approved marketing screenshots at the repository root, and each one is traced to
its source in [`CLAIMS-TO-VERIFY.md`](CLAIMS-TO-VERIFY.md). The pages carry no
ratings, download counts, testimonials, awards, or prices — prices live in the
App Store, where they can change without this repository knowing.

> **Read `CLAIMS-TO-VERIFY.md` before publishing.** The Elemora iOS source is
> not in this repository, so the privacy policy's statements about networking,
> analytics, crash reporting and third-party SDKs were written from the app's
> observable behaviour rather than from an audit of its code. That file lists
> each one, with the exact page and heading, so they can be confirmed against
> the app in a single pass.

No secrets, keys, tokens or internal hostnames appear anywhere in this
directory.
