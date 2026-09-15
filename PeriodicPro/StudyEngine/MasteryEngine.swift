import Foundation

/// Pure mastery transition rules. Deliberately not spaced repetition — a small
/// honest score is enough to power the Progress screen in V1.
enum MasteryEngine {
    /// A correct answer advances one step, capped at `.mastered`.
    /// An incorrect answer steps back one, but never below `.learning`, so that
    /// attempting an element always registers as having started it.
    static func next(from level: MasteryLevel, correct: Bool) -> MasteryLevel {
        if correct {
            return MasteryLevel(rawValue: min(level.rawValue + 1, MasteryLevel.mastered.rawValue))
                ?? .mastered
        }
        return MasteryLevel(rawValue: max(level.rawValue - 1, MasteryLevel.learning.rawValue))
            ?? .learning
    }

    /// Elements to put in front of the learner first: least-known before
    /// best-known, then by atomic number so ordering is deterministic.
    static func studyPriority(
        _ elements: [ChemicalElement],
        mastery: (Int) -> MasteryLevel
    ) -> [ChemicalElement] {
        elements.sorted { lhs, rhs in
            let left = mastery(lhs.atomicNumber).rawValue
            let right = mastery(rhs.atomicNumber).rawValue
            if left != right { return left < right }
            return lhs.atomicNumber < rhs.atomicNumber
        }
    }
}

/// Counts consecutive days of study activity.
enum StreakCalculator {
    static let dayKeyFormat = "yyyy-MM-dd"

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// A streak stays alive while the learner studied today, or studied
    /// yesterday and simply has not opened the app yet today.
    static func currentStreak(
        days: Set<String>,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        guard !days.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: today)
        if !days.contains(dayKey(for: cursor, calendar: calendar)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  days.contains(dayKey(for: yesterday, calendar: calendar)) else {
                return 0
            }
            cursor = yesterday
        }

        var streak = 0
        while days.contains(dayKey(for: cursor, calendar: calendar)) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }
}
