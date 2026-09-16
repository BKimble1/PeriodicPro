import Foundation
import Observation

/// Drives the compound section of the table's search: local results at once,
/// PubChem after a pause, and never for a query that is plainly an element.
///
/// One in-flight request at a time. Every keystroke cancels the previous
/// lookup and starts the debounce again, so PubChem sees one request per
/// pause in typing rather than one per character.
@MainActor
@Observable
final class CompoundSearchModel {
    /// Where the online half of the search is.
    enum Status: Equatable, Sendable {
        case idle
        case searching
        case done
        case failed(String)
    }

    static let debounce: Duration = .milliseconds(400)
    static let minimumRemoteLength = 3

    private(set) var query = ""
    private(set) var localResults: [CompoundMatchCandidate] = []
    /// PubChem hits the device did not already have.
    private(set) var remoteResults: [CompoundMatchCandidate] = []
    private(set) var status: Status = .idle
    /// True once PubChem was actually asked for the current query.
    private(set) var askedRemote = false
    @ObservationIgnored private var task: Task<Void, Never>?

    var allResults: [CompoundMatchCandidate] { localResults + remoteResults }
    var isEmpty: Bool { allResults.isEmpty }

    func update(query rawQuery: String, store: CompoundStore) {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        query = trimmed
        task?.cancel()
        remoteResults = []
        askedRemote = false
        guard !trimmed.isEmpty else {
            localResults = []
            status = .idle
            return
        }
        localResults = store.localSearch(trimmed).map(CompoundMatchCandidate.init(local:))
        guard Self.shouldQueryRemote(trimmed), store.isOnlineLookupEnabled else {
            status = .done
            return
        }
        status = .searching
        askedRemote = true
        task = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled, let self else { return }
            await self.fetchRemote(trimmed, store: store)
        }
    }

    /// Runs the online half again after a failure.
    func retry(store: CompoundStore) {
        guard !query.isEmpty, Self.shouldQueryRemote(query), store.isOnlineLookupEnabled else { return }
        task?.cancel()
        status = .searching
        askedRemote = true
        let current = query
        task = Task { [weak self] in
            guard let self else { return }
            await self.fetchRemote(current, store: store)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private func fetchRemote(_ query: String, store: CompoundStore) async {
        do {
            let hits = try await store.remoteSearch(name: query)
            guard !Task.isCancelled, self.query == query else { return }
            let localIDs = Set(localResults.map(\.id))
            remoteResults = hits.filter { !localIDs.contains($0.id) }
            status = .done
        } catch let error as PubChemError {
            guard !Task.isCancelled, self.query == query else { return }
            switch error {
            case .notFound, .canceled, .invalidQuery: status = .done
            default: status = .failed(error.userMessage)
            }
        } catch {
            guard !Task.isCancelled, self.query == query else { return }
            status = .failed(PubChemError.malformed("").userMessage)
        }
    }

    /// PubChem is only asked for something that could be a compound name:
    /// never for a number, which is an atomic number, and never for one or two
    /// letters, which is a symbol. Pure, so it is callable from anywhere.
    nonisolated static func shouldQueryRemote(_ query: String) -> Bool {
        guard query.count >= minimumRemoteLength, Int(query) == nil else { return false }
        return PubChemClient.isPlausibleName(query)
    }
}
