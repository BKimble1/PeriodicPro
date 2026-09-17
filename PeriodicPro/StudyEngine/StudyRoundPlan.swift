import Foundation

/// Everything needed to deal a configured quiz or match round, captured once
/// when the round starts so the deck is frozen for the session and "Study
/// again" can deal a fresh one from a fresh seed.
struct QuizRoundDealer: Hashable, Sendable {
    let configuration: QuizConfiguration
    let subjects: [QuizSubject]
    let elementDistractors: [ChemicalElement]
    let compoundDistractors: [ChemicalCompound]

    /// The questions for one session. The same seed always deals the same
    /// questions in the same order with the same options.
    func questions(seed: UInt64) -> [QuizQuestion] {
        QuizGenerator.makeQuiz(
            subjects: subjects,
            elementDistractors: elementDistractors,
            compoundDistractors: compoundDistractors,
            difficulty: configuration.difficulty,
            count: configuration.clampedQuestionCount,
            seed: seed,
            shuffles: configuration.shuffles
        )
    }

    /// The pairs for one Match session.
    func matchRound(seed: UInt64) -> MatchRound {
        MatchRoundBuilder.round(subjects: subjects, pairCount: configuration.clampedQuestionCount, seed: seed)
    }
}

/// Everything needed to deal a round of advanced chemistry.
///
/// Captured before the round is presented, the same way the quiz dealer is,
/// so the questions are frozen for the session and "Study again" deals a
/// fresh set from a fresh seed.
struct AdvancedRoundDealer: Hashable, Sendable {
    let count: Int
    let kinds: [AdvancedQuestion.Kind]
    /// The element catalog, as its elements: `ElementCatalog` is not itself
    /// `Hashable`, and `StudyRoundPlan` has to be.
    let elements: [ChemicalElement]
    let compounds: [ChemicalCompound]

    init(
        count: Int = 8,
        kinds: [AdvancedQuestion.Kind] = AdvancedQuestion.Kind.allCases,
        catalog: ElementCatalog,
        compounds: [ChemicalCompound]
    ) {
        self.count = count
        self.kinds = kinds
        self.elements = catalog.elements
        self.compounds = compounds
    }

    func questions(seed: UInt64) -> [AdvancedQuestion] {
        AdvancedQuestionBuilder.round(
            count: count, seed: seed, kinds: kinds,
            catalog: ElementCatalog(elements: elements),
            compounds: CompoundCatalog(compounds: compounds)
        )
    }
}

/// What a study round is made of. The mode decides the screen; the payload
/// is whatever that screen needs, captured before the round is presented.
enum StudyRoundPlan: Identifiable, Hashable, Sendable {
    /// Flashcards, Identify or Smart Review over an element queue.
    case cards(StudyMode, [ChemicalElement])
    /// A configured multiple-choice round.
    case quiz(QuizRoundDealer)
    /// A configured Match round.
    case match(QuizRoundDealer)
    /// A round of advanced chemistry: calculations, configurations and trends.
    case advanced(AdvancedRoundDealer)

    var mode: StudyMode {
        switch self {
        case .cards(let mode, _): return mode
        case .quiz: return .quiz
        case .match: return .match
        case .advanced: return .advanced
        }
    }

    /// The same identity the mode has, so a second tap on the same mode
    /// never re-presents a round that is already on screen.
    var id: String { mode.id }
}
