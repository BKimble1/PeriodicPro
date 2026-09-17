import Foundation
import Observation
import OSLog
import SwiftData

/// The single owner of everything the learner has done: favorites, per-element
/// familiarity, recent searches and study days.
///
/// In-memory value-typed state is the source of truth the UI reads, and
/// SwiftData is written through behind it. That has two consequences worth
/// knowing about: the 118-tile table never re-renders because an unrelated row
/// changed, and the store keeps working — for this launch — even when SwiftData
/// cannot give us a container at all.
@MainActor
@Observable
final class ProgressStore {
    /// `nil` when persistence is unavailable; every method still works, the
    /// results simply do not survive the app closing.
    private let context: ModelContext?
    private let calendar: Calendar

    // Managed objects, held so writes never have to re-fetch the whole table.
    @ObservationIgnored private var records: [Int: ElementProgressRecord] = [:]
    @ObservationIgnored private var dayRecords: [String: StudyDayRecord] = [:]
    @ObservationIgnored private var searchRecords: [String: RecentSearchRecord] = [:]
    /// Completed rounds per day key, held in memory as well as in the store.
    ///
    /// The store's contract is that every method works when `container` is nil,
    /// with the results simply not surviving a relaunch. Reading this count
    /// straight off the managed objects broke that: with no context there are
    /// no records, so the count stayed at zero and the free daily allowance
    /// became unlimited for anyone whose on-disk store failed to open.
    @ObservationIgnored private var roundsByDay: [String: Int] = [:]
    @ObservationIgnored private var compoundRecords: [String: CompoundProgressRecord] = [:]

    private(set) var snapshots: [Int: ElementProgressSnapshot] = [:]
    /// Compound progress, keyed by the compound's stable identifier.
    private(set) var compoundSnapshots: [String: CompoundProgressSnapshot] = [:]
    private(set) var recentSearches: [String] = []
    private(set) var studyDayKeys: Set<String> = []

    /// Rounds finished today, which is what the free daily allowance counts.
    /// Published separately from `studyDayKeys` so the Study screen re-renders
    /// the moment a round completes.
    private(set) var completedRoundsToday: Int = 0

    /// Set when a write could not be saved, so the UI can say so instead of
    /// quietly losing the change.
    private(set) var writeFailureMessage: String?

    /// Set when saved data could not be read back at launch. Kept separate from
    /// `writeFailureMessage` because the two clear on different events: a
    /// successful save says nothing about whether the read that preceded it
    /// worked, and folding them together let `reload()`'s own trailing `save()`
    /// erase the warning it had just raised.
    private(set) var readFailureMessage: String?

    let storage: PersistenceController.Storage

    static let recentSearchLimit = 8

    init(
        container: ModelContainer?,
        storage: PersistenceController.Storage,
        calendar: Calendar = .current
    ) {
        self.context = container.map { ModelContext($0) }
        self.storage = storage
        self.calendar = calendar
        reload()
    }

    // MARK: - Loading

