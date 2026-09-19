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
    quiz/index.html          a shared quiz, for a recipient without the app
    404.html                 served by Netlify for unmatched paths
    _redirects               Netlify redirect rules, incl. the /quiz/* rewrite
    _headers                 Netlify response headers (CSP, caching, JSON type)
    .well-known/
      apple-app-site-association.template    the Universal Links file, minus
                                             the Team ID
      apple-app-site-association             generated; git-ignored
    robots.txt  sitemap.xml  favicon.ico
    assets/css/site.css      the entire stylesheet
    assets/img/              optimized images, all generated (see below)

  config.json                THE App Store URL lives here, and only here
  src-assets/                fonts and Apple's badge; never served directly
  scripts/build_assets.py    regenerates every file in site/assets/img
  scripts/apply_config.py    turns config.json into the call-to-action markup
  scripts/build_aasa.py      writes the association file from APPLE_TEAM_ID
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
| A shared quiz | `https://elemora.idlery.com/quiz/<encoded payload>` |
| Universal Links | `https://elemora.idlery.com/.well-known/apple-app-site-association` |
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

Loads all five pages plus the 404 at 320, 390, 430, 820, 1180, 1280, 1440 and
1920 px, in light mode, plus dark mode at 390 px and 1440 px — under the same
`Content-Security-Policy` that `_headers` deploys. The shared-quiz page is
loaded through the `/quiz/*` rewrite with a real encoded payload, so what is
checked is the URL a recipient actually opens.

It fails on a console error, a failed request, a broken image, horizontal
overflow, a tap target under 44 px, a dead internal link, an `<img>` with no
`alt`, a `mailto:` that is not `support@idlery.com`, a `_redirects` rule that
does not fire, or an `apple-app-site-association` that is missing, redirected,
not JSON, or served as anything other than `application/json`. Full-page
screenshots land in `.preview/`.

Generate the association file first, or that last check fails as it should:

```sh
APPLE_TEAM_ID=XXXXXXXXXX python3 scripts/build_aasa.py
```

### Package it

```sh
APPLE_TEAM_ID=XXXXXXXXXX ./website/scripts/make_zip.sh   # -> ./elemora-netlify.zip
```

The contents of `site/` go in at the **ZIP root**, so `index.html` is at the top
level with no wrapper folder. That is what Netlify's manual deploy expects, and
it is what makes `_redirects` and `_headers` take effect.

A drag-and-drop deploy runs no build command, so the one generated file —
`.well-known/apple-app-site-association` — has to be generated before packaging.
`make_zip.sh` does that itself, refuses to run without `APPLE_TEAM_ID`, checks
the site still matches `config.json`, and then proves the real association file
is inside the ZIP rather than the template. Without the Team ID nothing is
written, because a placeholder association file is worse than none: Apple's CDN
caches it for hours.

> ### The committed `elemora-netlify.zip` has no association file
>
> It is built with `--without-universal-links`, on purpose. The association
> file carries the Apple Team ID, and this repository does not commit signing
> identifiers — not in the entitlement, not in the template, and not smuggled
> inside a binary either. `Tools/check_website.py` enforces that for the files
> it can read; this note is the part it cannot.
>
> **So the committed ZIP is not the one to deploy.** Build the real one first:
>
> ```sh
> APPLE_TEAM_ID=XXXXXXXXXX ./website/scripts/make_zip.sh
> ```
>
> That overwrites `elemora-netlify.zip` in place with the association file
> included. Deploy that, and do not commit it: `git checkout --
> elemora-netlify.zip` puts the committed build back afterwards. Everything
> else in the two archives is byte-for-byte the same, and
> `Tools/check_website.py` fails if a ZIP carrying a Team ID is ever
> committed.

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
"website/site"`, `command = "python3 website/scripts/build_aasa.py"`). Set
`APPLE_TEAM_ID` under **Site configuration → Environment variables** if you
deploy that way; the build fails without it, on purpose. The ZIP workflow does
not read `netlify.toml` at all.

## Apple's badge

`src-assets/brand/apple-download-badge-us-uk-black.svg` is Apple's own artwork.
Per Apple's marketing guidelines it is used unmodified, painted at 52 px tall
(the onscreen minimum is 40), with clear space of at least a quarter of its
height, and every page carries Apple's trademark attribution in the footer. Do
not recreate, recolour, rotate, or animate it. It is only referenced once
`config.json` has a real `appStoreUrl` — a badge that links nowhere would breach
those guidelines.

## Universal Links and the shared quiz

Elemora shares a saved quiz as an ordinary https link:

```
https://elemora.idlery.com/quiz/<encoded payload>
```

The quiz is *inside* the link — its name and settings, compressed and base64url
encoded. There is no account, no database and nothing stored on this site, which
is why the same link opens the same quiz on any device and why there is nothing
here to delete.

Three pieces have to agree, and all three are in this repository:

| Piece | Where |
|---|---|
| The entitlement: `applinks:elemora.idlery.com` | `Config/Elemora.entitlements`, wired in as `CODE_SIGN_ENTITLEMENTS` for both configurations |
| The association file: `<TeamID>.com.idlery.periodicpro`, path `/quiz/*` | `site/.well-known/apple-app-site-association.template` + `scripts/build_aasa.py` |
| The routing: `/quiz/* -> /quiz/index.html` with a **200** | `site/_redirects` |

`Tools/check_website.py` asserts that agreement on every run, and
`Tools/check_share_link.py` exercises the link format itself.

**The rewrite is a 200, never a 301.** A redirect would change the URL, and the
URL is the quiz. A 200 rewrite leaves the address bar exactly as the sender sent
it, which is also what Apple's Universal Link matching reads.

**Only `/quiz/*` is claimed.** The home page, `/support`, `/privacy` and
`/terms` stay ordinary web pages, so a tap on the privacy policy opens a
browser, not the app.

### The Team ID

The ten-character Apple Team ID is a signing identifier and is never committed.
`site/.well-known/apple-app-site-association` is git-ignored and written by
`scripts/build_aasa.py` from `APPLE_TEAM_ID` — the same value as the
repository's `APPLE_TEAM_ID` GitHub secret. The script validates the shape of
the ID, parses the JSON it produced, checks the app ID and the claimed path, and
refuses to write a placeholder.

### What this repository cannot do for you

Serving the association file is necessary, not sufficient. On the Apple side,
`developer.apple.com` → Certificates, Identifiers & Profiles → the
`com.idlery.periodicpro` identifier must have **Associated Domains** enabled,
and the provisioning profiles used to sign must be regenerated afterwards.
A build signed without that entitlement will not pick up a shared link no matter
what this site serves.

## Content rules

Every product claim on these pages is limited to behavior visible in the
approved marketing screenshots at the repository root, and each one is traced to
its source in [`CLAIMS-TO-VERIFY.md`](CLAIMS-TO-VERIFY.md). The pages carry no
ratings, download counts, testimonials, awards, or prices — prices live in the
App Store, where they can change without this repository knowing.

> **Read `CLAIMS-TO-VERIFY.md` before publishing.** The privacy policy's
> statements about networking, analytics, crash reporting and third-party SDKs
> were originally written from the app's observable behavior, because the
> Elemora iOS source was not in this repository at the time. It is now, and that
> file records what each claim was checked against — including the one that was
> wrong: the site said Elemora makes no network request for a compound, and it
> does, to PubChem. The policy has been corrected from the app's own
> `PRIVACY.md`. **The App Store Connect privacy answers need to match.**

No secrets, keys, tokens or internal hostnames appear anywhere in this
directory.
