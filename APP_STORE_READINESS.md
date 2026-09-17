# App Store readiness — Elemora Build 5

Every release-critical item, with a verdict. **PASS** means it is done and
checkable in this repository. **MANUAL ACTION** means it is outside what a
build can do and needs a person in App Store Connect, the Apple Developer
portal or the website host. There is no "looks good".

Audited at Build 5. Version `5.0.0`, bundle identifier `com.idlery.periodicpro`.

---

## 1. Subscriptions and StoreKit

| Item | Verdict | Evidence |
| --- | --- | --- |
| Product identifiers unchanged | **PASS** | `periodicpro.pro.monthly`, `periodicpro.pro.yearly` in `Config/PeriodicPro.storekit`; `Tools/check_storekit.py` fails the build if either changes |
| Subscription group unchanged | **PASS** | `periodicpro.pro`, same check |
| User-facing name is "Elemora Pro" | **PASS** | `Tools/check_branding.py` |
| Subscription length shown | **PASS** | `PaywallView` renders each product's period from StoreKit |
| Price comes from StoreKit, never hardcoded | **PASS** | `Product.displayPrice` only; no price literal exists in the source |
| Auto-renewing nature disclosed | **PASS** | `PaywallView.renewalTerms` states charge at confirmation, automatic renewal, the 24-hour cancellation window and where to cancel |
| Restore Purchases | **PASS** | `PaywallView`, button `paywall.restore` |
| Manage Subscription | **PASS** | `.manageSubscriptionsSheet`, and a row in Settings |
| Privacy and Terms links on the paywall | **PASS** | Both, from `ElemoraLinks` |
| No external purchase mechanism | **PASS** | The app opens no purchase URL of any kind; StoreKit is the only path |
| No misleading discount | **PASS** | The saving shown is computed from the two StoreKit prices, not asserted |
| Products missing is handled | **PASS** | The paywall shows an unavailable state with a retry rather than an empty screen; unit-tested |

**MANUAL ACTION — App Store Connect:** both subscriptions must be in the
*Ready to Submit* state with a localized display name, description, review
screenshot and price tier, in the `periodicpro.pro` group. A build referencing
a product that is not yet approved shows the unavailable state to reviewers.

## 2. Privacy policy, terms and support

| Item | Verdict | Evidence |
| --- | --- | --- |
| Privacy Policy reachable in the app | **PASS** | Settings → Legal → Privacy Policy → `https://elemora.idlery.com/privacy` |
| Terms of Use reachable in the app | **PASS** | Settings → Legal → Terms of Service, and on the paywall |
| Support reachable in the app | **PASS** | Settings → Support → `https://elemora.idlery.com/support`, plus a pre-addressed mail to `support@idlery.com` |
| All URLs in one place | **PASS** | `PeriodicPro/Utilities/ElemoraLinks.swift` |
| Every linked page exists in the repository | **PASS** | `Tools/check_website.py` fails if the app links a page the site does not serve |
| Privacy policy covers the scanner | **PASS** | `PRIVACY.md` → *The chemistry scanner*; website → *The chemistry scanner* |
| Privacy policy covers notifications | **PASS** | `PRIVACY.md` → *Notifications*; website → *Notifications* |

**MANUAL ACTION — website host:** this repository contains the site's source
under `Website/site/`. Deploying it is external to the build, and nothing here
can verify that `https://elemora.idlery.com/privacy` currently answers over
HTTPS. Before submitting, open all four URLs in a browser and confirm each
returns 200 over HTTPS with the updated text:

- `https://elemora.idlery.com`
- `https://elemora.idlery.com/privacy`
- `https://elemora.idlery.com/terms`
- `https://elemora.idlery.com/support`

**MANUAL ACTION — App Store Connect:** the *Privacy Policy URL* and *Support
URL* fields on the app record must be set to the privacy and support addresses
above. App Review checks the Privacy Policy URL specifically and will reject a
submission where it 404s.

## 3. Camera

| Item | Verdict | Evidence |
| --- | --- | --- |
| `NSCameraUsageDescription` present and accurate | **PASS** | `INFOPLIST_KEY_NSCameraUsageDescription` in both build configurations: "Elemora uses the camera to recognize chemical names, formulas, and structure identifiers you point it at. Frames are analyzed on your device and are never recorded or uploaded." |
| Access requested only in context | **PASS** | `ChemistryScannerModel.start(isSupported:)` is the only caller of `CameraAuthorization.request()`, and it runs when the scanner is opened |
| Nothing asked for at launch | **PASS** | No camera API is touched anywhere on the launch path |
| Denial handled without a crash | **PASS** | Denied, restricted and unsupported are three distinct screens, each offering a search fallback; a UI test drives the path |
| No photo library access | **PASS** | No `NSPhotoLibraryUsageDescription`, and no Photos API is linked |
| Frames never leave the device | **PASS** | Recognition is `DataScannerViewController` on device. No image is written to disk and no image-bearing request exists in the source. Only recognized text can reach PubChem |
| No third-party recognition service | **PASS** | The app has zero third-party packages; `OCSR.md` records why no hosted OCSR was adopted |

