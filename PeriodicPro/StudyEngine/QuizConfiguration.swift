import Foundation

/// What a quiz asks about: the elements, the compounds, or both.
enum QuizContent: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case elements
    case compounds
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .elements: return "Elements"
        case .compounds: return "Compounds"
        case .both: return "Both"
        }
    }

    var includesElements: Bool { self != .compounds }
    var includesCompounds: Bool { self != .elements }
}

/// Which part of the material a round draws from.
enum QuizScope: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case all
    case favorites
    case recentlyMissed
    case notMastered
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Everything"
        case .favorites: return "Favorites"
        case .recentlyMissed: return "Recently missed"
        case .notMastered: return "Not yet mastered"
        case .custom: return "Custom selection"
        }
    }

    var detail: String {
        switch self {
        case .all: return "Every element or compound the filters allow"
        case .favorites: return "Only what you have marked with a heart"
        case .recentlyMissed: return "What you answered wrongly, most recent first"
        case .notMastered: return "Everything you have not yet mastered"
        case .custom: return "Pick the exact elements and compounds"
        }
    }
}

/// How hard the questions are, which decides which question types are dealt.
enum QuizDifficulty: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case easy
    case medium
    case hard
    case mixed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .easy: return "Easy"
        case .medium: return "Medium"
        case .hard: return "Hard"
        case .mixed: return "Mixed"
        }
    }

    /// The question types this level deals, for elements.
    var elementKinds: [QuizQuestion.Kind] {
        switch self {
        case .easy: return [.symbolForName, .nameForSymbol]
        case .medium: return [.numberForName, .familyForElement, .phaseForElement, .periodForElement]
        case .hard: return [.configurationForElement, .elementForClue, .groupForElement, .massForElement]
        case .mixed: return QuizDifficulty.easy.elementKinds + QuizDifficulty.medium.elementKinds
            + QuizDifficulty.hard.elementKinds
        }
    }

    /// The question types this level deals, for compounds.
    var compoundKinds: [QuizQuestion.Kind] {
        switch self {
        case .easy: return [.formulaForCompound, .compoundForFormula]
        case .medium: return [.molarMassForCompound, .bondingForCompound, .elementInCompound]
        case .hard: return [.atomCountForCompound, .compoundForDescription]
        case .mixed: return QuizDifficulty.easy.compoundKinds + QuizDifficulty.medium.compoundKinds
            + QuizDifficulty.hard.compoundKinds
        }
    }
}

/// Narrows the element pool. Empty sets mean "no restriction".
struct QuizElementFilters: Codable, Hashable, Sendable {
    var categories: Set<ElementCategory> = []
    var phases: Set<MatterPhase> = []
    var periods: Set<Int> = []
    var groups: Set<Int> = []
    /// Inclusive atomic-number bounds. `nil` means unbounded on that side.
    var minimumAtomicNumber: Int?
    var maximumAtomicNumber: Int?

    var isActive: Bool {
        !categories.isEmpty || !phases.isEmpty || !periods.isEmpty || !groups.isEmpty
            || minimumAtomicNumber != nil || maximumAtomicNumber != nil
    }

    func matches(_ element: ChemicalElement) -> Bool {
        if !categories.isEmpty, !categories.contains(element.category) { return false }
        if !phases.isEmpty, !phases.contains(element.phase) { return false }
        if !periods.isEmpty, !periods.contains(element.period) { return false }
        if !groups.isEmpty {
            guard let group = element.group, groups.contains(group) else { return false }
        }
        if let minimumAtomicNumber, element.atomicNumber < minimumAtomicNumber { return false }
        if let maximumAtomicNumber, element.atomicNumber > maximumAtomicNumber { return false }
        return true
    }

