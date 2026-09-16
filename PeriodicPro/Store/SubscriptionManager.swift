import Foundation
import Observation
import OSLog
import StoreKit

/// The app's single point of contact with StoreKit.
///
/// No view calls StoreKit directly. Views read `entitlement` and
/// `purchaseState` and call `purchase`, `restore` or `refresh` here, which
/// means the gating rules have exactly one source of truth and the whole of the
/// UI can be driven from an injected state in tests and previews.
///
/// Created once by `AppServices` and held for the lifetime of the process, so
/// the `Transaction.updates` listener is never torn down while the app is
/// running — that listener is how a renewal, a refund, a revocation or a
/// purchase made on another device reaches this session without a relaunch.
@MainActor
@Observable
final class SubscriptionManager {
    private(set) var entitlement: ProEntitlement = .unknown
    private(set) var purchaseState: PurchaseState = .idle
    /// Loaded products, preferred plan first.
    private(set) var products: [Product] = []

    /// False in tests, previews and UI-test runs. Nothing in this type touches
    /// StoreKit when it is false, so a unit test can never reach Apple's
    /// servers and a UI test is never blocked by a purchase sheet.
    @ObservationIgnored private let isStoreKitEnabled: Bool
    /// Whether `loadProducts` may run. Separate from `isStoreKitEnabled`
    /// because product fetching is the one path with a test seam in front of
    /// it; everything else here talks to StoreKit directly.
    @ObservationIgnored private let canRequestProducts: Bool
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var hasStarted = false
    /// Whether a product request has come back, either way. Read by the
    /// bounded wait in `loadProducts(within:)`.
    @ObservationIgnored private var hasProductAnswer = false

    /// How products are fetched. Exactly one thing ever supplies a different
    /// value: a test that needs a request which never answers, which is the
    /// case the bounded wait exists for and the only one that cannot be
    /// reached through StoreKit itself. Production has no other caller.
    @ObservationIgnored
    private let productRequest: @Sendable () async throws -> [Product]

    private static func liveProductRequest() async throws -> [Product] {
        try await Product.products(for: SubscriptionProduct.allProductIDs)
    }

    @ObservationIgnored
    private static let logger = Logger(subsystem: "com.periodicpro.app", category: "store")

    init() {
        // A UI test stubs StoreKit out unless it has explicitly asked for the
        // local configuration, which is the only way to see real prices on the
        // paywall without a sandbox account.
        let stubsStoreKit = RuntimeFlags.isUITesting && !RuntimeFlags.usesLocalStoreKit
        isStoreKitEnabled = !stubsStoreKit
        canRequestProducts = !stubsStoreKit
        productRequest = Self.liveProductRequest
        if stubsStoreKit {
            // UI tests drive the paywall and the Pro-gated paths deterministically
            // from a launch argument rather than from a sandbox account.
            entitlement = RuntimeFlags.forcesProEntitlement ? .pro(Self.uiTestingSubscription) : .free
        }
    }

    /// Tests and previews. Never opens a connection to StoreKit.
    ///
    /// `productRequest` is the one seam: pass a request that never returns to
    /// exercise the bounded wait in `loadProducts(within:)`, which is the case
    /// that cannot be produced any other way — a real StoreKit that hangs is
    /// exactly what a test cannot arrange. `enablesLoading` opens the guard on
    /// `loadProducts` alone, and deliberately does *not* set
    /// `isStoreKitEnabled`: `refresh`, `purchase`, `restore` and `start` reach
    /// StoreKit directly rather than through this seam, so that flag stays
    /// false here and the promise above — that a test can never reach Apple's
    /// servers — keeps holding.
    init(testingEntitlement: ProEntitlement,
         products: [Product] = [],
         enablesLoading: Bool = false,
         productRequest: @escaping @Sendable () async throws -> [Product] = { [] }) {
        isStoreKitEnabled = false
        canRequestProducts = enablesLoading
        self.entitlement = testingEntitlement
        self.products = products
        self.productRequest = productRequest
    }

    private static let uiTestingSubscription = ProSubscriptionInfo(
        productID: SubscriptionProduct.yearly.rawValue,
        expirationDate: nil
    )

    var isPro: Bool { entitlement.isPro }

    func isUnlocked(_ feature: ProFeature) -> Bool {
        ProAccess.isUnlocked(feature, isPro: isPro)
    }

    // MARK: - Lifecycle

    /// Idempotent. Safe to call from `onAppear` as well as at launch.
    func start() {
        guard isStoreKitEnabled, !hasStarted else { return }
        hasStarted = true

        // The listener is installed before anything else so a transaction that
        // completes while the app was closed is picked up on the next launch.
        updatesTask = Task { [weak self] in
            for await update in StoreKit.Transaction.updates {
                guard let self else { return }
                await self.handle(update)
            }
        }

        Task { await refresh() }
    }