    func reload() {
        guard let context else { return }

        var failures: [String] = []

        do {
            let fetched = try context.fetch(FetchDescriptor<ElementProgressRecord>())
            records = Dictionary(fetched.map { ($0.atomicNumber, $0) },
                                 uniquingKeysWith: { first, _ in first })
            snapshots = records.mapValues(Self.snapshot(from:))
        } catch {
            failures.append("progress")
            PersistenceController.logger.error(
                "Progress reload failed: \(String(describing: error), privacy: .public)")
        }

        do {
            let fetched = try context.fetch(FetchDescriptor<RecentSearchRecord>(
                sortBy: [SortDescriptor(\RecentSearchRecord.timestamp, order: .reverse)]
            ))
            // Trim anything an older build left behind so the table cannot grow
            // without bound.
            let keep = Array(fetched.prefix(Self.recentSearchLimit))
            for stale in fetched.dropFirst(Self.recentSearchLimit) {
                context.delete(stale)
            }
            searchRecords = Dictionary(keep.map { ($0.text.lowercased(), $0) },
                                       uniquingKeysWith: { first, _ in first })
            recentSearches = keep.map(\.text)
        } catch {
            failures.append("recent searches")
            PersistenceController.logger.error(
                "Search reload failed: \(String(describing: error), privacy: .public)")
        }

        do {
            let fetched = try context.fetch(FetchDescriptor<StudyDayRecord>())
            dayRecords = Dictionary(fetched.map { ($0.dayKey, $0) },
                                    uniquingKeysWith: { first, _ in first })
            // A day counts toward the streak because cards were answered on it.
            // Resetting progress zeroes those counts but keeps today's row, so
            // the row alone must not resurrect the streak.
            studyDayKeys = Set(dayRecords.filter { $0.value.answeredCount > 0 }.keys)
            roundsByDay = dayRecords.mapValues(\.completedRounds)
        } catch {
            failures.append("study history")
            PersistenceController.logger.error(
                "Study day reload failed: \(String(describing: error), privacy: .public)")
        }

        do {
            let fetched = try context.fetch(FetchDescriptor<CompoundProgressRecord>())
            compoundRecords = Dictionary(fetched.map { ($0.compoundID, $0) },
                                         uniquingKeysWith: { first, _ in first })
            compoundSnapshots = compoundRecords.mapValues(Self.snapshot(from:))
        } catch {
            failures.append("compound progress")
            PersistenceController.logger.error(
                "Compound progress reload failed: \(String(describing: error), privacy: .public)")
        }

        readFailureMessage = failures.isEmpty
            ? nil
            : "Some saved data could not be read (\(failures.joined(separator: ", ")))."

        refreshCompletedRoundsToday()
        save()
    }

    // MARK: - Reads

    func snapshot(for atomicNumber: Int) -> ElementProgressSnapshot {
        snapshots[atomicNumber] ?? ElementProgressSnapshot(atomicNumber: atomicNumber)
    }

    func isFavorite(_ atomicNumber: Int) -> Bool { snapshot(for: atomicNumber).isFavorite }

    func mastery(for atomicNumber: Int) -> MasteryLevel { snapshot(for: atomicNumber).mastery }

    var favoriteAtomicNumbers: [Int] {
        snapshots.values.filter(\.isFavorite).map(\.atomicNumber).sorted()
    }

    var masteredCount: Int {
        snapshots.values.filter { $0.mastery == .mastered }.count
    }

    var startedCount: Int {
        snapshots.values.filter { $0.mastery != .notStarted }.count
    }

    var totalAnswered: Int {
        snapshots.values.reduce(0) { $0 + $1.attempts }
    }

    var currentStreak: Int {
        StreakCalculator.currentStreak(days: studyDayKeys, today: Date(), calendar: calendar)
    }

    /// Most recently reviewed elements, newest first.
    func recentlyStudied(limit: Int = 8) -> [Int] {
        guard limit > 0 else { return [] }
        return snapshots.values
            .compactMap { snapshot -> (atomicNumber: Int, date: Date)? in
                guard let date = snapshot.lastReviewed else { return nil }
                return (snapshot.atomicNumber, date)
            }
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map { $0.atomicNumber }
    }

    func masteredCount(in category: ElementCategory, catalog: ElementCatalog) -> Int {
        catalog.elements(in: category).filter { mastery(for: $0.atomicNumber) == .mastered }.count
    }

    /// The elements the learner is weakest on, worst first. Smart Review draws
    /// from this; the regular modes use `MasteryEngine.studyPriority`.
    func weakestSnapshots() -> [ElementProgressSnapshot] {
        SmartReviewBuilder.ranked(Array(snapshots.values))
    }

    // MARK: - Compounds

    func compoundSnapshot(for id: String) -> CompoundProgressSnapshot {
        compoundSnapshots[id] ?? CompoundProgressSnapshot(compoundID: id)
    }

    func isCompoundFavorite(_ id: String) -> Bool { compoundSnapshot(for: id).isFavorite }
    func isCompoundSaved(_ id: String) -> Bool { compoundSnapshot(for: id).isSaved }
    func compoundMastery(for id: String) -> MasteryLevel { compoundSnapshot(for: id).mastery }

