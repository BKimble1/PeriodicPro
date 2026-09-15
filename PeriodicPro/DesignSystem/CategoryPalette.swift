import SwiftUI

/// Color assignments for the ten element families.
///
/// Hues follow the reference direction (coral → orange → gold → green → mint →
/// cyan → blue → lavender → violet → magenta) at restrained saturation. Each
/// family exposes four roles so the same hue works as a 17-point tile fill, a
/// large hero wash, a legend dot and a nucleus label without ever losing
/// contrast.
///
/// The colors are built once into a static table rather than recomputed per
/// access: the periodic table reads three of them for each of 118 tiles, and a
/// dynamic `UIColor` allocates a closure every time it is constructed.
struct FamilyPalette: Sendable {
    /// Saturated "ink": dots, glyphs, ring strokes, text accents.
    let accent: Color
    /// Soft tile or card fill.
    let fill: Color
    /// Symbol and number drawn on top of `fill`.
    let onFill: Color
    /// Text and glyphs drawn directly on `accent`.
    let onAccent: Color
}

extension ElementCategory {
    var palette: FamilyPalette { Self.palettes[self] ?? Self.fallbackPalette }

    var accentColor: Color { palette.accent }
    var tileFill: Color { palette.fill }
    var onTileColor: Color { palette.onFill }
    var onAccentColor: Color { palette.onAccent }

    /// Wash behind the element hero on the detail screen.
    var heroGradient: LinearGradient {
        LinearGradient(
            colors: [tileFill, tileFill.opacity(0.35)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Full-bleed background gradient behind the detail screen.
    var backdropGradient: LinearGradient {
        LinearGradient(
            colors: [tileFill.opacity(0.85), AppColor.canvas, AppColor.canvas],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - The table

    /// Near-black, for the two families whose accent is too light to carry
    /// white, and for every family in dark mode where all accents brighten.
    private static let accentInk = Color(red: 0.075, green: 0.086, blue: 0.110)

    private static let fallbackPalette = FamilyPalette(
        accent: AppColor.secondaryText,
        fill: AppColor.surfaceMuted,
        onFill: AppColor.primaryText,
        onAccent: .white
    )

    private static func make(
        accentLight: (Double, Double, Double),
        accentDark: (Double, Double, Double),
        fillLight: (Double, Double, Double),
        fillDark: (Double, Double, Double),
        inkLight: (Double, Double, Double),
        /// Gold and orange keep dark ink even after being darkened: it is the
        /// higher-contrast pairing, and `Tools/check_contrast.py` proves it.
        darkTextOnAccent: Bool = false
    ) -> FamilyPalette {
        FamilyPalette(
            accent: Color(light: Color(red: accentLight.0, green: accentLight.1, blue: accentLight.2),
                          dark: Color(red: accentDark.0, green: accentDark.1, blue: accentDark.2)),
            fill: Color(light: Color(red: fillLight.0, green: fillLight.1, blue: fillLight.2),
                        dark: Color(red: fillDark.0, green: fillDark.1, blue: fillDark.2)),
            onFill: Color(light: Color(red: inkLight.0, green: inkLight.1, blue: inkLight.2),
                          dark: .white.opacity(0.94)),
            onAccent: darkTextOnAccent
                ? accentInk
                : Color(light: .white, dark: accentInk)
        )
    }

    private static let palettes: [ElementCategory: FamilyPalette] = [
        .alkaliMetal: make(
            accentLight: (0.902, 0.325, 0.353), accentDark: (1.000, 0.478, 0.494),
            fillLight: (0.996, 0.918, 0.918), fillDark: (0.278, 0.149, 0.161),
            inkLight: (0.580, 0.161, 0.188)
        ),
        .alkalineEarthMetal: make(
            accentLight: (0.875, 0.416, 0.145), accentDark: (1.000, 0.596, 0.318),
            fillLight: (0.996, 0.925, 0.851), fillDark: (0.302, 0.192, 0.118),
            inkLight: (0.565, 0.271, 0.075),
            darkTextOnAccent: true
        ),
        .transitionMetal: make(
            accentLight: (0.639, 0.541, 0.078), accentDark: (0.937, 0.851, 0.318),
            fillLight: (0.984, 0.976, 0.827), fillDark: (0.263, 0.251, 0.098),
            inkLight: (0.443, 0.396, 0.043),
            darkTextOnAccent: true
        ),
        .postTransitionMetal: make(
            accentLight: (0.196, 0.557, 0.337), accentDark: (0.412, 0.816, 0.561),
            fillLight: (0.898, 0.969, 0.925), fillDark: (0.110, 0.239, 0.169),
            inkLight: (0.118, 0.400, 0.239)
        ),
        .metalloid: make(
            accentLight: (0.129, 0.565, 0.541), accentDark: (0.325, 0.827, 0.784),
            fillLight: (0.878, 0.965, 0.957), fillDark: (0.078, 0.239, 0.231),
            inkLight: (0.055, 0.396, 0.376)
        ),
        .reactiveNonmetal: make(
            accentLight: (0.200, 0.596, 0.827), accentDark: (0.376, 0.741, 0.965),
            fillLight: (0.882, 0.949, 0.996), fillDark: (0.086, 0.208, 0.294),
            inkLight: (0.075, 0.337, 0.494)
        ),
        .halogen: make(
            accentLight: (0.294, 0.478, 0.914), accentDark: (0.463, 0.631, 1.000),
            fillLight: (0.898, 0.925, 0.996), fillDark: (0.118, 0.169, 0.318),
            inkLight: (0.149, 0.271, 0.588)
        ),
        .nobleGas: make(
            accentLight: (0.494, 0.435, 0.898), accentDark: (0.639, 0.588, 1.000),
            fillLight: (0.929, 0.918, 0.996), fillDark: (0.180, 0.157, 0.318),
            inkLight: (0.294, 0.239, 0.588)
        ),
        .lanthanide: make(
            accentLight: (0.635, 0.396, 0.847), accentDark: (0.776, 0.561, 0.965),
            fillLight: (0.949, 0.906, 0.984), fillDark: (0.216, 0.145, 0.298),
            inkLight: (0.376, 0.196, 0.541)
        ),
        .actinide: make(
            accentLight: (0.831, 0.376, 0.702), accentDark: (0.941, 0.541, 0.831),
            fillLight: (0.988, 0.898, 0.965), fillDark: (0.263, 0.137, 0.231),
            inkLight: (0.522, 0.184, 0.424)
        ),
    ]
}
