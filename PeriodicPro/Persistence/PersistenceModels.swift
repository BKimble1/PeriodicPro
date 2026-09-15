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
/// One calendar day on which the learner answered at least one card.
@Model
final class StudyDayRecord {
    @Attribute(.unique) var dayKey: String
    var answeredCount: Int

    init(dayKey: String, answeredCount: Int = 0) {
        self.dayKey = dayKey
        self.answeredCount = answeredCount
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
