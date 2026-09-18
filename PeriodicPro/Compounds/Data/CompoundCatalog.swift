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
                name: Self.folded(compound.preferredName),
                names: compound.alternateNames.map(Self.folded),
                formula: ElementSearch.normalize(CompoundFormula.unsubscripted(compound.formula)),
                hillFormula: ElementSearch.normalize(compound.hillFormula),
                iupac: Self.folded(compound.iupacName ?? "")
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
        let query = folded(CompoundFormula.unsubscripted(rawQuery))
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
        // Nothing matched as written. Try it as a misspelling — but only now,
        // so a query that matches something exactly can never be beaten by a
        // near miss on something else.
        if scored.isEmpty {
            let tolerance = Self.editTolerance(for: query.count)
            guard tolerance > 0 else { return [] }
            var best: (distance: Int, entry: SearchEntry)?
            for entry in entries {
                for name in [entry.name] + entry.names {
                    let distance = Self.editDistance(query, name, cap: tolerance)
                    guard distance <= tolerance else { continue }
                    if let current = best, current.distance <= distance { continue }
                    best = (distance, entry)
                }
            }
            guard let best else { return [] }
            return [best.entry.compound]
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

    // MARK: - Spelling and near misses

    /// The same chemical spelled two ways. British on the left, American on
    /// the right, because the catalog and PubChem both use American.
    ///
    /// Applied to the index and to the query alike, so "sulfuric acid" and
    /// "sulfuric acid" are one string by the time anything is compared. A
    /// learner taught one spelling should not have to know the other exists.
    private static let spellings: [(String, String)] = [
        ("sulph", "sulf"),
        ("aluminum", "aluminum"),
        ("cesium", "cesium"),
        ("glycerine", "glycerin"),
    ]

    /// Case-folded, punctuation-stripped, and spelled the way the catalog
    /// spells it.
    static func folded(_ text: String) -> String {
        var value = ElementSearch.normalize(text)
        for (british, american) in spellings {
            value = value.replacingOccurrences(of: british, with: american)
        }
        return value
    }

    /// How far wrong a query of this length may be and still be understood.
    ///
    /// Nothing for a short query: at four characters or fewer, one edit is the
    /// difference between two real compounds, and guessing there would answer
    /// a question the learner did not ask. The allowance grows with the word
    /// because a long name has more room to be mistyped without becoming a
    /// different name.
    static func editTolerance(for length: Int) -> Int {
        switch length {
        case ...4: return 0
        case 5...7: return 1
        default: return 2
        }
    }

    /// Damerau-Levenshtein distance, abandoned once it passes `cap`.
    ///
    /// Transpositions count as one edit rather than two, because swapping a
    /// pair of letters is the commonest typing mistake there is — "hydrogne"
    /// for "hydrogen". The cap is not just an optimisation: a row whose best
    /// value already exceeds it can only get worse, so returning early is the
    /// same answer sooner.
    static func editDistance(_ lhs: String, _ rhs: String, cap: Int) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        guard abs(a.count - b.count) <= cap else { return cap + 1 }
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var twoAgo: [Int] = []
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            var bestInRow = current[0]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                var value = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    value = min(value, twoAgo[j - 2] + 1)
                }
                current[j] = value
                bestInRow = min(bestInRow, value)
            }
            guard bestInRow <= cap else { return cap + 1 }
            twoAgo = previous
            previous = current
        }
        return previous[b.count]
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

    /// The bundled catalog, loaded once, for callers with no store to read it
    /// from. Empty rather than crashing if the resource is unreadable.
    static let bundled: CompoundCatalog = loadFromApplicationBundle()

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
