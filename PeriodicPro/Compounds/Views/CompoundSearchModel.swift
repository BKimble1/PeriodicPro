import Foundation
import Observation

/// Drives a chemistry search: local results at once, PubChem after a pause.
///
/// One field, every identifier a learner might be holding. `ChemicalQuery`
/// decides which — a name, a molecular formula, a PubChem CID, a SMILES
/// string, an InChI or an InChIKey — and each reaches its own endpoint.
///
/// One in-flight request at a time. Every keystroke cancels the previous
/// lookup and restarts the debounce, so PubChem sees one request per pause in
/// typing rather than one per character.
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

    /// What a bare number means here.
    ///
    /// On the Table screen a number is an atomic number and never reaches
    /// PubChem — that is the whole search's meaning there. Build's search is
    /// compound-only, so a number there is a CID, which is what somebody who
    /// pasted one from a PubChem page meant by it.
    enum Interpretation: Sendable {
        /// The Table screen: numbers and one- or two-letter symbols are
        /// elements, and are not sent anywhere.
        case elementAware
        /// The Build screen: every kind of chemical identifier is in play.
        case compoundOnly
    }

    static let debounce: Duration = .milliseconds(400)
    static let suggestionDebounce: Duration = .milliseconds(320)
    /// `nonisolated` because `shouldQueryRemote` is, and reading a main
    /// actor-isolated static from a nonisolated function is an error under
    /// Swift 6. A constant has no isolation to lose.
    nonisolated static let minimumRemoteLength = 3
    /// Short enough to feel instant on a prefix, long enough to be worth
    /// asking about.
    static let minimumSuggestionLength = 2

    let interpretation: Interpretation

    private(set) var query = ""
    private(set) var recognized: ChemicalQuery = .empty
    private(set) var localResults: [CompoundMatchCandidate] = []
    /// PubChem hits the device did not already have.
    private(set) var remoteResults: [CompoundMatchCandidate] = []
    /// Name suggestions from PubChem's autocomplete. Terms, not records:
    /// picking one performs an exact lookup.
    private(set) var suggestions: [String] = []
    private(set) var status: Status = .idle
    /// True once PubChem was actually asked for the current query.
    private(set) var askedRemote = false
    /// Set when a formula search has more matches than are shown.
    private(set) var formulaCursor: FormulaSearchCursor?
    private(set) var isLoadingMore = false

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var suggestionTask: Task<Void, Never>?

    init(interpretation: Interpretation = .elementAware) {
        self.interpretation = interpretation
    }

    var allResults: [CompoundMatchCandidate] { localResults + remoteResults }
    var isEmpty: Bool { allResults.isEmpty }
    var hasMore: Bool { formulaCursor.map { !$0.isExhausted } ?? false }

    /// What kind of identifier the field currently holds, for the interface
    /// to say so — "Molecular formula", "PubChem CID", "SMILES".
    var recognizedKind: String? {
        switch recognized {
        case .empty, .name: return nil
        default: return recognized.kindDescription
        }
    }

    func update(query rawQuery: String, store: CompoundStore) {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        query = trimmed
        task?.cancel()
        suggestionTask?.cancel()
        remoteResults = []
        suggestions = []
        formulaCursor = nil
        askedRemote = false
        guard !trimmed.isEmpty else {
            localResults = []
            recognized = .empty
            status = .idle
            return
        }

        localResults = store.localSearch(trimmed).map(CompoundMatchCandidate.init(local:))
        recognized = classify(trimmed)

        guard shouldQueryRemote(trimmed), store.isOnlineLookupEnabled else {
            status = .done
            return
        }
        status = .searching
        askedRemote = true
        let recognized = self.recognized
        task = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled, let self else { return }
            await self.fetchRemote(trimmed, recognized: recognized, store: store)
        }
        startSuggestions(for: recognized, text: trimmed, store: store)
    }

    /// Runs the online half again after a failure.
    func retry(store: CompoundStore) {
        guard !query.isEmpty, shouldQueryRemote(query), store.isOnlineLookupEnabled else { return }
        task?.cancel()
        status = .searching
        askedRemote = true
        let current = query
        let recognized = self.recognized
        task = Task { [weak self] in
            guard let self else { return }
            await self.fetchRemote(current, recognized: recognized, store: store)
        }
    }

    /// The next page of a formula search.
    func loadMore(store: CompoundStore) {
        guard let cursor = formulaCursor, !cursor.isExhausted, !isLoadingMore,
              store.isOnlineLookupEnabled else { return }
        isLoadingMore = true
        let current = query
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.isLoadingMore = false }
            do {
                let page = try await store.moreCandidates(after: cursor)
                guard !Task.isCancelled, self.query == current else { return }
                self.formulaCursor = page.cursor
                let localIDs = Set(self.localResults.map(\.id))
                self.remoteResults = page.candidates.filter { !localIDs.contains($0.id) }
                self.status = .done
            } catch let error as PubChemError {
                guard !Task.isCancelled, self.query == current, error != .canceled else { return }
                self.status = .failed(error.userMessage)
            } catch {
                guard !Task.isCancelled, self.query == current else { return }
                self.status = .failed(PubChemError.malformed("").userMessage)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        suggestionTask?.cancel()
        suggestionTask = nil
    }

    // MARK: - Fetching

    private func fetchRemote(_ query: String, recognized: ChemicalQuery, store: CompoundStore) async {
        do {
            let hits: [CompoundMatchCandidate]
            if case .formula(_, let text) = recognized {
                let hill = ChemicalFormulaParser.parse(text)?.hill() ?? text
                let page = try await store.remoteCandidates(hillFormula: hill)
                guard !Task.isCancelled, self.query == query else { return }
                formulaCursor = page.cursor
                hits = page.candidates
            } else {
                hits = try await store.remoteSearch(query: recognized)
            }
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

    /// Suggestions are for names only, on their own shorter debounce, and
    /// their failure is never a failure of the search: a prefix that returns
    /// nothing simply shows no suggestions.
    private func startSuggestions(for recognized: ChemicalQuery, text: String, store: CompoundStore) {
        guard interpretation == .compoundOnly, recognized.acceptsSuggestions,
              text.count >= Self.minimumSuggestionLength, store.isOnlineLookupEnabled else { return }
        suggestionTask = Task { [weak self] in
            try? await Task.sleep(for: Self.suggestionDebounce)
            guard !Task.isCancelled, let self else { return }
            let terms = (try? await store.suggestions(for: recognized)) ?? []
            guard !Task.isCancelled, self.query == text else { return }
            // A suggestion identical to what was typed adds nothing.
            self.suggestions = terms.filter { $0.caseInsensitiveCompare(text) != .orderedSame }
        }
    }

    // MARK: - Recognizing

    private func classify(_ text: String) -> ChemicalQuery {
        switch interpretation {
        case .compoundOnly:
            return ChemicalQueryClassifier.classify(text)
        case .elementAware:
            // A bare number is an atomic number on the Table screen, and a
            // one- or two-letter symbol is an element. Neither is a compound
            // query, so neither is classified as one.
            if Int(text) != nil { return .empty }
            return ChemicalQueryClassifier.classify(text)
        }
    }

    private func shouldQueryRemote(_ text: String) -> Bool {
        switch interpretation {
        case .elementAware:
            return Self.shouldQueryRemote(text)
        case .compoundOnly:
            switch recognized {
            case .empty: return false
            case .name(let name): return name.count >= Self.minimumRemoteLength
            default: return true
            }
        }
    }

    /// PubChem is only asked for something that could be a compound name:
    /// never for a number, which is an atomic number, and never for one or two
    /// letters, which is a symbol. Pure, so it is callable from anywhere.
    ///
    /// This is the Table screen's rule. Build's search has its own, because
    /// there a number is a CID and `Fe` is a formula.
    nonisolated static func shouldQueryRemote(_ query: String) -> Bool {
        guard query.count >= minimumRemoteLength, Int(query) == nil else { return false }
        return PubChemClient.isPlausibleName(query)
    }
}
