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

Two things that might be expected to leave the device do not:

- **Camera frames are processed on your device and are never uploaded or
  stored.** See **The chemistry scanner** below.
- **Notifications are created on your device.** There is no notification
  server and no push account. See **Notifications** below.

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
| Quizzes you saved, and quizzes opened from a shared link (a name and the quiz settings) | SwiftData store | My Quizzes |
| Whether you have seen the three onboarding pages | `UserDefaults` | So onboarding only appears once |
| Your appearance choice: System, Light or Dark | `UserDefaults` | So the app opens in the appearance you picked |
| Which notification categories you turned on, and the time you chose | `UserDefaults` | So reminders arrive when and how you asked |
| The day you last completed the Daily Challenge | `UserDefaults` | So today's challenge is not offered twice |
| How many advanced-chemistry questions you answered each day, and how many were right | SwiftData store | The depth part of your learning rank |

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
  or the formula you assembled in the builder, once you have stopped changing
  it and only if nothing already on the device matches, or a PubChem compound
  identifier when a page needs the full record. Nothing else:
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

## The chemistry scanner

Scan Chemistry uses the camera to read chemical names, molecular formulas and
structure identifiers off a page.

- **Camera frames are analyzed on your device and are never recorded, saved or
  uploaded.** The recognition runs inside Apple's VisionKit on the device.
  Elemora keeps no image, writes no image to disk, and sends no image
  anywhere. There is no third-party recognition service in this app.
- **The only thing that can leave the device is the recognized text** — a
  chemical name, a formula, a SMILES string, an InChI or an InChIKey — and
  only when Elemora's own catalog and your on-device cache do not already have
  it, and only after you have held the camera steady on it long enough for the
  scanner to settle. That text goes to PubChem exactly like a typed search,
  described under **Compound lookups**.
- **Camera access is requested only when you open Scan**, never at launch and
  never as a side effect of anything else. Declining leaves everything else in
  the app working, and the scanner offers a search field instead.
- **No photo library access is requested at all.** Elemora does not ask for
  your photos and cannot read them.
- **The scanner reads text only** — chemical names, formulas and structure
  identifiers, from the band inside the frame on screen. It does not read
  structure diagrams. Doing that would need a different kind of model and, in
  every hosted form, would mean uploading a picture of whatever you were
  pointing at; the reasoning is written up in `OCSR.md`.

## Notifications

Study reminders are optional, off until you turn them on, and built entirely
on your device.

- **There is no notification server and no push account.** Elemora schedules
  local notifications with iOS. Nothing about what you study is sent anywhere
  to produce one, because the scheduling happens on the device from progress
  that never leaves it.
- **Permission is requested only when you turn a reminder on in Settings**,
  after the app has told you what that category does — never at launch.
- **Notification text contains no sensitive information**: a count of items due
  for review, the length of a streak, or that today's challenge is ready.
- At most one a day, and never at a critical or time-sensitive interruption
  level, so a Focus silences them.
- Turning the master switch off removes every reminder Elemora has pending.

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

- **Progress → ⚙︎ → Reset Progress** clears familiarity scores, answer counts and
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
formula and nothing personal. A saved quiz can be shared as a link, and that
link carries only a name and the quiz settings, encoded into the link itself —
there is no server holding the quiz and nothing is uploaded to share one. The
app refuses any link that is not exactly that.

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

The camera changes nothing in that answer, and it is worth being precise
about why. Apple's questionnaire asks about data *collected* — transmitted off
the device. Camera frames are not transmitted off the device: they are
analyzed by VisionKit on the device and discarded. Nothing is written to disk
and nothing is uploaded. The recognized text follows exactly the same path a
typed search does, and is covered by the same reasoning above. If a future
build ever sent an image anywhere, this section and the App Store answers
would have to change together, and that change would be stated here rather
than made quietly.

Notifications change nothing either: they are local, they carry no personal
information, and no notification token or account is involved.

This is checkable rather than asserted. The app links no third-party package
at all, and contains no analytics, advertising or attribution SDK. The only
URL it ever *requests* is PubChem's public REST endpoint. The Elemora
addresses in `PeriodicPro/Utilities/ElemoraLinks.swift` — the website, the
privacy policy, the terms, the support page and the base a shared quiz link is
built on — are links the app hands to Safari or to Messages when somebody taps
one, never requests the app makes. Nothing is fetched from them in the
background and nothing is sent to them.

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

## Shared quiz links

A quiz shared from **My Quizzes → Share** becomes an ordinary https link under
`https://elemora.idlery.com/quiz/`. The quiz travels *inside* the link: its name
and its settings are compressed and encoded into the address itself, so there is
no upload, no server storing it and nothing to delete afterwards. No progress,
no favorites, no history and no identifier of the person who made it is
included, and `PeriodicProTests/SavedQuizTests.swift` asserts exactly that by
decoding a link and checking which keys it carries.

Opening someone else's link validates it — the domain, the path, the size, the
format version, the quiz name, that every element exists and that every compound
reference is a PubChem identifier — and then saves the quiz on the device.
Nothing else on the device is read, changed or deleted, and a link that is not
one of ours is ignored rather than opened.

If the recipient does not have Elemora, the link opens
`https://elemora.idlery.com/quiz/…` in a browser, which shows a branded page
saying a quiz was shared and where to get the app. The page is a static file: it
sets no cookies, runs no scripts, loads nothing from a third party, and never
displays the encoded quiz.

## The website

The pages at `https://elemora.idlery.com` are plain static files with no
cookies, no analytics and no third-party embeds of any kind. The hosted privacy
policy at `/privacy` is the same statement as this document, and `Website/` in
this repository is its source; the two are kept in step deliberately, because
the App Store listing points at the hosted one and the app's Settings links to
it.

## Contact

<support@idlery.com>, or the repository's issue tracker.

_Last updated for the UX polish release (version 4.0.0)._
