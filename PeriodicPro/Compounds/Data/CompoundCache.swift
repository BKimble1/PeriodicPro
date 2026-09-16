import Foundation
import OSLog
import SwiftData

/// A compound the learner looked up, kept so it works offline afterwards.
///
/// The record stores the compound as JSON rather than as columns: the domain
/// type is `Codable`, it changes with the app, and a cache is the one place
/// where a lightweight "decode or discard" beats a schema migration.
@Model
final class CachedCompoundRecord {
    @Attribute(.unique) var compoundID: String
    var pubChemCID: Int?
    var payload: Data
    var fetchedAt: Date

    init(compoundID: String, pubChemCID: Int?, payload: Data, fetchedAt: Date) {
        self.compoundID = compoundID
        self.pubChemCID = pubChemCID
        self.payload = payload
        self.fetchedAt = fetchedAt
    }
}

/// The on-device compound cache, with the same contract as `ProgressStore`:
/// every method works with no container at all, the results simply do not
/// survive the app closing.
///
/// A record that fails to decode — a corrupt row, or one written by a newer
/// build — is deleted rather than allowed to poison the list.
@MainActor
final class CompoundCache {
    static let maximumEntries = 200
    private static let logger = Logger(subsystem: "com.periodicpro.app", category: "compound-cache")

    private let context: ModelContext?
    private var records: [String: CachedCompoundRecord] = [:]
    private(set) var compounds: [String: ChemicalCompound] = [:]
    /// Set when a write could not be saved.
    private(set) var writeFailureMessage: String?

    init(container: ModelContainer?) {
        context = container.map { ModelContext($0) }
        reload()
    }

    var all: [ChemicalCompound] {
        compounds.values.sorted { $0.preferredName < $1.preferredName }
    }

    func compound(id: String) -> ChemicalCompound? { compounds[id] }

    func compound(cid: Int) -> ChemicalCompound? {
        compounds.values.first { $0.pubChemCID == cid }
    }

    func reload() {
        guard let context else { return }
        do {
            let fetched = try context.fetch(FetchDescriptor<CachedCompoundRecord>(
                sortBy: [SortDescriptor(\CachedCompoundRecord.fetchedAt, order: .reverse)]
            ))
            var loaded: [String: ChemicalCompound] = [:]
            var kept: [String: CachedCompoundRecord] = [:]
            for record in fetched {
                if let compound = try? JSONDecoder().decode(ChemicalCompound.self, from: record.payload),
                   compound.id == record.compoundID {
                    loaded[record.compoundID] = compound
                    kept[record.compoundID] = record
                } else {
                    // Corrupt or foreign: gone, and logged, rather than kept
                    // as a row nothing can read.
                    Self.logger.error("Discarding unreadable cached compound \(record.compoundID, privacy: .public)")
                    context.delete(record)
                }
            }
            compounds = loaded
            records = kept
            trim()
            save()
        } catch {
            Self.logger.error("Compound cache reload failed: \(String(describing: error), privacy: .public)")
        }
    }

    func store(_ compound: ChemicalCompound) {
        compounds[compound.id] = compound
        guard let context else { return }
        guard let payload = try? JSONEncoder().encode(compound) else { return }
        if let record = records[compound.id] {
            record.payload = payload
            record.pubChemCID = compound.pubChemCID
            record.fetchedAt = Date()
        } else {
            let record = CachedCompoundRecord(
                compoundID: compound.id, pubChemCID: compound.pubChemCID, payload: payload, fetchedAt: Date()
            )
            context.insert(record)
            records[compound.id] = record
        }
        trim()
        save()
    }

    func remove(id: String) {
        compounds.removeValue(forKey: id)
        if let record = records.removeValue(forKey: id) {
            context?.delete(record)
        }
        save()
    }

    /// Keeps the cache bounded: the oldest fetches go first, but never a
    /// hypothetical composition the learner chose to keep.
    private func trim() {
        guard records.count > Self.maximumEntries else { return }
        let ordered = records.values
            .filter { !$0.compoundID.hasPrefix("hypothetical-") }
            .sorted { $0.fetchedAt < $1.fetchedAt }
        for record in ordered.prefix(records.count - Self.maximumEntries) {
            remove(id: record.compoundID)
        }
    }

    private func save() {
        guard let context, context.hasChanges else { return }
        do {
            try context.save()
            writeFailureMessage = nil
        } catch {
            Self.logger.error("Compound cache save failed: \(String(describing: error), privacy: .public)")
            writeFailureMessage = "A looked-up compound could not be saved for offline use."
        }
    }
}
