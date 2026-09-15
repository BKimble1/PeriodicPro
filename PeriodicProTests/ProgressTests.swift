import Foundation
import Testing
@testable import PeriodicPro

@Suite("Mastery rules")
struct MasteryEngineTests {
    @Test("Three correct answers take an element from untouched to mastered")
    func correctAnswersAdvance() {
        var level = MasteryLevel.notStarted
        level = MasteryEngine.next(from: level, correct: true)
        #expect(level == .learning)
        level = MasteryEngine.next(from: level, correct: true)
        #expect(level == .familiar)
        level = MasteryEngine.next(from: level, correct: true)
        #expect(level == .mastered)
    }

    @Test("Mastery is capped and never overflows")
    func masteryIsCapped() {
        var level = MasteryLevel.mastered
        for _ in 0..<5 {
            level = MasteryEngine.next(from: level, correct: true)
        }
        #expect(level == .mastered)
    }

    @Test("A wrong answer costs one step but never drops below Learning")
    func incorrectAnswersStepBack() {
        #expect(MasteryEngine.next(from: .mastered, correct: false) == .familiar)
        #expect(MasteryEngine.next(from: .familiar, correct: false) == .learning)
        #expect(MasteryEngine.next(from: .learning, correct: false) == .learning)
        #expect(MasteryEngine.next(from: .notStarted, correct: false) == .learning)
    }

    @Test("Levels are ordered and report a sensible fraction")
    func levelOrdering() {
        #expect(MasteryLevel.notStarted < MasteryLevel.learning)
        #expect(MasteryLevel.familiar < MasteryLevel.mastered)
        #expect(MasteryLevel.notStarted.fraction == 0)
        #expect(MasteryLevel.mastered.fraction == 1)
    }

    @Test("The study queue puts the least familiar elements first")
    func studyPriorityOrdersByFamiliarity() {
        let catalog = TestCatalog.shared
        let elements = Array(catalog.elements.prefix(6))
        let levels: [Int: MasteryLevel] = [1: .mastered, 2: .notStarted, 3: .familiar,
                                           4: .notStarted, 5: .learning, 6: .mastered]
        let ordered = MasteryEngine.studyPriority(elements) { levels[$0] ?? .notStarted }
        #expect(ordered.map(\.atomicNumber) == [2, 4, 5, 3, 1, 6])
    }
}

@Suite("Streaks")
struct StreakCalculatorTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private func day(_ offset: Int, from today: Date) -> String {
        StreakCalculator.dayKey(
            for: calendar.date(byAdding: .day, value: offset, to: today) ?? today,
            calendar: calendar
        )
    }

    private var today: Date { Date(timeIntervalSince1970: 1_767_312_000) }   // 2026-01-02 UTC

    @Test("No activity means no streak")
    func emptyHistory() {
        #expect(StreakCalculator.currentStreak(days: [], today: today, calendar: calendar) == 0)
    }

    @Test("Studying today alone is a one-day streak")
    func singleDay() {
        let days: Set<String> = [day(0, from: today)]
        #expect(StreakCalculator.currentStreak(days: days, today: today, calendar: calendar) == 1)
    }

    @Test("Consecutive days accumulate")
    func consecutiveDays() {
        let days = Set([0, -1, -2, -3].map { day($0, from: today) })
        #expect(StreakCalculator.currentStreak(days: days, today: today, calendar: calendar) == 4)
    }

    @Test("A streak survives until the end of the following day")
    func yesterdayKeepsTheStreakAlive() {
        let days = Set([-1, -2].map { day($0, from: today) })
        #expect(StreakCalculator.currentStreak(days: days, today: today, calendar: calendar) == 2)
    }

    @Test("A two-day gap breaks the streak")
    func gapBreaksStreak() {
        let days = Set([-2, -3, -4].map { day($0, from: today) })
        #expect(StreakCalculator.currentStreak(days: days, today: today, calendar: calendar) == 0)
    }

    @Test("Only the run ending today counts")
    func olderRunsAreIgnored() {
        let days = Set([0, -1, -5, -6, -7].map { day($0, from: today) })
        #expect(StreakCalculator.currentStreak(days: days, today: today, calendar: calendar) == 2)
    }

    @Test("Day keys are sortable and zero-padded")
    func dayKeyFormat() {
        let date = Date(timeIntervalSince1970: 1_767_312_000)
        #expect(StreakCalculator.dayKey(for: date, calendar: calendar) == "2026-01-02")
    }
}

