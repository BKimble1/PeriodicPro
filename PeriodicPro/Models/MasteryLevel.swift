import SwiftUI

/// Lightweight four-step familiarity score kept per element.
enum MasteryLevel: Int, Codable, CaseIterable, Comparable, Hashable, Sendable {
    case notStarted = 0
    case learning = 1
    case familiar = 2
    case mastered = 3

    static func < (lhs: MasteryLevel, rhs: MasteryLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .notStarted: return "Not Started"
        case .learning: return "Learning"
        case .familiar: return "Familiar"
        case .mastered: return "Mastered"
        }
    }

    var symbolName: String {
        switch self {
        case .notStarted: return "circle.dotted"
        case .learning: return "circle.lefthalf.filled"
        case .familiar: return "circle.righthalf.filled"
        case .mastered: return "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .notStarted: return AppColor.tertiaryText
        case .learning: return AppColor.warning
        case .familiar: return AppColor.accent
        case .mastered: return AppColor.positive
        }
    }

    /// Fraction of the way to mastery, used by rings and bars.
    var fraction: Double {
        Double(rawValue) / Double(MasteryLevel.mastered.rawValue)
    }
}