    var favoriteCompoundIDs: [String] {
        compoundSnapshots.values.filter(\.isFavorite).map(\.compoundID).sorted()
    }

    var savedCompoundIDs: [String] {
        compoundSnapshots.values.filter(\.isSaved).map(\.compoundID).sorted()
    }

    /// Everything the learner has chosen or practiced: the study pool.
    var studyCompoundIDs: [String] {
        compoundSnapshots.values.filter(\.isInStudy).map(\.compoundID).sorted()
    }

    var masteredCompoundCount: Int {
        compoundSnapshots.values.filter { $0.mastery == .mastered }.count
    }

    var totalCompoundAnswered: Int {
        compoundSnapshots.values.reduce(0) { $0 + $1.attempts }
    }

    @discardableResult
    func toggleCompoundFavorite(_ id: String) -> Bool {
        var snapshot = compoundSnapshot(for: id)
        snapshot.isFavorite.toggle()
        applyCompound(snapshot)
        return snapshot.isFavorite
    }

    func setCompoundSaved(_ id: String, _ isSaved: Bool) {
        var snapshot = compoundSnapshot(for: id)
        guard snapshot.isSaved != isSaved else { return }
        snapshot.isSaved = isSaved
        applyCompound(snapshot)
    }

    func recordCompoundAnswer(id: String, correct: Bool, date: Date = Date()) {
        var snapshot = compoundSnapshot(for: id)
        snapshot.mastery = MasteryEngine.next(from: snapshot.mastery, correct: correct)
        if correct { snapshot.correctCount += 1 } else { snapshot.incorrectCount += 1 }
        snapshot.lastReviewed = date
        applyCompound(snapshot, save: false)
        registerStudyDay(on: date)
        save()
    }

    /// Whether anything still points at this compound.
    ///
    /// The cache and the learner's choices are stored separately on purpose,
    /// so this is the question that decides whether a cached record can be
    /// thrown away: a compound nobody has favorited, saved or answered is one
    /// nothing will ask for by identifier again.
    func hasCompoundReferences(_ id: String) -> Bool {
        guard let snapshot = compoundSnapshots[id] else { return false }
        return snapshot.isFavorite || snapshot.isSaved || snapshot.attempts > 0
            || snapshot.mastery != .notStarted
    }

    /// Erases everything the learner's progress holds about a compound.
    ///
    /// Used when a composition is deleted outright, which only a hypothetical
    /// one can be. Nothing is left behind pointing at an identifier that no
    /// longer resolves — there is no dangling progress row, because the row
    /// itself goes.
    func removeCompoundProgress(_ id: String) {
        compoundSnapshots.removeValue(forKey: id)
        if let record = compoundRecords.removeValue(forKey: id), let context {
            context.delete(record)
        }
        save()
    }

    private static func snapshot(from record: CompoundProgressRecord) -> CompoundProgressSnapshot {
        CompoundProgressSnapshot(
            compoundID: record.compoundID,
            isFavorite: record.isFavorite,
            isSaved: record.isSaved,
            mastery: MasteryLevel(rawValue: record.masteryRaw) ?? .notStarted,
            correctCount: record.correctCount,
            incorrectCount: record.incorrectCount,
            lastReviewed: record.lastReviewed
        )
    }

    private func applyCompound(_ snapshot: CompoundProgressSnapshot, save shouldSave: Bool = true) {
        compoundSnapshots[snapshot.compoundID] = snapshot
        if let record = compoundRecords[snapshot.compoundID] {
            record.isFavorite = snapshot.isFavorite
            record.isSaved = snapshot.isSaved
            record.masteryRaw = snapshot.mastery.rawValue
            record.correctCount = snapshot.correctCount
            record.incorrectCount = snapshot.incorrectCount
            record.lastReviewed = snapshot.lastReviewed
        } else if let context {
            let record = CompoundProgressRecord(
                compoundID: snapshot.compoundID,
                isFavorite: snapshot.isFavorite,
                isSaved: snapshot.isSaved,
                masteryRaw: snapshot.mastery.rawValue,
                correctCount: snapshot.correctCount,
                incorrectCount: snapshot.incorrectCount,
                lastReviewed: snapshot.lastReviewed
            )
            context.insert(record)
            compoundRecords[snapshot.compoundID] = record
        }
        if shouldSave { save() }
    }

