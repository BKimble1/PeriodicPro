# Shipping Periodic Pro to TestFlight

This repository is wired so that a TestFlight build needs **no code changes** —
only credentials and two identifiers you own. Everything below is a one-time
setup; after that, pushing a `v*` tag ships a build.

---

## 0. What you need before you start

- An **Apple Developer Program** membership (paid). Individual or Organization.
- Admin or Account Holder access to **App Store Connect** (to create an API key).
- A bundle identifier you own, e.g. `com.yourcompany.periodicpro`.

Everything else — the archive, the signing, the upload — is automated.

---

## 1. Claim a bundle identifier

The repository ships with the deliberate placeholder
`com.example.periodicpro`, which you do not own and cannot upload.

1. Go to <https://developer.apple.com/account/resources/identifiers/list>.
2. **Identifiers → + → App IDs → App**.
3. Description: `Periodic Pro`. Bundle ID: **Explicit**,
   `com.yourcompany.periodicpro`.
4. Capabilities: leave everything off. The app needs none.
5. Register.

Then set it in **one** of two places:

- **For CI (recommended):** repository → Settings → Secrets and variables →
  Actions → **Variables** → New repository variable
  `BUNDLE_IDENTIFIER` = `com.yourcompany.periodicpro`.
- **For local builds:** `cp Config/Local.xcconfig.sample Config/Local.xcconfig`
  and edit it. That file is git-ignored.

You may instead edit `PRODUCT_BUNDLE_IDENTIFIER_BASE` in `Config/Shared.xcconfig`
and commit it — fine for a private fork, but then the identifier lives in git.

---

## 2. Create the app record in App Store Connect

1. <https://appstoreconnect.apple.com> → **Apps → + → New App**.
2. Platform **iOS**, Name `Periodic Pro` (or your own name — see *Renaming*
   below), Primary Language, your bundle ID, SKU `periodicpro-1`.
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

Supply these four **only** if your organisation forbids cloud signing, or you
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

Either way the workflow will:

1. check out the repository
2. select Xcode 26 — App Store Connect rejects builds from older toolchains, so
   the job fails loudly rather than silently producing a rejectable archive
3. install the API key into `~/.appstoreconnect/private_keys`
4. decide between cloud signing and manual signing
5. run the unit tests on an iPhone simulator
6. compute the build number as `run number + BUILD_NUMBER_OFFSET`
7. archive Release for a generic iOS device
8. export a signed `.ipa` using `app-store-connect` export options
9. **validate** the `.ipa` against App Store Connect
10. **upload** it
11. publish a job summary with the version, build number and signing mode, and
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

   - **What to Test:** "Tap any element to open its detail page. Try the search
     field with a name, a symbol and an atomic number. Run a flashcard round and
     a quick quiz, then check the Progress tab."
   - **Feedback Email:** yours.
   - **Beta App Description:** "A clean, offline reference and study app for the
     periodic table. Explore all 118 elements, then practise with flashcards,
     quizzes and identify rounds."
   - **Sign-in required:** No.

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

Everything is in `Config/Shared.xcconfig`:

| Setting | Effect |
| --- | --- |
| `APP_DISPLAY_NAME` | The name under the icon |
| `PRODUCT_BUNDLE_IDENTIFIER_BASE` | The app's bundle ID; the test bundles derive `.tests` and `.uitests` from it |
| `MARKETING_VERSION` | The version testers see |
| `CURRENT_PROJECT_VERSION` | Build number (CI overrides this) |
| `APP_DEVELOPMENT_TEAM` | Signing team |

Only the Xcode *target* name stays `PeriodicPro`; nothing user-visible depends
on it.

---

## Troubleshooting

**`Xcode 26.0 is not installed on this runner`**
GitHub has rotated its image. Check the runner's Xcode list in the failed step's
log and update `XCODE_VERSION` in both workflow files. Do not fall back to an
older major version — App Store Connect will reject the build.

**`No profiles for 'com.example.periodicpro' were found`**
`BUNDLE_IDENTIFIER` is unset, so the build used the placeholder. Set the
repository variable from step 1.

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

**Upload succeeds but the build never appears**
Check the email on the Apple ID that owns the API key. App Store Connect emails
processing failures (most often a missing privacy manifest or an invalid icon)
rather than showing them in the UI.
