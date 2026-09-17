import SwiftUI

/// Design tokens. Every spacing value, corner radius and shadow in the app is
/// drawn from here so the product stays visually consistent.
enum Theme {
    /// An 8-point rhythm. The ramp is kept complete even where a step is not
    /// currently used, so reaching for the next size up never means inventing
    /// a number.
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 28
        static let xxxl: CGFloat = 40

        /// Horizontal page margin used by every scrollable screen.
        static let screenMargin: CGFloat = 20
        /// Vertical rhythm between major sections.
        static let section: CGFloat = 26
    }

    enum Radius {
        static let tile: CGFloat = 5
        static let card: CGFloat = 20
        static let hero: CGFloat = 28
        static let control: CGFloat = 14
    }

    enum Shadow {
        static let card = ShadowStyle(color: .black.opacity(0.05), radius: 14, y: 6)
        static let raised = ShadowStyle(color: .black.opacity(0.08), radius: 22, y: 10)
        static let subtle = ShadowStyle(color: .black.opacity(0.035), radius: 6, y: 2)
    }

    struct ShadowStyle {
        let color: Color
        let radius: CGFloat
        let y: CGFloat
    }

    enum Motion {
        static let tap = SwiftUI.Animation.spring(response: 0.28, dampingFraction: 0.72)
        static let reveal = SwiftUI.Animation.spring(response: 0.42, dampingFraction: 0.82)
        static let soft = SwiftUI.Animation.easeOut(duration: 0.24)
    }

    /// Minimum comfortable hit target. Used by the expanded table layout and
    /// every control outside the compact table.
    static let minimumTouchTarget: CGFloat = 44

    /// The widest a column of cards and running text is allowed to get.
    ///
    /// Wider than any phone, so nothing changes there; on an iPad it keeps a
    /// stack of cards a readable column rather than a phone layout stretched
    /// across a thousand points. The periodic table itself is deliberately
    /// exempt — it is the one thing on the screen that should use every point
    /// of width it is given.
    static let readableWidth: CGFloat = 700
}

extension View {
    func themeShadow(_ style: Theme.ShadowStyle) -> some View {
        shadow(color: style.color, radius: style.radius, x: 0, y: style.y)
    }
}
