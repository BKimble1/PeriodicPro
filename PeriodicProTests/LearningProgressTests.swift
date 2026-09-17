import Foundation
import Testing
@testable import PeriodicPro

/// The rank exists to describe one person's progress. The weights exist to
/// make one specific thing impossible.
@Suite("Learning rank")
struct LearningRankTests {
    private let elementCount = 118

    private func snapshots(
        mastered: Int = 0, familiar: Int = 0, learning: Int = 0, from start: Int = 1
    ) -> [Int: ElementProgressSnapshot] {
        var found: [Int: ElementProgressSnapshot] = [:]
        var number = start
        func add(_ count: Int, _ level: MasteryLevel) {
            for _ in 0..<count {
                found[number] = ElementProgressSnapshot(
                    atomicNumber: number, mastery: level, correctCount: 3, incorrectCount: 0
                )
                number += 1
            }
        }
        add(mastered, .mastered)
        add(familiar, .familiar)
        add(learning, .learning)
        return found
    }

    private func standing(
        elements: [Int: ElementProgressSnapshot] = [:],
        compounds: [String: CompoundProgressSnapshot] = [:],
        hardCorrect: Int = 0, hardAnswered: Int = 0,
        studyDays: Int = 0, path: Double = 0
    ) -> RankStanding {
        LearningRankCalculator.standing(
            elements: elements, elementCount: elementCount, compounds: compounds,
            hardQuestionsCorrect: hardCorrect, hardQuestionsAnswered: hardAnswered,
            studyDaysInLastMonth: studyDays, pathCompletion: path
        )
    }

    @Test("A new learner starts at the first rank")
    func startsAtTheBeginning() {
        let start = standing()
        #expect(start.rank == .explorer)
        #expect(start.score == 0)
        #expect(start.progressToNext == 0)
    }

    @Test("Answering one element ten thousand times reaches nothing")
    func drillingOneElementGoesNowhere() {
        // The whole point of weighting for breadth. Hydrogen, mastered, with
        // ten thousand answers behind it.
        let hydrogen: [Int: ElementProgressSnapshot] = [
            1: ElementProgressSnapshot(
                atomicNumber: 1, mastery: .mastered, correctCount: 10_000, incorrectCount: 0
            ),
        ]
        let obsessive = standing(elements: hydrogen, studyDays: 30)
        #expect(obsessive.rank == .explorer,
                "one element and perfect attendance is not a rank; it is one element")
        #expect(obsessive.elementBreadth < 0.01)

