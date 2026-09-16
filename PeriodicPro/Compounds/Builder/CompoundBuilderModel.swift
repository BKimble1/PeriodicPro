import Foundation
import Observation

/// The state of the Compound Builder: the composition being assembled and
/// what the lookup found for it.
///
/// The lookup is honest by construction. A formula is matched against the
/// bundled catalog first, then PubChem; one match is shown, several are
/// offered for the learner to choose between, and none is reported as
/// exactly that — a miss, never a discovery. A failed request (offline, a
/// timeout, PubChem busy) is a fourth, separate state, because "we could not
/// ask" is not "nothing is known".
@MainActor
@Observable
final class CompoundBuilderModel {
    /// One element in the tray and how many of it.
    struct Entry: Identifiable, Hashable, Sendable {
        let element: ChemicalElement
        var count: Int
        var id: Int { element.atomicNumber }
    }

    /// What the lookup produced.
    enum LookupState: Equatable, Sendable {
        case idle
        case searching
        /// Exactly one known compound has this formula.
        case matched(ChemicalCompound)
        /// Several do: the learner picks.
        case choices([CompoundMatchCandidate])
        /// The catalog and PubChem were both asked and neither has it.
        case noMatch
        /// The learner chose to keep an unmatched composition.
        case hypothetical(ChemicalCompound)
        /// PubChem could not be asked, or did not answer.
        case failed(String)
    }

    static let maximumDistinctElements = 6
    static let maximumCountPerElement = 30

    private(set) var entries: [Entry] = []
    private(set) var state: LookupState = .idle
    @ObservationIgnored private var task: Task<Void, Never>?

    var isEmpty: Bool { entries.isEmpty }
    var canAddElement: Bool { entries.count < Self.maximumDistinctElements }

    /// Atomic number → count.
    var composition: [Int: Int] {
        Dictionary(entries.map { ($0.element.atomicNumber, $0.count) }, uniquingKeysWith: { first, _ in first })
    }

    func displayFormula(catalog: ElementCatalog) -> String {
        CompoundFormula.subscripted(CompoundFormula.display(composition, catalog: catalog))
    }

    func hillFormula(catalog: ElementCatalog) -> String {
        CompoundFormula.hill(composition, catalog: catalog)
    }

    func molarMass(catalog: ElementCatalog) -> Double? {
        CompoundFormula.molarMass(composition, catalog: catalog)
    }

    var totalAtoms: Int { entries.reduce(0) { $0 + $1.count } }

    // MARK: - Composition

    func add(_ element: ChemicalElement) {
        if let index = entries.firstIndex(where: { $0.element == element }) {
            increment(entries[index].element.atomicNumber)
            return
        }
        guard canAddElement else { return }
        entries.append(Entry(element: element, count: 1))
        resetLookup()
    }

    func increment(_ atomicNumber: Int) {
        guard let index = entries.firstIndex(where: { $0.element.atomicNumber == atomicNumber }),
              entries[index].count < Self.maximumCountPerElement else { return }
        entries[index].count += 1
        resetLookup()
    }

    func decrement(_ atomicNumber: Int) {
        guard let index = entries.firstIndex(where: { $0.element.atomicNumber == atomicNumber }) else { return }
        if entries[index].count > 1 {
            entries[index].count -= 1
        } else {
            entries.remove(at: index)
        }
        resetLookup()
    }

    func remove(_ atomicNumber: Int) {
        entries.removeAll { $0.element.atomicNumber == atomicNumber }
        resetLookup()
    }

    func clear() {
        entries = []
        resetLookup()
    }

    /// Loads a known compound's composition into the tray, for "edit this".
    func load(_ compound: ChemicalCompound, catalog: ElementCatalog) {
        entries = compound.composition.keys.sorted().compactMap { number in
            guard let element = catalog.element(atomicNumber: number), let count = compound.composition[number] else {
                return nil
            }
            return Entry(element: element, count: min(count, Self.maximumCountPerElement))
        }
        resetLookup()
    }

    func resetLookup() {
        task?.cancel()
        task = nil
        state = .idle
    }

    // MARK: - Lookup

    /// Catalog first, then PubChem. Never the network for an empty tray.
    func lookUp(store: CompoundStore, catalog: ElementCatalog) {
        task?.cancel()
        guard !entries.isEmpty else {
            state = .idle
            return
        }
        let formula = hillFormula(catalog: catalog)
        let local = store.localCandidates(hillFormula: formula)
        if !local.isEmpty {
            settle(on: local, store: store)
            return
        }
        guard store.isOnlineLookupEnabled else {
            state = .failed(PubChemError.offline.userMessage)
            return
        }
        state = .searching
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let remote = try await store.remoteCandidates(hillFormula: formula)
                guard !Task.isCancelled else { return }
                if remote.isEmpty {
                    self.state = .noMatch
                } else {
                    self.settle(on: remote, store: store)
                }
            } catch let error as PubChemError {
                guard !Task.isCancelled else { return }
                switch error {
                case .notFound: self.state = .noMatch
                case .canceled: break
                default: self.state = .failed(error.userMessage)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.state = .failed(PubChemError.malformed("").userMessage)
            }
        }
    }

    /// One candidate resolves straight away; more than one is a choice.
    private func settle(on candidates: [CompoundMatchCandidate], store: CompoundStore) {
        if candidates.count == 1, let only = candidates.first {
            choose(only, store: store)
        } else {
            state = .choices(candidates)
        }
    }

    /// Resolves a chosen candidate to its full record.
    func choose(_ candidate: CompoundMatchCandidate, store: CompoundStore) {
        task?.cancel()
        if let local = candidate.local {
            state = .matched(local)
            return
        }
        state = .searching
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let compound = try await store.resolve(candidate)
                guard !Task.isCancelled else { return }
                self.state = .matched(compound)
            } catch let error as PubChemError {
                guard !Task.isCancelled, error != .canceled else { return }
                self.state = .failed(error.userMessage)
            } catch {
                guard !Task.isCancelled else { return }
                self.state = .failed(PubChemError.malformed("").userMessage)
            }
        }
    }

    /// Keeps an unmatched composition, as exactly that.
    func saveHypothetical(store: CompoundStore, progress: ProgressStore, catalog: ElementCatalog) {
        guard case .noMatch = state else { return }
        let compound = ChemicalCompound.hypothetical(composition: composition, catalog: catalog)
        store.remember(compound)
        progress.setCompoundSaved(compound.id, true)
        state = .hypothetical(compound)
    }
}