@MainActor
@Suite("Progress store")
struct ProgressStoreTests {
    private let catalog = TestCatalog.shared

    @Test("A fresh store is empty")
    func startsEmpty() {
        let store = makeTestStore()
        #expect(store.masteredCount == 0)
        #expect(store.startedCount == 0)
        #expect(store.totalAnswered == 0)
        #expect(store.favoriteAtomicNumbers.isEmpty)
        #expect(store.recentSearches.isEmpty)
        #expect(store.currentStreak == 0)
        #expect(store.snapshot(for: 8).mastery == .notStarted)
    }

    @Test("Favorites toggle on and off and stay sorted")
    func favoritesToggle() {
        let store = makeTestStore()
        #expect(store.toggleFavorite(8) == true)
        #expect(store.isFavorite(8))
        #expect(store.toggleFavorite(1) == true)
        #expect(store.favoriteAtomicNumbers == [1, 8])

        #expect(store.toggleFavorite(8) == false)
        #expect(!store.isFavorite(8))
        #expect(store.favoriteAtomicNumbers == [1])
    }

    @Test("Answers move an element through the mastery levels")
    func recordingAnswersUpdatesMastery() {
        let store = makeTestStore()
        store.recordAnswer(atomicNumber: 26, correct: true)
        #expect(store.mastery(for: 26) == .learning)
        store.recordAnswer(atomicNumber: 26, correct: true)
        store.recordAnswer(atomicNumber: 26, correct: true)
        #expect(store.mastery(for: 26) == .mastered)
        #expect(store.masteredCount == 1)

        store.recordAnswer(atomicNumber: 26, correct: false)
        #expect(store.mastery(for: 26) == .familiar)
        #expect(store.masteredCount == 0)

        let snapshot = store.snapshot(for: 26)
        #expect(snapshot.correctCount == 3)
        #expect(snapshot.incorrectCount == 1)
        #expect(snapshot.attempts == 4)
        #expect(store.totalAnswered == 4)
        #expect(store.startedCount == 1)
    }

    @Test("Answering records a study day, which drives the streak")
    func answeringStartsAStreak() {
        let store = makeTestStore()
        store.recordAnswer(atomicNumber: 3, correct: true)
        #expect(store.currentStreak == 1)
    }

    @Test("Recently studied lists the newest elements first")
    func recentlyStudiedOrder() {
        let store = makeTestStore()
        let base = Date(timeIntervalSince1970: 1_767_312_000)
        store.recordAnswer(atomicNumber: 1, correct: true, date: base)
        store.recordAnswer(atomicNumber: 2, correct: true, date: base.addingTimeInterval(60))
        store.recordAnswer(atomicNumber: 3, correct: true, date: base.addingTimeInterval(120))
        #expect(store.recentlyStudied(limit: 2) == [3, 2])
    }

    @Test("Per-family mastery counts only that family")
    func categoryMastery() {
        let store = makeTestStore()
        for _ in 0..<3 { store.recordAnswer(atomicNumber: 3, correct: true) }   // Lithium
        #expect(store.masteredCount(in: .alkaliMetal, catalog: catalog) == 1)
        #expect(store.masteredCount(in: .nobleGas, catalog: catalog) == 0)
    }

    @Test("Recent searches deduplicate, stay newest-first and are capped")
    func recentSearches() {
        let store = makeTestStore()
        store.recordSearch("oxygen")
        store.recordSearch("gold")
        #expect(store.recentSearches.first == "gold")
        #expect(store.recentSearches.count == 2)

        store.recordSearch("OXYGEN")
        #expect(store.recentSearches.count == 2, "Case-insensitive duplicates should merge")

        for index in 0..<12 {
            store.recordSearch("term\(index)")
        }
        #expect(store.recentSearches.count <= ProgressStore.recentSearchLimit)

        store.clearRecentSearches()
        #expect(store.recentSearches.isEmpty)
    }

    @Test("Blank and oversized search terms are ignored")
    func searchTermValidation() {
        let store = makeTestStore()
        store.recordSearch("   ")
        store.recordSearch(String(repeating: "x", count: 64))
        #expect(store.recentSearches.isEmpty)
    }

