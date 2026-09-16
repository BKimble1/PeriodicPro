import Foundation
import OSLog

/// The structure profiles for all 118 elements, loaded once from
/// `structures.json`.
///
/// Missing data is never papered over with a generic lattice. If the file
/// cannot be read, or an element has no entry, `entry(atomicNumber:)` returns
/// an explicit `unknown` profile that says the structure is not established —
/// which is untrue for gold, but is the honest thing a broken bundle can say,
/// and `StructureProfileTests` guarantees the shipped file has all 118.
struct ElementStructureCatalog: Sendable {
    let entries: [Int: ElementStructureEntry]
    /// Non-nil when the bundled file could not be read.
    let loadError: String?

    static let expectedCount = 118

    init(entries: [ElementStructureEntry], loadError: String? = nil) {
        self.entries = Dictionary(entries.map { ($0.atomicNumber, $0) },
                                  uniquingKeysWith: { first, _ in first })
        self.loadError = loadError
    }

    var count: Int { entries.count }
    var isComplete: Bool { entries.count == Self.expectedCount }

    func entry(atomicNumber: Int) -> ElementStructureEntry {
        entries[atomicNumber] ?? Self.missingEntry(atomicNumber: atomicNumber)
    }

    /// What an element with no data gets: the atom, labeled honestly.
    static func missingEntry(atomicNumber: Int) -> ElementStructureEntry {
        ElementStructureEntry(
            atomicNumber: atomicNumber,
            primary: ElementStructureProfile(
                representationKind: .unknown,
                allotropeName: nil,
                phase: .unknown,
                crystalSystem: nil,
                latticeType: nil,
                spaceGroup: nil,
                latticeParameters: nil,
                molecularGeometry: nil,
                bondOrders: nil,
                bondLengthAngstrom: nil,
                coordination: nil,
                temperatureContext: "not available",
                isExperimentallyEstablished: false,
                source: "No structure data is bundled for this element.",
                notes: "Bulk crystal structure not available in this build.",
                geometry: StructureGeometrySpec(
                    template: "atom", cOverA: nil, basis: nil, contactFactor: nil, discreteBonds: nil
                ),
                pickerTitle: nil
            ),
            alternatives: []
        )
    }

    // MARK: - Loading

    enum LoadError: Error, CustomStringConvertible {
        case resourceMissing
        case decodingFailed(String)

        var description: String {
            switch self {
            case .resourceMissing: return "structures.json is missing from the app bundle."
            case .decodingFailed(let reason): return "structures.json could not be read: \(reason)"
            }
        }
    }

    static func load(from bundle: Bundle) throws -> ElementStructureCatalog {
        guard let url = bundle.url(forResource: "structures", withExtension: "json") else {
            throw LoadError.resourceMissing
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([ElementStructureEntry].self, from: data)
            return ElementStructureCatalog(entries: decoded)
        } catch {
            throw LoadError.decodingFailed(String(describing: error))
        }
    }

    /// The main bundle first, then the bundle holding the app's own code —
    /// which differs when unit tests run inside a host app.
    static func loadFromApplicationBundle() -> ElementStructureCatalog {
        var lastError: Error = LoadError.resourceMissing
        for bundle in [Bundle.main, Bundle(for: BundleToken.self)] {
            do {
                return try load(from: bundle)
            } catch {
                lastError = error
            }
        }
        Logger(subsystem: "com.periodicpro.app", category: "structures")
            .fault("Structure profiles failed to load: \(String(describing: lastError), privacy: .public)")
        return ElementStructureCatalog(entries: [], loadError: String(describing: lastError))
    }

    /// Loaded on first use and shared: the profiles are immutable data.
    static let shared = loadFromApplicationBundle()
}
