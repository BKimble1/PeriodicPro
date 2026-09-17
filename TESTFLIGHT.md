# Shipping Elemora to TestFlight

This repository is wired so that a TestFlight build needs **no code changes** —
only credentials and two identifiers you own. Everything below is a one-time
setup; after that, pushing a `v*` tag ships a build — or, while the workflows are
still on the feature branch, a commit marked `[testflight]` (see §6).

> ## Names versus identifiers
>
> | | Value | May it change? |
> | --- | --- | --- |
> | App Store name | **Elemora: Periodic Table** | brand |
> | Home Screen name (`APP_DISPLAY_NAME`) | **Elemora** | brand |
> | Paid tier, everywhere a customer reads it | **Elemora Pro** | brand |
> | Bundle identifier | `com.idlery.periodicpro` | **no — permanent** |
> | Monthly product identifier | `periodicpro.pro.monthly` | **no — permanent** |
> | Yearly product identifier | `periodicpro.pro.yearly` | **no — permanent** |
> | Subscription group identifier | `periodicpro.pro` | **no — permanent** |
> | Xcode project, scheme, target, test bundles | `PeriodicPro` | no — wired into CI |
>
> The `periodicpro` identifiers are deliberate. Apple binds the App Store
> record, the provisioning profiles and every subscriber's receipt to them, and
> none of them can be changed after the first upload. Renaming one would need a
> second App Store Connect app and would strand existing subscribers.

---

## 0. What you need before you start

- An **Apple Developer Program** membership (paid). Individual or Organization.
- Admin or Account Holder access to **App Store Connect** (to create an API key).
- The bundle identifier `com.idlery.periodicpro`, already registered.

Everything else — the archive, the signing, the upload — is automated.

---

## 1. Claim a bundle identifier

**Already done.** The identifier is `com.idlery.periodicpro`, it is registered
at Apple, and it is committed as `PRODUCT_BUNDLE_IDENTIFIER_BASE` in
`Config/Shared.xcconfig`. It keeps the `periodicpro` spelling on purpose; see
*Names versus identifiers* at the top of this file.

CI also reads it from the repository variable `BUNDLE_IDENTIFIER`
(Settings → Secrets and variables → Actions → **Variables**), which must hold
the same value, `com.idlery.periodicpro`. The variable wins when both are set,
so the two must not drift apart.

For a local build with a different team, copy
`Config/Local.xcconfig.sample` to `Config/Local.xcconfig` and override it
there. That file is git-ignored.

If you ever need to register it again:

1. Go to <https://developer.apple.com/account/resources/identifiers/list>.
2. **Identifiers → + → App IDs → App**.
3. Description: `Elemora`. Bundle ID: **Explicit**, `com.idlery.periodicpro`.
4. Capabilities: tick **Associated Domains**. Nothing else is needed.
5. Register.

**Associated Domains is required.** Elemora's shared quiz links are universal
links to `elemora.idlery.com`, and `Config/Elemora.entitlements` claims
`applinks:elemora.idlery.com`. If the capability is not enabled on the App ID,
the archive step fails to sign with a provisioning-profile error naming the
entitlement. The fix is the portal toggle above for `com.idlery.periodicpro`,
not removing the entitlement — removing it would silently turn every shared
quiz link into a web page that cannot open the app. The TestFlight workflow
detects this specific failure and prints it as an actionable error.

---

## 2. Create the app record in App Store Connect

1. <https://appstoreconnect.apple.com> → **Apps → + → New App**.
2. Platform **iOS**, Name `Elemora: Periodic Table`, Primary Language,
   bundle ID `com.idlery.periodicpro`, SKU `periodicpro-1`.
3. User Access: Full Access.
4. Create.

You do **not** need to fill in screenshots, pricing or the store listing to use
TestFlight. You do need the App Privacy answers, which take about a minute —
see `PRIVACY.md` (the answer is "No data collected").

---

## 3. Create an App Store Connect API key

This is what lets CI sign and upload without any human at a Mac.

1. App Store Connect → **Users and Access → Integrations → App Store Connect API**.
2. **Team Keys → +**.
3. Name: `GitHub Actions`. Access: **App Manager**.
   *App Manager is required — a Developer-level key cannot create the signing
   certificates that automatic cloud signing needs.*
4. Generate, then **Download** the `.p8` file. **You can only download it once.**
5. Note the **Key ID** (10 characters, shown in the row) and the **Issuer ID**
   (a UUID shown above the table).

---

## 4. Find your Team ID

<https://developer.apple.com/account> → **Membership details** → *Team ID*.
Ten alphanumeric characters, e.g. `A1B2C3D4E5`.

---

## 5. Add the GitHub secrets

Repository → **Settings → Secrets and variables → Actions → Secrets → New
repository secret**.

