import Foundation

/// The three things Elemora Pro unlocks.
///
/// Everything else in the app — all 118 elements, the whole table, search,
/// filters, favorites, the facts, About, Common Uses, Memory Hooks, Progress,
/// and all three practice modes — stays free. Pro buys depth, not access to the
/// periodic table.
enum ProFeature: Hashable, Sendable {
    /// The full interactive 3D explorer for one element.
    case interactiveStructure(atomicNumber: Int)
    /// Study rounds beyond the free daily allowance.
    case unlimitedStudy
    /// Rounds built from the elements the learner keeps getting wrong.
    case smartReview

    var title: String {
        switch self {
        case .interactiveStructure: return "Interactive 3D Structures"
        case .unlimitedStudy: return "Unlimited Study"
        case .smartReview: return "Smart Review"
        }
    }
}

/// Decides whether a feature is available. Pure: no StoreKit, no SwiftUI, no
/// dates, no I/O — so every combination is unit-testable.
enum ProAccess {
    /// Six elements are fully explorable in 3D without paying anything.
    ///
    /// The point is that "Explore in 3D" is not a locked door the learner has to
    /// take on trust. Hydrogen, carbon, oxygen, sodium, iron and gold cover
    /// every structure type the explorer can draw — a diatomic molecule, a
    /// covalent network, a second diatomic with a double bond, and three
    /// metallic lattices — so a free user sees the real feature, not a trailer.
    static let demoAtomicNumbers: Set<Int> = [
        1,   // Hydrogen — diatomic, single bond
        6,   // Carbon — covalent network
        8,   // Oxygen — diatomic, double bond
        11,  // Sodium — metallic lattice
        26,  // Iron — metallic lattice
        79,  // Gold — metallic lattice
    ]

    static func isDemo(atomicNumber: Int) -> Bool {
        demoAtomicNumbers.contains(atomicNumber)
    }

    static func isUnlocked(_ feature: ProFeature, isPro: Bool) -> Bool {
        if isPro { return true }
        switch feature {
        case .interactiveStructure(let atomicNumber):
            return isDemo(atomicNumber: atomicNumber)
        case .unlimitedStudy, .smartReview:
            return false
        }
    }
}

/// The free daily study allowance.
///
/// Three complete rounds a day. A round is the existing ten-card or
/// ten-question session, and it is only counted once it finishes — so quitting
/// half way through, or being interrupted, never costs the learner an attempt.
enum DailyStudyLimiter {
    static let freeRoundsPerDay = 3

    /// Whether a new round may start now.
    static func canStartRound(completedToday: Int, isPro: Bool) -> Bool {
        if isPro { return true }
        return completedToday < freeRoundsPerDay
    }

    /// Rounds left today, or `nil` when the learner is Pro and there is no
    /// number to show.
    static func remainingRounds(completedToday: Int, isPro: Bool) -> Int? {
        if isPro { return nil }
        return max(0, freeRoundsPerDay - completedToday)
    }

    /// The line under the Practice heading. `nil` for Pro, where a counter
    /// would be noise.
    static func allowanceDescription(completedToday: Int, isPro: Bool) -> String? {
        guard let remaining = remainingRounds(completedToday: completedToday, isPro: isPro) else {
            return nil
        }
        switch remaining {
        case 0: return "No free rounds left today"
        case 1: return "1 free round left today"
        default: return "\(remaining) free rounds left today"
        }
    }
}
