import Foundation
import Testing
@testable import PeriodicPro

/// The Home Screen widget's contract with the app.
///
/// Every test here runs against a temporary directory rather than the real
/// App Group, so the suite passes on a simulator that was never provisioned
/// for one — which is what CI runs on.
@Suite("Home Screen widget")
@MainActor
struct WidgetBridgeTests {
    // MARK: - Scaffolding

    /// A log, a snapshot store, a state store and a ledger, all pointing at a
    /// directory that is deleted when the test ends.
    private struct Sandbox {
        let directory: URL
        let log: WidgetEventLog
        let snapshots: WidgetSnapshotStore
        let state: WidgetStateStore
        let defaults: UserDefaults
        private let suiteName: String

        init() {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("elemora-widget-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            log = WidgetEventLog(url: directory.appendingPathComponent(WidgetEventLog.fileName))
            snapshots = WidgetSnapshotStore(
                url: directory.appendingPathComponent(WidgetProgressSnapshot.fileName)
            )
            state = WidgetStateStore(
                url: directory.appendingPathComponent(WidgetInteractionState.fileName)
            )
            suiteName = "elemora.widget.tests.\(UUID().uuidString)"
            defaults = UserDefaults(suiteName: suiteName) ?? .standard
        }

        var ledger: WidgetMergeLedger { WidgetMergeLedger(defaults: defaults) }

        func tearDown() {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func event(
        id: UUID = UUID(),
        atomicNumber: Int = 26,
        correct: Bool = true,
        at date: Date = Date(),
        isAdvanced: Bool = false
    ) -> WidgetAnswerEvent {
        WidgetAnswerEvent(
            id: id,
            questionID: "q-\(atomicNumber)",
            subjectKey: "element-\(atomicNumber)",
            isCorrect: correct,
            answeredAt: date,
            isAdvanced: isAdvanced
        )
    }

    // MARK: - Idempotence

    @Test("An intent that iOS runs twice counts once")
    func duplicateEventCountsOnce() {
        let sandbox = Sandbox()
        defer { sandbox.tearDown() }
        let progress = makeTestStore()
        let duplicated = event()

        // The same event, appended twice, exactly as a retried intent would.
        sandbox.log.append(duplicated)
        sandbox.log.append(duplicated)

        let outcome = WidgetBridge.drain(
            log: sandbox.log, into: progress, ledger: sandbox.ledger
        )
        #expect(outcome.applied == 1)
        #expect(outcome.alreadyMerged == 1)
        #expect(progress.snapshot(for: 26).correctCount == 1)
    }

    @Test("Merging the same log a second time changes nothing")
    func secondMergeIsANoOp() {
        let sandbox = Sandbox()
        defer { sandbox.tearDown() }
        let progress = makeTestStore()
        let events = [event(atomicNumber: 26), event(atomicNumber: 8)]

        let first = WidgetBridge.merge(events, into: progress, ledger: sandbox.ledger)
        #expect(first.applied == 2)

        // The crash case: the events were applied and saved, but the log was
        // never cleared, so the next launch reads them again.
        let second = WidgetBridge.merge(events, into: progress, ledger: sandbox.ledger)
        #expect(second.applied == 0)
        #expect(second.alreadyMerged == 2)
        #expect(progress.totalAnswered == 2)
    }

    @Test("A drained log is empty, and draining an empty log does nothing")
    func drainClearsTheLog() {
        let sandbox = Sandbox()
        defer { sandbox.tearDown() }
        let progress = makeTestStore()
        sandbox.log.append(event())

        #expect(WidgetBridge.drain(log: sandbox.log, into: progress, ledger: sandbox.ledger)
            .applied == 1)
        #expect(sandbox.log.read().isEmpty)
        #expect(WidgetBridge.drain(log: sandbox.log, into: progress, ledger: sandbox.ledger)
            == WidgetBridge.MergeOutcome())
    }

