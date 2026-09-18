import Observation
import OSLog
import SwiftData
import SwiftUI
import UserNotifications

/// Entry point. Builds the two long-lived services and hands them to the
/// view hierarchy through the environment.
@main
@MainActor
struct PeriodicProApp: App {
    @State private var services = AppServices()
    @State private var hasLaunched = false
    /// Held for the life of the app: `UNUserNotificationCenter` keeps its
    /// delegate weakly, and a delegate that is deallocated stops receiving
    /// taps without saying so.
    @State private var notificationDelegate = StudyNotificationDelegate()
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
                // While the loading screen is up, what is behind it is not
                // there as far as VoiceOver is concerned. Without this the
                // tabs and the table stay in the accessibility tree under a
                // cover that hides them visually, so a learner using
                // VoiceOver can swipe into a half-built table while the app
                // is still saying it is loading.
                .accessibilityHidden(!hasLaunched)
                .environment(\.elementCatalog, services.catalog)
                .environment(services.progress)
                .environment(services.store)
                .environment(services.compounds)
                .environment(services.savedQuizzes)
                .environment(services.notifications)
                .tint(AppColor.accent)
                // Starting the StoreKit listener here rather than in
                // `AppServices.init` keeps the initializer synchronous and
                // means a transaction that completed while the app was closed
                // is picked up as soon as there is a scene to show it in.
                .task { services.store.start() }
                // A cold launch merges before the first screen appears, so a
                // learner who answered on the Home Screen this morning opens
                // the app to a streak that already counts it.
                .task { services.synchronizeWidget() }
                .task {
                    UNUserNotificationCenter.current().delegate = notificationDelegate
                    await services.notifications.refreshAuthorization()
                }
                // The free daily allowance is measured against the current
                // calendar day. Backgrounding the app overnight is the normal
                // case, so without this a learner who used their rounds last
                // night would still be locked out this morning.
                .onChange(of: scenePhase) { _, phase in
                    // Leaving the app republishes the widget, so a Home Screen
                    // that is about to become visible shows what the session
                    // just changed rather than what it knew an hour ago.
                    guard phase == .active else {
                        if phase == .background { services.synchronizeWidget() }
                        return
                    }
                    services.progress.refreshCompletedRoundsToday()
                    // Anything answered on the Home Screen since the app last
                    // ran is merged here, before any screen reads progress.
                    services.synchronizeWidget()
                    // Every foreground reconciles what is scheduled with what
                    // the learner's progress now calls for, so nothing stale
                    // is ever left pending.
                    Task { @MainActor in
                        await services.notifications.reconcile(
                            state: .current(progress: services.progress)
                        )
                    }
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
    /// Local study reminders. Nothing is scheduled, and no permission is
    /// asked for, until the learner turns a category on in Settings.
    let notifications: StudyNotificationScheduler
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
        // A UI-test launch gets a scheduler that talks to nothing, so no run
        // can leave a notification pending on the simulator.
        let isTesting = RuntimeFlags.isUITesting
        let center: NotificationScheduling = isTesting
            ? InertNotificationScheduler()
            : SystemNotificationScheduler()
        let store = isTesting
            ? (UserDefaults(suiteName: "uiTesting.notifications") ?? .standard)
            : .standard
        self.notifications = StudyNotificationScheduler(center: center, defaults: store)
    }

    /// Merges anything the Home Screen widget recorded and republishes what
    /// the widget draws.
    ///
    /// A no-op when the App Group is unavailable, which is every UI-test run
    /// and every unprovisioned simulator: there is no shared container to read
    /// or write, and the app behaves exactly as it did before the widget
    /// existed.
    func synchronizeWidget() {
        guard !RuntimeFlags.isUITesting else { return }
        WidgetBridge.synchronize(
            progress: progress,
            catalog: catalog,
            compounds: compounds.catalog.compounds
        )
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
