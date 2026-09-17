import Foundation
import Testing
@testable import PeriodicPro

@Suite("Smart Review")
struct SmartReviewTests {
    private let catalog = TestCatalog.shared

    private func snapshot(
        _ atomicNumber: Int,
        mastery: MasteryLevel = .learning,
        correct: Int = 0,
        incorrect: Int = 0,
        reviewed: Date? = nil
    ) -> ElementProgressSnapshot {
        ElementProgressSnapshot(
            atomicNumber: atomicNumber,
            isFavorite: false,
            mastery: mastery,
            correctCount: correct,
            incorrectCount: incorrect,
            lastReviewed: reviewed
        )
    }

    @Test("The most-missed element comes first")
    func mostMissedComesFirst() {
        let ranked = SmartReviewBuilder.ranked([
            snapshot(1, mastery: .familiar, correct: 5, incorrect: 1),
            snapshot(2, mastery: .learning, correct: 1, incorrect: 4),
            snapshot(3, mastery: .learning, correct: 2, incorrect: 2),
        ])
        #expect(ranked.map(\.atomicNumber) == [2, 3, 1])
    }

    @Test("With equal misses, the least familiar comes first")
    func masteryBreaksTies() {
        let ranked = SmartReviewBuilder.ranked([
            snapshot(10, mastery: .mastered, correct: 4, incorrect: 2),
            snapshot(11, mastery: .learning, correct: 1, incorrect: 2),
            snapshot(12, mastery: .familiar, correct: 3, incorrect: 2),
        ])
        #expect(ranked.map(\.atomicNumber) == [11, 12, 10])
    }

    @Test("With equal misses and familiarity, the longest unseen comes first")
    func recencyBreaksRemainingTies() {
        let old = Date(timeIntervalSinceReferenceDate: 1_000)
        let recent = Date(timeIntervalSinceReferenceDate: 9_000)
        let ranked = SmartReviewBuilder.ranked([
            snapshot(20, mastery: .learning, correct: 1, incorrect: 1, reviewed: recent),
            snapshot(21, mastery: .learning, correct: 1, incorrect: 1, reviewed: old),
        ])
        #expect(ranked.map(\.atomicNumber) == [21, 20])
    }

    @Test("Ranking is deterministic when everything else is equal")
    func rankingIsDeterministic() {
        let input = [
            snapshot(30, correct: 1, incorrect: 1),
            snapshot(31, correct: 1, incorrect: 1),
            snapshot(32, correct: 1, incorrect: 1),
        ]
        #expect(SmartReviewBuilder.ranked(input).map(\.atomicNumber) == [30, 31, 32])
        #expect(SmartReviewBuilder.ranked(input.reversed()).map(\.atomicNumber) == [30, 31, 32])
    }

    @Test("Elements never attempted are not part of a review")
    func unattemptedElementsAreExcluded() {
        let ranked = SmartReviewBuilder.ranked([
            snapshot(40, mastery: .notStarted, correct: 0, incorrect: 0),
            snapshot(41, mastery: .learning, correct: 0, incorrect: 2),
        ])
        #expect(ranked.map(\.atomicNumber) == [41])
    }

    @Test("A favorite with no attempts is not treated as a weak element")
    func favoritesAreNotHistory() {
        var favorite = snapshot(50, mastery: .notStarted)
        favorite.isFavorite = true
        #expect(SmartReviewBuilder.ranked([favorite]).isEmpty)
    }

    // MARK: - Availability

    @Test("Smart Review needs a few attempted elements before it means anything")
    func availabilityThreshold() {
        var snapshots: [Int: ElementProgressSnapshot] = [:]
        for atomicNumber in 1...4 {
            snapshots[atomicNumber] = snapshot(atomicNumber, correct: 1)
        }
        #expect(!SmartReviewBuilder.isAvailable(snapshots: snapshots))
        #expect(SmartReviewBuilder.unavailableReason(snapshots: snapshots) != nil)

        snapshots[5] = snapshot(5, correct: 1)
        #expect(SmartReviewBuilder.isAvailable(snapshots: snapshots))
        #expect(SmartReviewBuilder.unavailableReason(snapshots: snapshots) == nil)
    }