    @Test("The ledger is bounded and stays correct at its boundary")
    func ledgerIsBounded() {
        let sandbox = Sandbox()
        defer { sandbox.tearDown() }
        var ledger = sandbox.ledger
        let identifiers = (0..<(WidgetMergeLedger.capacity + 10)).map { _ in UUID() }
        // `#expect` captures its subexpressions in a closure, so a mutating
        // call has to happen outside it and be asserted on afterwards.
        for id in identifiers {
            let wasNew = ledger.markMerged(id)
            #expect(wasNew)
        }

        #expect(ledger.count == WidgetMergeLedger.capacity)
        // The newest are kept; the oldest ten have aged out, which is the
        // trade the bound buys.
        #expect(ledger.contains(identifiers.last!))
        #expect(!ledger.contains(identifiers.first!))
        let repeated = ledger.markMerged(identifiers.last!)
        #expect(!repeated)
    }

    // MARK: - What a merge does to progress

    @Test("An answer from the widget moves mastery exactly as one from a round")
    func masteryMovesTheSameWay() {
        let sandbox = Sandbox()
        defer { sandbox.tearDown() }
        let viaWidget = makeTestStore()
        let viaSession = makeTestStore()
        let now = Date()

        WidgetBridge.merge(
            [event(atomicNumber: 26, correct: true, at: now)],
            into: viaWidget,
            ledger: sandbox.ledger
        )
        viaSession.recordAnswer(atomicNumber: 26, correct: true, date: now)

        #expect(viaWidget.snapshot(for: 26).mastery == viaSession.snapshot(for: 26).mastery)
        #expect(viaWidget.snapshot(for: 26).correctCount == viaSession.snapshot(for: 26).correctCount)
    }

    @Test("A wrong answer is recorded as wrong")
    func wrongAnswersCount() {
        let sandbox = Sandbox()
        defer { sandbox.tearDown() }
        let progress = makeTestStore()
        WidgetBridge.merge(
            [event(atomicNumber: 79, correct: false)], into: progress, ledger: sandbox.ledger
        )
        #expect(progress.snapshot(for: 79).incorrectCount == 1)
        #expect(progress.snapshot(for: 79).correctCount == 0)
    }

    @Test("An answer counts on the day it was given, not the day it was merged")
    func streakUsesTheAnswersOwnDate() {
        let sandbox = Sandbox()
        defer { sandbox.tearDown() }
        let progress = makeTestStore()
        let yesterday = Date().addingTimeInterval(-.day)

        WidgetBridge.merge(
            [event(atomicNumber: 26, at: yesterday)], into: progress, ledger: sandbox.ledger
        )

        // The merge happens today; the study day belongs to yesterday, which
        // is when the learner actually answered.
        #expect(progress.hasStudied(on: yesterday))
        #expect(!progress.hasStudied(on: Date()))
    }

    @Test("An advanced answer counts against its subject and against the hard material")
    func advancedAnswersCountTwice() {
        let sandbox = Sandbox()
        defer { sandbox.tearDown() }
        let progress = makeTestStore()

        WidgetBridge.merge(
            [event(atomicNumber: 26, correct: true, isAdvanced: true)],
            into: progress,
            ledger: sandbox.ledger
        )
        #expect(progress.snapshot(for: 26).correctCount == 1)
        #expect(progress.advancedAnswered == 1)
        #expect(progress.advancedCorrect == 1)
    }

    @Test("An ordinary answer does not count as advanced")
    func ordinaryAnswersAreNotAdvanced() {
        let sandbox = Sandbox()
        defer { sandbox.tearDown() }
        let progress = makeTestStore()
        WidgetBridge.merge([event()], into: progress, ledger: sandbox.ledger)
        #expect(progress.advancedAnswered == 0)
    }

    @Test("A compound answer is recorded against the compound, not an element")
    func compoundAnswersRoute() {
        let sandbox = Sandbox()
        defer { sandbox.tearDown() }
        let progress = makeTestStore()
        guard let compound = TestCompounds.catalog.compounds.first else {
            Issue.record("The bundled compound catalog is empty")
            return
        }
        let answer = WidgetAnswerEvent(
            questionID: "q-compound",
            subjectKey: compound.id,
            isCorrect: true
        )
        #expect(answer.atomicNumber == nil)

        WidgetBridge.merge([answer], into: progress, ledger: sandbox.ledger)
        #expect(progress.compoundSnapshot(for: compound.id).correctCount == 1)
        #expect(progress.snapshots.isEmpty)
    }

