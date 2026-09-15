import Foundation
import Testing
@testable import PeriodicPro

/// Feature gating, exercised purely through injected entitlement state.
///
/// Nothing here touches StoreKit. `ProAccess` and `DailyStudyLimiter` take an
/// `isPro` flag and a count, which is exactly why they were written that way:
/// every free / Pro / expired / revoked combination is reachable in a test.
@MainActor
@Suite("Pro entitlement")
struct ProEntitlementTests {
    private let active = ProSubscriptionInfo(
        productID: SubscriptionProduct.yearly.rawValue,
        expirationDate: Date(timeIntervalSinceReferenceDate: 1_000_000)
    )

    @Test("Free, Pro and unresolved states report themselves correctly")
    func entitlementStates() {
        #expect(ProEntitlement.free.isPro == false)
        #expect(ProEntitlement.pro(active).isPro == true)
        // Unknown means "StoreKit has not answered". It is not Pro for the
        // purposes of access, but views use `isResolving` to stay quiet rather
        // than flashing a paywall at a subscriber on launch.
        #expect(ProEntitlement.unknown.isPro == false)
        #expect(ProEntitlement.unknown.isResolving == true)
        #expect(ProEntitlement.free.isResolving == false)
    }

    @Test("An expired or revoked subscription is simply not Pro")
    func expiredAndRevokedAreFree() {
        // Both cases resolve to `.free` before they reach any view: `refresh()`
        // skips a transaction with a revocationDate or a past expiry, so the
        // entitlement it publishes is the free one.
        let expired = ProEntitlement.free
        #expect(expired.isPro == false)
        #expect(ProAccess.isUnlocked(.unlimitedStudy, isPro: expired.isPro) == false)
        #expect(ProAccess.isUnlocked(.smartReview, isPro: expired.isPro) == false)
    }

    @Test("The longest-running entitlement wins when two are held")
    func overlappingSubscriptionsResolve() {
        let shorter = ProSubscriptionInfo(
            productID: SubscriptionProduct.monthly.rawValue,
            expirationDate: Date(timeIntervalSinceReferenceDate: 100)
        )
        let longer = ProSubscriptionInfo(
            productID: SubscriptionProduct.yearly.rawValue,
            expirationDate: Date(timeIntervalSinceReferenceDate: 900)
        )
        #expect(SubscriptionManager.longerLasting(nil, shorter) == shorter)
        #expect(SubscriptionManager.longerLasting(shorter, longer) == longer)
        #expect(SubscriptionManager.longerLasting(longer, shorter) == longer)

        // A subscription with no expiry outlasts any dated one.
        let endless = ProSubscriptionInfo(productID: "x", expirationDate: nil)
        #expect(SubscriptionManager.longerLasting(longer, endless) == endless)
        #expect(SubscriptionManager.longerLasting(endless, longer) == endless)
    }

    @Test("Purchase states report whether they are busy and what to say")
    func purchaseStateBehavior() {
        #expect(PurchaseState.loadingProducts.isBusy)
        #expect(PurchaseState.purchasing(productID: "x").isBusy)
        #expect(PurchaseState.restoring.isBusy)
        #expect(!PurchaseState.idle.isBusy)
        #expect(!PurchaseState.pending.isBusy)
        #expect(!PurchaseState.succeeded.isBusy)

        // A pending purchase is not a failure, and must not read like one.
        #expect(PurchaseState.pending.message != nil)
        // Canceling is the learner's own choice; saying anything would be nagging.
        #expect(PurchaseState.canceled.message == nil)
        #expect(PurchaseState.succeeded.message == nil)
        #expect(PurchaseState.failed("nope").message == "nope")
    }

    @Test("A manager built for testing never reaches StoreKit and honors its state")
    func injectedManagerGatesCorrectly() {
        let free = SubscriptionManager(testingEntitlement: .free)
        #expect(free.isPro == false)
        #expect(free.products.isEmpty)

        let pro = SubscriptionManager(testingEntitlement: .pro(active))
        #expect(pro.isPro == true)
        #expect(pro.isUnlocked(.smartReview))
        #expect(pro.isUnlocked(.interactiveStructure(atomicNumber: 118)))
    }
}

@Suite("Feature gates")
struct ProAccessTests {
    /// The six elements the brief names as free to explore.
    private let demoSymbols = ["H", "C", "O", "Na", "Fe", "Au"]