    /// A short description for the setup screen, or `nil` when nothing is set.
    var summary: String? {
        var parts: [String] = []
        if !categories.isEmpty { parts.append(categories.count == 1 ? "1 family" : "\(categories.count) families") }
        if !phases.isEmpty { parts.append(phases.map(\.displayName).sorted().joined(separator: "/")) }
        if !periods.isEmpty { parts.append("periods " + periods.sorted().map(String.init).joined(separator: ", ")) }
        if !groups.isEmpty { parts.append("groups " + groups.sorted().map(String.init).joined(separator: ", ")) }
        switch (minimumAtomicNumber, maximumAtomicNumber) {
        case let (low?, high?): parts.append("Z \(low)–\(high)")
        case let (low?, nil): parts.append("Z ≥ \(low)")
        case let (nil, high?): parts.append("Z ≤ \(high)")
        case (nil, nil): break
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Narrows the compound pool. Empty sets mean "no restriction".
struct QuizCompoundFilters: Codable, Hashable, Sendable {
    var bondingClasses: Set<CompoundBondingClass> = []
    var tags: Set<CompoundTag> = []
    /// Only compounds the learner saved or favorited, rather than the whole
    /// bundled catalog.
    var onlySaved = false

    var isActive: Bool { !bondingClasses.isEmpty || !tags.isEmpty || onlySaved }

    func matches(_ compound: ChemicalCompound, isSaved: Bool) -> Bool {
        if onlySaved, !isSaved { return false }
        if !bondingClasses.isEmpty, !bondingClasses.contains(compound.bondingClass) { return false }
        if !tags.isEmpty, tags.isDisjoint(with: compound.tags) { return false }
        return true
    }

    var summary: String? {
        var parts: [String] = []
        if onlySaved { parts.append("saved only") }
        if !bondingClasses.isEmpty { parts.append(bondingClasses.map(\.displayName).sorted().joined(separator: "/")) }
        if !tags.isEmpty { parts.append(tags.map(\.displayName).sorted().joined(separator: "/")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Everything that decides what a quiz or match round contains.
///
/// A value type, `Codable`, so it can be saved as a quiz, shared as a package
/// and, above all, tested: the same configuration and seed always deal the
/// same round.
struct QuizConfiguration: Codable, Hashable, Sendable {
    static let lengthPresets = [5, 10, 20]
    static let minimumQuestions = 3
    static let maximumQuestions = 50
    static let matchPairPresets = [6, 8, 10]
    static let timerPresets = [15, 30, 60]
    /// Custom selections are capped so a shared quiz can never be a payload.
    static let maximumCustomItems = 200

    var content: QuizContent = .elements
    var scope: QuizScope = .all
    var elementFilters = QuizElementFilters()
    var compoundFilters = QuizCompoundFilters()
    /// Atomic numbers, for `scope == .custom`.
    var customElementIDs: [Int] = []
    /// Compound identifiers, for `scope == .custom`.
    var customCompoundIDs: [String] = []
    var difficulty: QuizDifficulty = .mixed
    var questionCount: Int = 10
    /// Seconds per question. `nil` is the default: no timer.
    var timerSeconds: Int?
    /// Whether the deck is shuffled. On by default; off keeps the pool's own
    /// order, which for the "recently missed" scope is most recent first.
    var shuffles = true

    var isTimed: Bool { timerSeconds != nil }

    /// The count clamped to what a round may contain.
    var clampedQuestionCount: Int {
        min(max(questionCount, Self.minimumQuestions), Self.maximumQuestions)
    }

    /// The configuration with every list capped and every number in range, so
    /// an imported or hand-edited value can never produce a broken round.
    func sanitized() -> QuizConfiguration {
        var copy = self
        copy.questionCount = clampedQuestionCount
        copy.customElementIDs = Array(copy.customElementIDs.filter { (1...118).contains($0) }
            .prefix(Self.maximumCustomItems))
        copy.customCompoundIDs = Array(copy.customCompoundIDs.prefix(Self.maximumCustomItems))
        if let timer = copy.timerSeconds, !(5...300).contains(timer) {
            copy.timerSeconds = nil
        }
        if let low = copy.elementFilters.minimumAtomicNumber, let high = copy.elementFilters.maximumAtomicNumber,
           low > high {
            copy.elementFilters.minimumAtomicNumber = high
            copy.elementFilters.maximumAtomicNumber = low
        }
        return copy
    }

    /// One line for a list row: "10 questions · Elements · Mixed".
    var summary: String {
        var parts = ["\(clampedQuestionCount) questions", content.title, difficulty.title]
        if scope != .all { parts.append(scope.title) }
        if isTimed { parts.append("timed") }
        return parts.joined(separator: " · ")
    }

    /// The defaults the setup screen opens with.
    static let standard = QuizConfiguration()
}

/// The thing a question is about.
enum QuizSubject: Hashable, Sendable {
    case element(ChemicalElement)
    case compound(ChemicalCompound)

    var element: ChemicalElement? {
        if case .element(let element) = self { return element }
        return nil
    }

    var compound: ChemicalCompound? {
        if case .compound(let compound) = self { return compound }
        return nil
    }

    /// A stable key for deduplication and for recording answers.
    var key: String {
        switch self {
        case .element(let element): return "element-\(element.atomicNumber)"
        case .compound(let compound): return compound.id
        }
    }

    var displayName: String {
        switch self {
        case .element(let element): return element.name
        case .compound(let compound): return compound.preferredName
        }
    }
}

/// Session seeds.
///
/// Every round gets a fresh seed from a UUID, so two sessions never deal the
/// same order — unless a test injects one, in which case the round is exactly
/// reproducible.
enum QuizSeed {
    static func fresh() -> UInt64 {
        let uuid = UUID().uuid
        var value: UInt64 = 0
        for byte in [uuid.0, uuid.1, uuid.2, uuid.3, uuid.4, uuid.5, uuid.6, uuid.7] {
            value = (value << 8) | UInt64(byte)
        }
        return value == 0 ? 0x9E37_79B9_7F4A_7C15 : value
    }
}
