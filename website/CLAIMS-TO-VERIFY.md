# Claims to verify before publishing

**Read this before the site goes live, and before the Privacy Policy URL is
submitted to App Store Connect.**

## Why this file exists

The Elemora website was built inside `BKimble1/PeriodicPro` at a time when that
branch held nine files — eight marketing images and a one-line `README.md` —
and no iOS source at all. So the normal order of work, audit the code and then
write the policy, could only be half-done, and this file recorded which claims
were grounded in what.

**That is no longer the situation.** The app now sits beside the site in this
branch: `PeriodicPro/` (Swift source), `PeriodicPro.xcodeproj`, `Config/`
(`Info.plist`, `Elemora.entitlements`, `PeriodicPro.storekit`),
`PeriodicPro/PrivacyInfo.xcprivacy`, and a test target. Section **C** below has
been walked against that source; each line now says what was found and where.
**One claim was wrong and has been corrected** — see *Compound lookups* below.

| Confidence | What it means | Action |
|---|---|---|
| **A — Seen** | Visible in an approved screenshot at the repository root | None; re-check only if a screenshot is replaced |
| **B — Platform** | Apple's documented behaviour, independent of Elemora's code | None |
| **C — Assumed** | Consistent with the app's visible design, **not confirmed against its source** | **Confirm before publishing** |
| **D — Decision** | Needs a business or legal answer, not a code answer | **Decide before publishing** |

Everything in **C** and **D** is listed below with the page and heading it
appears under. A single pass through the app's source clears all of section C.

---

## A — Seen in the approved screenshots

These are safe. Each one is visible in the images at the repository root.

| Claim | Screenshot |
|---|---|
| Four tabs: Table, Study, Build, Progress | all |
| All 118 elements, true periodic positions, lanthanides and actinides on their own rows | `IMG_2838` |
| Search field reading "Element, symbol, or number" | `IMG_2838` |
| Filters: All / Metals / Nonmetals / Metalloids | `IMG_2838` |
| Family filters, combinable ("Tap more than one to combine them") | `IMG_2838` |
| Pinch to zoom, drag to pan | `IMG_2838` |
| Element tile with atomic number, symbol, name, mass; category pill; one-line hook | `IMG_2840` |
| Shell diagram, and its "simplified shell model … electrons do not travel on fixed circular paths" caveat | `IMG_2840` |
| Atomic number, atomic mass, electron configuration | `IMG_2840` |
| Quick Facts: Category, State at 25 °C, Group, Period; "More properties" | `IMG_2849` |
| "About <element>" prose and "Common Uses" tiles | `IMG_2849` |
| Favourite (heart) on an element | `IMG_2840`, `IMG_2849` |
| Build: formula, Hill formula, molar mass, atom count | `IMG_2845` |
| "Matched in the Elemora catalog" | `IMG_2845` |
| Caffeine = C₈H₁₀N₄O₂, 194.19 g/mol, 24 atoms, "Molecular (covalent)" | `IMG_2845` |
| Skeletal structure rendering | `IMG_2845` |
| Save / Favorite / Details, and "Explore in 3D" | `IMG_2845` |
| "Bonding hints — NOT A VERIFICATION" | `IMG_2845` |
| Study: day streak, "% Elements mastered", Daily Challenge, Flashcards, Practice modes | `IMG_2852` |
| Identify drill: "Which element has this atomic number?", 10-card sets, flip, "I knew this" / "Review again" | `IMG_2851` |
| Progress: mastery ring "x of 118", compounds studied, recent accuracy | `IMG_2853` |
| Ranks "Periodic Pathfinder" → "Pattern Reader" | `IMG_2853` |
| Activity: day streak, cards answered, elements started, favourites saved | `IMG_2853` |
| A settings gear at the top right of the Progress tab | `IMG_2853` |

---

## B — Apple platform behaviour

Independent of Elemora's code; no verification needed.

- Apple processes App Store payments and holds payment details.
- Subscriptions are managed at **Settings → your name → Subscriptions** and at
  `apps.apple.com/account/subscriptions`.
- Auto-renewal must be turned off at least 24 hours before the period ends.
- Refunds go through `reportaproblem.apple.com`.
- A purchase restores only to the Apple Account that made it.
- Deleting an app removes its app container.
- Device backups may include an app's data.
- Crash and performance data reach developers only if the user has enabled
  *Share iPhone Analytics* **and** *Share With App Developers*.
- Apple's Standard EULA and Media Services Terms apply to App Store
  distribution.

---

## C — Checked against the app's source

Every line below was a statement the site makes. Each now names the file the
check was made against. `[x]` means confirmed; a correction says what changed.

### `/privacy` — "No account, no sign-in"

- [x] No account, no sign-in, no CloudKit, no developer backend.
      *Checked:* no `CloudKit` / `NSPersistentCloudKitContainer` anywhere in
      `PeriodicPro/`; persistence is SwiftData in a local container
      (`PeriodicPro/Persistence/`), and the project has no Swift package
      dependencies at all (`packageProductDependencies` is absent from
      `PeriodicPro.xcodeproj/project.pbxproj`).

