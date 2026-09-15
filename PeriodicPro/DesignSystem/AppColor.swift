import SwiftUI
import UIKit

/// Semantic surface colors. Light mode is the primary visual direction; the
/// dark variants are hand-tuned rather than inverted so cards keep separation
/// from the background instead of collapsing into flat gray.
enum AppColor {
    /// The page background: a very soft off-white in light mode.
    static let canvas = Color(
        light: Color(red: 0.976, green: 0.980, blue: 0.988),
        dark: Color(red: 0.055, green: 0.059, blue: 0.075)
    )

    /// Raised card surface.
    static let surface = Color(
        light: .white,
        dark: Color(red: 0.106, green: 0.114, blue: 0.137)
    )

    /// A secondary surface used for insets inside cards.
    static let surfaceMuted = Color(
        light: Color(red: 0.961, green: 0.969, blue: 0.980),
        dark: Color(red: 0.145, green: 0.153, blue: 0.180)
    )

    /// Hairline separator / card border.
    static let hairline = Color(
        light: Color(red: 0.898, green: 0.914, blue: 0.937),
        dark: Color(red: 0.227, green: 0.239, blue: 0.278)
    )

    static let primaryText = Color(
        light: Color(red: 0.067, green: 0.086, blue: 0.129),
        dark: Color(red: 0.949, green: 0.957, blue: 0.976)
    )

    static let secondaryText = Color(
        light: Color(red: 0.388, green: 0.427, blue: 0.494),
        dark: Color(red: 0.612, green: 0.643, blue: 0.702)
    )

    static let tertiaryText = Color(
        light: Color(red: 0.549, green: 0.584, blue: 0.647),
        dark: Color(red: 0.478, green: 0.510, blue: 0.573)
    )

    /// The single accent used for interactive emphasis.
    /// The single accent used for interactive emphasis. The dark variant sits
    /// close to the system blue Apple uses on dark backgrounds: light enough to
    /// read as a link on the canvas, dark enough to carry white button labels.
    static let accent = Color(
        light: Color(red: 0.161, green: 0.451, blue: 0.937),
        dark: Color(red: 0.161, green: 0.541, blue: 1.0)
    )

    static let positive = Color(
        light: Color(red: 0.086, green: 0.639, blue: 0.408),
        dark: Color(red: 0.239, green: 0.788, blue: 0.541)
    )

    static let warning = Color(
        light: Color(red: 0.898, green: 0.451, blue: 0.239),
        dark: Color(red: 0.969, green: 0.573, blue: 0.361)
    )
}

extension Color {
    /// Builds a color that resolves differently in light and dark mode.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}
