import SwiftUI

/// Color assignments for the ten element families.
///
/// Hues follow the reference direction (coral → orange → gold → green → mint →
/// cyan → blue → lavender → violet → magenta) at restrained saturation. Each
/// family exposes three roles so the same hue works as a 19-point tile fill, a
/// large hero wash and a legend dot without ever losing contrast.
extension ElementCategory {
    /// Saturated "ink" color: dots, glyphs, ring strokes, text accents.
    var accentColor: Color {
        switch self {
        case .alkaliMetal:
            return Color(light: Color(red: 0.902, green: 0.325, blue: 0.353),
                         dark: Color(red: 1.000, green: 0.478, blue: 0.494))
        case .alkalineEarthMetal:
            return Color(light: Color(red: 0.902, green: 0.447, blue: 0.180),
                         dark: Color(red: 1.000, green: 0.596, blue: 0.318))
        case .transitionMetal:
            return Color(light: Color(red: 0.792, green: 0.686, blue: 0.129),
                         dark: Color(red: 0.937, green: 0.851, blue: 0.318))
        case .postTransitionMetal:
            return Color(light: Color(red: 0.278, green: 0.663, blue: 0.424),
                         dark: Color(red: 0.412, green: 0.816, blue: 0.561))
        case .metalloid:
            return Color(light: Color(red: 0.180, green: 0.671, blue: 0.639),
                         dark: Color(red: 0.325, green: 0.827, blue: 0.784))
        case .reactiveNonmetal:
            return Color(light: Color(red: 0.200, green: 0.596, blue: 0.827),
                         dark: Color(red: 0.376, green: 0.741, blue: 0.965))
        case .halogen:
            return Color(light: Color(red: 0.294, green: 0.478, blue: 0.914),
                         dark: Color(red: 0.463, green: 0.631, blue: 1.000))
        case .nobleGas:
            return Color(light: Color(red: 0.494, green: 0.435, blue: 0.898),
                         dark: Color(red: 0.639, green: 0.588, blue: 1.000))
        case .lanthanide:
            return Color(light: Color(red: 0.635, green: 0.396, blue: 0.847),
                         dark: Color(red: 0.776, green: 0.561, blue: 0.965))
        case .actinide:
            return Color(light: Color(red: 0.831, green: 0.376, blue: 0.702),
                         dark: Color(red: 0.941, green: 0.541, blue: 0.831))
        }
    }

    /// Soft tile / card fill. Light mode uses a pale wash of the hue; dark mode
    /// uses a low-luminance version that still reads as the same family.
    var tileFill: Color {
        switch self {
        case .alkaliMetal:
            return Color(light: Color(red: 0.996, green: 0.918, blue: 0.918),
                         dark: Color(red: 0.278, green: 0.149, blue: 0.161))
        case .alkalineEarthMetal:
            return Color(light: Color(red: 0.996, green: 0.925, blue: 0.851),
                         dark: Color(red: 0.302, green: 0.192, blue: 0.118))
        case .transitionMetal:
            return Color(light: Color(red: 0.984, green: 0.976, blue: 0.827),
                         dark: Color(red: 0.263, green: 0.251, blue: 0.098))
        case .postTransitionMetal:
            return Color(light: Color(red: 0.898, green: 0.969, blue: 0.925),
                         dark: Color(red: 0.110, green: 0.239, blue: 0.169))
        case .metalloid:
            return Color(light: Color(red: 0.878, green: 0.965, blue: 0.957),
                         dark: Color(red: 0.078, green: 0.239, blue: 0.231))
        case .reactiveNonmetal:
            return Color(light: Color(red: 0.882, green: 0.949, blue: 0.996),
                         dark: Color(red: 0.086, green: 0.208, blue: 0.294))
        case .halogen:
            return Color(light: Color(red: 0.898, green: 0.925, blue: 0.996),
                         dark: Color(red: 0.118, green: 0.169, blue: 0.318))
        case .nobleGas:
            return Color(light: Color(red: 0.929, green: 0.918, blue: 0.996),
                         dark: Color(red: 0.180, green: 0.157, blue: 0.318))
        case .lanthanide:
            return Color(light: Color(red: 0.949, green: 0.906, blue: 0.984),
                         dark: Color(red: 0.216, green: 0.145, blue: 0.298))
        case .actinide:
            return Color(light: Color(red: 0.988, green: 0.898, blue: 0.965),
                         dark: Color(red: 0.263, green: 0.137, blue: 0.231))
        }
    }

    /// Text and glyphs drawn directly on `accentColor`.
    ///
    /// Gold and orange are far too light to carry white in either appearance,
    /// and every accent is brightened for dark mode, so dark ink is the right
    /// answer there across the board.
    var onAccentColor: Color {
        switch self {
        case .transitionMetal, .alkalineEarthMetal:
            return Self.accentInk
        default:
            return Color(light: .white, dark: Self.accentInk)
        }
    }

    fileprivate static let accentInk = Color(red: 0.075, green: 0.086, blue: 0.110)

    /// Symbol / number color drawn on top of `tileFill`.
    var onTileColor: Color {
        Color(light: accentColorDarkened, dark: .white.opacity(0.94))
    }

    private var accentColorDarkened: Color {
        switch self {
        case .alkaliMetal: return Color(red: 0.580, green: 0.161, blue: 0.188)
        case .alkalineEarthMetal: return Color(red: 0.565, green: 0.271, blue: 0.075)
        case .transitionMetal: return Color(red: 0.443, green: 0.396, blue: 0.043)
        case .postTransitionMetal: return Color(red: 0.118, green: 0.400, blue: 0.239)
        case .metalloid: return Color(red: 0.055, green: 0.396, blue: 0.376)
        case .reactiveNonmetal: return Color(red: 0.075, green: 0.337, blue: 0.494)
        case .halogen: return Color(red: 0.149, green: 0.271, blue: 0.588)
        case .nobleGas: return Color(red: 0.294, green: 0.239, blue: 0.588)
        case .lanthanide: return Color(red: 0.376, green: 0.196, blue: 0.541)
        case .actinide: return Color(red: 0.522, green: 0.184, blue: 0.424)
        }
    }

    /// Wash behind the element hero on the detail screen.
    var heroGradient: LinearGradient {
        LinearGradient(
            colors: [
                tileFill,
                tileFill.opacity(0.35),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Full-bleed background gradient behind the detail screen.
    var backdropGradient: LinearGradient {
        LinearGradient(
            colors: [
                tileFill.opacity(0.85),
                AppColor.canvas,
                AppColor.canvas,
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
