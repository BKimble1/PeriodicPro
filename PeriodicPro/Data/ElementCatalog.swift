import Foundation

/// Marker used to locate the app bundle from inside a hosted test bundle.
final class BundleToken {}

/// The immutable, bundled element dataset plus every index the UI needs.
///
/// Built once at launch from `elements.json`. All the grouping, folding and
/// row-splitting happens here rather than inside view bodies, so scrolling the
/// table and typing in the search field cost nothing but a dictionary lookup.
struct ElementCatalog: Sendable {
    let elements: [ChemicalElement]

    /// Elements on the seven main rows of the table.
    let mainTableElements: [ChemicalElement]
    let lanthanideRow: [ChemicalElement]
    let actinideRow: [ChemicalElement]

    private let byAtomicNumber: [Int: ChemicalElement]
    private let bySymbol: [String: ChemicalElement]
    private let byCategory: [ElementCategory: [ChemicalElement]]
    private let searchEntries: [ElementSearch.Entry]

    init(elements: [ChemicalElement]) {
        // Sorted and deduplicated on the way in: a duplicate atomic number would
        // otherwise survive in `elements` while vanishing from the index, and
        // hand `ForEach` two views with the same identity.
        var seen = Set<Int>()
        let unique = elements
            .sorted { $0.atomicNumber < $1.atomicNumber }
            .filter { seen.insert($0.atomicNumber).inserted }

        self.elements = unique
        self.mainTableElements = unique.filter { $0.gridY <= 7 }
        self.lanthanideRow = unique.filter { $0.gridY == 9 }
        self.actinideRow = unique.filter { $0.gridY == 10 }
        self.byAtomicNumber = Dictionary(uniqueKeysWithValues: unique.map { ($0.atomicNumber, $0) })
        self.bySymbol = Dictionary(unique.map { ($0.symbol.lowercased(), $0) },
                                   uniquingKeysWith: { first, _ in first })
        self.byCategory = Dictionary(grouping: unique, by: \.category)
        self.searchEntries = ElementSearch.makeEntries(unique)
    }

    var isEmpty: Bool { elements.isEmpty }
    var count: Int { elements.count }

    func element(atomicNumber: Int) -> ChemicalElement? { byAtomicNumber[atomicNumber] }
    func element(symbol: String) -> ChemicalElement? { bySymbol[symbol.lowercased()] }

    func elements(in category: ElementCategory) -> [ChemicalElement] { byCategory[category] ?? [] }

    func count(of category: ElementCategory) -> Int { byCategory[category]?.count ?? 0 }

    /// Searches the prebuilt, prefolded index.
    func search(_ query: String, limit: Int = ElementSearch.resultLimit) -> [ChemicalElement] {
        ElementSearch.results(for: query, in: searchEntries, limit: limit)
    }
}

// MARK: - Loading

extension ElementCatalog {
    enum LoadError: Error, CustomStringConvertible {
        case resourceMissing
        case decodingFailed(String)

        var description: String {
            switch self {
            case .resourceMissing:
                return "elements.json is missing from the app bundle."
            case .decodingFailed(let reason):
                return "elements.json could not be read: \(reason)"
            }
        }
    }

    static func load(from bundle: Bundle) throws -> ElementCatalog {
        guard let url = bundle.url(forResource: "elements", withExtension: "json") else {
            throw LoadError.resourceMissing
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([ChemicalElement].self, from: data)
            return ElementCatalog(elements: decoded)
        } catch {
            throw LoadError.decodingFailed(String(describing: error))
        }
    }

    /// Searches the main bundle first, then the bundle that contains the app's
    /// own code (which differs when unit tests run inside a host app).
    static func loadFromApplicationBundle() -> Result<ElementCatalog, Error> {
        let candidates = [Bundle.main, Bundle(for: BundleToken.self)]
        var lastError: Error = LoadError.resourceMissing
        for bundle in candidates {
            do {
                return .success(try load(from: bundle))
            } catch {
                lastError = error
            }
        }
        return .failure(lastError)
    }
}
