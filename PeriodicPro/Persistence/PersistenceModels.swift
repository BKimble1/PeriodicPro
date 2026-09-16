import Foundation
import SwiftData

/// Per-element user state: favorite flag and familiarity score.
@Model
final class ElementProgressRecord {
    @Attribute(.unique) var atomicNumber: Int
    var isFavorite: Bool
    var masteryRaw: Int
    var correctCount: Int
    var incorrectCount: Int
    var lastReviewed: Date?

    init(
        atomicNumber: Int,
        isFavorite: Bool = false,
        masteryRaw: Int = MasteryLevel.notStarted.rawValue,
        correctCount: Int = 0,
        incorrectCount: Int = 0,
        lastReviewed: Date? = nil
    ) {
        self.atomicNumber = atomicNumber
        self.isFavorite = isFavorite
        self.masteryRaw = masteryRaw
        self.correctCount = correctCount
        self.incorrectCount = incorrectCount
        self.lastReviewed = lastReviewed
    }
}

/// A term the learner typed into the table search field.
@Model
final class RecentSearchRecord {
    @Attribute(.unique) var text: String
    var timestamp: Date

    init(text: String, timestamp: Date) {
        self.text = text
        self.timestamp = timestamp
    }
}

/// One calendar day on which the learner answered at least one card.
@Model
final class StudyDayRecord {
    @Attribute(.unique) var dayKey: String
    var answeredCount: Int
    /// Rounds finished on this day, which is what the free daily allowance is
    /// measured against. Counted only when a round reaches its summary, so
    /// abandoning one half way through never costs an attempt.
    ///
    /// Declared with a default so adding it is a lightweight SwiftData
    /// migration rather than a schema break for anyone already on a build.
    var completedRounds: Int = 0

    init(dayKey: String, answeredCount: Int = 0, completedRounds: Int = 0) {
        self.dayKey = dayKey
        self.answeredCount = answeredCount
        self.completedRounds = completedRounds
    }
}

/// Immutable snapshot the UI reads, so views never touch managed objects
/// directly and never re-render because of unrelated store churn.
struct ElementProgressSnapshot: Hashable, Sendable {
    var atomicNumber: Int
    var isFavorite: Bool = false
    var mastery: MasteryLevel = .notStarted
    var correctCount: Int = 0
    var incorrectCount: Int = 0
    var lastReviewed: Date?

    var attempts: Int { correctCount + incorrectCount }
}

/// Per-compound user state: favorite, saved for study, and familiarity.
///
/// Keyed by the compound's stable local identifier (`pubchem-962`), which is
/// the same whether the record came from the bundled catalog or a lookup.
@Model
final class CompoundProgressRecord {
    @Attribute(.unique) var compoundID: String
    var isFavorite: Bool
    var isSaved: Bool
    var masteryRaw: Int
    var correctCount: Int
    var incorrectCount: Int
    var lastReviewed: Date?

    init(
        compoundID: String,
        isFavorite: Bool = false,
        isSaved: Bool = false,
        masteryRaw: Int = MasteryLevel.notStarted.rawValue,
        correctCount: Int = 0,
        incorrectCount: Int = 0,
        lastReviewed: Date? = nil
    ) {
        self.compoundID = compoundID
        self.isFavorite = isFavorite
        self.isSaved = isSaved
        self.masteryRaw = masteryRaw
        self.correctCount = correctCount
        self.incorrectCount = incorrectCount
        self.lastReviewed = lastReviewed
    }
}

/// Immutable snapshot of one compound's progress, for the same reason
/// `ElementProgressSnapshot` exists.
struct CompoundProgressSnapshot: Hashable, Sendable {
    var compoundID: String
    var isFavorite: Bool = false
    var isSaved: Bool = false
    var mastery: MasteryLevel = .notStarted
    var correctCount: Int = 0
    var incorrectCount: Int = 0
    var lastReviewed: Date?

    var attempts: Int { correctCount + incorrectCount }
    /// Part of the learner's study material: chosen, or already practiced.
    var isInStudy: Bool { isSaved || isFavorite || attempts > 0 }
}