## 4. Notifications

| Item | Verdict | Evidence |
| --- | --- | --- |
| Permission requested only in context | **PASS** | `StudyNotificationScheduler.enable(state:)` is the only caller of `requestAuthorization`, reached from the Settings toggle; a unit test asserts that merely opening Settings does not prompt |
| Nothing asked for at launch | **PASS** | `refreshAuthorization()` reads the status and never requests |
| Value explained before the prompt | **PASS** | Each category states what it does beside its switch |
| Everything off by default | **PASS** | `NotificationPreferences()` is disabled with no categories; unit-tested |
| Rate limited | **PASS** | One a day, priority-ordered; inactivity waits three days then a week; unit-tested |
| No critical or time-sensitive alerts | **PASS** | `interruptionLevel = .active`, and `.criticalAlert` is never requested |
| Local only | **PASS** | No push entitlement, no token, no server |
| Deep links land where they say | **PASS** | `NotificationDestination` round-trips through `userInfo`; unit-tested |
| Stale requests cannot accumulate | **PASS** | Stable identifiers, and every reconcile removes this app's own pending requests first; unit-tested |

## 4a. The Home Screen widget

| Item | Verdict | Evidence |
| --- | --- | --- |
| The widget reaches no network | **PASS** | `ElemoraWidgets/` contains no URL, no `URLSession` and no networking import; it reads one JSON file |
| The widget never writes the learner's progress | **PASS** | It appends to a log; `WidgetBridge` in the app is the only thing that writes `ProgressStore` |
| A repeated intent cannot double-count | **PASS** | A UUID per answer plus a bounded merge ledger; unit-tested, including a second merge of the same batch |
| Existing progress is not migrated or erased | **PASS** | No schema change: `WidgetBridge` calls the same `recordAnswer` a study round does. A test asserts pre-existing progress is identical after a merge |
| The App Group is the only new capability | **PASS** | `Config/Elemora.entitlements` and `Config/ElemoraWidgets.entitlements` declare `com.apple.security.application-groups` and nothing else; `Tools/check_widget_shared.py` fails if the app gains a third |
| An unavailable App Group is handled | **PASS** | Every store takes an optional URL and no-ops on `nil`; the widget renders an explanatory state; unit-tested |
| The extension declares its extension point | **PASS** | `Config/ElemoraWidgets-Info.plist`, checked by `Tools/check_widget_shared.py` — without it the widget builds and never appears |
| The shared serialization cannot drift | **PASS** | Byte-for-byte comparison of the two copies, in `Tools/verify.sh` and CI |

**MANUAL ACTION — Apple Developer portal:** the App Group
`group.com.idlery.periodicpro` and the widget's App ID
`com.idlery.periodicpro.widgets` must exist under the team. Archiving passes
`-allowProvisioningUpdates` with the App Store Connect API key, which normally
registers both on the first archive — but that depends on the key having the
**App Manager** role. If the archive fails on provisioning, create the App
Group under *Certificates, Identifiers & Profiles → Identifiers → App Groups*,
enable it on both App IDs, and re-run. This is the one part of Build 5 that
can fail at signing, which is why the widget is its own commit and can be
reverted on its own.

## 5. Privacy manifest and required-reason APIs

| Item | Verdict | Evidence |
| --- | --- | --- |
| `PrivacyInfo.xcprivacy` present and shipped | **PASS** | Copied into the bundle; the archive step lists it |
| `NSPrivacyTracking` = false | **PASS** | No tracking of any kind exists in the app |
| `NSPrivacyTrackingDomains` empty | **PASS** | Correct while tracking is false |
| `NSPrivacyCollectedDataTypes` empty | **PASS** | Nothing is transmitted off the device in a form that outlives servicing the request. Reasoning in `PRIVACY.md` → *App Store privacy declaration* |
| `UserDefaults` reason declared | **PASS** | `CA92.1` |
| File timestamp reason declared | **PASS** | `C617.1` |
| No newly used required-reason API | **PASS** | Build 5 adds AVFoundation authorization, VisionKit, UserNotifications, WidgetKit and AppIntents. None is on Apple's required-reason list; no disk-space, boot-time or active-keyboard API is used |
| The widget's file access is already declared | **PASS** | It reads and writes JSON in the app group container, covered by the existing `C617.1` file-timestamp reason; it uses no `UserDefaults` |