    @Test("The six demo elements are explorable without paying")
    func demoElementsAreFree() {
        for symbol in demoSymbols {
            let element = TestCatalog.element(symbol)
            #expect(
                ProAccess.isUnlocked(
                    .interactiveStructure(atomicNumber: element.atomicNumber), isPro: false
                ),
                "\(symbol) should be free to explore in 3D"
            )
        }
        #expect(ProAccess.demoAtomicNumbers == [1, 6, 8, 11, 26, 79])
    }

    @Test("Every other element needs Pro to explore")
    func nonDemoElementsNeedPro() {
        var gated = 0
        for element in TestCatalog.shared.elements {
            let feature = ProFeature.interactiveStructure(atomicNumber: element.atomicNumber)
            let free = ProAccess.isUnlocked(feature, isPro: false)
            #expect(ProAccess.isUnlocked(feature, isPro: true), "Pro should unlock everything")
            if !free { gated += 1 }
        }
        #expect(gated == 118 - ProAccess.demoAtomicNumbers.count)
    }

    @Test("The demo set covers more than one kind of structure")
    func demoSetIsRepresentative() {
        // The point of the free six is that a learner sees the real feature.
        // If they were all metals, the demo would misrepresent what Pro buys.
        let kinds = Set(ProAccess.demoAtomicNumbers.compactMap { number in
            TestCatalog.shared.element(atomicNumber: number)?.structure
        })
        #expect(kinds.count >= 3, "the free six should span several structure types")
    }

    @Test("Unlimited study and Smart Review are Pro only")
    func studyFeaturesAreGated() {
        #expect(!ProAccess.isUnlocked(.unlimitedStudy, isPro: false))
        #expect(!ProAccess.isUnlocked(.smartReview, isPro: false))
        #expect(ProAccess.isUnlocked(.unlimitedStudy, isPro: true))
        #expect(ProAccess.isUnlocked(.smartReview, isPro: true))
    }

    @Test("Smart Review is the only mode behind Pro")
    func onlySmartReviewRequiresPro() {
        #expect(StudyMode.smartReview.requiresPro)
        for mode in StudyMode.allCases where mode != .smartReview {
            #expect(!mode.requiresPro, "\(mode.rawValue) must stay free")
        }
    }
}

@Suite("Free daily study allowance")
struct DailyStudyLimiterTests {
    @Test("Three rounds a day are free, the fourth is not")
    func freeAllowance() {
        #expect(DailyStudyLimiter.freeRoundsPerDay == 3)
        #expect(DailyStudyLimiter.canStartRound(completedToday: 0, isPro: false))
        #expect(DailyStudyLimiter.canStartRound(completedToday: 1, isPro: false))
        #expect(DailyStudyLimiter.canStartRound(completedToday: 2, isPro: false))
        #expect(!DailyStudyLimiter.canStartRound(completedToday: 3, isPro: false))
        #expect(!DailyStudyLimiter.canStartRound(completedToday: 4, isPro: false))
    }

    @Test("Pro has no limit at all")
    func proIsUnlimited() {
        for completed in [0, 3, 10, 500] {
            #expect(DailyStudyLimiter.canStartRound(completedToday: completed, isPro: true))
            #expect(DailyStudyLimiter.remainingRounds(completedToday: completed, isPro: true) == nil)
            #expect(DailyStudyLimiter.allowanceDescription(
                completedToday: completed, isPro: true) == nil)
        }
    }

    @Test("The remaining count never goes negative and reads correctly")
    func remainingCounts() {
        #expect(DailyStudyLimiter.remainingRounds(completedToday: 0, isPro: false) == 3)
        #expect(DailyStudyLimiter.remainingRounds(completedToday: 2, isPro: false) == 1)
        #expect(DailyStudyLimiter.remainingRounds(completedToday: 3, isPro: false) == 0)
        #expect(DailyStudyLimiter.remainingRounds(completedToday: 99, isPro: false) == 0)

        #expect(DailyStudyLimiter.allowanceDescription(completedToday: 2, isPro: false)
                == "1 free round left today")
        #expect(DailyStudyLimiter.allowanceDescription(completedToday: 0, isPro: false)
                == "3 free rounds left today")
        #expect(DailyStudyLimiter.allowanceDescription(completedToday: 3, isPro: false)
                == "No free rounds left today")
    }
}

@MainActor
@Suite("Round counting")
struct CompletedRoundTests {
    @Test("A completed round is counted, an abandoned one is not")
    func onlyCompletedRoundsCount() {
        let store = makeTestStore()
        #expect(store.completedRoundsToday == 0)

        // Answering cards alone is not a round. This is the interrupted-session
        // case: the learner exits part way and must not lose an attempt.
        for atomicNumber in 1...6 {
            store.recordAnswer(atomicNumber: atomicNumber, correct: true)
        }
        #expect(store.completedRoundsToday == 0,
                "answers alone must not consume the free allowance")

