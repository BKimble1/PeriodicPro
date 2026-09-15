import SwiftUI

/// Tabs are deliberately limited to three. Search lives inside Table, and
/// favorites live inside Study and on each element's detail page.
enum AppTab: String, Hashable, CaseIterable {
    case table
    case study
    case progress

    var title: String {
        switch self {
        case .table: return "Table"
        case .study: return "Study"
        case .progress: return "Progress"
        }
    }

    var symbolName: String {
        switch self {
        case .table: return "square.grid.3x3.fill"
        case .study: return "graduationcap.fill"
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
}

/// Environment storage for the bundled dataset.
private struct ElementCatalogKey: EnvironmentKey {
    static let defaultValue = ElementCatalog(elements: [])
}

extension EnvironmentValues {
    /// The bundled element dataset, injected once at launch.
    var elementCatalog: ElementCatalog {
        get { self[ElementCatalogKey.self] }
        set { self[ElementCatalogKey.self] = newValue }
    }
}

/// Applies the native zoom navigation transition, falling back to the standard
/// push when the learner has Reduce Motion enabled.
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
