import OSLog
import SwiftData
import SwiftUI

@main
@MainActor
struct PeriodicProApp: App {
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.elementCatalog, services.catalog)
                .environment(services.progress)
                .tint(AppColor.accent)
        }
        .modelContainer(services.container)
    }
}

/// Owns the two things the whole app depends on: the bundled element catalog
/// and the learner's local progress. Built once, at launch.
@MainActor
@Observable
final class AppServices {
    let catalog: ElementCatalog
    let progress: ProgressStore
    let container: ModelContainer
    /// Non-nil when `elements.json` could not be read, which drives the
    /// data-unavailable screen instead of an empty, silent table.
    let catalogError: String?

    init() {
        let outcome: PersistenceController.Outcome
        let catalogResult: Result<ElementCatalog, Error>

        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            // UI tests always start from a clean, in-memory store so runs are
            // independent of whatever is left on the simulator.
            outcome = PersistenceController.Outcome(
                container: PersistenceController.makeInMemoryContainer(),
                recoveredFromCorruptStore: false,
                isEphemeral: false
            )
        } else {
            outcome = PersistenceController.makeOutcome()
        }

        catalogResult = ElementCatalog.loadFromApplicationBundle()

        switch catalogResult {
        case .success(let catalog):
            self.catalog = catalog
            self.catalogError = nil
        case .failure(let error):
            self.catalog = ElementCatalog(elements: [])
            self.catalogError = String(describing: error)
            Logger(subsystem: "com.periodicpro.app", category: "catalog")
                .fault("Element catalog failed to load: \(String(describing: error), privacy: .public)")
        }

        self.container = outcome.container
        self.progress = ProgressStore(container: outcome.container, isEphemeral: outcome.isEphemeral)
    }
}
