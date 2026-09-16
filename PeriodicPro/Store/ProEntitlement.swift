import Foundation

/// What the App Store says the learner is currently entitled to.
///
/// A plain value type with no StoreKit in it, so the whole of the gating logic —
/// and every view that reads it — can be exercised in tests without touching
/// Apple's servers.
enum ProEntitlement: Hashable, Sendable {
    /// StoreKit has not answered yet. Treated as *not* Pro for access, but the
    /// UI shows nothing about Pro state until it resolves, so a subscriber never
    /// sees a paywall flash on launch.
    case unknown
    case free
    case pro(ProSubscriptionInfo)

    var isPro: Bool {
        if case .pro = self { return true }
        return false
    }

    /// True while the answer is still in flight. Views use this to stay quiet
    /// rather than to deny access.
    var isResolving: Bool { self == .unknown }

    var subscription: ProSubscriptionInfo? {
        if case .pro(let info) = self { return info }
        return nil
    }
}

/// The details of an active subscription, as far as the app needs them.
///
/// Deliberately small. Renewal state, billing retries and cancellation all live
/// in Apple's own Manage Subscription sheet, which the paywall links to and
/// which is always more accurate than anything this app could cache.
struct ProSubscriptionInfo: Hashable, Sendable {
    let productID: String
    /// `nil` for a non-renewing entitlement. Present for both subscriptions
    /// this app sells.
    let expirationDate: Date?

    var product: SubscriptionProduct? { SubscriptionProduct(productID: productID) }
}

/// What the paywall is doing right now.
///
/// Separate from the entitlement on purpose: a failed purchase does not change
/// what the learner owns, and an entitlement arriving from another device does
/// not mean a purchase succeeded here.
enum PurchaseState: Hashable, Sendable {
    case idle
    case loadingProducts
    /// StoreKit answered, but with nothing sellable — usually no network, or
    /// products not yet approved in App Store Connect.
    case productsUnavailable(String)
    case purchasing(productID: String)
    /// Ask to Buy, or a bank confirmation. The purchase may complete later, so
    /// the paywall says so instead of reading as a failure.
    case pending
    case restoring
    case succeeded
    case canceled
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .loadingProducts, .purchasing, .restoring: return true
        case .idle, .productsUnavailable, .pending, .succeeded, .canceled, .failed: return false
        }
    }

    /// The message to show, or `nil` when there is nothing worth saying.
    var message: String? {
        switch self {
        case .idle, .loadingProducts, .purchasing, .restoring, .succeeded:
            return nil
        case .productsUnavailable(let reason):
            return reason
        case .pending:
            return "Your purchase is waiting for approval. Elemora Pro will unlock as soon as it "
                + "goes through — there is nothing else you need to do."
        case .canceled:
            return nil
        case .failed(let reason):
            return reason
        }
    }
}
