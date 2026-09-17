import Foundation
import Observation
import SwiftData

/// Everything the app knows about compounds, behind one door.
///
/// Three sources, always consulted in this order: the bundled catalog, the
/// on-device cache of compounds the learner has looked up, and PubChem. The
/// first two work offline; the third is only ever asked for something the
/// learner typed or built, one short request at a time.
@MainActor
@Observable
final class CompoundStore {
    let catalog: CompoundCatalog
    @ObservationIgnored private let cache: CompoundCache
    @ObservationIgnored let client: PubChemClient
    /// False in the UI-test build unless it explicitly asks for the stub.
    let isOnlineLookupEnabled: Bool

    /// Bumped whenever the cache changes, so lists that read it refresh.
    private(set) var cacheVersion = 0

    init(
        container: ModelContainer?,
        catalog: CompoundCatalog = CompoundCatalog.loadFromApplicationBundle(),
        client: PubChemClient? = nil,
        isOnlineLookupEnabled: Bool = true
    ) {
        self.catalog = catalog
        self.cache = CompoundCache(container: container)
        self.client = client ?? PubChemClient()
        self.isOnlineLookupEnabled = isOnlineLookupEnabled
    }

    // MARK: - Local reads

    /// The compound behind an identifier, from the bundle or the cache.
    ///
    /// `cacheVersion` is read deliberately. Study resolves its favorites and
    /// saved compounds through here, and the cache is not itself observable —
    /// so without this read, favoriting a compound that had just been fetched
    /// left the shelf empty until something else happened to redraw it.
    func compound(id: String) -> ChemicalCompound? {
        _ = cacheVersion
        return catalog.compound(id: id) ?? cache.compound(id: id)
    }

    func compound(cid: Int) -> ChemicalCompound? {
        _ = cacheVersion
        return catalog.compound(cid: cid) ?? cache.compound(cid: cid)
    }

    /// Compounds the learner has fetched or saved, newest name-sorted.
    var cachedCompounds: [ChemicalCompound] {
        _ = cacheVersion
        return cache.all
    }

    /// Bundled and cached compounds, deduplicated by identity.
    var allKnownCompounds: [ChemicalCompound] {
        var seen = Set<String>()
        return (catalog.compounds + cachedCompounds).filter { seen.insert($0.id).inserted }
    }

    /// Search over everything on the device: the catalog first, then the
    /// cache, ranked the same way.
    func localSearch(_ query: String, limit: Int = 12) -> [ChemicalCompound] {
        let bundled = catalog.search(query, limit: limit)
        guard bundled.count < limit else { return bundled }
        let cachedOnly = cachedCompounds.filter { catalog.compound(id: $0.id) == nil }
        let extra = CompoundCatalog(compounds: cachedOnly).search(query, limit: limit - bundled.count)
        return bundled + extra
    }

    /// Every local compound with this Hill formula, as candidates.
    func localCandidates(hillFormula: String) -> [CompoundMatchCandidate] {
        let bundled = catalog.compounds(hillFormula: hillFormula)
        let cached = cachedCompounds.filter {
            $0.hillFormula.lowercased() == hillFormula.lowercased() && catalog.compound(id: $0.id) == nil
                && !$0.isHypothetical
        }
        return (bundled + cached).map(CompoundMatchCandidate.init(local:))
    }

    // MARK: - Network

    /// Name search on PubChem, with local records attached where the app
    /// already has them.
    func remoteSearch(name: String) async throws -> [CompoundMatchCandidate] {
        guard isOnlineLookupEnabled else { return [] }
        let hits = try await client.search(name: name)
        return attachLocal(hits)
    }

    /// Formula search on PubChem.
    ///
    /// Many compounds can share a formula, and all of them come back — neutral
    /// species and ions alike, ranked but never filtered down to one. The
    /// page carries a cursor so "Load more" costs a page of properties rather
    /// than a second search.
    func remoteCandidates(hillFormula: String) async throws -> FormulaSearchPage {
        guard isOnlineLookupEnabled else { return .empty }
        let page = try await client.search(hillFormula: hillFormula)
        return page.replacingCandidates(attachLocal(page.candidates))
    }

