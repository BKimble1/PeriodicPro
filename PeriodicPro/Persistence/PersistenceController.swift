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
    ])

    /// Result of building the container, so the UI can tell the learner when
    /// their saved progress could not be recovered.
    struct Outcome {
        let container: ModelContainer
        let recoveredFromCorruptStore: Bool
        let isEphemeral: Bool
    }

    static func makeInMemoryContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // An in-memory store cannot fail for a valid schema; if it somehow does
        // there is no meaningful fallback left, so surface it loudly in debug.
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unable to create in-memory model container: \(error)")
        }
    }

    static func makeOutcome() -> Outcome {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            return Outcome(container: container, recoveredFromCorruptStore: false, isEphemeral: false)
        } catch {
            logger.error("Persistent store failed to open: \(String(describing: error))")
        }

        // Second chance: remove the on-disk store and start fresh. Everything in
        // it is locally derived study progress, so this is recoverable data loss
        // rather than anything the learner can never get back.
        removeStoreFiles()

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            return Outcome(container: container, recoveredFromCorruptStore: true, isEphemeral: false)
        } catch {
            logger.error("Store rebuild failed, continuing in memory: \(String(describing: error))")
            return Outcome(container: makeInMemoryContainer(),
                           recoveredFromCorruptStore: true,
                           isEphemeral: true)
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
