# Privacy

**Elemora collects nothing.** There is no account, no sign-in, no
analytics, no advertising, no crash-reporting SDK and no network request of any
kind made by this app's own code. The app works fully offline, by design: the
entire periodic table is bundled inside it.

The one exception is the optional subscription, which is handled entirely by
Apple's StoreKit. That is Apple talking to the App Store, not this app talking
to a server of ours — see **Subscriptions** below.

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
| Whether you have seen the three onboarding pages | `UserDefaults` | So onboarding only appears once |

Nothing else is recorded. In particular the app does not store your name, email
address, contacts, location, photos, identifiers for advertising, or any device
identifier.

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

There are none. The app has zero third-party dependencies and makes no outbound
connections of its own. No data is sold or shared, because no data leaves the
device.

## Your control over the data

- **Progress → ⋯ → Reset progress** clears familiarity scores, answer counts and
  your streak. Favorites are kept, because they are a choice you made rather
  than progress.
- **Search → Clear** removes stored recent searches.
- **Deleting the app** removes everything above permanently. iOS deletes the
  app container with the app.

If iCloud Backup or iCloud Keychain is enabled on your device, iOS may include
the app's container in your personal encrypted device backup. That is Apple's
system-level backup, under your control in iOS Settings; this project never
receives it.

## Children

The app is suitable for all ages and collects no personal information from
anyone, including children. It contains no user-generated content, no chat, no
links out to the web, and no purchases.

## App Store privacy declaration

For the App Store Connect *App Privacy* questionnaire, answer:

- **Do you or your third-party partners collect data from this app?** → **No**

That single answer covers the whole questionnaire. The bundled
`PeriodicPro/PrivacyInfo.xcprivacy` privacy manifest matches it:
`NSPrivacyTracking` is `false`, `NSPrivacyTrackingDomains` and
`NSPrivacyCollectedDataTypes` are empty, and the only declared required-reason
API is `UserDefaults` with reason code `CA92.1` (access limited to the app
itself, to store the onboarding flag).

## Export compliance

The app uses no encryption beyond what iOS itself provides for local storage, so
it qualifies for the standard exemption. `Config/Info.plist` sets
`ITSAppUsesNonExemptEncryption` to `false`, which means TestFlight distributes
builds without stopping to ask.

## Contact

Questions about this document belong in the repository's issue tracker.

_Last updated for version 1.0.0._