### `/privacy` — "What Elemora stores on your device"

- [x] Favourites, saved compounds, study history, mastery, streak, daily
      challenge state and settings are written to the app's own container.
      *Checked:* `PeriodicPro/Persistence/ProgressStore.swift`,
      `PeriodicPro/StudyEngine/SavedQuiz.swift`, both SwiftData-backed and local.
      No iCloud or CloudKit sync is configured.

### `/privacy` — "The chemistry data inside Elemora"

- [!] **This was wrong and has been corrected.** The site said the chemistry data
      is bundled and that a lookup makes no network call. Elements are indeed all
      bundled, but **compounds are not**: a shipped build creates
      `PubChemClient()` over `URLSessionTransport`
      (`PeriodicPro/Compounds/Data/CompoundStore.swift:31`,
      `PeriodicPro/Compounds/Networking/NetworkTransport.swift`) and queries
      `https://pubchem.ncbi.nlm.nih.gov/rest/pug`
      (`PeriodicPro/Compounds/Networking/PubChemClient.swift:124`).
      `isOnlineLookupEnabled` defaults to `true` and is turned off only for UI
      tests (`PeriodicPro/App/PeriodicProApp.swift:149-167`).
      → `/privacy` now carries a **Compound lookups and PubChem** section, and
      *What leaves your device*, *Third parties* and *The short version* name it.
      The wording is taken from the app's own `PRIVACY.md`, which had it right
      all along; the website was simply written before that source was available.
      **The App Store Connect privacy answers must match this** — see the
      remaining-work list at the end of this file.

### `/privacy` — "Camera"

- [x] There is a camera feature (Scan Chemistry), `NSCameraUsageDescription`
      exists and reads sensibly
      (`PeriodicPro.xcodeproj/project.pbxproj`, `INFOPLIST_KEY_NSCameraUsageDescription`),
      recognition runs on device, and no image is uploaded or written to a photo
      library. *Checked:* `PeriodicPro/Scanner/`.
      → The page now also says that **recognised text** can go to PubChem, which
      is what `PRIVACY.md` says and what the scanner actually does.
- [x] No other `NS*UsageDescription` key exists: camera is the only permission.

### `/privacy` — "What leaves your device"

- [!] Corrected from two causes to four: a PubChem lookup and a shared quiz link
      join a purchase and an email.

### `/privacy` — "Subscriptions and Apple"

- [x] StoreKit 2, verified on device, no receipt server.
      *Checked:* `PeriodicPro/Store/SubscriptionManager.swift`,
      `PeriodicPro/Store/ProEntitlement.swift`.

### `/privacy` — "Analytics, tracking and advertising"

- [x] No analytics, attribution or crash-reporting SDK of any kind. *Checked:*
      the project has no package dependencies, and no Firebase / Crashlytics /
      Sentry / Amplitude / Mixpanel / Segment / PostHog / TelemetryDeck /
      AppsFlyer / Adjust / Branch / Bugsnag / `ASIdentifierManager` /
      `ATTrackingManager` symbol appears in any Swift file.
      `PeriodicPro/PrivacyInfo.xcprivacy` declares `NSPrivacyTracking` false,
      `NSPrivacyTrackingDomains` empty and `NSPrivacyCollectedDataTypes` empty.

### `/privacy` — "Crashes and diagnostics"

- [x] No third-party crash reporter is linked. Follows from the check above.

### `/privacy` — "Third parties"

- [!] Corrected: Apple **and** PubChem (U.S. National Library of Medicine).

### `/privacy` and `/support` — "Deleting your information" / settings paths

- [x] Settings is the gear at the top right of the Progress tab, and it contains
      the version number, **Restore Purchases** and **Reset progress**.
      *Checked:* `PeriodicPro/Views/Progress/SettingsScreen.swift` lines 63, 77,
      107 and 306.

### `/privacy` — "Sharing a quiz"

- [x] A shared link carries the schema version, the quiz name and the quiz
      configuration, and nothing else. *Checked:*
      `PeriodicPro/StudyEngine/QuizShareLink.swift` (`QuizSharePayload` has three
      fields) and asserted in `PeriodicProTests/SavedQuizTests.swift`, which
      decodes a real link and checks the key set.
- [x] The website page never decodes or displays the payload, runs no script and
      makes no third-party request. *Checked:* `website/site/quiz/index.html` is
      static HTML with no `<script>`, and `_headers` sets `script-src 'none'`
      plus `Referrer-Policy: no-referrer` and `Cache-Control: no-store` on
      `/quiz/*`.

### `/privacy` — "This website"

- [x] No cookies, no analytics, no tracking pixels, no third-party fonts or
      scripts, no forms. The only `<script>` on the site is the JSON-LD block on
      the home page, which is data rather than code, and
      `Tools/check_website.py` fails the build on any other one.

