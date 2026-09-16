import SwiftUI

/// Four tabs. Search lives inside Table, favorites live inside Study and on
/// each detail page, and Build is the Compound Builder beta.
enum AppTab: String, Hashable, CaseIterable {
    case table
    case study
    case build
    case progress

    var title: String {
        switch self {
        case .table: return "Table"
        case .study: return "Study"
        case .build: return "Build"
        case .progress: return "Progress"
        }
    }

    var symbolName: String {
        switch self {
        case .table: return "square.grid.3x3.fill"
        case .study: return "graduationcap.fill"
        case .build: return "circle.hexagongrid.fill"
        case .progress: return "chart.bar.fill"
        }
    }
}

/// Launch arguments, resolved once. `ProcessInfo.arguments` rebuilds an array
/// every time it is read, which is not something a view body should do.
enum RuntimeFlags {
    /// Set by the UI test bundle: skips onboarding, uses an in-memory store and
    /// silences haptics so runs are independent and deterministic.
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    /// Set alongside `-uiTesting` to exercise the Pro paths. StoreKit is never
    /// contacted during a UI test — a sandbox purchase sheet cannot be driven
    /// reliably from XCUITest — so entitlement is decided here instead.
    static let forcesProEntitlement = ProcessInfo.processInfo.arguments.contains("-proEntitled")

    /// Set alongside `-uiTesting` to load products from the *local* StoreKit
    /// configuration instead of stubbing StoreKit out entirely.
    ///
    /// The paywall's prices come from `Product.displayPrice`, so with StoreKit
    /// stubbed there is no way to see whether the prices, the per-month figure
    /// and the savings badge actually render — the paywall just says its
    /// options are unavailable. This flag closes that hole. It never reaches a
    /// purchase sheet: nothing taps Subscribe, and the scheme points StoreKit
    /// at `Config/PeriodicPro.storekit`, so no request leaves the device.
    static let usesLocalStoreKit = ProcessInfo.processInfo.arguments.contains("-storeKitLocal")

    /// Set alongside `-uiTesting` to answer PubChem requests from the bundled
    /// catalog instead of the network, so compound search, the builder and the
    /// screenshot tour are deterministic and offline. Without it a UI-test run
    /// makes no network requests at all.
    static let stubsCompoundNetwork = ProcessInfo.processInfo.arguments.contains("-compoundNetworkStub")
}

/// Environment storage for the bundled dataset.
private struct ElementCatalogKey: EnvironmentKey {
    static let defaultValue = ElementCatalog(elements: [])
}

/// Lets a screen move the learner to another tab.
///
/// The Study tab's streak and mastery cards lead to Progress, which is where
/// those numbers live in full. Passing an action rather than a binding keeps
/// `RootView` the only owner of the selection.
private struct SelectTabKey: EnvironmentKey {
    static let defaultValue: (AppTab) -> Void = { _ in }
}

extension EnvironmentValues {
    /// The bundled element dataset, injected once at launch.
    var elementCatalog: ElementCatalog {
        get { self[ElementCatalogKey.self] }
        set { self[ElementCatalogKey.self] = newValue }
    }

    /// Switches the visible tab. Injected by `RootView`.
    var selectTab: (AppTab) -> Void {
        get { self[SelectTabKey.self] }
        set { self[SelectTabKey.self] = newValue }
    }
}

/// Applies the native zoom navigation transition, falling back to the standard
/// push when the learner has Reduce Motion enabled.
///
/// The `if` makes the two cases structurally different views, so toggling
/// Reduce Motion while a detail page is open resets that page's local state
/// (which is only the "More properties" disclosure). `NavigationTransition` has
/// no single concrete type that can express both cases, so the alternative
/// would be to drop Reduce Motion support entirely — a far worse trade.
struct ZoomTransitionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let id: Int
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        }
    }
}

extension View {
    /// Destination side of the signature tile-expands-into-page transition.
    func zoomTransition(id: Int, namespace: Namespace.ID) -> some View {
        modifier(ZoomTransitionModifier(id: id, namespace: namespace))
    }

    /// Source side. Always applied — it is inert when the destination opts out.
    func zoomTransitionSource(id: Int, namespace: Namespace.ID) -> some View {
        matchedTransitionSource(id: id, in: namespace)
    }
}