    /// The next page of a formula search already under way.
    func moreCandidates(after cursor: FormulaSearchCursor) async throws -> FormulaSearchPage {
        guard isOnlineLookupEnabled else { return .empty }
        let page = try await client.page(of: cursor)
        return page.replacingCandidates(attachLocal(page.candidates))
    }

    /// Whatever the learner typed, resolved to compounds.
    ///
    /// The classifier decides which PubChem namespace the text belongs to;
    /// this dispatches to it. A name, a formula, a CID, a SMILES string, an
    /// InChI or an InChIKey all arrive through the same field and all work.
    func remoteSearch(query: ChemicalQuery) async throws -> [CompoundMatchCandidate] {
        guard isOnlineLookupEnabled else { return [] }
        switch query {
        case .empty:
            return []
        case .name(let name):
            return attachLocal(try await client.search(name: name))
        case .formula(_, let text):
            let hill = ChemicalFormulaParser.parse(text)?.hill() ?? text
            return try await remoteCandidates(hillFormula: hill).candidates
        case .cid(let cid):
            return attachLocal(try await client.candidates(cids: [cid]))
        case .smiles(let smiles):
            return attachLocal(try await client.search(smiles: smiles))
        case .inchi(let inchi):
            return attachLocal(try await client.search(inchi: inchi))
        case .inchiKey(let key):
            return attachLocal(try await client.search(inchiKey: key))
        }
    }

    /// Name suggestions while the learner is still typing. Only for names:
    /// a formula, an identifier or a structure string has an exact answer.
    func suggestions(for query: ChemicalQuery) async throws -> [String] {
        guard isOnlineLookupEnabled, case .name(let name) = query else { return [] }
        return try await client.suggestions(startingWith: name)
    }

    /// The full compound for a candidate: what the app already holds, or a
    /// fetch that is then cached so it works offline from now on.
    func resolve(_ candidate: CompoundMatchCandidate) async throws -> ChemicalCompound {
        if let local = candidate.local { return local }
        if let known = compound(cid: candidate.cid) { return known }
        guard isOnlineLookupEnabled else { throw PubChemError.offline }
        let fetched = try await client.compound(cid: candidate.cid)
        remember(fetched)
        return fetched
    }

    /// Fetches a compound by CID, or returns the local record.
    func compoundLoadingIfNeeded(cid: Int) async throws -> ChemicalCompound {
        if let known = compound(cid: cid) { return known }
        guard isOnlineLookupEnabled else { throw PubChemError.offline }
        let fetched = try await client.compound(cid: cid)
        remember(fetched)
        return fetched
    }

    func remember(_ compound: ChemicalCompound) {
        cache.store(compound)
        cacheVersion += 1
    }

    /// Makes sure a compound will still resolve by identifier afterwards.
    ///
    /// Anything the learner attaches state to — a favorite, a saved study
    /// item — has to be findable by `compound(id:)` later, and a record that
    /// came from PubChem lives only in the cache. Progress and the compound
    /// itself are stored separately on purpose, so this is what keeps the two
    /// halves resolvable: call it before writing the state, never after.
    /// A bundled record is already permanent, so this does nothing for one.
    func retain(_ compound: ChemicalCompound) {
        guard catalog.compound(id: compound.id) == nil else { return }
        remember(compound)
    }

    func forget(id: String) {
        cache.remove(id: id)
        cacheVersion += 1
    }

    private func attachLocal(_ hits: [CompoundMatchCandidate]) -> [CompoundMatchCandidate] {
        hits.map { hit in
            guard let local = compound(cid: hit.cid) else { return hit }
            return CompoundMatchCandidate(local: local)
        }
    }
}
