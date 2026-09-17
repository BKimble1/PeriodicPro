import Observation
import OSLog
import SwiftData
import SwiftUI

/// Entry point. Builds the two long-lived services and hands them to the
/// view hierarchy through the environment.
@main
@MainActor
struct PeriodicProApp: App {
    @State private var services = AppServices()
    @State private var hasLaunched = false
    @Environment(\.scenePhase) private var scenePhase

    /// Whether there is an app worth showing yet: a dataset resolved one way
    /// or the other, and — outside the UI tests, which never contact StoreKit
    /// — an answer about the learner's subscription, so nothing opens showing
    /// a Pro lock it is about to take away.
    private var isReady: Bool {
        guard !services.catalog.isEmpty || services.catalogError != nil else { return false }
        if RuntimeFlags.isUITesting { return true }
        return services.store.entitlement != .unknown
    }

    var body: some Scene {
        WindowGroup {
            // `ProgressStore` owns the app's only `ModelContext`; no view uses
            // `@Query` or `\.modelContext`, so injecting a second context here
            // would only create two views of the same store.
            RootView(catalogError: services.catalogError)
                .environment(\.elementCatalog, services.catalog)
                .environment(services.progress)
                .environment(services.store)
                .environment(services.compounds)
                .environment(services.savedQuizzes)
                .tint(AppColor.accent)
                // Starting the StoreKit listener here rather than in
                // `AppServices.init` keeps the initializer synchronous and
                // means a transaction that completed while the app was closed
                // is picked up as soon as there is a scene to show it in.
                .task { services.store.start() }
                // The free daily allowance is measured against the current
                // calendar day. Backgrounding the app overnight is the normal
                // case, so without this a learner who used their rounds last
                // night would still be locked out this morning.
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    services.progress.refreshCompletedRoundsToday()
                }
                // The loading screen sits over the whole window, above the
                // tabs and above onboarding, so the first thing a learner
                // sees is Elemora rather than a half-built tab bar.
                .overlay {
                    if !hasLaunched {
                        LaunchScreenView(isReady: isReady && !RuntimeFlags.holdsLaunchScreen) {
                            withAnimation(Theme.Motion.soft) { hasLaunched = true }
                        }
                        .transition(.opacity)
                    }
                }
        }
    }
}

/// Owns the things the whole app depends on: the bundled element catalog,
/// the learner's local progress, the compound catalog and cache, and the
/// saved quizzes. Built once, at launch.
@MainActor
@Observable
final class AppServices {
    let catalog: ElementCatalog
    let progress: ProgressStore
    /// The app's only StoreKit connection. Views read entitlement state from
    /// here; none of them talks to StoreKit directly.
    let store: SubscriptionManager
    /// Bundled compounds, the on-device cache, and the PubChem client.
    let compounds: CompoundStore
    /// The learner's own quizzes.
    let savedQuizzes: SavedQuizStore
    /// Non-nil when `elements.json` could not be read, which drives the
    /// data-unavailable screen instead of an empty, silent table.
    let catalogError: String?

    init() {
        let outcome = RuntimeFlags.isUITesting
            ? PersistenceController.makeTestingOutcome()
            : PersistenceController.makeOutcome()

        // The appearance is the one preference stored in the simulator's real
        // defaults rather than in the in-memory container, so a UI-test launch
        // starts from System unless it explicitly asked to keep what is there.
        if RuntimeFlags.isUITesting, !RuntimeFlags.keepsAppearance {
            UserDefaults.standard.removeObject(forKey: AppAppearance.storageKey)
        }

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
        self.store = SubscriptionManager()
        self.compounds = Self.makeCompoundStore(container: outcome.container)
        self.savedQuizzes = SavedQuizStore(container: outcome.container)
    }

    /// The compound store, with the network wired the way this launch needs.
    ///
    /// A UI-test launch makes no network request at all unless it explicitly
    /// asks for the catalog-backed stub, which answers PubChem's endpoints
    /// from the bundled data through the real request and parsing code.
    private static func makeCompoundStore(container: ModelContainer?) -> CompoundStore {
        let catalog = CompoundCatalog.loadFromApplicationBundle()
        if catalog.loadError != nil {
            Logger(subsystem: "com.periodicpro.app", category: "compounds")
                .error("Compound catalog unavailable: \(catalog.loadError ?? "", privacy: .public)")
        }
        guard RuntimeFlags.isUITesting else {
            return CompoundStore(container: container, catalog: catalog)
        }
        guard RuntimeFlags.stubsCompoundNetwork else {
            return CompoundStore(container: container, catalog: catalog, isOnlineLookupEnabled: false)
        }
        let client = PubChemClient(
            transport: CatalogBackedStubTransport(catalog: catalog),
            maximumRetries: 0,
            minimumGap: .zero
        )
        return CompoundStore(container: container, catalog: catalog, client: client)
    }
}
