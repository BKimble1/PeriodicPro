# Periodic Pro — subscriptions

Everything the app needs to sell Periodic Pro, and everything that still has to
be created in App Store Connect before a build can take a real payment.

No third-party subscription SDK is used. There is no RevenueCat, no analytics,
no account and no server. Entitlement comes from StoreKit 2 and nothing else.

---

## What Pro unlocks

| | Free | Periodic Pro |
|---|---|---|
| All 118 elements, the full table, search, filters | ✅ | ✅ |
| Favorites, core facts, About, Common Uses, Memory Hooks | ✅ | ✅ |
| Progress, streak, per-family breakdown | ✅ | ✅ |
| Flashcards, Quick Quiz, Identify | ✅ | ✅ |
| Study rounds per day | 3 | Unlimited |
| Interactive 3D structure explorer | 6 elements | All 118 |
| Smart Review | — | ✅ |

**Nothing scientific is behind the paywall.** Every fact, every diagram caption,
every element page is free. Pro buys depth: unlimited practice, the interactive
explorer for the whole table, and rounds targeted at what you keep missing.

### The free 3D elements

Hydrogen, carbon, oxygen, sodium, iron and gold — atomic numbers 1, 6, 8, 11, 26
and 79 — are fully explorable without paying. They are chosen to cover several
structure types (a single-bonded diatomic, a double-bonded diatomic, a covalent
network and three metallic lattices) so a free user sees the real feature rather
than a trailer. The list lives in `ProAccess.demoAtomicNumbers` and is asserted
by `ProAccessTests`.

---

## Products to create in App Store Connect

Create **one subscription group** containing **two subscriptions**.

| Field | Value |
|---|---|
| Subscription group reference name | `Periodic Pro` |
| Group identifier used in the app | `periodicpro.pro` |

| Product | Identifier | Duration | Target price (US) |
|---|---|---|---|
| Monthly | `periodicpro.pro.monthly` | 1 month | $2.99 |
| Yearly | `periodicpro.pro.yearly` | 1 year | $19.99 |

The target prices are what to enter when creating the products. **The app never
displays them from source.** Every price on the paywall comes from
`Product.displayPrice`, and the yearly plan's "per month" figure and its savings
badge are computed from the two live `Product.price` values. Change the price in
App Store Connect and the paywall follows, in the right currency, with no code
change. `Tools/check_storekit.py` fails the build if the identifiers in
`SubscriptionProduct.swift` and `Config/PeriodicPro.storekit` ever disagree.

### Steps in App Store Connect

1. **App Store Connect → your app → Subscriptions → Create a subscription group.**
   Reference name `Periodic Pro`.
2. Add subscription `periodicpro.pro.monthly`, duration 1 month, price $2.99.
3. Add subscription `periodicpro.pro.yearly`, duration 1 year, price $19.99.
4. Give each a display name and description for every locale you ship.
   English is enough to start.
5. Add the **subscription group localization** (the group needs its own display
   name — `Periodic Pro`), or the products stay in "Missing Metadata".
6. Upload a **review screenshot** of the paywall for each product.
7. Fill in the **App Store Server Notifications** URL only if you want one — this
   app does not need it, because it has no server and reads entitlement directly
   from the device.
8. Set the **Privacy Policy URL** and **Terms of Use (EULA)** in App Information.
   The paywall links to Apple's standard EULA and shows the app's own privacy
   statement in a sheet, but App Store Connect still requires a hosted privacy
   policy URL. `PRIVACY.md` is the text to host.

Products can be submitted for review alongside the first build that contains
them. They must be **Approved** before a TestFlight sandbox purchase will
succeed against the real App Store.

---

## Testing locally in Xcode

`Config/PeriodicPro.storekit` is a StoreKit configuration file containing both
subscriptions at the target prices. It is **not** inside `PeriodicPro/`, and that
is deliberate: that folder is a synchronized group, so anything dropped in it
ships inside the app bundle. A StoreKit configuration must not.

It is wired into the shared scheme's Run action:

```
PeriodicPro.xcodeproj/xcshareddata/xcschemes/PeriodicPro.xcscheme
  → LaunchAction → StoreKitConfigurationFileReference
      identifier = "../../../Config/PeriodicPro.storekit"
```

So **Run** uses the local configuration and never contacts the App Store.

To exercise the flows:

1. Run the app. Tap Smart Review, or "Explore in 3D" on any element that is not
   one of the free six. The paywall appears with both plans and real formatted
   prices from the configuration.
2. Buy either plan. The purchase completes instantly; the paywall dismisses as
   soon as the entitlement resolves, not as soon as the tap succeeds.