        // And a learner who has met sixty elements properly is far ahead of
        // them, on a fraction of the answers.
        let broad = standing(elements: snapshots(mastered: 60))
        #expect(broad.elementBreadth > obsessive.elementBreadth * 50)
        #expect(broad.rank > obsessive.rank)
    }

    @Test("Breadth is coverage, and it saturates at the target")
    func breadthIsCoverage() {
        #expect(LearningRankCalculator.breadth(levels: [], target: 118) == 0)
        #expect(LearningRankCalculator.breadth(
            levels: Array(repeating: .mastered, count: 118), target: 118) == 1)
        // Past the target it stops, rather than running away.
        #expect(LearningRankCalculator.breadth(
            levels: Array(repeating: .mastered, count: 400), target: 118) == 1)
        // Partial familiarity is partial credit, in order.
        #expect(LearningRankCalculator.credit(for: .notStarted) == 0)
        #expect(LearningRankCalculator.credit(for: .learning) < LearningRankCalculator.credit(for: .familiar))
        #expect(LearningRankCalculator.credit(for: .familiar) < LearningRankCalculator.credit(for: .mastered))
        #expect(LearningRankCalculator.credit(for: .mastered) == 1)
    }

    @Test("A lucky first hard question is not a fifth of the score")
    func hardQuestionsAreDiscountedUntilTheyMeanSomething() {
        let lucky = LearningRankCalculator.questionDepth(correct: 1, answered: 1)
        let earned = LearningRankCalculator.questionDepth(correct: 40, answered: 40)
        #expect(lucky < 0.05, "one correct answer is not a hundred percent of anything")
        #expect(earned == 1)
        #expect(LearningRankCalculator.questionDepth(correct: 0, answered: 0) == 0)
        #expect(LearningRankCalculator.questionDepth(correct: 20, answered: 40) < earned)
    }

    @Test("The top rank needs the whole table, the compounds and the chemistry")
    func theTopRankIsEarnedAcrossTheBoard() {
        // Everything mastered but nothing else: still not the top.
        let elementsOnly = standing(elements: snapshots(mastered: 118))
        #expect(elementsOnly.elementBreadth == 1)
        #expect(elementsOnly.rank < .periodicMaster,
                "the table alone is forty percent of the score, not all of it")

        var compounds: [String: CompoundProgressSnapshot] = [:]
        for index in 0..<40 {
            compounds["c\(index)"] = CompoundProgressSnapshot(
                compoundID: "c\(index)", mastery: .mastered, correctCount: 3
            )
        }
        let complete = standing(
            elements: snapshots(mastered: 118), compounds: compounds,
            hardCorrect: 60, hardAnswered: 60, studyDays: 20, path: 1
        )
        #expect(complete.rank == .periodicMaster)
        #expect(complete.score >= LearningRank.periodicMaster.threshold)
        #expect(complete.progressToNext == 1)
        #expect(complete.rank.next == nil)
    }

    @Test("Compounds count, and cannot overpower the 118-element goal")
    func compoundsContributeWithoutTakingOver() {
        var compounds: [String: CompoundProgressSnapshot] = [:]
        for index in 0..<200 {
            compounds["c\(index)"] = CompoundProgressSnapshot(
                compoundID: "c\(index)", mastery: .mastered, correctCount: 3
            )
        }
        let compoundsOnly = standing(compounds: compounds)
        #expect(compoundsOnly.compoundBreadth == 1, "the compound term saturates")
        #expect(compoundsOnly.score <= 0.21,
                "compounds are a fifth of the score however many there are")
        #expect(compoundsOnly.rank < .bondBuilder)
    }

    @Test("The rank does not fall because two days were missed")
    func missingDaysDoesNotDemote() {
        let elements = snapshots(mastered: 70)
        let studying = standing(elements: elements, studyDays: 20, path: 0.5)
        let skippedTwoDays = standing(elements: elements, studyDays: 18, path: 0.5)
        // The consistency target is twelve days in thirty, so a couple of
        // missed days is not even a different number, let alone a demotion.
        #expect(skippedTwoDays.score == studying.score)
        #expect(skippedTwoDays.rank == studying.rank,
                "what was learned does not un-happen; only what is due changes")

        // And a long absence can only cost what consistency is worth, which
        // is a tenth — the other ninety percent is what they learned.
        let awayForAMonth = standing(elements: elements, studyDays: 0, path: 0.5)
        #expect(studying.score - awayForAMonth.score <= 0.1 + 1e-9)
        #expect(awayForAMonth.elementBreadth == studying.elementBreadth)
    }

    @Test("Thresholds are ordered and the ranks are distinct")
    func thresholdsAreWellFormed() {
        let ranks = LearningRank.allCases
        #expect(ranks.count == 8)
        #expect(Set(ranks.map(\.title)).count == ranks.count)
        for (lower, upper) in zip(ranks, ranks.dropFirst()) {
            #expect(lower.threshold < upper.threshold, "\(lower) and \(upper) overlap")
        }
        #expect(LearningRankCalculator.rank(for: 0) == .explorer)
        #expect(LearningRankCalculator.rank(for: 1) == .periodicMaster)
        #expect(LearningRankCalculator.rank(for: -5) == .explorer)
        // And nothing claims to be a qualification.
        for rank in ranks {
            for word in ["certified", "licensed", "degree", "PhD", "professor", "accredited"] {
                #expect(!rank.title.lowercased().contains(word.lowercased()))
                #expect(!rank.summary.lowercased().contains(word.lowercased()))
            }
        }
    }
}

/// The path recommends an order. It never locks anything.
@Suite("Learning path")
struct LearningPathTests {
    private let catalog = TestCatalog.shared

    private func steps(
        elements: [Int: ElementProgressSnapshot] = [:],
        compounds: [String: CompoundProgressSnapshot] = [:],
        advanced: Int = 0
    ) -> [LearningPathStep] {
        LearningPathBuilder.steps(
            catalog: catalog, elements: elements, compounds: compounds, advancedAnswered: advanced
        )
    }

    @Test("Every stage measures itself, and a new learner is at the first")
    func newLearner() {
        let path = steps()
        #expect(path.count == LearningPathStage.allCases.count)
        // Bound rather than written inside #expect: the macro rewrites a bare
        // call so it can describe the receiver on failure, and that rewrite
        // could not be type-checked here.
        let allUnstarted = path.allSatisfy { $0.progress == 0 }
        #expect(allUnstarted)
        #expect(path.first?.isCurrent == true)
        let oneCurrent = path.dropFirst().allSatisfy { !$0.isCurrent }
        #expect(oneCurrent, "only one stage is next")
        #expect(LearningPathBuilder.completion(path) == 0)
    }

    @Test("Mastering the first twenty finishes Foundations and moves the marker on")
    func foundationsCompletes() {
        var elements: [Int: ElementProgressSnapshot] = [:]
        for number in 1...20 {
            elements[number] = ElementProgressSnapshot(
                atomicNumber: number, mastery: .mastered, correctCount: 3
            )
        }
        let path = steps(elements: elements)
        let foundations = path.first { $0.stage == .foundations }
        #expect(foundations?.isComplete == true)
        #expect(foundations?.isCurrent == false)
        #expect(path.first { $0.isCurrent }?.stage != .foundations)
        #expect(foundations?.detail == "20 of 20 mastered")
    }

