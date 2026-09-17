import SwiftUI

/// Four tabs. Search lives in Table; favorites live in Study and on each
/// detail page; Build is the Compound Builder beta.
struct RootView: View {
    /// Diagnostic detail shown only when the bundled dataset cannot be read.
    var catalogError: String?

    @Environment(\.elementCatalog) private var catalog
    @Environment(SavedQuizStore.self) private var savedQuizzes: SavedQuizStore

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue
    @State private var selection: AppTab = .table

    /// System, light or dark — applied once, here, so a change in Settings
    /// reaches every tab, sheet and full-screen cover at the same moment.
    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .system
    }

    var body: some View {
        Group {
            if catalog.isEmpty {
                DataUnavailableView(detail: catalogError)
            } else {
                TabView(selection: $selection) {
                    PeriodicTableScreen()
                        .tabItem { Label(AppTab.table.title, systemImage: AppTab.table.symbolName) }
                        .tag(AppTab.table)

                    StudyScreen()
                        .tabItem { Label(AppTab.study.title, systemImage: AppTab.study.symbolName) }
                        .tag(AppTab.study)

                    CompoundBuilderScreen()
                        .tabItem { Label(AppTab.build.title, systemImage: AppTab.build.symbolName) }
                        .tag(AppTab.build)

                    ProgressScreen()
                        .tabItem { Label(AppTab.progress.title, systemImage: AppTab.progress.symbolName) }
                        .tag(AppTab.progress)
                }
                .accessibilityIdentifier("root.tabView")
                .environment(\.selectTab) { tab in
                    selection = tab
                }
            }
        }
        .fullScreenCover(isPresented: shouldShowOnboarding) {
            OnboardingView { hasCompletedOnboarding = true }
        }
        // A quiz link — https://elemora.idlery.com/quiz/… — opened from
        // Messages, Notes or anywhere else. It is validated and saved before
        // anything is shown, and the Study tab presents the result. A URL
        // that is not one of ours is left alone.
        .onOpenURL { url in
            guard savedQuizzes.open(shareURL: url, catalog: catalog) else { return }
            selection = .study
        }
        // A tapped notification lands where it said it would. Every
        // destination is a tab this app already has; nothing here can open
        // anything a learner could not reach themselves.
        .onReceive(NotificationCenter.default.publisher(for: .elemoraNotificationTapped)) { note in
            guard let destination = note.object as? NotificationDestination else { return }
            selection = destination.tab
        }
        .preferredColorScheme(appearance.colorScheme)
    }

    private var shouldShowOnboarding: Binding<Bool> {
        Binding(
            get: { !hasCompletedOnboarding && !RuntimeFlags.isUITesting && !catalog.isEmpty },
            set: { newValue in
                if !newValue { hasCompletedOnboarding = true }
            }
        )
    }
}

/// Shown only if the bundled dataset is unreadable — which should never happen
/// in a shipped build, but beats a silent empty table if it ever does.
struct DataUnavailableView: View {
    var detail: String?

    var body: some View {
        // The detail line is an unbounded error description, so this is the one
        // screen whose height the app cannot predict. It scrolls.
        ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                EmptyStateView(
                    symbolName: "exclamationmark.triangle",
                    title: "Element data unavailable",
                    message: "The bundled periodic table could not be read. Reinstalling the app will restore it."
                )
                if let detail {
                    Text(detail)
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.tertiaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.xl)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.canvas)
        .accessibilityIdentifier("root.dataUnavailable")
    }
}
