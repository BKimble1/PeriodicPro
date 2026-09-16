import SwiftUI

/// Three tabs, no more. Search lives in Table; favorites live in Study and on
/// each element page.
struct RootView: View {
    /// Diagnostic detail shown only when the bundled dataset cannot be read.
    var catalogError: String?

    @Environment(\.elementCatalog) private var catalog

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var selection: AppTab = .table

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
