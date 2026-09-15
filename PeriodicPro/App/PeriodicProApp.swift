import OSLog
import SwiftData
import SwiftUI

/// Entry point. Builds the two long-lived services and hands them to the
/// view hierarchy through the environment.
@main
@MainActor
struct PeriodicProApp: App {
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            // `ProgressStore` owns the app's only `ModelContext`; no view uses
            // `@Query` or `\.modelContext`, so injecting a second context here
            // would only create two views of the same store.
            RootView(catalogError: services.catalogError)
                .environment(\.elementCatalog, services.catalog)
                .environment(services.progress)
                .tint(AppColor.accent)
        }
    }
}

/// Owns the two things the whole app depends on: the bundled element catalog
/// and the learner's local progress. Built once, at launch.
@MainActor
@Observable
final class AppServices {
    let catalog: ElementCatalog
    let progress: ProgressStore
    /// Non-nil when `elements.json` could not be read, which drives the
    /// data-unavailable screen instead of an empty, silent table.
    let catalogError: String?

    init() {
        let outcome = RuntimeFlags.isUITesting
            ? PersistenceController.makeTestingOutcome()
            : PersistenceController.makeOutcome()

        switch ElementCatalog.loadFromApplicationBundle() {
        case .success(let catalog):
            self.catalog = catalog
            self.catalogError = nil
        case .failure(let error):
            self.catalog = ElementCatalog(elements: [])
            self.catalogError = String(describing: error)
            Logger(subsystem: "com.periodicpro.app", category: "catalog")
                .fault("Element catalog failed to load: \(String(describing: error), privacy: .public)")
        }

        self.progress = ProgressStore(container: outcome.container, storage: outcome.storage)
    }
}