    @Test("Merging never disturbs progress that was already there")
    func existingProgressSurvives() {
        let sandbox = Sandbox()
        defer { sandbox.tearDown() }
        let progress = makeTestStore()

        // Progress from before the widget existed.
        for _ in 0..<4 { progress.recordAnswer(atomicNumber: 1, correct: true) }
        progress.toggleFavorite(2)
        let before = progress.snapshot(for: 1)
        let favorites = progress.favoriteAtomicNumbers

        WidgetBridge.merge([event(atomicNumber: 26)], into: progress, ledger: sandbox.ledger)

        #expect(progress.snapshot(for: 1) == before)
        #expect(progress.favoriteAtomicNumbers == favorites)
        #expect(progress.snapshot(for: 26).correctCount == 1)
    }

    // MARK: - The log itself

    @Test("The log is append-only and reads back in order")
    func logAppends() {
        let sandbox = Sandbox()
        defer { sandbox.tearDown() }
        let first = event(atomicNumber: 1)
        let second = event(atomicNumber: 2)
        sandbox.log.append(first)
        sandbox.log.append(second)

        let read = sandbox.log.read()
        #expect(read.count == 2)
        #expect(read.first?.id == first.id)
        #expect(read.last?.id == second.id)
        #expect(read.first?.answeredAt.timeIntervalSince1970
            == first.answeredAt.timeIntervalSince1970)
    }

    @Test("A corrupted line is skipped rather than stopping the merge")
    func corruptedLinesAreSkipped() throws {
        let sandbox = Sandbox()
        defer { sandbox.tearDown() }
        let good = event(atomicNumber: 26)
        sandbox.log.append(good)
        // A truncated write — the case a crash mid-append would leave behind.
        let url = try #require(sandbox.log.url)
        let text = try String(contentsOf: url, encoding: .utf8) + "{\"questionID\":\"tru\n"
        try text.write(to: url, atomically: true, encoding: .utf8)

        let read = sandbox.log.read()
        #expect(read.count == 1)
        #expect(read.first?.id == good.id)
    }

    @Test("With no shared container nothing is written and nothing crashes")
    func noAppGroupIsSurvivable() {
        let log = WidgetEventLog(url: nil)
        let snapshots = WidgetSnapshotStore(url: nil)
        let state = WidgetStateStore(url: nil)

        #expect(!log.isAvailable)
        log.append(event())
        log.clear()
        #expect(log.read().isEmpty)

        snapshots.write(WidgetProgressSnapshot(masteredElements: 9))
        #expect(snapshots.read() == nil)

        state.write(WidgetInteractionState(answeredQuestionIDs: ["a"]))
        #expect(state.read() == WidgetInteractionState())
    }

    @Test("A snapshot survives a round trip through the file")
    func snapshotRoundTrips() {
        let sandbox = Sandbox()
        defer { sandbox.tearDown() }
        let progress = makeTestStore()
        let snapshot = WidgetBridge.snapshot(
            progress: progress,
            catalog: TestCatalog.shared,
            compounds: TestCompounds.catalog.compounds
        )
        sandbox.snapshots.write(snapshot)
        #expect(sandbox.snapshots.read() == snapshot)
    }
}

/// What the widget puts on screen, given a snapshot and its own state.
@Suite("Widget content")
@MainActor
struct WidgetContentTests {
    private func snapshot(progress: ProgressStore, date: Date = Date()) -> WidgetProgressSnapshot {
        WidgetBridge.snapshot(
            progress: progress,
            catalog: TestCatalog.shared,
            compounds: TestCompounds.catalog.compounds,
            date: date
        )
    }

    @Test("The snapshot reports the table, the streak and the rank")
    func snapshotReportsProgress() {
        let progress = makeTestStore()
        let built = snapshot(progress: progress)
        #expect(built.totalElements == TestCatalog.shared.count)
        #expect(built.masteredElements == 0)
        #expect(built.rankTitle == LearningRank.explorer.title)
        #expect(!built.questions.isEmpty)
    }

