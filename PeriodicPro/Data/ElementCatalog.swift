import Foundation

/// Marker used to locate the app bundle from inside a hosted test bundle.
final class BundleToken {}

/// The immutable, bundled element dataset plus the lookup indexes the UI needs.
///
/// Loading happens once at launch from `elements.json`. The catalog is a value
/// type holding only `Sendable` data, so it is safe to share everywhere.
struct ElementCatalog: Sendable {
    let elements: [ChemicalElement]

    private let byAtomicNumber: [Int: ChemicalElement]
    private let bySymbol: [String: ChemicalElement]

    init(elements: [ChemicalElement]) {
        let sorted = elements.sorted { $0.atomicNumber < $1.atomicNumber }
        self.elements = sorted
        self.byAtomicNumber = Dictionary(sorted.map { ($0.atomicNumber, $0) },
                                         uniquingKeysWith: { first, _ in first })
        self.bySymbol = Dictionary(sorted.map { ($0.symbol.lowercased(), $0) },
                                   uniquingKeysWith: { first, _ in first })
    }

    var isEmpty: Bool { elements.isEmpty }
    var count: Int { elements.count }

    func element(atomicNumber: Int) -> ChemicalElement? { byAtomicNumber[atomicNumber] }
    func element(symbol: String) -> ChemicalElement? { bySymbol[symbol.lowercased()] }

    func elements(in category: ElementCategory) -> [ChemicalElement] {
        elements.filter { $0.category == category }
    }

    /// Elements on the seven main rows of the table.
    var mainTableElements: [ChemicalElement] { elements.filter { $0.gridY <= 7 } }
    var lanthanideRow: [ChemicalElement] { elements.filter { $0.gridY == 9 } }
    var actinideRow: [ChemicalElement] { elements.filter { $0.gridY == 10 } }
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