    @Test("Compounds and Advanced measure what they are about")
    func nonElementStages() {
        var compounds: [String: CompoundProgressSnapshot] = [:]
        for index in 0..<LearningPathBuilder.compoundTarget {
            compounds["c\(index)"] = CompoundProgressSnapshot(
                compoundID: "c\(index)", mastery: .familiar, correctCount: 2
            )
        }
        let path = steps(compounds: compounds, advanced: LearningPathBuilder.advancedQuestionTarget)
        #expect(path.first { $0.stage == .compounds }?.isComplete == true)
        #expect(path.first { $0.stage == .advanced }?.isComplete == true)
        // And they stop at their target rather than running past it.
        let more = LearningPathBuilder.steps(
            catalog: catalog, elements: [:], compounds: compounds, advancedAnswered: 10_000
        )
        #expect(more.first { $0.stage == .advanced }?.progress == 1)
    }

    @Test("Completion is the mean of the stages, and feeds the rank")
    func completionIsAveraged() {
        var elements: [Int: ElementProgressSnapshot] = [:]
        for number in 1...20 {
            elements[number] = ElementProgressSnapshot(
                atomicNumber: number, mastery: .mastered, correctCount: 3
            )
        }
        let completion = LearningPathBuilder.completion(steps(elements: elements))
        #expect(completion > 0)
        #expect(completion < 1)
    }

    @Test("Every stage knows what to start, and none of them is Pro-only")
    func stagesAreReachable() {
        for stage in LearningPathStage.allCases {
            #expect(!stage.title.isEmpty)
            #expect(!stage.subtitle.isEmpty)
            // Smart Review is the one Pro mode, and it is where the path
            // ends rather than where it blocks.
            if stage != .mastery { #expect(!stage.recommendedMode.requiresPro) }
        }
    }
}

/// Five questions, the same five all day.
@MainActor
@Suite("Daily Challenge")
struct DailyChallengeTests {
    private let catalog = TestCatalog.shared
    private let day = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("The same day deals the same five, and a different day does not")
    func deterministicPerDay() {
        let today = DailyChallenge.questions(
            catalog: catalog, snapshots: [:], compounds: TestCompounds.catalog.compounds, date: day
        )
        let againToday = DailyChallenge.questions(
            catalog: catalog, snapshots: [:], compounds: TestCompounds.catalog.compounds, date: day
        )
        #expect(today.count == DailyChallenge.questionCount)
        #expect(today.map(\.prompt) == againToday.map(\.prompt))

        let tomorrow = DailyChallenge.questions(
            catalog: catalog, snapshots: [:], compounds: TestCompounds.catalog.compounds,
            date: day.addingTimeInterval(.day)
        )
        #expect(tomorrow.map(\.prompt) != today.map(\.prompt))
    }

    @Test("It mixes the weak with something already known")
    func theMix() {
        var snapshots: [Int: ElementProgressSnapshot] = [:]
        // Three elements answered badly, one mastered.
        // Dated against the real clock, because the review schedule these go
        // through reads the real clock: a fixture ten days "before" a date in
        // 2027 is still in the future and is not overdue at all.
        for number in [3, 11, 19] {
            snapshots[number] = ElementProgressSnapshot(
                atomicNumber: number, mastery: .learning, correctCount: 0, incorrectCount: 4,
                lastReviewed: Date().addingTimeInterval(-10 * .day)
            )
        }
        snapshots[8] = ElementProgressSnapshot(
            atomicNumber: 8, mastery: .mastered, correctCount: 6,
            lastReviewed: Date().addingTimeInterval(-.day)
        )
        let subjects = DailyChallenge.subjects(
            catalog: catalog, snapshots: snapshots, seed: DailyChallenge.seed(for: day)
        )
        let numbers = Set(subjects.map(\.atomicNumber))
        #expect(subjects.count == DailyChallenge.questionCount)
        #expect(Set(subjects.map(\.atomicNumber)).count == subjects.count, "never the same element twice")
        #expect(numbers.contains(3) || numbers.contains(11) || numbers.contains(19),
                "the weak spots should be in it")
        #expect(numbers.contains(8), "and something already known, because recall decays")
    }

    @Test("A learner with no history still gets five")
    func worksFromNothing() {
        let subjects = DailyChallenge.subjects(
            catalog: catalog, snapshots: [:], seed: DailyChallenge.seed(for: day)
        )
        #expect(subjects.count == DailyChallenge.questionCount)
    }

    @Test("Completion is recorded per day and does not carry over")
    func completionIsPerDay() {
        let defaults = UserDefaults(suiteName: "DailyChallengeTests-\(UUID().uuidString)")
        guard let defaults else {
            Issue.record("could not make a test defaults suite")
            return
        }
        defer { DailyChallengeRecord.clear(defaults: defaults) }

        #expect(!DailyChallengeRecord.isComplete(on: day, defaults: defaults))
        DailyChallengeRecord.markComplete(on: day, defaults: defaults)
        #expect(DailyChallengeRecord.isComplete(on: day, defaults: defaults))
        #expect(!DailyChallengeRecord.isComplete(on: day.addingTimeInterval(.day), defaults: defaults),
                "yesterday's challenge does not count as today's")
    }
}
