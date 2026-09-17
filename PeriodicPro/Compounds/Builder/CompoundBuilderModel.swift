import Foundation
import Observation

/// The state of the Compound Builder: the composition being assembled and
/// what is known about it.
///
/// The identification is honest by construction. A formula is matched against
/// the bundled catalog and the on-device cache first, then PubChem; one match
/// is named, several are offered for the learner to choose between, and none
/// is reported as exactly that — a miss, never a discovery. A failed request
/// (offline, a timeout, PubChem busy) is a separate state, because "we could
/// not ask" is not "nothing is known". A name is never derived from
/// stoichiometry: every name shown here belongs to a record.
///
/// Identification now happens as the composition changes rather than behind a
/// button. Local data is consulted immediately — it is a dictionary lookup —
/// and PubChem only after the learner has stopped editing for
/// `lookupDebounce`, with the previous request canceled, so holding down the
/// plus button is one request rather than thirty.
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

    /// Where the answer on screen came from, for the status line.
    enum LookupOrigin: Equatable, Sendable {
        case local
        case remote
    }

    /// How many different elements one composition may name.
    ///
    /// Sixteen, not six. Six ruled out a great deal of real chemistry —
    /// chlorophyll a is C₅₅H₇₂MgN₄O₅, and any organometallic with a couple of
    /// halogens passes six without being exotic. This is a resource bound on
    /// the tray, not a claim about what molecules can contain.
    static let maximumDistinctElements = 16

    /// How many atoms of one element a composition may name.
    ///
    /// Nine hundred and ninety-nine, which is a software safety limit rather
    /// than a statement about chemistry. The thirty it replaces was the second
    /// kind: it made cholesterol (C₂₇H₄₆O) unbuildable because of the
    /// forty-six hydrogens, and β-carotene (C₄₀H₅₆) unbuildable twice over.
    /// Real formulas run far past both.
    static let maximumCountPerElement = 999

    /// Every atom in the composition, bounded so a formula cannot be made
    /// arbitrarily large by adding elements.
    ///
    /// Separate from what gets drawn. A composition may name thousands of
    /// atoms; whether a molecule of that size is rendered atom by atom is a
    /// question for the structure views, which have their own thresholds, and
    /// never a reason to refuse the formula.
    static let maximumTotalAtoms = 4_000

    /// How long the learner has to stop editing before PubChem is asked.
    static let lookupDebounce: Duration = .milliseconds(650)

    private(set) var entries: [Entry] = []
    private(set) var state: LookupState = .idle
    private(set) var origin: LookupOrigin = .local
    /// How many times PubChem has been asked in this session. Read by a test
    /// that proves the builder debounces rather than requesting per tap.
    private(set) var remoteRequestCount = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var store: CompoundStore?
    @ObservationIgnored private var catalog: ElementCatalog = .bundledOrEmpty

    var isEmpty: Bool { entries.isEmpty }
    var canAddElement: Bool { entries.count < Self.maximumDistinctElements }
    /// The range a count may be typed into.
    static var countRange: ClosedRange<Int> { 1...maximumCountPerElement }

    /// Atomic number → count.
    var composition: [Int: Int] {
        Dictionary(entries.map { ($0.element.atomicNumber, $0.count) }, uniquingKeysWith: { first, _ in first })
    }

    /// Wires the model to the app's data. Until this is called the builder is
    /// inert — every mutation just clears the last answer — which is what the
    /// unit tests exercise when they drive `lookUp` by hand.
    func configure(store: CompoundStore, catalog: ElementCatalog) {
        self.store = store
        self.catalog = catalog
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

    /// One line describing what the builder is doing about this composition.
    var statusMessage: String? {
        switch state {
        case .idle: return nil
        case .searching:
            return origin == .remote
                ? "No local match — checking PubChem…"
                : "Checking known compounds…"
        case .matched:
            return origin == .local ? "Matched in the Elemora catalog" : "Matched on PubChem"
        case .choices(let candidates):
            return "\(candidates.count) known compounds share this formula"
        case .noMatch: return "No known match found"
        case .hypothetical: return "Saved as a hypothetical composition"
        case .failed(let message): return message
        }
    }

    // MARK: - Composition

    func add(_ element: ChemicalElement) {
        if let index = entries.firstIndex(where: { $0.element == element }) {
            increment(entries[index].element.atomicNumber)
            return
        }
        guard canAddElement, totalAtoms < Self.maximumTotalAtoms else { return }
        entries.append(Entry(element: element, count: 1))
        compositionChanged()
    }

    func increment(_ atomicNumber: Int) {
        guard let index = entries.firstIndex(where: { $0.element.atomicNumber == atomicNumber }) else { return }
        setCount(entries[index].count + 1, for: atomicNumber)
    }

    /// Sets a count directly — what typing a number into the tray does.
    ///
    /// Clamped rather than rejected: a learner who types 1500 gets the cap,
    /// which is a visible answer, instead of a field that silently refuses
    /// them. Zero and below remove the element, which is what the minus button
    /// at one already does.
    func setCount(_ count: Int, for atomicNumber: Int) {
        guard let index = entries.firstIndex(where: { $0.element.atomicNumber == atomicNumber }) else { return }
        guard count >= 1 else {
            remove(atomicNumber)
            return
        }
        let headroom = Self.maximumTotalAtoms - (totalAtoms - entries[index].count)
        let clamped = min(count, Self.maximumCountPerElement, max(1, headroom))
        guard clamped != entries[index].count else { return }
        entries[index].count = clamped
        compositionChanged()
    }

    /// Parses what was typed. `nil` for anything that is not a whole number,
    /// so the field can say so rather than quietly becoming 1.
    static func parseCount(_ text: String) -> Int? {
        let digits = text.trimmingCharacters(in: .whitespaces)
        guard !digits.isEmpty, digits.count <= 6, digits.allSatisfy(\.isWholeNumber) else { return nil }
        return Int(digits)
    }

    func decrement(_ atomicNumber: Int) {
        guard let index = entries.firstIndex(where: { $0.element.atomicNumber == atomicNumber }) else { return }
        if entries[index].count > 1 {
            entries[index].count -= 1
            compositionChanged()
        } else {
            remove(atomicNumber)
        }
    }

    func remove(_ atomicNumber: Int) {
        entries.removeAll { $0.element.atomicNumber == atomicNumber }
        compositionChanged()
    }

    func clear() {
        entries = []
        compositionChanged()
    }

    func resetLookup() {
        task?.cancel()
        task = nil
        state = .idle
        origin = .local
    }

    // MARK: - Automatic identification

    /// Called after every change to the tray.
    private func compositionChanged() {
        guard let store else {
            resetLookup()
            return
        }
        identify(store: store, catalog: catalog, debounced: true)
    }

    /// Local data now, PubChem after a pause.
    ///
    /// The local half is synchronous, so the formula and its verified name
    /// appear in the same frame as the atom that produced them. Only a formula
    /// nothing on the device knows reaches the network, and only once the
    /// learner has stopped changing it.
    func identify(store: CompoundStore, catalog: ElementCatalog, debounced: Bool) {
        task?.cancel()
        task = nil
        guard !entries.isEmpty else {
            state = .idle
            origin = .local
            return
        }
        let formula = hillFormula(catalog: catalog)
        let local = store.localCandidates(hillFormula: formula)
        if !local.isEmpty {
            origin = .local
            settle(on: local, store: store)
            return
        }
        origin = .remote
        guard store.isOnlineLookupEnabled else {
            // Not a miss. Nothing on the device knows this formula and PubChem
            // could not be asked, which is a different claim entirely.
            state = .failed(PubChemError.offline.userMessage)
            return
        }
        state = .searching
        task = Task { [weak self] in
            if debounced {
                try? await Task.sleep(for: Self.lookupDebounce)
                guard !Task.isCancelled else { return }
            }
            guard let self else { return }
            await self.fetchRemote(hillFormula: formula, store: store)
        }
    }

    /// The explicit "check again" action. Same path, no debounce.
    func lookUp(store: CompoundStore, catalog: ElementCatalog) {
        identify(store: store, catalog: catalog, debounced: false)
    }

    private func fetchRemote(hillFormula formula: String, store: CompoundStore) async {
        remoteRequestCount += 1
        do {
            let remote = try await store.remoteCandidates(hillFormula: formula)
            guard !Task.isCancelled else { return }
            if remote.isEmpty {
                state = .noMatch
            } else {
                settle(on: remote, store: store)
            }
        } catch let error as PubChemError {
            guard !Task.isCancelled else { return }
            switch error {
            case .notFound: state = .noMatch
            case .canceled: break
            default: state = .failed(error.userMessage)
            }
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(PubChemError.malformed("").userMessage)
        }
    }

    /// One candidate resolves straight away; more than one is a choice.
    ///
    /// This is the whole of the "auto name" rule. A formula that maps to
    /// exactly one record gets that record's name; a formula that maps to two
    /// gets neither of them, because C₂H₆O is ethanol and dimethyl ether and
    /// picking one would be a guess dressed up as an answer.
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
