import Foundation
import Observation
import SwiftData

/// The single owner of everything the learner has done: favorites, per-element
/// familiarity, recent searches and study days.
///
/// Views read from the in-memory snapshot dictionary (fast, value-typed) while
/// writes go straight to SwiftData. That keeps the 118-tile table from
/// re-rendering every time an unrelated row changes.
@MainActor
@Observable
final class ProgressStore {
    private let context: ModelContext
    private let calendar: Calendar

    private(set) var snapshots: [Int: ElementProgressSnapshot] = [:]
    private(set) var recentSearches: [String] = []
    private(set) var studyDayKeys: Set<String> = []
    private(set) var lastWriteFailure: String?

    /// `true` when progress is being kept only for this launch because the
    /// on-disk store could not be opened.
    let isEphemeral: Bool

    static let recentSearchLimit = 8

    init(container: ModelContainer, isEphemeral: Bool = false, calendar: Calendar = .current) {
        self.context = ModelContext(container)
        self.isEphemeral = isEphemeral
        self.calendar = calendar
        reload()
    }

    // MARK: - Loading

    func reload() {
        do {
            let records = try context.fetch(FetchDescriptor<ElementProgressRecord>())
            var built: [Int: ElementProgressSnapshot] = [:]
            built.reserveCapacity(records.count)
            for record in records {
                built[record.atomicNumber] = ElementProgressSnapshot(
                    atomicNumber: record.atomicNumber,
                    isFavorite: record.isFavorite,
                    mastery: MasteryLevel(rawValue: record.masteryRaw) ?? .notStarted,
                    correctCount: record.correctCount,
                    incorrectCount: record.incorrectCount,
                    lastReviewed: record.lastReviewed
                )
            }
            snapshots = built

            var searchDescriptor = FetchDescriptor<RecentSearchRecord>(
                sortBy: [SortDescriptor(\RecentSearchRecord.timestamp, order: .reverse)]
            )
            searchDescriptor.fetchLimit = Self.recentSearchLimit
            recentSearches = try context.fetch(searchDescriptor).map(\.text)

            let days = try context.fetch(FetchDescriptor<StudyDayRecord>())
            studyDayKeys = Set(days.map(\.dayKey))
        } catch {
            PersistenceController.logger.error("Reload failed: \(String(describing: error))")
            lastWriteFailure = "Saved progress could not be read."
        }
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
        snapshots.values
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
        let record = fetchOrCreateRecord(atomicNumber)
        record.isFavorite.toggle()
        let value = record.isFavorite
        applySnapshot(from: record)
        save()
        return value
    }

    func recordAnswer(atomicNumber: Int, correct: Bool, date: Date = Date()) {
        let record = fetchOrCreateRecord(atomicNumber)
        let current = MasteryLevel(rawValue: record.masteryRaw) ?? .notStarted
        record.masteryRaw = MasteryEngine.next(from: current, correct: correct).rawValue
        if correct { record.correctCount += 1 } else { record.incorrectCount += 1 }
        record.lastReviewed = date
        applySnapshot(from: record)
        registerStudyDay(on: date)
        save()
    }

    func recordSearch(_ rawTerm: String) {
        let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, term.count <= 32 else { return }

        do {
            let existing = try context.fetch(FetchDescriptor<RecentSearchRecord>())
            if let match = existing.first(where: { $0.text.caseInsensitiveCompare(term) == .orderedSame }) {
                match.timestamp = Date()
            } else {
                context.insert(RecentSearchRecord(text: term, timestamp: Date()))
            }
            save()

            // Trim anything beyond the visible window so the store stays tiny.
            let all = try context.fetch(FetchDescriptor<RecentSearchRecord>(
                sortBy: [SortDescriptor(\RecentSearchRecord.timestamp, order: .reverse)]
            ))
            guard all.count > Self.recentSearchLimit else {
                recentSearches = all.map(\.text)
                return
            }
            for stale in all.dropFirst(Self.recentSearchLimit) {
                context.delete(stale)
            }
            recentSearches = all.prefix(Self.recentSearchLimit).map(\.text)
            save()
        } catch {
            PersistenceController.logger.error("Search write failed: \(String(describing: error))")
        }
    }

    func clearRecentSearches() {
        do {
            for record in try context.fetch(FetchDescriptor<RecentSearchRecord>()) {
                context.delete(record)
            }
            recentSearches = []
            save()
        } catch {
            PersistenceController.logger.error("Clearing searches failed: \(String(describing: error))")
        }
    }

    /// Clears familiarity, answer counts and the streak. Favorites are kept —
    /// they are a deliberate choice the learner made, not progress.
    func resetAllProgress() {
        do {
            for record in try context.fetch(FetchDescriptor<ElementProgressRecord>()) {
                if record.isFavorite {
                    record.masteryRaw = MasteryLevel.notStarted.rawValue
                    record.correctCount = 0
                    record.incorrectCount = 0
                    record.lastReviewed = nil
                } else {
                    context.delete(record)
                }
            }
            for record in try context.fetch(FetchDescriptor<StudyDayRecord>()) {
                context.delete(record)
            }
            studyDayKeys = []
            save()
            reload()
        } catch {
            PersistenceController.logger.error("Reset failed: \(String(describing: error))")
        }
    }

    // MARK: - Private

    private func registerStudyDay(on date: Date) {
        let key = StreakCalculator.dayKey(for: date, calendar: calendar)
        do {
            let days = try context.fetch(FetchDescriptor<StudyDayRecord>())
            if let existing = days.first(where: { $0.dayKey == key }) {
                existing.answeredCount += 1
            } else {
                context.insert(StudyDayRecord(dayKey: key, answeredCount: 1))
            }
            studyDayKeys.insert(key)
        } catch {
            PersistenceController.logger.error("Study day write failed: \(String(describing: error))")
        }
    }

    private func fetchOrCreateRecord(_ atomicNumber: Int) -> ElementProgressRecord {
        let existing = (try? context.fetch(FetchDescriptor<ElementProgressRecord>())) ?? []
        if let match = existing.first(where: { $0.atomicNumber == atomicNumber }) {
            return match
        }
        let record = ElementProgressRecord(atomicNumber: atomicNumber)
        context.insert(record)
        return record
    }

    private func applySnapshot(from record: ElementProgressRecord) {
        snapshots[record.atomicNumber] = ElementProgressSnapshot(
            atomicNumber: record.atomicNumber,
            isFavorite: record.isFavorite,
            mastery: MasteryLevel(rawValue: record.masteryRaw) ?? .notStarted,
            correctCount: record.correctCount,
            incorrectCount: record.incorrectCount,
            lastReviewed: record.lastReviewed
        )
    }

    private func save() {
        do {
            try context.save()
            lastWriteFailure = nil
        } catch {
            PersistenceController.logger.error("Save failed: \(String(describing: error))")
            lastWriteFailure = "Your latest change could not be saved."
        }
    }
}