    @Test("The unavailable message counts down accurately")
    func unavailableMessageIsAccurate() {
        var snapshots: [Int: ElementProgressSnapshot] = [:]
        snapshots[1] = snapshot(1, correct: 1)
        snapshots[2] = snapshot(2, correct: 1)
        snapshots[3] = snapshot(3, correct: 1)
        snapshots[4] = snapshot(4, correct: 1)
        // One short of the threshold: the message must say one, and say it in
        // the singular.
        let reason = SmartReviewBuilder.unavailableReason(snapshots: snapshots) ?? ""
        #expect(reason.contains("1 more element"))
        #expect(!reason.contains("1 more elements"))
    }

    // MARK: - Queue

    @Test("The queue leads with the weakest elements")
    func queueLeadsWithWeakest() {
        var snapshots: [Int: ElementProgressSnapshot] = [:]
        snapshots[26] = snapshot(26, mastery: .learning, correct: 0, incorrect: 5)   // Iron
        snapshots[79] = snapshot(79, mastery: .learning, correct: 1, incorrect: 3)   // Gold
        snapshots[8] = snapshot(8, mastery: .familiar, correct: 4, incorrect: 1)     // Oxygen

        let queue = SmartReviewBuilder.queue(
            elements: catalog.elements, snapshots: snapshots
        )
        #expect(queue.prefix(3).map(\.atomicNumber) == [26, 79, 8])
    }

    @Test("The queue is topped up so a round never repeats a card")
    func queueIsToppedUp() {
        // Only three weak elements, but a round needs ten cards from a pool.
        var snapshots: [Int: ElementProgressSnapshot] = [:]
        for atomicNumber in [3, 14, 47] {
            snapshots[atomicNumber] = snapshot(atomicNumber, correct: 0, incorrect: 2)
        }
        let queue = SmartReviewBuilder.queue(elements: catalog.elements, snapshots: snapshots)
        #expect(queue.count == StudyDeckBuilder.defaultPoolSize)
        #expect(Set(queue.map(\.atomicNumber)).count == queue.count,
                "the pool must not contain the same element twice")
    }

    @Test("A Smart Review deck holds ten distinct elements")
    func deckHasNoDuplicates() {
        var snapshots: [Int: ElementProgressSnapshot] = [:]
        for atomicNumber in 1...12 {
            snapshots[atomicNumber] = snapshot(
                atomicNumber, correct: 1, incorrect: atomicNumber % 4
            )
        }
        let queue = SmartReviewBuilder.queue(elements: catalog.elements, snapshots: snapshots)
        let deck = StudyDeckBuilder.flashcards(pool: queue, seed: 7)
        #expect(deck.count == StudyDeckBuilder.defaultCardCount)
        #expect(Set(deck.map(\.element.atomicNumber)).count == deck.count,
                "a round must not show the same element twice")
    }

    @Test("A Smart Review card never shows its own answer")
    func cardsDoNotLeakTheAnswer() {
        var snapshots: [Int: ElementProgressSnapshot] = [:]
        for atomicNumber in 1...20 {
            snapshots[atomicNumber] = snapshot(atomicNumber, correct: 1, incorrect: 1)
        }
        let queue = SmartReviewBuilder.queue(elements: catalog.elements, snapshots: snapshots)
        for seed in UInt64(0)..<12 {
            for card in StudyDeckBuilder.flashcards(pool: queue, seed: seed) {
                switch card.clue {
                case .text(let shown):
                    // A flashcard shows either the name or the symbol, and asks
                    // for the other. It must never show both.
                    let asksForSymbol = shown == card.element.name
                    let asksForName = shown == card.element.symbol
                    #expect(asksForSymbol || asksForName)
                    #expect(!(asksForSymbol && asksForName))
                case .structure, .description:
                    Issue.record("flashcards should only use text clues")
                }
                #expect(!card.question.contains(card.element.name))
            }
        }
    }

    @Test("An empty history yields an empty ranking rather than crashing")
    func emptyHistoryIsSafe() {
        #expect(SmartReviewBuilder.ranked([]).isEmpty)
        #expect(!SmartReviewBuilder.isAvailable(snapshots: [:]))
        let queue = SmartReviewBuilder.queue(elements: catalog.elements, snapshots: [:])
        // With no history it falls back to the normal study priority, so a
        // round is still possible once the threshold is met.
        #expect(queue.count == StudyDeckBuilder.defaultPoolSize)
    }

    @Test("Smart Review draws different material from Flashcards")
    func smartReviewDivergesFromFlashcards() {
        #expect(StudyMode.smartReview.seedSalt != StudyMode.flashcards.seedSalt)
        var snapshots: [Int: ElementProgressSnapshot] = [:]
        // A learner who is weak on the heavy end of the table.
        for atomicNumber in 90...110 {
            snapshots[atomicNumber] = snapshot(atomicNumber, correct: 0, incorrect: 3)
        }
        let smart = SmartReviewBuilder.queue(elements: catalog.elements, snapshots: snapshots)
        let ordinary = MasteryEngine.studyPriority(catalog.elements) {
            snapshots[$0]?.mastery ?? .notStarted
        }
        #expect(smart.prefix(5).map(\.atomicNumber) != ordinary.prefix(5).map(\.atomicNumber),
                "Smart Review should lead with the missed elements, not the unseen ones")
    }
}

