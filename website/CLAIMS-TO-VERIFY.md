# Claims to verify before publishing

**Read this before the site goes live, and before the Privacy Policy URL is
submitted to App Store Connect.**

## Why this file exists

The Elemora website was built inside `BKimble1/PeriodicPro`, but **that
repository does not contain the Elemora iOS application.** At the time this site
was written the repository held exactly nine files: eight marketing images and a
one-line `README.md`. There is no Xcode project, no Swift source, no
`Info.plist`, no `.storekit` file, no entitlements file, and no privacy manifest
anywhere in it — and no other repository on the account contains them either.

So the normal order of work — audit the code, then write the policy — could only
be half-done. Everything on the site is grounded in something real, but the
grounding differs in strength, and this file says which is which.

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

## C — Assumed, and NOT confirmed against the app's source

**Each line below is a statement the live site makes. Confirm or correct it.**

### `/privacy` — "No account, no sign-in"

- [ ] Elemora never asks for a name, email, password, phone number or date of
      birth, and has no "sign in with" button anywhere.
      *Basis: no sign-in appears in any of the seven screenshots, and Progress is
      presented as device-local. Not proven across every screen.*
      → Confirm there is no account, no CloudKit, and no developer backend.
      **This claim also appears on the home page**, in the "Your studying belongs
      on your device" band (`site/index.html`, the `.privacy-band` section) —
      correct both if it is wrong.

### `/privacy` — "What Elemora stores on your device"

- [ ] Favourites, saved compounds, study history, mastery, streak, daily
      challenge state and settings are written to Elemora's own app container.
      *Basis: all are displayed as per-device values.*
      → Confirm the storage layer (SwiftData / Core Data / `UserDefaults` /
      files) is local and that **no** iCloud or CloudKit sync is enabled. If
      CloudKit *is* on, this section and "Device backups" both need rewriting,
      and the App Privacy answers change.

### `/privacy` — "The chemistry data inside Elemora"

- [ ] The element data, explanations, structures and the compound catalogue ship
      inside the app and are read from the device.
      *Basis: "Matched in the Elemora catalog" in `IMG_2845` reads as a bundled
      catalogue.*
      → **Confirm no network call is made** for compound lookup, "Details", or
      "Explore in 3D". Search the source for `URLSession`, `URLRequest`,
      `NWConnection`, `pubchem`, `rest/pug`, `cactus.nci.nih.gov`, `wikipedia`.
      **If Elemora queries PubChem or any other external service, the privacy
      policy is wrong as written** and must gain a section naming the service,
      what is sent (typically the formula or compound name), and a link to that
      service's own privacy policy.

### `/privacy` — "Camera"

- [ ] Elemora has a camera feature; iOS prompts for permission; declining leaves
      the rest of the app working; images are used on device and are not
      uploaded or written to a photo library.
      *Basis: a camera/viewfinder button is visible at the top right of the table
      screen in `IMG_2838`. **What it does is unknown.***
      → Confirm what the button does, that `NSCameraUsageDescription` exists and
      reads sensibly, and that no image bytes leave the device. If there is no
      camera feature, **delete this section**. If it uses the photo library too,
      add `NSPhotoLibraryUsageDescription` to it.
- [ ] Elemora never requests location, contacts, microphone, health or calendar.
      → Confirm against `Info.plist`: no other `NS*UsageDescription` keys.

### `/privacy` — "What leaves your device"

- [ ] Only a purchase/restore and an email to support cause anything to leave the
      device; favourites, progress, mastery, streak and settings are never sent.
      → Follows from the networking check above. Re-confirm with it.

### `/privacy` — "Subscriptions and Apple"

- [ ] Elemora stores only a local entitlement flag and runs no
      receipt-validation server of its own.
      → Confirm StoreKit 2 on-device verification and no server round-trip.

### `/privacy` — "Analytics, tracking and advertising"

- [ ] No advertising, no advertising identifier, no cross-app tracking, no ATT
      prompt, no profile, no sale or sharing of personal information.
      → **This is the highest-risk claim on the site.** Search the source and the
      package graph for Firebase, Crashlytics, Sentry, Amplitude, Mixpanel,
      Segment, PostHog, TelemetryDeck, AppsFlyer, Adjust, Branch, Bugsnag,
      `ASIdentifierManager`, `ATTrackingManager`, `AppTrackingTransparency`.
      Check `packageProductDependencies` on every target. Confirm
      `NSPrivacyTracking` is `false` and `NSPrivacyTrackingDomains` is empty in
      `PrivacyInfo.xcprivacy`. **If any analytics or attribution SDK is present,
      this section is false and must be rewritten before publishing**, and the
      App Store Connect privacy answers change with it.

### `/privacy` — "Crashes and diagnostics"

- [ ] The only crash/performance data reaching Idlery is Apple's own, via App
      Store Connect.
      → Confirm no third-party crash reporter is linked.

### `/privacy` — "Third parties"

- [ ] Apple is the only third party involved in normal use.
      → Follows from the two checks above.

### `/privacy` and `/support` — "Deleting your information" / settings paths

- [ ] Elemora's settings are reached from the gear at the top right of the
      Progress tab. *(Seen — `IMG_2853`.)*
- [ ] Those settings contain a **version number**, **Restore Purchases**, and an
      option to **reset progress or clear stored data**.
      *Basis: expected, not seen — the settings screen is not among the
      screenshots.*
      → Confirm all three exist and are worded as the support page describes. If
      "Restore Purchases" lives elsewhere, correct `/support#subscriptions` and
      `/terms#restore`. If there is no reset option, correct
      `/privacy#deleting`.

### `/privacy` — "This website"

- [x] No cookies, no analytics, no tracking pixels, no third-party fonts or
      scripts, no forms. **Verified** — the deployed site is static HTML and one
      stylesheet, and `_headers` sets `script-src 'none'`.

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

## The app's own legal links — not updated

The brief asked for the iOS project's privacy / terms / support URLs to be
re-pointed at `elemora.idlery.com`, and for the app's tests to be run afterwards.
**Neither was possible: there is no iOS source in this repository to change, and
no test target to run.**

When the Elemora app source is available, search it for and re-point:

| Look for | Should become |
|---|---|
| any privacy-policy URL | `https://elemora.idlery.com/privacy` |
| any terms / EULA URL | `https://elemora.idlery.com/terms` |
| any support URL | `https://elemora.idlery.com/support` |
| any marketing / publisher URL | `https://elemora.idlery.com` |
| old Periodic Pro URLs, GitHub Pages URLs, `example.com`, placeholders | the above |
| any other support email | `support@idlery.com` |

Also check, in the same pass: the bundle identifier (it may still carry a legacy
Periodic Pro name — discover it, do not guess it), `PrivacyInfo.xcprivacy`, any
legal documents bundled inside the app, and the Associated Domains entitlement.
Then run the app's test suite.
