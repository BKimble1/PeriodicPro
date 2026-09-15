import Foundation

/// The practice modes.
///
/// Three card formats — reveal, multiple choice, and name-it-from-its-structure
/// — plus Smart Review, which is the flashcard format run over the elements the
/// learner keeps getting wrong rather than over the whole table.
enum StudyMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case flashcards
    case quiz
    case identify
    case smartReview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flashcards: return "Flashcards"
        case .quiz: return "Quiz"
        case .identify: return "Identify"
        case .smartReview: return "Smart Review"
        }
    }

    /// The longer name, used where there is room for it.
    var fullTitle: String {
        switch self {
        case .quiz: return "Quick Quiz"
        default: return title
        }
    }

    var subtitle: String {
        switch self {
        case .flashcards: return "Reveal and self-rate"
        case .quiz: return "10 multiple-choice questions"
        case .identify: return "Name it from its structure"
        case .smartReview: return "The elements you keep missing"
        }
    }

    var symbolName: String {
        switch self {
        case .flashcards: return "rectangle.on.rectangle.angled"
        case .quiz: return "questionmark.circle.fill"
        case .identify: return "eye.fill"
        // A crosshair: the right idea for a mode that aims at weak spots.
        // (The obvious name for that symbol does not exist in SF Symbols.)
        case .smartReview: return "scope"
        }
    }

    /// Smart Review is the one mode behind Pro.
    var requiresPro: Bool { self == .smartReview }

    /// Mixed into the session seed so the modes do not draw the same ten
    /// elements, in the same order, on the same day.
    var seedSalt: UInt64 {
        switch self {
        case .flashcards: return 0x9E37_79B9_7F4A_7C15
        case .quiz: return 0x85EB_CA6B_C2B2_AE35
        case .identify: return 0x27D4_EB2F_1656_67C5
        case .smartReview: return 0x1F83_D9AB_FB41_BD6B
        }
    }
}

/// What the learner is shown before the answer is revealed.
enum StudyClue: Equatable, Hashable, Sendable {
    /// A large piece of text: an element name, a symbol, or a number.
    case text(String)
    /// The simplified shell diagram for the element.
    case structure
    /// A short written hint, e.g. "Alkali metal in period 3".
    case description(String)
}

/// One card in a flashcard or identify session.
struct StudyCard: Identifiable, Equatable, Hashable, Sendable {
    let id: Int
    let element: ChemicalElement
    /// The question above the clue, e.g. "What is the symbol?"
    let question: String
    let clue: StudyClue
    /// Large answer, e.g. "O".
    let answerTitle: String
    /// Supporting answer line, e.g. "Oxygen \u{00B7} Atomic number 8".
    let answerDetail: String
}

/// One multiple-choice question.
struct QuizQuestion: Identifiable, Equatable, Hashable, Sendable {
    let id: Int
    let kind: Kind
    let element: ChemicalElement
    let prompt: String
    let options: [String]
    let correctIndex: Int

    enum Kind: String, CaseIterable, Hashable, Sendable {
        case symbolForName
        case nameForSymbol
        case numberForName
        case familyForElement
    }

    var correctAnswer: String { options[correctIndex] }

    func isCorrect(_ index: Int) -> Bool { index == correctIndex }
}

/// Outcome of a completed session.
struct StudyResult: Equatable, Hashable, Sendable {
    let mode: StudyMode
    let correct: Int
    let total: Int

    var accuracy: Double { total == 0 ? 0 : Double(correct) / Double(total) }

    /// Calm, factual encouragement — no confetti, no cartoon celebration.
    var headline: String {
        switch accuracy {
        case 1.0: return "Perfect round."
        case 0.8..<1.0: return "Strong round."
        case 0.5..<0.8: return "Solid progress."
        default: return "Good start."
        }
    }

    var message: String {
        switch accuracy {
        case 1.0:
            return "Every answer correct. These elements are sticking."
        case 0.8..<1.0:
            return "Nearly all correct. A short review will close the gap."
        case 0.5..<0.8:
            return "More than half correct. Repetition is what moves these to mastered."
        default:
            return "Everything you reviewed is now tracked. Familiarity builds fastest with short, regular rounds."
        }
    }
}
