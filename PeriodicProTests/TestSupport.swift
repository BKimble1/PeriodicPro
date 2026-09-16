import Foundation
import SwiftData
import Testing
@testable import PeriodicPro

/// Loads the bundled dataset once for the whole test run.
enum TestCatalog {
    static let shared: ElementCatalog = {
        switch ElementCatalog.loadFromApplicationBundle() {
        case .success(let catalog):
            return catalog
        case .failure(let error):
            fatalError("elements.json could not be loaded for tests: \(error)")
        }
    }()

    static func element(_ symbol: String) -> ChemicalElement {
        guard let element = shared.element(symbol: symbol) else {
            fatalError("Missing element \(symbol) in test catalog")
        }
        return element
    }
}

/// A throwaway, in-memory progress store so tests never touch real user data.
@MainActor
func makeTestStore(calendar: Calendar = Calendar(identifier: .gregorian)) -> ProgressStore {
    ProgressStore(
        container: PersistenceController.makeInMemoryContainer(),
        storage: .memoryOnlyForTesting,
        calendar: utcCalendar(calendar)
    )
}

/// A store with no SwiftData container at all, exercising the path the app
/// falls back to when persistence is unavailable.
@MainActor
func makeContainerlessStore(calendar: Calendar = Calendar(identifier: .gregorian)) -> ProgressStore {
    ProgressStore(container: nil, storage: .memoryOnlyFallback, calendar: utcCalendar(calendar))
}

private func utcCalendar(_ base: Calendar) -> Calendar {
    var calendar = base
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return calendar
}

/// Locates the PubChem fixture files inside the test bundle.
///
/// Small, real-shaped JSON captured in PubChem's PUG REST schema, so the
/// parser tests never touch the network.
enum Fixtures {
    private final class Token {}

    static func url(_ name: String) -> URL? {
        let bundle = Bundle(for: Token.self)
        return bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? bundle.url(forResource: name, withExtension: "json")
    }

    static func data(_ name: String) -> Data {
        guard let url = url(name), let data = try? Data(contentsOf: url) else {
            fatalError("Missing fixture \(name).json in the test bundle")
        }
        return data
    }
}

/// The bundled compound catalog, loaded once for the whole test run.
enum TestCompounds {
    static let catalog = CompoundCatalog.loadFromApplicationBundle()

    static func compound(_ name: String) -> ChemicalCompound {
        guard let compound = catalog.compounds.first(where: { $0.preferredName == name }) else {
            fatalError("Missing compound \(name) in the bundled catalog")
        }
        return compound
    }
}
