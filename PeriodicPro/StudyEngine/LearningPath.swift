import Foundation

/// A recommended order through the chemistry, not a gate on it.
///
/// Nothing in Elemora is locked behind a stage. A learner can open any
/// element, build any compound and start any mode on the first launch, and
/// always could. What the path adds is an answer to "where should I start",
/// which a table of 118 tiles does not give on its own.
///
/// Each stage measures itself from progress the app already keeps, so the path
/// fills in as a consequence of studying rather than as a separate thing to
/// tick off.
enum LearningPathStage: Int, CaseIterable, Identifiable, Codable, Sendable {
    case foundations = 0
    case families
    case patterns
    case transitionMetals
    case compounds
    case advanced
    case mastery

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .foundations: return "Foundations"
        case .families: return "Families"
        case .patterns: return "Periodic Patterns"
        case .transitionMetals: return "Transition Metals"
        case .compounds: return "Compounds and Bonding"
        case .advanced: return "Advanced Chemistry"
        case .mastery: return "Periodic Mastery"
        }
    }

    var subtitle: String {
        switch self {
        case .foundations: return "Symbols and atomic numbers"
        case .families: return "The main groups"
        case .patterns: return "Trends and relationships"
        case .transitionMetals: return "The d block"
        case .compounds: return "Formulas, structures and what holds them together"
        case .advanced: return "Molar mass, moles and configurations"
        case .mastery: return "All 118"
        }
    }

    /// What tapping the stage should start.
    var recommendedMode: StudyMode {
        switch self {
        case .foundations: return .flashcards
        case .families: return .quiz
        case .patterns: return .quiz
        case .transitionMetals: return .flashcards
        case .compounds: return .match
        case .advanced: return .advanced
        case .mastery: return .smartReview
        }
    }

    var symbolName: String {
        switch self {
        case .foundations: return "textformat"
        case .families: return "square.grid.2x2"
        case .patterns: return "chart.line.uptrend.xyaxis"
        case .transitionMetals: return "square.grid.3x3.fill"
        case .compounds: return "circle.hexagongrid.fill"
        case .advanced: return "function"
        case .mastery: return "checkmark.seal.fill"
        }
    }

    /// The elements this stage is measured over, where it is measured over
    /// elements at all.
    func elements(in catalog: ElementCatalog) -> [ChemicalElement] {
        switch self {
        case .foundations:
            // The first twenty, which is where every course starts.
            return catalog.elements.filter { $0.atomicNumber <= 20 }
        case .families:
            return catalog.elements.filter { element in
                [.alkaliMetal, .alkalineEarthMetal, .halogen, .nobleGas].contains(element.category)
            }
        case .patterns:
            // Periods 2 and 3 end to end: the rows where the trends are
            // clearest and every group is represented.
            return catalog.elements.filter { (3...18).contains($0.atomicNumber) }
        case .transitionMetals:
            return catalog.elements.filter { $0.category == .transitionMetal }
        case .mastery:
            return catalog.elements
        case .compounds, .advanced:
            return []
        }
    }
}

/// One stage, with how far through it the learner is.
struct LearningPathStep: Identifiable, Equatable, Sendable {
    let stage: LearningPathStage
    /// 0 to 1.
    let progress: Double
    /// What the number is counting — "14 of 20 mastered".
    let detail: String
    /// The first stage that is not finished: where the learner is now.
    let isCurrent: Bool

    var id: Int { stage.id }
    var isComplete: Bool { progress >= 0.999 }
}

/// Measures the path from the progress the app already keeps.
enum LearningPathBuilder {
    /// A stage counts as done at this much of it, rather than at every last
    /// item — the last few elements of a stage are the ones a learner will
    /// pick up anyway, and holding the whole path on them helps nobody.
    static let completionThreshold = 0.9

    /// How many advanced questions count as having worked through that stage.
    static let advancedQuestionTarget = 30
    /// And how many compounds count as having worked through that one.
    static let compoundTarget = 12

    static func steps(
        catalog: ElementCatalog,
        elements: [Int: ElementProgressSnapshot],
        compounds: [String: CompoundProgressSnapshot],
        advancedAnswered: Int
    ) -> [LearningPathStep] {
        var found: [LearningPathStep] = []
        var currentAssigned = false

        for stage in LearningPathStage.allCases {
            let measured = measure(
                stage, catalog: catalog, elements: elements,
                compounds: compounds, advancedAnswered: advancedAnswered
            )
            let isComplete = measured.progress >= completionThreshold
            let isCurrent = !isComplete && !currentAssigned
            if isCurrent { currentAssigned = true }
            found.append(LearningPathStep(
                stage: stage,
                progress: measured.progress,
                detail: measured.detail,
                isCurrent: isCurrent
            ))
        }
        return found
    }

    /// How much of the path is done, for the rank's path term.
    static func completion(_ steps: [LearningPathStep]) -> Double {
        guard !steps.isEmpty else { return 0 }
        return steps.reduce(0) { $0 + min(1, $1.progress) } / Double(steps.count)
    }

    static func measure(
        _ stage: LearningPathStage,
        catalog: ElementCatalog,
        elements: [Int: ElementProgressSnapshot],
        compounds: [String: CompoundProgressSnapshot],
        advancedAnswered: Int
    ) -> (progress: Double, detail: String) {
        switch stage {
        case .compounds:
            let known = compounds.values.filter { $0.mastery >= .familiar }.count
            return (
                min(1, Double(known) / Double(compoundTarget)),
                "\(known) of \(compoundTarget) compounds familiar"
            )
        case .advanced:
            return (
                min(1, Double(advancedAnswered) / Double(advancedQuestionTarget)),
                "\(min(advancedAnswered, advancedQuestionTarget)) of "
                    + "\(advancedQuestionTarget) advanced questions answered"
            )
        default:
            let stageElements = stage.elements(in: catalog)
            guard !stageElements.isEmpty else { return (0, "") }
            let mastered = stageElements.filter {
                (elements[$0.atomicNumber]?.mastery ?? .notStarted) == .mastered
            }.count
            return (
                Double(mastered) / Double(stageElements.count),
                "\(mastered) of \(stageElements.count) mastered"
            )
        }
    }
}
