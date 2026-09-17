# Privacy

**Elemora collects nothing.** There is no account, no sign-in, no
analytics, no advertising and no crash-reporting SDK. The app has no server of
its own. The entire periodic table and a starter set of fifty compounds are
bundled inside it, and everything about the elements works fully offline.

Two things leave the device, and only these:

- **Online compound searches are sent to PubChem to retrieve requested chemical
  information.** See **Compound lookups** below.
- The optional subscription, which is handled entirely by Apple's StoreKit.
  That is Apple talking to the App Store, not this app talking to a server of
  ours — see **Subscriptions** below.

## What is stored, and where

Everything below is written to the app's own on-device container and never
leaves the device. It is not backed up to any server owned by this project, not
shared with third parties, and not readable by other apps.

| Data | Where it lives | Why |
| --- | --- | --- |
| Favorite elements | SwiftData store in the app container | So the Study tab can show the elements you saved |
| Familiarity score per element (0–3), correct/incorrect counts, last-reviewed date | SwiftData store | Powers the Progress screen and orders your study queue |
| Days on which you answered at least one card | SwiftData store | Powers the streak counter |
| Recent search terms (most recent 8) | SwiftData store | So the search field can offer what you looked up last |
| Rounds you have finished today | SwiftData store | Powers the free daily study allowance |
| Favorite compounds, compounds added to Study, and a familiarity score per compound | SwiftData store | Compound favorites, the Study shelf and compound questions |
| Compounds you looked up (the record PubChem returned, at most 200) | SwiftData store | So a compound you fetched once keeps working offline |
| Hypothetical compositions you chose to keep (formula and molar mass only) | SwiftData store | So the builder can show them again |
| Quizzes you saved (a name and the quiz settings) | SwiftData store | My Quizzes |
| Whether you have seen the three onboarding pages | `UserDefaults` | So onboarding only appears once |

Nothing else is recorded. In particular the app does not store your name, email
address, contacts, location, photos, identifiers for advertising, or any device
identifier.

## Compound lookups

The Compound Builder and the compound half of search can ask
[PubChem](https://pubchem.ncbi.nlm.nih.gov), the public chemistry database run
by the U.S. National Library of Medicine, for information the app does not
have bundled. When that happens:

- **What is sent:** the compound name you typed in search (after a pause in
  typing, and never for a bare number or a one- or two-letter element symbol),
  or the formula you assembled in the builder when you tap *Look up*, or a
  PubChem compound identifier when a page needs the full record. Nothing else:
  no identifier for you or your device, no progress, no favorites, no history.
- **When:** only when you search for a compound or look one up. Browsing the
  table, studying, and everything about the elements make no request at all.
- **How:** plain HTTPS requests to PubChem's public REST service, with no API
  key and no server of ours in between. The app never crawls PubChem and keeps
  requests a fraction of a second apart.
- **What comes back** is cached on this device so the compound works offline
  afterwards. It is never sent anywhere else.
- **Offline:** bundled and previously fetched compounds keep working; the app
  says when it cannot reach PubChem rather than pretending a lookup found
  nothing.

PubChem's own handling of the requests it receives is covered by the NIH
privacy policy, not this one. The app shows "Data source: PubChem" and the
compound identifier on every record that came from it.

## Subscriptions

Elemora Pro is optional. If you subscribe, the purchase is made through Apple
using StoreKit, exactly as any App Store purchase is.

- **The app never sees your payment details, your Apple Account, your name or
  your email.** It asks StoreKit one question — is there an active subscription
  on this device? — and gets back yes or no.
- **There is no subscription SDK.** No RevenueCat, no analytics on conversion,
  no third-party receipt service. There is no server of ours involved at any
  point, so there is nothing for us to store even if we wanted to.
- **Nothing about what you study, search for or look at is sent anywhere**,
  whether you subscribe or not.
- Managing or canceling a subscription happens in Apple's own Settings, which
  the app links to.

Apple's own handling of the transaction is covered by Apple's privacy policy,
not this one.

## Third parties

The app has zero third-party dependencies and no analytics or advertising
partners. Its only outbound connections of its own are the PubChem lookups
described above, which carry the search term and nothing else. No data is sold
or shared.

## Your control over the data

- **Progress → ⋯ → Reset progress** clears familiarity scores, answer counts and
  your streak. Favorites are kept, because they are a choice you made rather
  than progress.
- **Search → Clear** removes stored recent searches.
- **Study → My Quizzes** lets you delete any saved quiz.
- **Deleting the app** removes everything above permanently. iOS deletes the
  app container with the app.

If iCloud Backup or iCloud Keychain is enabled on your device, iOS may include
the app's container in your personal encrypted device backup. That is Apple's
system-level backup, under your control in iOS Settings; this project never
receives it.

## Children

The app is suitable for all ages and collects no personal information from
anyone, including children. It contains no chat and no advertising. Its only
outbound requests are the compound lookups above, which send a chemical name or
formula and nothing personal. A saved quiz can be shared as a file, and a
shared quiz file carries only a name and the quiz settings; the app refuses any
file that is not exactly that.

## App Store privacy declaration

For the App Store Connect *App Privacy* questionnaire, the answer stays:

- **Do you or your third-party partners collect data from this app?** → **No**

This is still correct with the PubChem lookups, and here is the reasoning so
it can be checked rather than trusted. Apple defines *collecting* as
transmitting data off the device in a way that lets the developer or a partner
access it for longer than is needed to service the request in real time. A
compound lookup sends a chemical name or formula to PubChem to answer that one
request, on the spot; nothing identifies the person, nothing is retained by
this project (it has no server), and PubChem is not a partner of the developer
— it is a public reference service the app queries the way a browser would.
Search history stays on the device and is never uploaded.

This is checkable rather than asserted. The app links no third-party package
at all, contains no analytics, advertising or attribution SDK, and the only
two URLs anywhere in its source are PubChem's public REST endpoint and
Apple's standard license page, which is a link rather than a request.

The bundled `PeriodicPro/PrivacyInfo.xcprivacy` privacy manifest matches the
"No" answer: `NSPrivacyTracking` is `false`, `NSPrivacyTrackingDomains` and
`NSPrivacyCollectedDataTypes` are empty, and the only declared required-reason
APIs are `UserDefaults` with reason code `CA92.1` (the onboarding flag) and
file timestamps with `C617.1`. PubChem is not a tracking domain and is
deliberately not listed as one.

## Export compliance

The app uses no encryption beyond what iOS itself provides — HTTPS to PubChem
and local storage — so it qualifies for the standard exemption.
`Config/Info.plist` sets `ITSAppUsesNonExemptEncryption` to `false`, which
means TestFlight distributes builds without stopping to ask.

## Contact

Questions about this document belong in the repository's issue tracker.

_Last updated for the compound release (version 3.0.0)._