    @Test("Resetting clears familiarity and streaks but keeps favorites")
    func resetProgress() {
        let store = makeTestStore()
        store.toggleFavorite(79)
        store.recordAnswer(atomicNumber: 79, correct: true)
        store.recordAnswer(atomicNumber: 8, correct: true)

        store.resetAllProgress()
        #expect(store.totalAnswered == 0)
        #expect(store.startedCount == 0)
        #expect(store.currentStreak == 0)
        #expect(store.isFavorite(79), "Favorites are a choice, not progress")
        #expect(store.favoriteAtomicNumbers == [79])

        store.reload()
        #expect(store.totalAnswered == 0)
        #expect(store.isFavorite(79))
    }

    @Test("Progress survives a reload from the same container")
    func progressPersistsAcrossReload() {
        let store = makeTestStore()
        store.toggleFavorite(47)
        store.recordAnswer(atomicNumber: 47, correct: true)
        store.reload()
        #expect(store.isFavorite(47))
        #expect(store.mastery(for: 47) == .learning)
    }

    @Test("A healthy store reports no storage problem")
    func healthyStoreHasNoWarnings() {
        let store = makeTestStore()
        #expect(store.writeFailureMessage == nil)
        #expect(store.readFailureMessage == nil)
        #expect(!store.storage.discardedPreviousProgress)
        #expect(!store.storage.losesProgressOnQuit)
    }
}

/// Everything above, again, with no SwiftData container at all — the path the
/// app falls back to rather than crashing when persistence is unavailable.
@MainActor
@Suite("Progress store without persistence")
struct ContainerlessProgressStoreTests {
    private let catalog = TestCatalog.shared

    @Test("Favorites still work in memory")
    func favoritesWork() {
        let store = makeContainerlessStore()
        #expect(store.toggleFavorite(8) == true)
        #expect(store.isFavorite(8))
        #expect(store.favoriteAtomicNumbers == [8])
        #expect(store.toggleFavorite(8) == false)
        #expect(store.favoriteAtomicNumbers.isEmpty)
    }

    @Test("Answers still move mastery and drive the streak")
    func answersWork() {
        let store = makeContainerlessStore()
        for _ in 0..<3 { store.recordAnswer(atomicNumber: 6, correct: true) }
        #expect(store.mastery(for: 6) == .mastered)
        #expect(store.masteredCount == 1)
        #expect(store.totalAnswered == 3)
        #expect(store.currentStreak == 1)
        #expect(store.masteredCount(in: .reactiveNonmetal, catalog: catalog) == 1)
    }

    @Test("Recent searches still deduplicate and stay capped")
    func searchesWork() {
        let store = makeContainerlessStore()
        store.recordSearch("gold")
        store.recordSearch("GOLD")
        #expect(store.recentSearches == ["GOLD"], "The newest spelling wins, without duplicating")

        for index in 0..<12 { store.recordSearch("term\(index)") }
        #expect(store.recentSearches.count == ProgressStore.recentSearchLimit)
        #expect(store.recentSearches.first == "term11")

        store.clearRecentSearches()
        #expect(store.recentSearches.isEmpty)
    }

    @Test("Reset clears progress and keeps favorites")
    func resetWorks() {
        let store = makeContainerlessStore()
        store.toggleFavorite(79)
        store.recordAnswer(atomicNumber: 79, correct: true)
        store.recordAnswer(atomicNumber: 8, correct: true)

        store.resetAllProgress()
        #expect(store.isFavorite(79))
        #expect(store.favoriteAtomicNumbers == [79])
        #expect(store.mastery(for: 79) == .notStarted)
        #expect(store.totalAnswered == 0)
        #expect(store.currentStreak == 0)
        #expect(store.recentlyStudied().isEmpty)
    }

    @Test("It reports that progress will be lost")
    func reportsItsLimitation() {
        let store = makeContainerlessStore()
        #expect(store.storage.losesProgressOnQuit)
        #expect(!store.storage.discardedPreviousProgress)
    }

    @Test("Reloading without a container is a no-op rather than a crash")
    func reloadIsSafe() {
        let store = makeContainerlessStore()
        store.toggleFavorite(3)
        store.reload()
        #expect(store.isFavorite(3), "In-memory state is kept when there is nothing to reload from")
    }
}
