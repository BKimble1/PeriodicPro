import Foundation
import WidgetKit

/// The app's half of the Home Screen widget.
///
/// Two jobs, both of which run on the app side because the app is the only
/// process allowed to write the learner's progress:
///
///   * draining the widget's answer log into `ProgressStore`, exactly once
///     per answer however many times the merge runs, and
///   * publishing the snapshot the widget draws, so the widget never has to
///     open the element catalog or recompute a rank in a 30 MB extension.
///
/// Nothing here fails loudly. An App Group that is unavailable — an
/// unprovisioned simulator, a build signed without the entitlement — means a
/// widget that shows a placeholder, not an app that stops working.
@MainActor
enum WidgetBridge {
    /// How many questions the app leaves ready for the widget.
    ///
    /// More than one so the timeline can move on after an answer without
    /// waiting for the app to run again, and few enough that the snapshot
    /// stays a small file the widget can decode in its memory budget.
    static let questionCount = 8

    /// What a merge did. Returned rather than logged so a test can assert on
    /// it, and so a second merge of the same log is visibly a no-op.
    struct MergeOutcome: Equatable, Sendable {
        var applied: Int = 0
        /// Events already merged by an earlier run, or repeated within this
        /// batch. The number that matters: a retried intent shows up here.
        var alreadyMerged: Int = 0

        var didChangeProgress: Bool { applied > 0 }
    }

    // MARK: - Merging

    /// Applies each event at most once, ever.
    ///
    /// Idempotence has two sources and needs both. Within a batch, the ledger
    /// is updated as each event is applied, so a log line written twice is
    /// applied once. Across runs, the ledger persists, so a crash between
    /// applying the events and clearing the log — which leaves the log full of
    /// events that are already in the store — cannot double-count them on the
    /// next launch.
    @discardableResult
    static func merge(
        _ events: [WidgetAnswerEvent],
        into progress: ProgressStore,
        ledger: WidgetMergeLedger
    ) -> MergeOutcome {
        var outcome = MergeOutcome()
        var ledger = ledger
        for event in events.sorted(by: { $0.answeredAt < $1.answeredAt }) {
            guard ledger.markMerged(event.id) else {
                outcome.alreadyMerged += 1
                continue
            }
            apply(event, to: progress)
            outcome.applied += 1
        }
        ledger.persist()
        return outcome
    }

    /// One event against the store it belongs in.
    ///
    /// The event carries the moment it was answered rather than the moment it
    /// was merged, so a question answered on the Home Screen last night counts
    /// towards last night's streak even though the app was not opened until
    /// this morning.
    private static func apply(_ event: WidgetAnswerEvent, to progress: ProgressStore) {
        if let atomicNumber = event.atomicNumber {
            progress.recordAnswer(
                atomicNumber: atomicNumber, correct: event.isCorrect, date: event.answeredAt
            )
        } else {
            progress.recordCompoundAnswer(
                id: event.subjectKey, correct: event.isCorrect, date: event.answeredAt
            )
        }
        // An advanced answer counts twice, exactly as it does in a session:
        // once against its subject, once against the harder material that the
        // rank's depth term reads.
        if event.isAdvanced {
            progress.recordAdvancedAnswer(correct: event.isCorrect, date: event.answeredAt)
        }
    }

    /// Reads the log, merges it, and clears it.
    ///
    /// The clear happens last and is safe to lose: the ledger has already
    /// recorded every identifier, so re-reading the same log merges nothing.
    @discardableResult
    static func drain(
        log: WidgetEventLog = WidgetEventLog(),
        into progress: ProgressStore,
        ledger: WidgetMergeLedger = WidgetMergeLedger()
    ) -> MergeOutcome {
        let events = log.read()
        guard !events.isEmpty else { return MergeOutcome() }
        let outcome = merge(events, into: progress, ledger: ledger)
        log.clear()
        return outcome
    }

    // MARK: - Publishing

    /// What the widget will draw until the app next runs.
    static func snapshot(
        progress: ProgressStore,
        catalog: ElementCatalog,
        compounds: [ChemicalCompound],
        date: Date = Date()
    ) -> WidgetProgressSnapshot {
        let pathSteps = LearningPathBuilder.steps(
            catalog: catalog,
            elements: progress.snapshots,
            compounds: progress.compoundSnapshots,
            advancedAnswered: progress.advancedAnswered
        )
        let standing = LearningRankCalculator.standing(
            elements: progress.snapshots,
            elementCount: catalog.count,
            compounds: progress.compoundSnapshots,
            hardQuestionsCorrect: progress.advancedCorrect,
            hardQuestionsAnswered: progress.advancedAnswered,
            studyDaysInLastMonth: progress.studyDayCount(inLast: 30, from: date),
            pathCompletion: LearningPathBuilder.completion(pathSteps)
        )
        let due = ReviewSchedule.dueElements(progress.snapshots, now: date).count
            + ReviewSchedule.dueCompounds(progress.compoundSnapshots, now: date).count

        return WidgetProgressSnapshot(
            masteredElements: progress.masteredCount,
            totalElements: max(catalog.count, 1),
            currentStreak: progress.currentStreak,
            dueReviewCount: due,
            rankTitle: standing.rank.title,
            questions: questions(
                progress: progress, catalog: catalog, compounds: compounds, date: date
            ),
            updatedAt: date
        )
    }

