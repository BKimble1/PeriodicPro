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
    var utcCalendar = calendar
    utcCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return ProgressStore(
        container: PersistenceController.makeInMemoryContainer(),
        isEphemeral: false,
        calendar: utcCalendar
    )
}