### `/support` — response time

- [ ] "We aim to reply within two business days."
      → A promise you are making. Change it if it is not one you want.

### `/terms` — subscriptions

- [ ] The subscription section is written conditionally ("Elemora **may** offer
      …") and names no tier, price, product ID, trial length or gated feature,
      because the repository contains no StoreKit configuration.
      → Once the products exist, decide whether to name the tier (e.g. "Elemora
      Pro") and its periods. **Do not add prices** — Apple sets them per
      storefront. Make sure the wording matches the in-app paywall exactly.
- [ ] "Elemora is free to download" appears in the *on-sale* call-to-action that
      `apply_config.py` writes (`scripts/apply_config.py`, `cta_released`).
      → If Elemora is a paid download, edit that string before going live.

---

## D — Decisions that are yours, not the code's

- [ ] **Governing law.** `/terms#law` uses **Ohio, Butler County** — the same
      choice Idlery Services LLC made for CoreCredit
      (`CoreCredit/docs/legal-public/terms.html`). Consistent for the same
      company, but it is a legal decision, not a fact discovered in this
      repository. Confirm it applies to Elemora.
- [ ] **Legal review.** The Privacy Policy and Terms of Use are drafted, not
      reviewed by a lawyer. The liability cap (`/terms#liability`, greater of
      amounts paid or US$20), the warranty disclaimer, and the consumer-rights
      carve-out should be read by counsel.
- [ ] **EULA.** The site assumes Apple's **Standard** Licensed Application EULA
      and links to it on Apple's domain, without claiming to replace it. That
      matches CoreCredit. If Idlery intends to submit a **custom** EULA in App
      Store Connect for Elemora, `/terms#apple` must change.
- [ ] **Storefronts.** `/terms#where` says "the storefronts where it is listed"
      rather than naming countries. CoreCredit v1 is US-only. Narrow this if
      Elemora is too.
- [ ] **Copyright year.** Footers and legal pages read 2026.
- [ ] **Effective dates.** Both documents are Version 1.0, effective
      19 September 2026. Move them to the actual publication date if it differs.
- [ ] **App Store URL.** Not known, and deliberately not invented. See
      `website/config.json` — it is the only place it is configured.
- [ ] **Universal Links.** Not configured. See the README for exactly what is
      needed if you want them.

---

## The app's own legal links — checked

The brief asked for the iOS project's privacy / terms / support URLs to be
re-pointed at `elemora.idlery.com`. With the app source now in this branch, that
has been checked rather than deferred.

| Address | Where it lives in the app | State |
|---|---|---|
| `https://elemora.idlery.com` | `ElemoraLinks.websiteString` | correct |
| `https://elemora.idlery.com/privacy` | `ElemoraLinks.privacyString` | correct |
| `https://elemora.idlery.com/terms` | `ElemoraLinks.termsString` | correct |
| `https://elemora.idlery.com/support` | `ElemoraLinks.supportString` | correct |
| `https://elemora.idlery.com/quiz/` | `ElemoraLinks.quizBaseString` | correct |
| `support@idlery.com` | `ElemoraLinks.supportEmailAddress` | correct |

`Tools/check_website.py` now asserts each of those against a file in
`website/site/`, so the two halves cannot drift apart silently. There is no
GitHub Pages URL, no `example.com` and no placeholder left in the app.

The bundle identifier is **`com.idlery.periodicpro`**
(`Config/Shared.xcconfig`, `PRODUCT_BUNDLE_IDENTIFIER_BASE`) — discovered, not
guessed. It keeps the original spelling on purpose: App Store Connect records
and provisioning profiles are bound to it and it cannot be changed after a
build has been uploaded. `Tools/check_branding.py` holds the line between that
identifier and the name people read, which is Elemora everywhere.

The Associated Domains entitlement (`Config/Elemora.entitlements`) claims
`applinks:elemora.idlery.com`, and is wired into both build configurations
(`CODE_SIGN_ENTITLEMENTS` in `PeriodicPro.xcodeproj/project.pbxproj`).
`website/site/.well-known/apple-app-site-association` — generated at package
time by `website/scripts/build_aasa.py` — names
`<TeamID>.com.idlery.periodicpro` and the single path `/quiz/*`.

The Swift test suite needs macOS and could not be run from the Linux environment
this pass was done in. The Python checks in `Tools/verify.sh` were run, and
`Tools/check_share_link.py` reproduces the share-link format independently of
Swift — reading the limits out of the Swift source so it cannot drift — so the
encoder's rules are exercised here too.

---

## Still yours to decide

- [ ] **App Store Connect privacy answers.** They must now account for the
      PubChem lookups. Nothing collected is linked to a user or used for
      tracking, but a lookup does send a compound name or formula to a third
      party, and the answers should say so.
- [ ] Everything under **D** above.
