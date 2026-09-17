import Foundation

/// When something the learner has practiced is worth seeing again.
///
/// A simplified SM-2: the interval grows with familiarity and shrinks with
/// how often the item has been missed, and the next due date is the last
/// review plus that interval. There is no ease factor and no per-item state,
/// which is deliberate on two counts — it keeps the whole rule a pure
/// function of data the app already stores, so no schema migration is needed
/// and nobody's existing progress has to be rewritten; and it keeps the rule
/// small enough to be completely tested.
///
/// What this feeds: Smart Review's ordering, the widget's choice of question,
/// the review-due notification, and the review-consistency term of the
/// learning rank. All four ask the same question, so all four get the same
/// answer.
enum ReviewSchedule {
    /// The base interval for each familiarity level.
    ///
    /// Roughly: a day for something just met, three days once it is starting
    /// to stick, a week once it is familiar, and three weeks once it is
    /// mastered. Nothing here claims to be a forgetting curve — it is a
    /// schedule chosen to be useful and honest about being a schedule.
    static func baseInterval(for mastery: MasteryLevel) -> TimeInterval {
        switch mastery {
        case .notStarted: return .day
        case .learning: return .day
        case .familiar: return 3 * .day
        case .mastered: return 21 * .day
        }
    }

    /// Longest and shortest an interval may become after the accuracy
    /// adjustment, so one bad round cannot pin an item to ten minutes and one
    /// lucky streak cannot push it past a month.
    static let shortestInterval: TimeInterval = .hours(8)
    static let longestInterval: TimeInterval = 60 * .day

    /// How long to wait before showing this again.
    ///
    /// The base interval for its familiarity, stretched by a good record and
    /// compressed by a poor one. An item answered correctly every time is
    /// shown at up to 1.5× its base interval; one missed more often than not
    /// comes back at a third of it.
    static func interval(mastery: MasteryLevel, correct: Int, incorrect: Int) -> TimeInterval {
        let base = baseInterval(for: mastery)
        let attempts = correct + incorrect
        guard attempts > 0 else { return base }
        let accuracy = Double(correct) / Double(attempts)
        // 0 accuracy → 0.33×, 0.5 → ~0.9×, 1.0 → 1.5×.
        let factor = 0.33 + accuracy * 1.17
        return min(longestInterval, max(shortestInterval, base * factor))
    }

    /// When this item is next worth showing, or `nil` if it has never been
    /// answered and so is not on a schedule at all.
    static func due(
        lastReviewed: Date?, mastery: MasteryLevel, correct: Int, incorrect: Int
    ) -> Date? {
        guard let lastReviewed, correct + incorrect > 0 else { return nil }
        return lastReviewed.addingTimeInterval(
            interval(mastery: mastery, correct: correct, incorrect: incorrect)
        )
    }

    static func isDue(
        lastReviewed: Date?, mastery: MasteryLevel, correct: Int, incorrect: Int,
        now: Date = Date()
    ) -> Bool {
        guard let due = due(lastReviewed: lastReviewed, mastery: mastery,
                            correct: correct, incorrect: incorrect) else { return false }
        return due <= now
    }

    /// How overdue something is, as a multiple of its own interval.
    ///
    /// Zero when it is not due yet, one when it has just come due, two when
    /// it has been waiting a whole interval past that. Expressed relative to
    /// the item's own interval so a mastered element a week late does not
    /// outrank a struggling one a day late.
    static func overdueFactor(
        lastReviewed: Date?, mastery: MasteryLevel, correct: Int, incorrect: Int,
        now: Date = Date()
    ) -> Double {
        guard let due = due(lastReviewed: lastReviewed, mastery: mastery,
                            correct: correct, incorrect: incorrect) else { return 0 }
        let span = interval(mastery: mastery, correct: correct, incorrect: incorrect)
        guard span > 0, due <= now else { return 0 }
        return 1 + now.timeIntervalSince(due) / span
    }

    /// How much this item wants reviewing, highest first.
    ///
    /// Overdue dominates, then a poor record, then unfamiliarity. An item not
    /// yet due scores below every item that is, which is the whole point of
    /// having a schedule.
    static func priority(
        lastReviewed: Date?, mastery: MasteryLevel, correct: Int, incorrect: Int,
        now: Date = Date()
    ) -> Double {
        let attempts = correct + incorrect
        let overdue = overdueFactor(lastReviewed: lastReviewed, mastery: mastery,
                                    correct: correct, incorrect: incorrect, now: now)
        let missRate = attempts > 0 ? Double(incorrect) / Double(attempts) : 0
        let unfamiliarity = Double(MasteryLevel.mastered.rawValue - mastery.rawValue) / 3
        return overdue * 10 + missRate * 3 + unfamiliarity
    }
}

extension ReviewSchedule {
    /// Everything due for review right now, out of a set of element snapshots.
    static func dueElements(
        _ snapshots: [Int: ElementProgressSnapshot], now: Date = Date()
    ) -> [ElementProgressSnapshot] {
        snapshots.values
            .filter {
                isDue(lastReviewed: $0.lastReviewed, mastery: $0.mastery,
                      correct: $0.correctCount, incorrect: $0.incorrectCount, now: now)
            }
            .sorted { lhs, rhs in
                let left = priority(lastReviewed: lhs.lastReviewed, mastery: lhs.mastery,
                                    correct: lhs.correctCount, incorrect: lhs.incorrectCount, now: now)
                let right = priority(lastReviewed: rhs.lastReviewed, mastery: rhs.mastery,
                                     correct: rhs.correctCount, incorrect: rhs.incorrectCount, now: now)
                if left != right { return left > right }
                return lhs.atomicNumber < rhs.atomicNumber
            }
    }

    /// The same, for compounds.
    static func dueCompounds(
        _ snapshots: [String: CompoundProgressSnapshot], now: Date = Date()
    ) -> [CompoundProgressSnapshot] {
        snapshots.values
            .filter {
                isDue(lastReviewed: $0.lastReviewed, mastery: $0.mastery,
                      correct: $0.correctCount, incorrect: $0.incorrectCount, now: now)
            }
            .sorted { $0.compoundID < $1.compoundID }
    }
}

extension TimeInterval {
    static let day: TimeInterval = 86_400
    static func hours(_ count: Double) -> TimeInterval { count * 3_600 }
}
