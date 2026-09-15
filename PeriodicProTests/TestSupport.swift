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