    /// The questions the app leaves ready.
    ///
    /// Drawn from what is weakest and overdue, using the same ranking Smart
    /// Review uses, so a tap on the Home Screen is time spent on the thing
    /// that needed it. Only the four short question types: a Home Screen
    /// widget has room for four options of two or three words, and a question
    /// whose answer is an electron configuration would be unreadable there.
    static func questions(
        progress: ProgressStore,
        catalog: ElementCatalog,
        compounds: [ChemicalCompound],
        date: Date = Date()
    ) -> [WidgetQuestion] {
        guard !catalog.elements.isEmpty else { return [] }
        let seed = SeededGenerator.dailySeed(for: date) &* 0x27D4_EB2F &+ 0x1656_67B1
        let subjects = DailyChallenge.subjects(
            catalog: catalog, snapshots: progress.snapshots, seed: seed, count: questionCount
        )
        guard !subjects.isEmpty else { return [] }

        return QuizGenerator.makeQuiz(
            subjects: subjects.map(QuizSubject.element),
            elementDistractors: catalog.elements,
            compoundDistractors: [],
            kinds: QuizQuestion.Kind.classic,
            count: questionCount,
            seed: seed
        ).map { question in
            WidgetQuestion(
                id: "\(StreakCalculator.dayKey(for: date))-\(question.id)",
                prompt: question.prompt,
                options: question.options,
                correctIndex: question.correctIndex,
                subjectKey: question.subject.key,
                detail: question.detail ?? ""
            )
        }
    }

    /// Merges anything the widget recorded, republishes the snapshot, and asks
    /// WidgetKit to redraw.
    ///
    /// Called on every foreground. It is cheap when nothing has happened: an
    /// empty log is one failed file read, and the snapshot write is a few
    /// hundred bytes.
    static func synchronize(
        progress: ProgressStore,
        catalog: ElementCatalog,
        compounds: [ChemicalCompound],
        log: WidgetEventLog = WidgetEventLog(),
        snapshotStore: WidgetSnapshotStore = WidgetSnapshotStore(),
        ledger: WidgetMergeLedger = WidgetMergeLedger(),
        date: Date = Date()
    ) {
        guard ElemoraAppGroup.isAvailable else { return }
        drain(log: log, into: progress, ledger: ledger)
        snapshotStore.write(
            snapshot(progress: progress, catalog: catalog, compounds: compounds, date: date)
        )
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Which widget answers have already been counted.
///
/// A bounded, ordered list of identifiers in the app's own defaults — not in
/// the shared container, because this is the app's record of what it has done
/// and the widget has no business reading or writing it.
///
/// Bounded because it cannot grow forever and does not need to: the log is
/// cleared after every merge, so the ledger only has to outlive the window
/// between a merge and the clear that follows it. A few hundred entries is
/// orders of magnitude more than that window can hold.
///
/// Not `Sendable`: it holds a `UserDefaults`, which is not, and it has no
/// reason to cross an actor — every caller is on the main actor with the
/// progress store it is merging into.
struct WidgetMergeLedger {
    static let storageKey = "widget.mergedEventIDs"
    static let capacity = 500

    private let defaults: UserDefaults
    private var identifiers: [String]
    private var seen: Set<String>
    private var isDirty = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.stringArray(forKey: Self.storageKey) ?? []
        self.identifiers = stored.suffix(Self.capacity)
        self.seen = Set(self.identifiers)
    }

    func contains(_ id: UUID) -> Bool { seen.contains(id.uuidString) }

    var count: Int { identifiers.count }

    /// Records an identifier. `false` means it was already there, which is the
    /// caller's signal to skip the event entirely.
    @discardableResult
    mutating func markMerged(_ id: UUID) -> Bool {
        let key = id.uuidString
        guard seen.insert(key).inserted else { return false }
        identifiers.append(key)
        if identifiers.count > Self.capacity {
            let dropped = identifiers.prefix(identifiers.count - Self.capacity)
            identifiers.removeFirst(identifiers.count - Self.capacity)
            for stale in dropped { seen.remove(stale) }
        }
        isDirty = true
        return true
    }

    mutating func persist() {
        guard isDirty else { return }
        defaults.set(identifiers, forKey: Self.storageKey)
        isDirty = false
    }
}
