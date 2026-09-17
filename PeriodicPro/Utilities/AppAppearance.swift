import SwiftUI

/// Whether the app follows the system, or is pinned to light or dark.
///
/// Stored in `UserDefaults` under one key and applied once, at the root, so a
/// change takes effect immediately across every tab and every sheet.
enum AppAppearance: String, CaseIterable, Identifiable, Hashable, Sendable {
    case system
    case light
    case dark

    /// The `@AppStorage` key. Named here so Settings, the root view and the
    /// tests all agree without repeating a string literal.
    static let storageKey = "appAppearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var symbolName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.stars.fill"
        }
    }

    /// What the root view applies. `nil` means "whatever iOS is doing", which
    /// is also what a UI test's `simctl ui appearance` override needs, so the
    /// default never fights the screenshot tour.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
