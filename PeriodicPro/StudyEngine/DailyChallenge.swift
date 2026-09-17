import Foundation

/// Five questions, the same five all day, different tomorrow.
///
/// Deterministic per calendar day, so backing out and coming back does not
/// reshuffle it and a learner comparing notes with a classmate on the same
/// day sees the same set. There is no server and no leaderboard — the
/// determinism is for the learner's own sake, not to compare them with
/// anybody.
///
/// The mix is deliberate: mostly what they are weakest on, one thing they
/// already know, and one harder question, so a challenge is neither a wall
/// nor a formality.
enum DailyChallenge {
    static let questionCount = 5

    /// The seed for a given day. Salted so the challenge does not deal the
    /// same material as any other mode that seeds itself from the date.
    static func seed(for date: Date = Date(), calendar: Calendar = .current) -> UInt64 {
        SeededGenerator.dailySeed(for: date, calendar: calendar) &* 0x9E37_79B9 &+ 0x5DEE_CE66
    }

    static func dayKey(for date: Date = Date(), calendar: Calendar = .current) -> String {
        StreakCalculator.dayKey(for: date, calendar: calendar)
    }

    /// The subjects today's challenge is about.
    ///
    /// Three from the weakest and overdue, one already mastered — recall
    /// decays, and a challenge that only ever asks about weak spots never
    /// confirms anything — and one drawn from the whole table so there is
    /// something new in it.
    static func subjects(
        catalog: ElementCatalog,
        snapshots: [Int: ElementProgressSnapshot],
        seed: UInt64,
        count: Int = questionCount
    ) -> [ChemicalElement] {
        guard count > 0, !catalog.elements.isEmpty else { return [] }
        var generator = SeededGenerator(seed: seed)
        let byNumber = Dictionary(
            catalog.elements.map { ($0.atomicNumber, $0) }, uniquingKeysWith: { first, _ in first }
        )

        var chosen: [ChemicalElement] = []
        var seen = Set<Int>()

        func take(_ element: ChemicalElement?) {
            guard let element, seen.insert(element.atomicNumber).inserted else { return }
            chosen.append(element)
        }

        // The weakest and the overdue, which is the same ordering Smart
        // Review uses.
        let weak = SmartReviewBuilder.ranked(Array(snapshots.values))
            .compactMap { byNumber[$0.atomicNumber] }
        for element in weak.prefix(max(0, count - 2)) { take(element) }

        // One already mastered.
        let mastered = snapshots.values
            .filter { $0.mastery == .mastered }
            .compactMap { byNumber[$0.atomicNumber] }
            .sorted { $0.atomicNumber < $1.atomicNumber }
        take(mastered.randomElement(using: &generator))

        // And fill from the whole table, so a new learner gets five and an
        // old one meets something they have not seen.
        let rest = catalog.elements.shuffled(using: &generator)
        for element in rest where chosen.count < count { take(element) }

        return Array(chosen.prefix(count))
    }

    /// Today's questions.
    static func questions(
        catalog: ElementCatalog,
        snapshots: [Int: ElementProgressSnapshot],
        compounds: [ChemicalCompound],
        date: Date = Date(),
        calendar: Calendar = .current
    ) -> [QuizQuestion] {
        let seed = seed(for: date, calendar: calendar)
        let elements = subjects(catalog: catalog, snapshots: snapshots, seed: seed)
        guard !elements.isEmpty else { return [] }
        return QuizGenerator.makeQuiz(
            subjects: elements.map(QuizSubject.element),
            elementDistractors: catalog.elements,
            compoundDistractors: compounds.filter { !$0.isHypothetical },
            // Mixed rather than easy: a daily challenge that never asks
            // anything hard is a formality.
            difficulty: .mixed,
            count: questionCount,
            seed: seed,
            shuffles: true
        )
    }
}

/// Whether today's challenge has been done, kept in the learner's defaults.
///
/// One string. There is no history to keep: the streak already records which
/// days were studied, and a challenge completed is a day studied.
@MainActor
enum DailyChallengeRecord {
    static let storageKey = "dailyChallenge.completedDay"

    static func isComplete(
        on date: Date = Date(),
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.string(forKey: storageKey) == DailyChallenge.dayKey(for: date, calendar: calendar)
    }

    static func markComplete(
        on date: Date = Date(),
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(DailyChallenge.dayKey(for: date, calendar: calendar), forKey: storageKey)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }
}