@Suite("Study greeting")
struct StudyGreetingTests {
    @Test("The salutation matches the time of day")
    func salutationBoundaries() {
        #expect(StudyGreeting.salutation(hour: 0) == "Good morning")
        #expect(StudyGreeting.salutation(hour: 11) == "Good morning")
        #expect(StudyGreeting.salutation(hour: 12) == "Good afternoon")
        #expect(StudyGreeting.salutation(hour: 17) == "Good afternoon")
        #expect(StudyGreeting.salutation(hour: 18) == "Good evening")
        #expect(StudyGreeting.salutation(hour: 23) == "Good evening")
    }

    @Test("A new learner is not congratulated for nothing")
    func encouragementIsHonest() {
        #expect(StudyGreeting.encouragement(masteredCount: 0, streak: 0, hasStudied: false)
                == "Start exploring.")
        #expect(StudyGreeting.encouragement(masteredCount: 0, streak: 0, hasStudied: true)
                == "Keep exploring.")
        #expect(StudyGreeting.encouragement(masteredCount: 4, streak: 3, hasStudied: true)
                == "Keep the streak going.")
    }
}

/// Spaced review: when something is worth seeing again, derived entirely from
/// the mastery data the app already keeps.
@Suite("Review scheduling")
struct ReviewScheduleTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(
        _ number: Int, mastery: MasteryLevel, correct: Int, incorrect: Int, daysAgo: Double
    ) -> ElementProgressSnapshot {
        ElementProgressSnapshot(
            atomicNumber: number,
            isFavorite: false,
            mastery: mastery,
            correctCount: correct,
            incorrectCount: incorrect,
            lastReviewed: now.addingTimeInterval(-daysAgo * .day)
        )
    }

    @Test("The interval grows with familiarity")
    func intervalsGrow() {
        let learning = ReviewSchedule.interval(mastery: .learning, correct: 1, incorrect: 1)
        let familiar = ReviewSchedule.interval(mastery: .familiar, correct: 1, incorrect: 1)
        let mastered = ReviewSchedule.interval(mastery: .mastered, correct: 1, incorrect: 1)
        #expect(learning < familiar)
        #expect(familiar < mastered)
        #expect(ReviewSchedule.baseInterval(for: .mastered) == 21 * .day)
    }

    @Test("A good record stretches the interval and a poor one compresses it")
    func accuracyAdjustsTheInterval() {
        let perfect = ReviewSchedule.interval(mastery: .familiar, correct: 10, incorrect: 0)
        let even = ReviewSchedule.interval(mastery: .familiar, correct: 5, incorrect: 5)
        let poor = ReviewSchedule.interval(mastery: .familiar, correct: 1, incorrect: 9)
        #expect(perfect > even)
        #expect(even > poor)
        // And never outside the bounds, whatever the record.
        for correct in [0, 1, 50] {
            for incorrect in [0, 1, 50] {
                let span = ReviewSchedule.interval(mastery: .mastered, correct: correct, incorrect: incorrect)
                #expect(span >= ReviewSchedule.shortestInterval)
                #expect(span <= ReviewSchedule.longestInterval)
            }
        }
    }

    @Test("Something never answered is not on a schedule at all")
    func neverAnsweredIsNotDue() {
        #expect(ReviewSchedule.due(lastReviewed: nil, mastery: .notStarted,
                                   correct: 0, incorrect: 0) == nil)
        #expect(ReviewSchedule.due(lastReviewed: now, mastery: .notStarted,
                                   correct: 0, incorrect: 0) == nil)
        #expect(!ReviewSchedule.isDue(lastReviewed: nil, mastery: .learning,
                                      correct: 3, incorrect: 0, now: now))
    }

    @Test("Due means due")
    func dueness() {
        // Learning, even record: about a day. Two days later it is due.
        #expect(ReviewSchedule.isDue(lastReviewed: now.addingTimeInterval(-2 * .day),
                                     mastery: .learning, correct: 1, incorrect: 1, now: now))
        // Mastered with a perfect record: weeks away.
        #expect(!ReviewSchedule.isDue(lastReviewed: now.addingTimeInterval(-2 * .day),
                                      mastery: .mastered, correct: 10, incorrect: 0, now: now))
        #expect(ReviewSchedule.overdueFactor(lastReviewed: now.addingTimeInterval(-2 * .day),
                                             mastery: .mastered, correct: 10, incorrect: 0,
                                             now: now) == 0)
    }

    @Test("Overdue is measured against the item's own interval")
    func overdueIsRelative() {
        // A mastered element a week late is less overdue, relatively, than a
        // learning one a day late — which is the point of the measure.
        let masteredLate = ReviewSchedule.overdueFactor(
            lastReviewed: now.addingTimeInterval(-40 * .day),
            mastery: .mastered, correct: 10, incorrect: 0, now: now
        )
        let learningLate = ReviewSchedule.overdueFactor(
            lastReviewed: now.addingTimeInterval(-10 * .day),
            mastery: .learning, correct: 1, incorrect: 3, now: now
        )
        #expect(masteredLate > 1)
        #expect(learningLate > masteredLate)
    }

    @Test("Smart Review puts an overdue element ahead of a merely weak one")
    func overdueOutranksWeak() {
        // Missed often but seen an hour ago, against missed less but a month
        // overdue. The overdue one comes first.
        let seenJustNow = snapshot(8, mastery: .learning, correct: 1, incorrect: 5, daysAgo: 0.04)
        let longOverdue = snapshot(26, mastery: .familiar, correct: 4, incorrect: 1, daysAgo: 40)
        let ordered = SmartReviewBuilder.ranked([seenJustNow, longOverdue], now: now)
        #expect(ordered.first?.atomicNumber == 26,
                "an element a month overdue should outrank one answered a moment ago")
    }

    @Test("What is due can be listed, worst first")
    func dueList() {
        let snapshots: [Int: ElementProgressSnapshot] = [
            1: snapshot(1, mastery: .learning, correct: 0, incorrect: 4, daysAgo: 30),
            2: snapshot(2, mastery: .mastered, correct: 10, incorrect: 0, daysAgo: 1),
            8: snapshot(8, mastery: .familiar, correct: 3, incorrect: 1, daysAgo: 20),
        ]
        let due = ReviewSchedule.dueElements(snapshots, now: now)
        #expect(due.map(\.atomicNumber).contains(1))
        #expect(due.map(\.atomicNumber).contains(8))
        #expect(!due.map(\.atomicNumber).contains(2), "a mastered element seen yesterday is not due")
        #expect(due.first?.atomicNumber == 1, "the worst should be first")
    }
}