3. **Xcode → Debug → StoreKit → Manage Transactions** to refund, expire or
   revoke the subscription. The app reacts without a relaunch, because
   `SubscriptionManager` listens to `Transaction.updates` for the whole process
   lifetime.
4. To test failure paths, open `Config/PeriodicPro.storekit` in Xcode and use the
   **editor's** error settings (Load Products, Purchase, Verification, App Store
   Sync). The paywall has a designed state for each: loading, unavailable with a
   Try again button, pending, canceled and failed.
5. **Ask to Buy** is simulated from the same editor; it drives `PurchaseState`
   to `.pending`, which the paywall reports as waiting for approval rather than
   as a failure.

### What the unit tests do

Nothing in `PeriodicProTests` contacts StoreKit. `SubscriptionManager` has a
second initializer, `init(testingEntitlement:products:)`, that never opens a
connection, and every gating decision lives in a pure function that takes an
`isPro` flag:

* `ProAccess.isUnlocked(_:isPro:)`
* `DailyStudyLimiter.canStartRound(completedToday:isPro:)`

So free, Pro, expired and revoked are all reachable as ordinary test inputs.
`ProGateTests` covers each, plus the demo-element list, the daily allowance
boundary at rounds 3 and 4, the day rollover, and the rule that an abandoned
round costs nothing.

### UI tests

UI tests never drive a purchase sheet — it cannot be done reliably from
XCUITest. They use launch arguments instead:

| Argument | Effect |
|---|---|
| `-uiTesting` | In-memory store, no onboarding, no haptics, **StoreKit disabled**, free entitlement |
| `-uiTesting -proEntitled` | The same, but the app behaves as a subscriber |

With StoreKit disabled the paywall still presents, still shows Restore, Privacy,
Terms and the auto-renewal wording, and still closes — which is what the UI
tests assert.

---

## TestFlight sandbox

TestFlight builds use the **sandbox** environment automatically. There is nothing
to configure in the app.

* Testers are not charged. Sandbox renewals are accelerated: a monthly
  subscription renews every 5 minutes, a yearly one every hour, and each
  auto-renews at most 6 times before expiring.
* A tester's sandbox Apple Account is managed in
  **Settings → Developer → Sandbox Apple Account** on the device.
* The products must be at least **Ready to Submit** in App Store Connect, or
  `Product.products(for:)` returns an empty array and the paywall correctly
  reports that options could not be loaded.
* Purchases made in TestFlight do not carry over to the App Store version.

---

## How entitlement works in the app

```
SubscriptionManager (@MainActor @Observable, one instance, app lifetime)
  ├─ Transaction.updates      → a renewal, refund, revocation, or a purchase
  │                             made on another device, without a relaunch
  ├─ Transaction.currentEntitlements → recomputed into ProEntitlement
  └─ publishes: entitlement, purchaseState, products

ProEntitlement  .unknown | .free | .pro(ProSubscriptionInfo)
ProFeature      .interactiveStructure(atomicNumber:) | .unlimitedStudy | .smartReview
ProAccess       pure gating rules
DailyStudyLimiter  pure free-allowance rules
```

No view calls StoreKit. Views read `store.isPro` / `store.isUnlocked(_:)` and
call `purchase`, `restore` or `loadProducts` on the manager.

`.unknown` is important: while StoreKit has not yet answered, the app treats the
learner as not-Pro for *access* but shows nothing about Pro state, so a
subscriber never sees a paywall flash on launch.

### Where the paywall can appear

Only when the learner asks for something behind it:

* tapping **Smart Review** without a subscription
* tapping **Explore in 3D** on an element outside the free six
* starting a **fourth round** in a day, or tapping the summary's primary button
  once the allowance is spent — the button says "Get Periodic Pro" at that
  point, so nobody is refused after tapping "Study again"

It never appears at launch, never during onboarding, and never over a round in
progress. A round that has started always finishes.

### Counting rounds

A round counts when it reaches its summary — `StudySessionContainer.finish(_:)`,
which is the single call site for all four modes. Exiting part way through
records the answers already given but does not consume part of the allowance.
The count lives on `StudyDayRecord.completedRounds`, keyed by the same calendar
day as the streak, and `resetAllProgress()` deliberately keeps it so that wiping
progress is not a way to refill the free rounds.

---

## What is deliberately not here

* No receipt validation server. StoreKit 2 verifies transactions on device with
  `VerificationResult`, and an unverified transaction is ignored.
* No promotional offers, introductory offers or free trials. They can be added
  in App Store Connect later; the paywall reads whatever StoreKit returns.
* No family sharing. Both products are created with
  `familyShareable: false`; change it in App Store Connect if you want it.
* No paywall A/B testing, no analytics on conversion. The app measures nothing.