    // MARK: - Writes

    @discardableResult
    func toggleFavorite(_ atomicNumber: Int) -> Bool {
        var snapshot = self.snapshot(for: atomicNumber)
        snapshot.isFavorite.toggle()
        apply(snapshot)
        return snapshot.isFavorite
    }

    func recordAnswer(atomicNumber: Int, correct: Bool, date: Date = Date()) {
        var snapshot = self.snapshot(for: atomicNumber)
        snapshot.mastery = MasteryEngine.next(from: snapshot.mastery, correct: correct)
        if correct { snapshot.correctCount += 1 } else { snapshot.incorrectCount += 1 }
        snapshot.lastReviewed = date
        apply(snapshot, save: false)
        registerStudyDay(on: date)
        save()
    }

    /// Called once, when a round reaches its summary.
    ///
    /// A round that the learner exits half way through never reaches here, so
    /// an interrupted session cannot consume part of the free daily allowance.
    func recordCompletedRound(date: Date = Date()) {
        // No `studyDayKeys` insert here: a round can only complete after cards
        // were answered, and `registerStudyDay` already recorded the day.
        let key = StreakCalculator.dayKey(for: date, calendar: calendar)

        // In memory first, so the count is right whether or not there is a
        // context to persist it to.
        roundsByDay[key, default: 0] += 1

        if let existing = dayRecords[key] {
            existing.completedRounds += 1
        } else if let context {
            let record = StudyDayRecord(dayKey: key, answeredCount: 0, completedRounds: 1)
            context.insert(record)
            dayRecords[key] = record
        }
        refreshCompletedRoundsToday(on: date)
        save()
    }

    /// Recomputed rather than incremented so it is correct after a reload, and —
    /// the case that matters — after midnight passes while the app is merely
    /// backgrounded. The app calls this whenever it becomes active; without
    /// that, a learner who spent their three rounds last night would find the
    /// app still locked this morning.
    func refreshCompletedRoundsToday(on date: Date = Date()) {
        let key = StreakCalculator.dayKey(for: date, calendar: calendar)
        completedRoundsToday = roundsByDay[key] ?? 0
    }

    func recordSearch(_ rawTerm: String) {
        let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, term.count <= 32 else { return }
        let key = term.lowercased()

        if let existing = searchRecords[key] {
            existing.timestamp = Date()
        } else if let context {
            let record = RecentSearchRecord(text: term, timestamp: Date())
            context.insert(record)
            searchRecords[key] = record
        }

        // Newest first, deduplicated case-insensitively. The list shows the
        // spelling just typed; the stored row keeps its original casing, which
        // only surfaces after a relaunch and is not worth risking a unique-key
        // conflict to change.
        var ordered = recentSearches.filter { $0.lowercased() != key }
        ordered.insert(term, at: 0)
        for stale in ordered.dropFirst(Self.recentSearchLimit) {
            if let record = searchRecords.removeValue(forKey: stale.lowercased()) {
                context?.delete(record)
            }
        }
        recentSearches = Array(ordered.prefix(Self.recentSearchLimit))
        save()
    }

    func clearRecentSearches() {
        for record in searchRecords.values {
            context?.delete(record)
        }
        searchRecords = [:]
        recentSearches = []
        save()
    }