### Required — these four are the whole setup

| Secret | Where it comes from |
| --- | --- |
| `APP_STORE_CONNECT_KEY_ID` | Step 3, the 10-character Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | Step 3, the issuer UUID |
| `APP_STORE_CONNECT_PRIVATE_KEY` | Step 3, the **entire contents** of the `.p8` file, including `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----`. Paste it verbatim, newlines and all |
| `APPLE_TEAM_ID` | Step 4 |

### Variables (not secrets — these are not sensitive)

| Variable | Value |
| --- | --- |
| `BUNDLE_IDENTIFIER` | Your bundle ID from step 1 |
| `BUILD_NUMBER_OFFSET` | Optional. Added to the workflow run number to form the build number. Set it if you have already uploaded builds and need the number to keep rising |

### Optional — only for manual signing

By default the workflow uses **Xcode cloud signing**: it passes the API key to
`xcodebuild -allowProvisioningUpdates`, and Xcode creates and fetches the
distribution certificate and provisioning profile itself. Nothing else is needed.

Supply these four **only** if your organization forbids cloud signing, or you
have hit the Apple limit of three distribution certificates and cannot revoke
one. Setting `BUILD_CERTIFICATE_BASE64` is what switches the workflow to manual
signing; it detects the mode automatically.

| Secret | How to produce it |
| --- | --- |
| `BUILD_CERTIFICATE_BASE64` | Export your *Apple Distribution* certificate and private key from Keychain Access as `.p12`, then `base64 -i cert.p12 \| pbcopy` |
| `P12_PASSWORD` | The password you set when exporting the `.p12` |
| `PROVISIONING_PROFILE_BASE64` | Download the App Store provisioning profile for your bundle ID, then `base64 -i profile.mobileprovision \| pbcopy` |
| `KEYCHAIN_PASSWORD` | Any strong random string. It only ever unlocks a temporary keychain on the runner, which is deleted at the end of the job |

**Never commit any of these.** `.gitignore` already blocks `*.p8`, `*.p12`,
`*.mobileprovision` and `Config/Local.xcconfig`.

---

## 6. Ship a build

### Automatically, from a tag

```bash
git tag v1.0.0
git push origin v1.0.0
```

### Manually

GitHub → **Actions → TestFlight → Run workflow**.

### Before the workflows reach `main`

Both routes above need something this repository does not have yet. GitHub
registers **Run workflow** from the default branch only, and `.github/workflows`
currently lives on the feature branch, so the button is not offered. A tag is no
better when the credentials pushing it are scoped to `refs/heads/claude/*`.

Until the workflows are merged, a push to a `claude/**` branch ships a build if,
and only if, its commit message contains `[testflight]`:

```bash
git commit -m "Whatever the change was [testflight]"
git push -u origin claude/my-branch
```

An ordinary push to those branches still ships nothing — the job is gated on that
marker, because a build number is spent and a build that reaches App Store Connect
cannot be unsent. Once the workflows are on `main`, delete the `branches:` line
and the `contains(...)` clause from `.github/workflows/testflight.yml` and use
tags.

Either way the workflow will:

1. check out the repository
2. select Xcode 26 — App Store Connect rejects builds from older toolchains, so
   the job fails loudly rather than silently producing a rejectable archive
3. install the API key into `~/.appstoreconnect/private_keys`
4. decide between cloud signing and manual signing
5. run the unit tests on an iPhone simulator
6. compute the build number as `run number + BUILD_NUMBER_OFFSET`
7. archive Release for a generic iOS device
8. read the archive back — device families, Home Screen name, version, build
   number and the export-compliance flag — and stop before the upload if any of
   them is not what was asked for
9. export a signed `.ipa` using `app-store-connect` export options
10. **validate** the `.ipa` against App Store Connect
11. **upload** it
12. publish a job summary with the version, build number and signing mode, and
    attach the `.ipa` and dSYMs as build artifacts for 14 days

Processing in App Store Connect usually takes 5–15 minutes after the upload
succeeds.

---

## 7. First TestFlight distribution

1. App Store Connect → your app → **TestFlight**.
2. The build appears under *iOS builds*, first as **Processing**.
3. Export compliance is answered automatically — `Config/Info.plist` declares
   `ITSAppUsesNonExemptEncryption = false`, so you are not asked.
4. **Internal Testing** → add yourself to a group → builds go out immediately,
   no review.