    private func handle(_ update: VerificationResult<StoreKit.Transaction>) async {
        switch update {
        case .verified(let transaction):
            // Finishing is what tells the App Store the app has delivered the
            // content. An unfinished transaction is redelivered forever.
            await transaction.finish()
            await refresh()
        case .unverified(_, let error):
            Self.logger.error(
                "Unverified transaction ignored: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Entitlement

    /// Recomputes what the learner owns from the App Store's own record.
    func refresh() async {
        guard isStoreKitEnabled else { return }

        var best: ProSubscriptionInfo?
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            // Only this app's subscriptions count.
            guard SubscriptionProduct(productID: transaction.productID) != nil else { continue }
            // A refund or a family-sharing removal revokes access immediately.
            guard transaction.revocationDate == nil else { continue }
            // currentEntitlements already filters expired subscriptions, but a
            // clock skew or a grace-period edge is cheap to guard against.
            if let expiry = transaction.expirationDate, expiry <= Date() { continue }

            let candidate = ProSubscriptionInfo(
                productID: transaction.productID,
                expirationDate: transaction.expirationDate
            )
            best = Self.longerLasting(best, candidate)
        }

        entitlement = best.map(ProEntitlement.pro) ?? .free
    }

    /// Waits for a pending entitlement answer, but not forever.
    ///
    /// `refresh()` reaches StoreKit, and StoreKit does not promise to answer
    /// promptly. On one CI simulator it never answered at all, and because the
    /// caller awaited it unbounded, tapping a Pro-gated control did nothing:
    /// no round, no paywall, not even an error. A control that can hang
    /// forever on a network call is worse than one that guesses.
    ///
    /// Past the deadline the caller proceeds with what is known. That is safe
    /// in the direction it fails: an unresolved entitlement reads as not-Pro,
    /// so the learner sees the paywall — and the paywall dismisses itself the
    /// moment a real entitlement arrives, which is exactly what a subscriber
    /// whose answer was merely slow will get. The refresh is left running
    /// rather than canceled, so that answer still lands when it comes.
    func resolveEntitlement(within duration: Duration = .seconds(3)) async {
        guard entitlement.isResolving else { return }
        Task { await self.refresh() }
        let deadline = ContinuousClock.now.advanced(by: duration)
        while entitlement.isResolving, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// If the learner somehow holds both plans — an upgrade mid-term, say —
    /// the one that runs longest is the one that matters.
    static func longerLasting(
        _ current: ProSubscriptionInfo?,
        _ candidate: ProSubscriptionInfo
    ) -> ProSubscriptionInfo {
        guard let current else { return candidate }
        // A missing expiry means it does not expire, which beats any date.
        guard let currentExpiry = current.expirationDate else { return current }
        guard let candidateExpiry = candidate.expirationDate else { return candidate }
        return candidateExpiry > currentExpiry ? candidate : current
    }

    // MARK: - Products

    /// Loads the subscription products, but does not wait forever for them.
    ///
    /// Bounded for the same reason `resolveEntitlement(within:)` is, and it is
    /// the same mistake twice in one file: `Product.products(for:)` reaches
    /// StoreKit, and StoreKit does not promise to answer. Awaiting it with no
    /// bound meant that when it did not, the paywall sat on "Loading
    /// subscription options…" forever — no prices, no error, and not even the
    /// Try again button, because that button only appears once a load has been
    /// *attempted* and this one never finished attempting. A spinner with no
    /// way out is the worst of the three states this screen can be in.
    ///
    /// Past the deadline the learner gets the unavailable state, which already
    /// says what happened and offers a retry. The request is left running
    /// rather than canceled — `Product.products(for:)` is not required to be
    /// cancellation-responsive, and a late answer is still worth having, so an
    /// arrival after the deadline simply fills the plans in.
    func loadProducts(within duration: Duration = .seconds(15)) async {
        guard canRequestProducts else { return }
        guard products.isEmpty else { return }

        purchaseState = .loadingProducts
        hasProductAnswer = false
        Task { await self.requestProducts() }

        let deadline = ContinuousClock.now.advanced(by: duration)
        while !hasProductAnswer, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }

        guard !hasProductAnswer else { return }
        purchaseState = .productsUnavailable(
            "Subscription options are taking longer than usual to load. "
                + "Check your connection and try again.")
    }

    private func requestProducts() async {
        do {
            let loaded = try await productRequest()
            products = Self.sorted(loaded)
            purchaseState = products.isEmpty
                ? .productsUnavailable(
                    "Subscription options could not be loaded. Check your connection and try again.")
                : .idle
        } catch {
            Self.logger.error(
                "Product load failed: \(String(describing: error), privacy: .public)")
            purchaseState = .productsUnavailable(
                "Subscription options could not be loaded. Check your connection and try again.")
        }
        hasProductAnswer = true
    }

    /// Preferred plan first, then by identifier so the order is stable.
    static func sorted(_ products: [Product]) -> [Product] {
        products.sorted { lhs, rhs in
            let left = SubscriptionProduct(productID: lhs.id)?.isPreferred ?? false
            let right = SubscriptionProduct(productID: rhs.id)?.isPreferred ?? false
            if left != right { return left }
            return lhs.id < rhs.id
        }
    }

    // MARK: - Purchasing

    func purchase(_ product: Product) async {
        guard isStoreKitEnabled else { return }
        purchaseState = .purchasing(productID: product.id)

        do {
            switch try await product.purchase() {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refresh()
                    // Only call it a success once the entitlement actually
                    // reflects it, so the paywall never dismisses onto a
                    // still-locked feature.
                    purchaseState = entitlement.isPro
                        ? .succeeded
                        : .failed("The purchase went through but has not unlocked yet. "
                                  + "Try Restore Purchases in a moment.")
                case .unverified:
                    purchaseState = .failed(
                        "That purchase could not be verified with the App Store. "
                            + "You have not been charged for an unverified purchase.")
                }
            case .pending:
                purchaseState = .pending
            case .userCancelled:
                purchaseState = .canceled
            @unknown default:
                purchaseState = .failed("The App Store returned an unexpected response.")
            }
        } catch {
            Self.logger.error("Purchase failed: \(String(describing: error), privacy: .public)")
            purchaseState = .failed("The purchase could not be completed. Please try again.")
        }
    }

    func restore() async {
        guard isStoreKitEnabled else { return }
        purchaseState = .restoring
        do {
            try await AppStore.sync()
            await refresh()
            purchaseState = entitlement.isPro
                ? .succeeded
                : .failed("No active Elemora Pro subscription was found for this Apple Account.")
        } catch {
            Self.logger.error("Restore failed: \(String(describing: error), privacy: .public)")
            purchaseState = .failed("Purchases could not be restored. Please try again.")
        }
    }

    /// Clears a transient message so the paywall does not keep showing a stale
    /// error after the learner has moved on.
    func clearTransientState() {
        switch purchaseState {
        case .canceled, .failed, .succeeded, .pending:
            purchaseState = .idle
        case .idle, .loadingProducts, .productsUnavailable, .purchasing, .restoring:
            break
        }
    }
}

// MARK: - Price presentation

/// Formats what StoreKit returns. The displayed price is always
/// `Product.displayPrice` — localized, currency-correct and authoritative —
/// never a string typed into the app.
enum SubscriptionPricing {
    /// "per month" / "per year", from the product's own subscription period.
    static func periodDescription(for product: Product) -> String? {
        guard let period = product.subscription?.subscriptionPeriod else { return nil }
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "day" : "days"
        case .week: unit = period.value == 1 ? "week" : "weeks"
        case .month: unit = period.value == 1 ? "month" : "months"
        case .year: unit = period.value == 1 ? "year" : "years"
        @unknown default: return nil
        }
        return period.value == 1 ? "per \(unit)" : "per \(period.value) \(unit)"
    }

