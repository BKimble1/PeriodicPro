import Foundation
import OSLog

/// The bundled starter catalog: fifty verified compounds, indexed for search.
///
/// Built once from `compounds.json`. Everything the search and the detail
/// page need offline lives here; PubChem only adds compounds this file does
/// not have.
struct CompoundCatalog: Sendable {
    let compounds: [ChemicalCompound]
    let loadError: String?

    private let byID: [String: ChemicalCompound]
    private let byCID: [Int: ChemicalCompound]
    private let byHillFormula: [String: [ChemicalCompound]]
    private let entries: [SearchEntry]

    /// Case-folded strings for one compound, folded once at load.
    struct SearchEntry: Sendable {
        let compound: ChemicalCompound
        let name: String
        let names: [String]
        let formula: String
        let hillFormula: String
        let iupac: String
    }

    init(compounds: [ChemicalCompound], loadError: String? = nil) {
        var seen = Set<String>()
        let unique = compounds.filter { seen.insert($0.id).inserted }
        self.compounds = unique
        self.loadError = loadError
        byID = Dictionary(unique.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        byCID = Dictionary(unique.compactMap { compound in
            compound.pubChemCID.map { ($0, compound) }
        }, uniquingKeysWith: { first, _ in first })
        byHillFormula = Dictionary(grouping: unique, by: { $0.hillFormula.lowercased() })
        entries = unique.map { compound in
            SearchEntry(
                compound: compound,
                name: ElementSearch.normalize(compound.preferredName),
                names: compound.alternateNames.map(ElementSearch.normalize),
                formula: ElementSearch.normalize(CompoundFormula.unsubscripted(compound.formula)),
                hillFormula: ElementSearch.normalize(compound.hillFormula),
                iupac: ElementSearch.normalize(compound.iupacName ?? "")
            )
        }
    }

    var count: Int { compounds.count }
    var isEmpty: Bool { compounds.isEmpty }

    func compound(id: String) -> ChemicalCompound? { byID[id] }
    func compound(cid: Int) -> ChemicalCompound? { byCID[cid] }

    /// Every bundled compound with this Hill formula — ethanol and dimethyl
    /// ether both answer to C2H6O.
    func compounds(hillFormula: String) -> [ChemicalCompound] {
        byHillFormula[hillFormula.lowercased()] ?? []
    }

    /// Ranked search: exact formula, name prefix, alternate-name prefix,
    /// name contains, IUPAC contains. Ties break by name so the order is
    /// stable and testable.
    func search(_ rawQuery: String, limit: Int = 12) -> [ChemicalCompound] {
        Self.search(rawQuery, in: entries, limit: limit)
    }

    static func search(_ rawQuery: String, in entries: [SearchEntry], limit: Int) -> [ChemicalCompound] {
        let query = ElementSearch.normalize(CompoundFormula.unsubscripted(rawQuery))
        guard !query.isEmpty, limit > 0 else { return [] }
        var scored: [(rank: Int, entry: SearchEntry)] = []
        for entry in entries {
            if entry.formula == query || entry.hillFormula == query {
                scored.append((0, entry))
            } else if entry.name == query {
                scored.append((0, entry))
            } else if entry.name.hasPrefix(query) {
                scored.append((1, entry))
            } else if entry.names.contains(where: { $0.hasPrefix(query) }) {
                scored.append((2, entry))
            } else if query.count >= 3, entry.name.contains(query) {
                scored.append((3, entry))
            } else if query.count >= 3, entry.names.contains(where: { $0.contains(query) }) {
                scored.append((4, entry))
            } else if query.count >= 4, entry.iupac.contains(query) {
                scored.append((5, entry))
            }
        }
        return scored
            .sorted { lhs, rhs in
                lhs.rank == rhs.rank
                    ? lhs.entry.compound.preferredName < rhs.entry.compound.preferredName
                    : lhs.rank < rhs.rank
            }
            .prefix(limit)
            .map(\.entry.compound)
    }

    // MARK: - Loading

    enum LoadError: Error, CustomStringConvertible {
        case resourceMissing
        case decodingFailed(String)

        var description: String {
            switch self {
            case .resourceMissing: return "compounds.json is missing from the app bundle."
            case .decodingFailed(let reason): return "compounds.json could not be read: \(reason)"
            }
        }
    }

    static func load(from bundle: Bundle) throws -> CompoundCatalog {
        guard let url = bundle.url(forResource: "compounds", withExtension: "json") else {
            throw LoadError.resourceMissing
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([ChemicalCompound].self, from: data)
            return CompoundCatalog(compounds: decoded)
        } catch {
            throw LoadError.decodingFailed(String(describing: error))
        }
    }

    static func loadFromApplicationBundle() -> CompoundCatalog {
        var lastError: Error = LoadError.resourceMissing
        for bundle in [Bundle.main, Bundle(for: BundleToken.self)] {
            do {
                return try load(from: bundle)
            } catch {
                lastError = error
            }
        }
        Logger(subsystem: "com.periodicpro.app", category: "compounds")
            .fault("Compound catalog failed to load: \(String(describing: lastError), privacy: .public)")
        return CompoundCatalog(compounds: [], loadError: String(describing: lastError))
    }
}