**MANUAL ACTION — App Store Connect:** confirm the *App Privacy* answers still
read **"Data Not Collected"**. Build 5 does not change what leaves the device,
so no answer should need changing — but the camera is the kind of addition a
reviewer looks at, and the answer is worth re-reading against the reasoning in
`PRIVACY.md` before submitting. If the site ever gains analytics, or a future
build sends an image anywhere, these answers change and the privacy policy has
to change with them.

## 6. Capabilities and signing

| Item | Verdict | Evidence |
| --- | --- | --- |
| Bundle identifier unchanged | **PASS** | `com.idlery.periodicpro`; the TestFlight workflow fails the run if the repository variable disagrees with `Config/Shared.xcconfig` |
| Associated Domains | **PASS** (already enabled) | `Config/Elemora.entitlements`; shared quiz links depend on it |
| Camera | **PASS** | Needs a purpose string only — no entitlement and no App ID capability |
| Notifications | **PASS** | Local notifications need no entitlement |
| App Groups | **NEEDS FIRST ARCHIVE** | New in Build 5, for the widget. See *4a*: automatic provisioning should register it, and the manual fallback is one page in the developer portal |
| Widget extension bundle identifier | **PASS** | `com.idlery.periodicpro.widgets`, derived from the app's rather than a new identifier; the main app's is untouched |
| Automatic signing via the API key | **PASS** | The archive step passes `-allowProvisioningUpdates` with the App Store Connect key |

## 7. Content and rights

| Item | Verdict | Evidence |
| --- | --- | --- |
| Element data sourced | **PASS** | `DATA_SOURCES.md` — IUPAC 2021 weights, and the validation the dataset passes |
| Compound data sourced | **PASS** | `COMPOUND_SOURCES.md` |
| Structure data sourced | **PASS** | `STRUCTURE_SOURCES.md`, and every structure now records its own provenance |
| Advanced question data sourced | **PASS** | `DATA_SOURCES.md` → *Advanced chemistry questions*, including the one curated table and why it is short |
| PubChem attributed | **PASS** | "Data source: PubChem, CID …" on every fetched record, and a line naming the National Library of Medicine |
| No third-party ML model shipped | **PASS** | None. `OCSR.md` records the licensing audit that would have to happen first |
| App icon original | **PASS** | Generated from geometry in `Tools/make_app_icon.py`; no third-party artwork |
| No advertising, analytics, accounts or leaderboards | **PASS** | Zero third-party packages |

## 8. Accessibility

| Item | Verdict | Evidence |
| --- | --- | --- |
| VoiceOver labels on new surfaces | **PASS** | Scanner, launch screen, rank, learning path, advanced questions and notification settings all carry labels |
| Rank and path are not color-only | **PASS** | Each rank has a distinct SF Symbol; the current path stage is marked with the word "NEXT" as well as a color |
| Dynamic Type | **PASS** | Everything new scales; the table's f-block captions scale down inside a reserved box so the table keeps fitting |
| Reduce Motion | **PASS** | Honored on the launch screen, the advanced session and the compound cards |
| 44-point targets | **PASS** | Every new control uses `Theme.minimumTouchTarget` |
| Scanner has a non-camera path | **PASS** | A search field on every dead end |
| 3D has a textual alternative | **PASS** | The accessible parts list, and the structure's spoken summary |

## 9. Remaining blockers

Nothing in the repository. Everything below needs a person.

1. **Deploy the website** and confirm all four URLs answer 200 over HTTPS.
2. **Set the Privacy Policy URL and Support URL** on the App Store Connect
   record.
3. **Re-read the App Privacy answers** against `PRIVACY.md` now that the app
   has a camera feature.
4. **Confirm both subscription products are Ready to Submit** in the
   `periodicpro.pro` group.
5. **Upload screenshots** for every device size the listing requires. CI
   captures a tour on four simulators and attaches it to each run as
   `elemora-simulator-screenshots`.
6. **Confirm the widget appears** after installing the TestFlight build:
   touch and hold the Home Screen → Edit → Add Widget → Elemora. A widget that
   never appears means the App Group or the extension point did not make it
   through signing — see *4a*.
7. **Test the scanner on a physical device.** A simulator has no camera and
   cannot run live text recognition, so the recognition core is unit-tested
   against text fixtures and the camera path is not exercised by CI. The
   TestFlight notes list the exact cases to try.
8. **Run the live PubChem smoke suite** (`python3 Tools/smoke_pubchem.py`) from
   a machine that can reach the internet. It is not in CI on purpose, and it
   has not been run from the environment that wrote this build — PubChem is
   unreachable from there, which the tool reports as unreachable rather than
   as a pass.