    /// The yearly plan's cost expressed per month, in the same currency
    /// StoreKit used. Shown as supporting detail, never as the headline price.
    static func monthlyEquivalent(for product: Product) -> String? {
        guard let period = product.subscription?.subscriptionPeriod else { return nil }
        let months: Int
        switch period.unit {
        case .year: months = period.value * 12
        case .month: months = period.value
        case .day, .week: return nil
        @unknown default: return nil
        }
        guard months > 1 else { return nil }
        let perMonth = product.price / Decimal(months)
        return perMonth.formatted(product.priceFormatStyle)
    }

    /// How much the yearly plan saves against twelve monthly payments, as a
    /// whole percentage. Returns `nil` unless both real prices are known, so
    /// the paywall can never show an invented discount.
    static func yearlySavingPercent(monthly: Product?, yearly: Product?) -> Int? {
        guard let monthly, let yearly else { return nil }
        guard monthly.priceFormatStyle.currencyCode == yearly.priceFormatStyle.currencyCode else {
            return nil
        }
        let twelveMonths = monthly.price * 12
        guard twelveMonths > 0, yearly.price < twelveMonths else { return nil }
        let saved = (twelveMonths - yearly.price) / twelveMonths * 100
        let percent = Int(truncating: NSDecimalNumber(decimal: saved))
        return percent > 0 ? percent : nil
    }
}
