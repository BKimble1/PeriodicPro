import SwiftUI

/// Three tabs, no more. Search lives in Table; favorites live in Study and on
/// each element page.
struct RootView: View {
    @Environment(\.elementCatalog) private var catalog

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var selection: AppTab = .table

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTesting")
    }

    var body: some View {
        Group {
            if catalog.isEmpty {
                DataUnavailableView()
            } else {
                TabView(selection: $selection) {
                    PeriodicTableScreen()
                        .tabItem { Label(AppTab.table.title, systemImage: AppTab.table.symbolName) }
                        .tag(AppTab.table)

                    StudyScreen()
                        .tabItem { Label(AppTab.study.title, systemImage: AppTab.study.symbolName) }
                        .tag(AppTab.study)

                    ProgressScreen()
                        .tabItem { Label(AppTab.progress.title, systemImage: AppTab.progress.symbolName) }
                        .tag(AppTab.progress)
                }
                .accessibilityIdentifier("root.tabView")
            }
        }
        .fullScreenCover(isPresented: shouldShowOnboarding) {
            OnboardingView { hasCompletedOnboarding = true }
        }
    }

    private var shouldShowOnboarding: Binding<Bool> {
        Binding(
            get: { !hasCompletedOnboarding && !isUITesting && !catalog.isEmpty },
            set: { newValue in
                if !newValue { hasCompletedOnboarding = true }
            }
        )
    }
}

/// Shown only if the bundled dataset is unreadable — which should never happen
/// in a shipped build, but beats a silent empty table if it ever does.
struct DataUnavailableView: View {
    var body: some View {
        VStack {
            EmptyStateView(
                symbolName: "exclamationmark.triangle",
                title: "Element data unavailable",
                message: "The bundled periodic table could not be read. Reinstalling the app will restore it."
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.canvas)
        .accessibilityIdentifier("root.dataUnavailable")
    }
}
