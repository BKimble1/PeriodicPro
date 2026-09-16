import Foundation
import OSLog
import SwiftData

/// Builds the SwiftData container, recovering automatically from an unreadable
/// store rather than crashing on launch.
enum PersistenceController {
    static let logger = Logger(subsystem: "com.periodicpro.app", category: "persistence")

    static let schema = Schema([
        ElementProgressRecord.self,
        RecentSearchRecord.self,
        StudyDayRecord.self,
        CompoundProgressRecord.self,
        CachedCompoundRecord.self,
        SavedQuizRecord.self,
    ])

    /// How the learner's progress is actually being stored this launch.
    enum Storage: Equatable, Sendable {
        /// The normal case: an on-disk store opened cleanly.
        case persistent
        /// The store could not be opened, so it was deleted and rebuilt. Past
        /// progress is gone and the learner deserves to be told.
        case rebuiltAfterCorruption
        /// Even a rebuild failed. Progress works for this launch only.
        case memoryOnlyFallback
        /// A deliberate in-memory store, so UI tests never touch real data.
        case memoryOnlyForTesting

        /// Nothing written this session will survive the app closing.
        var losesProgressOnQuit: Bool { self == .memoryOnlyFallback }

        /// Progress that existed before this launch was discarded.
        var discardedPreviousProgress: Bool { self == .rebuiltAfterCorruption }
    }

    struct Outcome: Sendable {
        /// `nil` only if SwiftData refuses even an in-memory store, in which
        /// case `ProgressStore` runs entirely from memory instead of crashing.
        let container: ModelContainer?
        let storage: Storage
    }

    /// Returns `nil` rather than trapping: a crash on launch is never a better
    /// outcome than an app that simply cannot remember this session.
    static func makeInMemoryContainer() -> ModelContainer? {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            logger.fault("In-memory container failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// A clean, isolated store for UI tests.
    static func makeTestingOutcome() -> Outcome {
        Outcome(container: makeInMemoryContainer(), storage: .memoryOnlyForTesting)
    }

    static func makeOutcome() -> Outcome {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            return Outcome(container: container, storage: .persistent)
        } catch {
            logger.error("Persistent store failed to open: \(String(describing: error), privacy: .public)")
        }

        // Second chance: remove the on-disk store and start fresh. Everything in
        // it is locally derived study progress, so this is recoverable data loss
        // rather than anything the learner can never get back.
        removeStoreFiles()

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            return Outcome(container: container, storage: .rebuiltAfterCorruption)
        } catch {
            logger.error("Store rebuild failed, continuing in memory: \(String(describing: error), privacy: .public)")
            return Outcome(container: makeInMemoryContainer(), storage: .memoryOnlyFallback)
        }
    }

    private static func removeStoreFiles() {
        let fileManager = FileManager.default
        guard let support = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return }

        for name in ["default.store", "default.store-shm", "default.store-wal"] {
            let url = support.appendingPathComponent(name)
            try? fileManager.removeItem(at: url)
        }
    }
}