    /// Clears familiarity, answer counts and the streak. Favorites are kept —
    /// they are a deliberate choice the learner made, not progress.
    func resetAllProgress() {
        for (atomicNumber, record) in records where !record.isFavorite {
            context?.delete(record)
            records.removeValue(forKey: atomicNumber)
        }
        for record in records.values {
            record.masteryRaw = MasteryLevel.notStarted.rawValue
            record.correctCount = 0
            record.incorrectCount = 0
            record.lastReviewed = nil
        }

        snapshots = snapshots.compactMapValues { snapshot in
            snapshot.isFavorite
                ? ElementProgressSnapshot(atomicNumber: snapshot.atomicNumber, isFavorite: true)
                : nil
        }

        // Compounds follow the same rule: favorites and saved choices stay,
        // familiarity goes.
        for (id, record) in compoundRecords where !record.isFavorite && !record.isSaved {
            context?.delete(record)
            compoundRecords.removeValue(forKey: id)
        }
        for record in compoundRecords.values {
            record.masteryRaw = MasteryLevel.notStarted.rawValue
            record.correctCount = 0
            record.incorrectCount = 0
            record.lastReviewed = nil
        }
        compoundSnapshots = compoundSnapshots.compactMapValues { snapshot in
            snapshot.isFavorite || snapshot.isSaved
                ? CompoundProgressSnapshot(
                    compoundID: snapshot.compoundID, isFavorite: snapshot.isFavorite, isSaved: snapshot.isSaved)
                : nil
        }

        // Today's row survives, with its answer count zeroed but its completed
        // rounds intact. Wiping it would turn "Reset progress" into a way to
        // refill the free daily allowance, and the streak still drops to zero
        // because the streak counts days on which cards were answered.
        let todayKey = StreakCalculator.dayKey(for: Date(), calendar: calendar)
        for (key, record) in dayRecords where key != todayKey {
            context?.delete(record)
            dayRecords.removeValue(forKey: key)
        }
        dayRecords[todayKey]?.answeredCount = 0
        roundsByDay = roundsByDay.filter { $0.key == todayKey }
        studyDayKeys = []
        refreshCompletedRoundsToday()
        save()
    }

    // MARK: - Private

    private static func snapshot(from record: ElementProgressRecord) -> ElementProgressSnapshot {
        ElementProgressSnapshot(
            atomicNumber: record.atomicNumber,
            isFavorite: record.isFavorite,
            mastery: MasteryLevel(rawValue: record.masteryRaw) ?? .notStarted,
            correctCount: record.correctCount,
            incorrectCount: record.incorrectCount,
            lastReviewed: record.lastReviewed
        )
    }

    /// Writes a snapshot through to SwiftData, creating the managed object the
    /// first time an element is touched.
    private func apply(_ snapshot: ElementProgressSnapshot, save shouldSave: Bool = true) {
        snapshots[snapshot.atomicNumber] = snapshot

        if let record = records[snapshot.atomicNumber] {
            record.isFavorite = snapshot.isFavorite
            record.masteryRaw = snapshot.mastery.rawValue
            record.correctCount = snapshot.correctCount
            record.incorrectCount = snapshot.incorrectCount
            record.lastReviewed = snapshot.lastReviewed
        } else if let context {
            let record = ElementProgressRecord(
                atomicNumber: snapshot.atomicNumber,
                isFavorite: snapshot.isFavorite,
                masteryRaw: snapshot.mastery.rawValue,
                correctCount: snapshot.correctCount,
                incorrectCount: snapshot.incorrectCount,
                lastReviewed: snapshot.lastReviewed
            )
            context.insert(record)
            records[snapshot.atomicNumber] = record
        }

        if shouldSave { save() }
    }

    private func registerStudyDay(on date: Date) {
        let key = StreakCalculator.dayKey(for: date, calendar: calendar)
        studyDayKeys.insert(key)

        if let existing = dayRecords[key] {
            existing.answeredCount += 1
        } else if let context {
            let record = StudyDayRecord(dayKey: key, answeredCount: 1)
            context.insert(record)
            dayRecords[key] = record
        }
    }

    private func save() {
        guard let context else { return }
        guard context.hasChanges else { return }
        do {
            try context.save()
            writeFailureMessage = nil
        } catch {
            PersistenceController.logger.error(
                "Save failed: \(String(describing: error), privacy: .public)")
            writeFailureMessage = "Your latest change could not be saved."
        }
    }
}