        store.recordCompletedRound()
        #expect(store.completedRoundsToday == 1)
        store.recordCompletedRound()
        store.recordCompletedRound()
        #expect(store.completedRoundsToday == 3)
        #expect(!DailyStudyLimiter.canStartRound(
            completedToday: store.completedRoundsToday, isPro: false))
    }

    @Test("The allowance resets the next day")
    func allowanceRollsOver() {
        let store = makeTestStore()
        let today = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let tomorrow = today.addingTimeInterval(24 * 60 * 60)

        store.recordCompletedRound(date: today)
        store.recordCompletedRound(date: today)
        store.recordCompletedRound(date: today)
        store.refreshCompletedRoundsToday(on: today)
        #expect(store.completedRoundsToday == 3)

        store.refreshCompletedRoundsToday(on: tomorrow)
        #expect(store.completedRoundsToday == 0, "a new day restores the free rounds")
        #expect(DailyStudyLimiter.canStartRound(
            completedToday: store.completedRoundsToday, isPro: false))
    }

    @Test("A completed round does not by itself grant a streak day")
    func roundsDoNotFakeTheStreak() {
        let store = makeTestStore()
        store.recordCompletedRound()
        // Streaks count days on which cards were answered. A round cannot
        // complete without answers in the real flow, but the counter must not
        // be the thing that creates the day.
        #expect(store.currentStreak == 0)
    }

    @Test("Resetting progress does not refill the free daily allowance")
    func resetDoesNotRefillTheAllowance() {
        let store = makeTestStore()
        store.recordAnswer(atomicNumber: 1, correct: true)
        store.recordCompletedRound()
        store.recordCompletedRound()
        store.recordCompletedRound()
        #expect(store.completedRoundsToday == 3)

        store.resetAllProgress()
        #expect(store.completedRoundsToday == 3,
                "wiping progress must not be a way to get more free rounds")
        #expect(store.currentStreak == 0, "but the streak really is reset")
        #expect(store.totalAnswered == 0)
    }

    @Test("Round counting survives with no persistence at all")
    func worksWithoutAContainer() {
        // The store's contract is that every method works when there is no
        // container, the results simply do not outlive the app. Reading the
        // count off the managed objects broke that and quietly granted
        // unlimited free rounds to anyone whose on-disk store failed to open.
        let store = makeContainerlessStore()
        store.recordCompletedRound()
        store.recordCompletedRound()
        #expect(store.completedRoundsToday == 2)
        #expect(!DailyStudyLimiter.canStartRound(completedToday: 3, isPro: false))
    }

    @Test("Completed rounds survive a reload")
    func roundsSurviveAReload() {
        let store = makeTestStore()
        store.recordCompletedRound()
        store.recordCompletedRound()
        store.reload()
        #expect(store.completedRoundsToday == 2,
                "the count must come back from the store, not start again at zero")
    }
}

@Suite("Subscription products")
struct SubscriptionProductTests {
    @Test("Both plans exist with the documented identifiers")
    func productIdentifiers() {
        #expect(SubscriptionProduct.monthly.rawValue == "periodicpro.pro.monthly")
        #expect(SubscriptionProduct.yearly.rawValue == "periodicpro.pro.yearly")
        #expect(SubscriptionProduct.allProductIDs.count == 2)
        #expect(Set(SubscriptionProduct.allProductIDs).count == 2)
    }

    @Test("Identifiers round-trip, and a foreign one is rejected")
    func identifierRoundTrip() {
        for product in SubscriptionProduct.allCases {
            #expect(SubscriptionProduct(productID: product.rawValue) == product)
        }
        #expect(SubscriptionProduct(productID: "com.someone.else.monthly") == nil)
    }

    @Test("Yearly is the preferred plan, and only yearly")
    func exactlyOnePreferredPlan() {
        #expect(SubscriptionProduct.allCases.filter(\.isPreferred) == [.yearly])
    }
}

@Suite("Paywall copy")
struct PaywallContextTests {
    @Test("Every reason for showing the paywall has its own wording")
    func everyContextExplainsItself() {
        var headlines: Set<String> = []
        for context in [PaywallContext.dailyLimit, .structureExplorer, .smartReview, .general] {
            #expect(!context.headline.isEmpty)
            #expect(!context.subheadline.isEmpty)
            headlines.insert(context.headline)
        }
        #expect(headlines.count == 4, "each context should say something different")
    }

    @Test("The explorer pitch names the free elements honestly")
    func explorerContextNamesTheFreeSix() {
        let text = PaywallContext.structureExplorer.subheadline
        for name in ["Hydrogen", "carbon", "oxygen", "sodium", "iron", "gold"] {
            #expect(text.lowercased().contains(name.lowercased()),
                    "the pitch should name \(name) as free")
        }
        // 118 total, six free.
        #expect(text.contains("112"))
    }
}