5. **External Testing** needs a short Beta App Review (usually under 24 hours)
   the first time. Fill in the *Test Information* fields:

   - **What to Test** (Build 5): "The whole periodic table is visible the
     moment the app opens — check it fits your screen without scrolling. Point
     the scanner at a printed formula or compound name. Add the Elemora widget
     to your Home Screen, answer a question there, then open the app and check
     it counted. Build a compound with more than thirty atoms. Try the Advanced
     mode in Study, and look at your rank and learning path in Progress."
     Section 7a lists the cases in full.
   - **Feedback Email:** yours.
   - **Beta App Description:** "A clean, offline reference and study app for the
     periodic table. Explore all 118 elements, then practice with flashcards,
     quizzes and identify rounds."
   - **Sign-in required:** No.

---

## 7a. Build 5 — what to test on a real device

Build 5 adds three things a simulator cannot fully exercise. These are the
cases worth a person's time; everything else in the build is covered by the
automated tests.

**The chemistry scanner** — Table tab → the scan button in the toolbar.
A simulator has no camera, so none of this has been run against live video.

- The camera permission prompt appears the *first time you open the scanner*
  and never at launch. Decline it: you should get a screen that explains and
  offers a search field, not a dead end. Grant it in iOS Settings and reopen.
- Point it at a printed formula — `H2O`, `NaCl`, `C8H10N4O2`. A match should
  settle rather than flicker: the reading has to hold still before it is
  offered.
- Point it at a compound name in a textbook — "sodium chloride", "acetic
  acid". Names need to look like names, so ordinary prose should be ignored.
  Sweep across a paragraph and confirm nothing is offered for "provide",
  "solution" or "state".
- Point it at an InChIKey or a SMILES string if you have one to hand.
- Point it at a **drawn skeletal structure**. It should *not* claim to
  recognize the molecule. Reading a drawing is a different problem from
  reading text, and `OCSR.md` records why nothing in this build claims to do
  it. If it ever says it has identified a structure from a drawing, that is a
  bug worth reporting immediately.
- Cover the lens, point it at a blank wall, point it at a moving page. None of
  those should produce a result or a crash.

**The Home Screen widget** — touch and hold the Home Screen → Edit → Add
Widget → Elemora.

- Both widgets should be offered: *Quick Question* (medium and large) and
  *Progress* (small and medium). If neither appears, the App Group did not
  survive signing — see `APP_STORE_READINESS.md` §4a.
- Answer a question on the Home Screen. It should tell you right or wrong and
  show the fact behind it, then move on when you tap Next.
- **Then open Elemora and check the Progress tab.** The answer should be
  counted: cards answered goes up, and the element you answered about moves.
  Answer one late at night and open the app the next morning — it should count
  for the night you answered it, not the morning you opened the app.
- Answer several, then open and close the app twice. Nothing should be counted
  twice.
- Add both widgets and answer in one. The other should keep working.

**Notifications** — Progress → ⚙︎ → Notifications.

- Nothing should have asked for permission before you get here.
- Turn the master switch on: the system prompt appears then, and two
  categories turn on, not five.
- Decline the prompt. The switch should go back off and say that iOS is
  blocking, with a way through to Settings.
- Set a reminder time and leave it a day. At most one notification should
  arrive.

---

## 7b. App Store Connect answers you will be asked for

These are the only questionnaire answers the app needs, and none of them
change between releases.

**Age rating** — the app qualifies for **4+**. Answer *None* to every content
question: no violence, no profanity, no horror, no mature or suggestive themes,
no alcohol/tobacco/drug references, no simulated gambling, no contests, no
medical or treatment information (the app describes elements, it never gives
health advice), no unrestricted web access, and no user-generated content.
There is no advertising.

The app **does** offer in-app purchases (the Elemora Pro subscription), so tick
that box on the App Store listing. It does not affect the 4+ rating.

**App Privacy** — *Do you or your third-party partners collect data from this
app?* → **No**. That single answer completes the section; see `PRIVACY.md`.
Subscriptions do not change this: Apple handles the transaction, and the app is
only ever told whether an entitlement is active. It never sees a payment
detail, an Apple Account or a name, and it has no server to send one to.

**Subscriptions** — two products in one group must exist and be at least *Ready
to Submit* before a TestFlight sandbox purchase will work. See
**MONETIZATION.md** for the identifiers, the prices, and the exact steps. The
app reads every price from StoreKit, so nothing needs changing in code when you
set them.

**Privacy Policy URL and Terms of Use (EULA)** are both required in App
Information because the app sells a subscription. Elemora hosts its own pages
and the paywall links to them, so use the same two URLs here:
`https://elemora.idlery.com/privacy` and `https://elemora.idlery.com/terms`.
`PRIVACY.md` is the source text for the privacy page, and `Website/site/` holds
both pages ready to deploy.

**Export compliance** — handled automatically. `Config/Info.plist` sets
`ITSAppUsesNonExemptEncryption` to `false`, so TestFlight never stops to ask.

**Content rights** — the app contains no third-party content. Element data is
assembled from public scientific reference values (see `DATA_SOURCES.md`) and
all artwork is original.

