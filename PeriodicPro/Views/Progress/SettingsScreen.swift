import StoreKit
import SwiftUI

/// Everything there is to set, and every link there is to follow.
///
/// Opened from the gear on Progress. Deliberately a plain grouped list rather
/// than a designed screen: this is the one place in the app where people
/// expect iOS's own conventions, and a subscription section that looks like
/// anything other than Settings invites suspicion.
///
/// Nothing here pretends to do Apple's job. "Manage Subscription" opens the
/// App Store's own sheet, which is the only place a subscription can actually
/// be changed or canceled; the app never claims it can do that itself.
struct SettingsScreen: View {
    @Environment(ProgressStore.self) private var progress: ProgressStore
    @Environment(SubscriptionManager.self) private var store: SubscriptionManager
    @Environment(\.openURL) private var openURL

    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue

    @State private var showsManageSubscriptions = false
    @State private var showsPaywall = false
    @State private var showsAbout = false
    @State private var showsResetConfirmation = false
    @State private var restoreMessage: String?

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .system
    }

    /// "Free", "Monthly", "Yearly" — or nothing at all while StoreKit is still
    /// answering, so a subscriber never reads "Free" for half a second.
    private var planDescription: String {
        switch store.entitlement {
        case .unknown: return "Checking…"
        case .free: return "Free"
        case .pro(let info):
            guard let plan = info.product?.planName else { return "Elemora Pro" }
            return "Elemora Pro · \(plan)"
        }
    }

    var body: some View {
        List {
            proSection
            appearanceSection
            supportSection
            legalSection
            aboutSection
            dataSection
        }
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .manageSubscriptionsSheet(isPresented: $showsManageSubscriptions)
        .sheet(isPresented: $showsPaywall) { PaywallView(context: .general) }
        .sheet(isPresented: $showsAbout) { AboutSheet() }
        .confirmationDialog(
            "Reset all progress?",
            isPresented: $showsResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset progress", role: .destructive) {
                progress.resetAllProgress()
                Haptics.tap()
            }
            .accessibilityIdentifier("settings.confirmReset")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Familiarity scores and your streak will be cleared. Favorites are kept.")
        }
        .alert(
            "Restore Purchases",
            isPresented: Binding(get: { restoreMessage != nil }, set: { if !$0 { restoreMessage = nil } })
        ) {
            Button("OK", role: .cancel) { restoreMessage = nil }
        } message: {
            Text(restoreMessage ?? "")
        }
        .accessibilityIdentifier("settings.screen")
    }

    // MARK: - Elemora Pro

    private var proSection: some View {
        Section {
            LabeledContent("Current plan", value: planDescription)
                .accessibilityIdentifier("settings.plan")

            if !store.isPro {
                row(title: "Explore Elemora Pro", symbol: "sparkles",
                    identifier: "settings.explorePro") {
                    showsPaywall = true
                }
            }

            row(title: "Manage Subscription", symbol: "creditcard",
                identifier: "settings.manageSubscription") {
                showsManageSubscriptions = true
            }

            row(title: "Restore Purchases", symbol: "arrow.counterclockwise",
                identifier: "settings.restore") {
                Task {
                    await store.restore()
                    restoreMessage = store.isPro
                        ? "Your Elemora Pro subscription has been restored."
                        : (store.purchaseState.message
                           ?? "No active Elemora Pro subscription was found for this Apple Account.")
                }
            }
            .disabled(store.purchaseState.isBusy)
        } header: {
            Text("Elemora Pro")
        } footer: {
            Text("Subscriptions are billed through your Apple Account. Changing or canceling one "
                 + "happens in the App Store's own subscription settings, which Manage Subscription "
                 + "opens.")
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section {
            ForEach(AppAppearance.allCases) { option in
                Button {
                    Haptics.tap()
                    appearanceRaw = option.rawValue
                } label: {
                    HStack(spacing: Theme.Spacing.m) {
                        Image(systemName: option.symbolName)
                            .font(.system(size: 15))
                            .foregroundStyle(AppColor.accent)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        Text(option.title)
                            .foregroundStyle(AppColor.primaryText)
                        Spacer(minLength: 0)
                        if appearance == option {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppColor.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(appearance == option ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("settings.appearance.\(option.rawValue)")
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text("System follows the appearance set in iOS Settings.")
        }
    }

    // MARK: - Support

    private var supportSection: some View {
        Section {
            linkRow(title: "Support", symbol: "questionmark.circle",
                    identifier: "settings.support", url: ElemoraLinks.support)
            linkRow(title: "Website", symbol: "globe",
                    identifier: "settings.website", url: ElemoraLinks.website)
            linkRow(title: "Contact Support", symbol: "envelope",
                    identifier: "settings.contactSupport",
                    url: ElemoraLinks.supportMail(version: AppVersion.short, build: AppVersion.build))
        } header: {
            Text("Support")
        } footer: {
            Text(verbatim: ElemoraLinks.supportEmailAddress)
                .accessibilityIdentifier("settings.supportEmail")
        }
    }

    // MARK: - Legal

    private var legalSection: some View {
        Section("Legal") {
            linkRow(title: "Privacy Policy", symbol: "hand.raised",
                    identifier: "settings.privacy", url: ElemoraLinks.privacy)
            linkRow(title: "Terms of Service", symbol: "doc.text",
                    identifier: "settings.terms", url: ElemoraLinks.terms)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Elemora", value: AppVersion.display)
                .accessibilityIdentifier("settings.version")
            row(title: "Data sources and acknowledgments", symbol: "info.circle",
                identifier: "settings.about") {
                showsAbout = true
            }
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        Section {
            Button(role: .destructive) {
                showsResetConfirmation = true
            } label: {
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "trash")
                        .font(.system(size: 15))
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text("Reset Progress")
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            // resetAllProgress() deliberately keeps favorites, so having
            // favorites is never a reason for this command to have work to do.
            .disabled(progress.totalAnswered == 0)
            .accessibilityIdentifier("settings.resetProgress")
        } header: {
            Text("Data")
        } footer: {
            Text("Everything Elemora stores is on this device. There is no account and nothing to "
                 + "sign out of.")
        }
    }

    // MARK: - Rows

    private func row(
        title: String,
        symbol: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(AppColor.accent)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .foregroundStyle(AppColor.primaryText)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func linkRow(title: String, symbol: String, identifier: String, url: URL?) -> some View {
        row(title: title, symbol: symbol, identifier: identifier) {
            if let url { openURL(url) }
        }
        .accessibilityValue(url?.absoluteString ?? "")
    }
}
