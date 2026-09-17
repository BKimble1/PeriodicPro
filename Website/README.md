# elemora.idlery.com

The production website for Elemora: the home page, the privacy policy, the
terms, the support page, the landing page a shared quiz link falls back to, and
the Apple app-site-association file that makes those links open the app.

Plain static files. No build step beyond one substitution, no framework, no
third-party request from any page — the site that serves a privacy policy
saying "no analytics, no tracking" does not itself load anything from anybody
else's domain.

```
Website/
  netlify.toml                                   build command and publish dir
  scripts/build.sh                               writes the association file
  site/
    index.html                                   /
    privacy/index.html                           /privacy
    terms/index.html                             /terms
    support/index.html                           /support
    quiz/index.html                              /quiz/<payload>  (rewritten)
    404.html  robots.txt  sitemap.xml  favicon.svg
    _redirects                                   /quiz/* -> the landing page
    _headers                                     JSON type for the AASA file
    assets/elemora.css
    assets/elemora-quiz-card.png                 1200x630 og:image
    .well-known/apple-app-site-association.template
```

The app's `ElemoraLinks` is the other half of this, and
`PeriodicProTests/SettingsTests.swift` asserts the exact strings. If a path here
changes, that test is what fails.

## Deploying

The site is a drop-in match for the shape `BKimble1/Idlery` already uses for
idlery.com (Netlify, `publish = "site"`, `_redirects` and `_headers`), so the
quickest route is a second Netlify site pointed at this directory.

1. **Create the Netlify site.** New site from this repository, base directory
   `Website`, build command `bash scripts/build.sh`, publish directory
   `Website/site`. (A drag-and-drop deploy works too, but the association file
   must then be generated locally first — see step 2.)

2. **Set `APPLE_TEAM_ID`.** Site settings → Environment variables →
   `APPLE_TEAM_ID` = the ten-character Apple Developer Team ID (the same value
   as the repository's `APPLE_TEAM_ID` secret). `scripts/build.sh` substitutes
   it into `apple-app-site-association` at deploy time; it is deliberately not
   committed, and the script refuses to build without it rather than shipping a
   placeholder that would silently fail verification.

   Locally: `APPLE_TEAM_ID=XXXXXXXXXX bash scripts/build.sh`.

3. **Point DNS at it.** Add `elemora` as a CNAME (or Netlify DNS record) under
   `idlery.com` for the new site, and let Netlify issue the certificate.
   **As of this writing `elemora.idlery.com` has no DNS record at all** — that
   is the one thing nothing in this repository can do for you, and until it
   exists every link in the app resolves to nothing.

4. **Check it.** All five must be true before the app's links are live:

   ```
   curl -sI https://elemora.idlery.com/
   curl -sI https://elemora.idlery.com/privacy
   curl -sI https://elemora.idlery.com/terms
   curl -sI https://elemora.idlery.com/support
   curl -s  https://elemora.idlery.com/.well-known/apple-app-site-association
   ```

   The last one must return `200`, `Content-Type: application/json`, no
   redirect, and JSON naming `<TeamID>.com.idlery.periodicpro`.

## Universal Links

`Config/Elemora.entitlements` in the app claims `applinks:elemora.idlery.com`.
For a link to open the app rather than Safari, all of this has to line up:

- The App ID `com.idlery.periodicpro` has the **Associated Domains**
  capability enabled in the Apple Developer portal.
- The installed build is signed with a profile that carries the entitlement.
- The association file above is reachable and correct.
- The link is under `/quiz/`. Every other path is excluded by the
  `components` list, so `/privacy` opens in a browser, as it should.

Apple's CDN caches the association file. After a change, a device may need a
reinstall of the app to re-fetch it.

## What the pages promise

The privacy policy states exactly what the app does today: local-only storage,
StoreKit subscriptions, PubChem lookups for compound searches, no account, no
analytics, no advertising. `PRIVACY.md` at the repository root is the same
statement and the two are kept in step deliberately — if one changes, so does
the other, and so do the App Store privacy answers.