**Category** — Primary: *Education*. Secondary: *Reference*. The build already
declares `LSApplicationCategoryType = public.app-category.education`.

**Sign-in required for review** → **No**. There is no account.

---

## 8. Releasing a new version

- **New build, same version** (e.g. fixing a bug in 1.0.0): just re-run the
  workflow. The build number rises with the run number, so the upload is
  accepted.
- **New version**: bump `MARKETING_VERSION` in `Config/Shared.xcconfig`, commit,
  tag `vX.Y.Z`, push the tag.

Version numbers are semantic: `MAJOR.MINOR.PATCH`.

---

## 9. Building and installing from your own Mac

```bash
cp Config/Local.xcconfig.sample Config/Local.xcconfig   # then edit it
open PeriodicPro.xcodeproj
```

Select the **PeriodicPro** scheme and your device, then ⌘R. With
`APP_DEVELOPMENT_TEAM` set in `Config/Local.xcconfig`, Xcode's automatic signing
handles the rest.

To archive by hand:

```bash
xcodebuild archive \
  -project PeriodicPro.xcodeproj \
  -scheme PeriodicPro \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/PeriodicPro.xcarchive
```

Then **Xcode → Window → Organizer → Distribute App → TestFlight & App Store**.

---

## Renaming the product

The user-visible name lives in `Config/Shared.xcconfig`:

| Setting | Effect | Current value |
| --- | --- | --- |
| `APP_DISPLAY_NAME` | The name under the icon | `Elemora` |
| `MARKETING_VERSION` | The version testers see | `3.0.0` |
| `CURRENT_PROJECT_VERSION` | Build number (CI overrides this) | `1` |
| `APP_DEVELOPMENT_TEAM` | Signing team | supplied by CI |

`PRODUCT_BUNDLE_IDENTIFIER_BASE` is in the same file but is **not** a rename
knob any more: it is `com.idlery.periodicpro`, Apple owns that binding, and
changing it after an upload means a new app record. The Xcode project, scheme,
target and test bundles are likewise still called `PeriodicPro`, and nothing
user-visible depends on any of them.

---

## Troubleshooting

**`Xcode 26.0 is not installed on this runner`**
GitHub has rotated its image. The failed step prints the runner's Xcode list;
update `XCODE_VERSION` in both workflow files to a version that is present, and
if the newer toolchain has moved to a newer image, update `runs-on` as well
(both workflows currently pin `macos-15`). Do not fall back to an older major
version — App Store Connect will reject the build.

**`No profiles for '<some identifier>' were found`**
The identifier the archive used is not one this Apple account owns. Check that
the repository variable `BUNDLE_IDENTIFIER` is exactly
`com.idlery.periodicpro` — it overrides `Config/Shared.xcconfig`, so a typo
there beats the committed value.

**`Your account does not have sufficient permissions`**
The API key was created with Developer access. Delete it and create a new one
with **App Manager** (step 3).

**`APP_STORE_CONNECT_PRIVATE_KEY does not look like a .p8 file`**
The secret is missing the PEM header. Paste the whole file, including the
`-----BEGIN PRIVATE KEY-----` line.

**`The provided entity includes an attribute with a value that has already been
used` (build number)**
That build number already exists in App Store Connect. Set the
`BUILD_NUMBER_OFFSET` variable high enough to clear the existing builds.

**`Invalid Bundle. The bundle does not support the minimum OS version`**
Deployment target and simulator destination disagree. `IPHONEOS_DEPLOYMENT_TARGET`
is 18.0 in `Config/Shared.xcconfig`; the archive destination must be
`generic/platform=iOS`.

**`No profiles for 'com.idlery.periodicpro.widgets' were found`, or an App
Group error, on the first Build 5 archive**
The widget extension is new in Build 5 and needs two things registered under
the team: its own App ID, and the App Group `group.com.idlery.periodicpro`.
`-allowProvisioningUpdates` normally creates both on the first archive, but
only if the API key has **App Manager** access rather than Developer. If it
does not, create them by hand — *Certificates, Identifiers & Profiles →
Identifiers*, add the App Group, then enable **App Groups** on both
`com.idlery.periodicpro` and `com.idlery.periodicpro.widgets` — and re-run.
Nothing about the main app's identifier changes either way.

If you would rather ship Build 5 without the widget than wait, revert the
commit that added it ("Answer a chemistry question without opening the app").
It is deliberately the only commit that touches signing, and reverting it
leaves every other Build 5 feature intact.

**Upload succeeds but the build never appears**
Check the email on the Apple ID that owns the API key. App Store Connect emails
processing failures (most often a missing privacy manifest or an invalid icon)
rather than showing them in the UI.
