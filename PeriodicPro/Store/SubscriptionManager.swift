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
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var hasStarted = false

    @ObservationIgnored
    private static let logger = Logger(subsystem: "com.periodicpro.app", category: "store")

    init() {
        isStoreKitEnabled = !RuntimeFlags.isUITesting
        if RuntimeFlags.isUITesting {
            // UI tests drive the paywall and the Pro-gated paths deterministically
            // from a launch argument rather than from a sandbox account.
            entitlement = RuntimeFlags.forcesProEntitlement ? .pro(Self.uiTestingSubscription) : .free
        }
    }

    /// Tests and previews. Never opens a connection to StoreKit.
    init(testingEntitlement: ProEntitlement, products: [Product] = []) {
        isStoreKitEnabled = false
        self.entitlement = testingEntitlement
        self.products = products
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

    func loadProducts() async {
        guard isStoreKitEnabled else { return }
        guard products.isEmpty else { return }

        purchaseState = .loadingProducts
        do {
            let loaded = try await Product.products(for: SubscriptionProduct.allProductIDs)
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
                : .failed("No active Periodic Pro subscription was found for this Apple Account.")
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
