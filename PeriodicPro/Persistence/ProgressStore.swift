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

    private(set) var snapshots: [Int: ElementProgressSnapshot] = [:]
    private(set) var recentSearches: [String] = []
    private(set) var studyDayKeys: Set<String> = []

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
            studyDayKeys = Set(dayRecords.keys)
        } catch {
            failures.append("study history")
            PersistenceController.logger.error(
                "Study day reload failed: \(String(describing: error), privacy: .public)")
        }

        readFailureMessage = failures.isEmpty
            ? nil
            : "Some saved data could not be read (\(failures.joined(separator: ", ")))."

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

        for record in dayRecords.values {
            context?.delete(record)
        }
        dayRecords = [:]
        studyDayKeys = []
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
