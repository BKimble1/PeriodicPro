import SwiftUI

/// Type ramp. Everything is a system font so Dynamic Type, tracking and
/// optical sizing behave exactly the way iOS expects.
enum AppFont {
    /// Large screen title, e.g. "Periodic Table".
    static let screenTitle = Font.system(.largeTitle, design: .default, weight: .bold)
    /// Section heading inside a card stack.
    static let sectionTitle = Font.system(.title3, design: .default, weight: .semibold)
    /// Card heading.
    static let cardTitle = Font.system(.headline, design: .default, weight: .semibold)
    static let body = Font.system(.body)
    static let callout = Font.system(.callout)
    static let subheadline = Font.system(.subheadline)
    static let footnote = Font.system(.footnote)
    static let caption = Font.system(.caption)
    static let caption2 = Font.system(.caption2)

    /// Monospaced digits for statistics that must not jitter as they animate.
    static let statNumber = Font.system(.title, design: .rounded, weight: .semibold).monospacedDigit()

    /// The element symbol on the hero. Fixed size, deliberately not Dynamic
    /// Type scaled, so the hero geometry stays stable during the zoom
    /// transition; the surrounding labels do scale.
    static func heroSymbol(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .default)
    }

    static func tileSymbol(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    static func tileNumber(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .default).monospacedDigit()
    }
}