    @Test("Every question is answerable: four options and a correct one among them")
    func questionsAreWellFormed() {
        let progress = makeTestStore()
        for question in snapshot(progress: progress).questions {
            #expect(question.options.count == 4)
            #expect(question.options.indices.contains(question.correctIndex))
            #expect(Set(question.options).count == question.options.count)
            #expect(!question.prompt.isEmpty)
            #expect(question.isCorrect(question.correctIndex))
            #expect(!question.correctAnswer.isEmpty)
            // The subject key is what the merge routes on; a question whose
            // key names nothing would be an answer counted against nobody.
            #expect(question.subjectKey.hasPrefix("element-"))
        }
    }

    @Test("The same day deals the same questions; the next day deals others")
    func questionsAreStableWithinADay() {
        let progress = makeTestStore()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        // Midday and an hour later, in UTC. The snapshot keys its questions
        // by the *current* calendar's day, so two instants an hour either side
        // of noon UTC fall on the same local day in every time zone on Earth,
        // and a runner that is not in UTC cannot turn this into a flake.
        let midday = calendar.date(from: DateComponents(year: 2_026, month: 5, day: 12, hour: 12))!
        let anHourLater = calendar.date(from: DateComponents(year: 2_026, month: 5, day: 12, hour: 13))!
        let tomorrow = calendar.date(from: DateComponents(year: 2_026, month: 5, day: 13, hour: 12))!

        let first = snapshot(progress: progress, date: midday).questions
        let later = snapshot(progress: progress, date: anHourLater).questions
        let next = snapshot(progress: progress, date: tomorrow).questions

        #expect(first.map(\.id) == later.map(\.id))
        #expect(first.map(\.prompt) == later.map(\.prompt))
        #expect(first.map(\.id) != next.map(\.id))
    }

    @Test("The widget works through its questions and then says it is done")
    func stateAdvancesThroughQuestions() {
        let progress = makeTestStore()
        let built = snapshot(progress: progress)
        var state = WidgetInteractionState()

        for expected in built.questions {
            let question = state.nextQuestion(in: built)
            #expect(question?.id == expected.id)
            state.record(questionID: expected.id, choice: expected.correctIndex, isCorrect: true)
            // While a result is on screen, that is what the widget shows.
            #expect(state.revealedQuestion(in: built)?.id == expected.id)
            state.dismissReveal()
        }
        #expect(state.nextQuestion(in: built) == nil)
        #expect(state.revealedQuestion(in: built) == nil)
    }

    @Test("Yesterday's answers do not suppress today's questions")
    func aNewDayStartsOver() {
        let progress = makeTestStore()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        // Exactly a day apart, which is a different day in every calendar.
        let today = calendar.date(from: DateComponents(year: 2_026, month: 5, day: 12, hour: 12))!
        let tomorrow = calendar.date(from: DateComponents(year: 2_026, month: 5, day: 13, hour: 12))!

        var state = WidgetInteractionState()
        for question in snapshot(progress: progress, date: today).questions {
            state.record(questionID: question.id, choice: 0, isCorrect: true)
            state.dismissReveal()
        }
        // The identifiers carry their day, so nothing has to expire them.
        #expect(state.nextQuestion(in: snapshot(progress: progress, date: tomorrow)) != nil)
    }

    @Test("The answered history is bounded")
    func historyIsBounded() {
        var state = WidgetInteractionState()
        for index in 0..<(WidgetInteractionState.historyLimit + 5) {
            state.record(questionID: "q-\(index)", choice: 0, isCorrect: true)
        }
        #expect(state.answeredQuestionIDs.count == WidgetInteractionState.historyLimit)
        #expect(state.hasAnswered("q-\(WidgetInteractionState.historyLimit + 4)"))
    }

    @Test("An empty catalog produces no questions rather than a broken one")
    func emptyCatalogIsHandled() {
        let progress = makeTestStore()
        let built = WidgetBridge.snapshot(
            progress: progress, catalog: ElementCatalog(elements: []), compounds: []
        )
        #expect(built.questions.isEmpty)
        #expect(built.totalElements == 1)
        #expect(WidgetInteractionState().nextQuestion(in: built) == nil)
    }
}
