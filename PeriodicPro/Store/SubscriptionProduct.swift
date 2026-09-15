import Foundation

/// The two products, named in one place.
///
/// These identifiers must match the ones created in App Store Connect and the
/// ones in `Config/PeriodicPro.storekit`. `MONETIZATION.md` documents how to
/// create them; a unit test asserts this list and the StoreKit configuration
/// file agree, so a typo cannot ship silently.
enum SubscriptionProduct: String, CaseIterable, Identifiable, Hashable, Sendable {
    case monthly = "periodicpro.pro.monthly"
    case yearly = "periodicpro.pro.yearly"

    var id: String { rawValue }

    /// The App Store Connect subscription group both products belong to. One
    /// group means the learner can move between monthly and yearly and the
    /// App Store handles the proration.
    static let subscriptionGroupIdentifier = "periodicpro.pro"
    static let subscriptionGroupDisplayName = "Periodic Pro"

    static var allProductIDs: [String] { allCases.map(\.rawValue) }

    /// Shown only while StoreKit has not answered yet, and never as the price
    /// the learner is charged — that always comes from `Product.displayPrice`,
    /// which is localized and authoritative.
    var planName: String {
        switch self {
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }

    /// Yearly is presented first and marked Best Value. It genuinely is cheaper
    /// per month, and the paywall shows the real saving computed from the two
    /// live prices rather than a number typed in here.
    var isPreferred: Bool { self == .yearly }

    init?(productID: String) {
        self.init(rawValue: productID)
    }
}
