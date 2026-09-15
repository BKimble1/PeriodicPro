import StoreKit
import SwiftUI

/// Periodic Pro.
///
/// Every price on this screen comes from `Product.displayPrice`, which is what
/// the App Store will actually charge in the learner's own currency. Nothing
/// here hard-codes an amount.
///
/// Yearly is listed first and marked Best Value because it genuinely is cheaper
/// per month, and the saving shown is computed from the two live prices. Both
/// plans are the same size, both are equally easy to select, and neither is
/// preselected in a way that hides the other.
struct PaywallView: View {
    var context: PaywallContext = .general

    @Environment(SubscriptionManager.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL

    @State private var selectedProductID: String?
    @State private var showsManageSubscriptions = false
    @State private var showsPrivacy = false
    /// False until `loadProducts` has returned once. Without it the plan
    /// section renders its "not available" state for the frame between the view
    /// appearing and `.task` starting, which reads as a failure that has not
    /// happened yet.
    @State private var hasAttemptedLoad = false

    /// Apple's standard license for apps that do not supply their own. Linking
    /// it is the documented option and avoids inventing a terms page.
    private static let termsURL = URL(
        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    )

    private var selectedProduct: Product? {
        store.products.first { $0.id == selectedProductID } ?? store.products.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    header
                    featureList
                    planSection
                    legal
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.top, Theme.Spacing.s)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(backdrop)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColor.secondaryText)
                            .frame(width: Theme.minimumTouchTarget,
                                   height: Theme.minimumTouchTarget)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("paywall.close")
                }
            }
            .safeAreaInset(edge: .bottom) { purchaseBar }
        }
        .tint(AppColor.accent)
        .task {
            // An entitlement that arrived between the tap and this sheet
            // appearing would not fire onChange, because it never changes while
            // the paywall is on screen.
            if store.isPro {
                dismiss()
                return
            }
            await store.loadProducts()
            hasAttemptedLoad = true
            if selectedProductID == nil {
                selectedProductID = store.products.first {
                    SubscriptionProduct(productID: $0.id)?.isPreferred == true
                }?.id ?? store.products.first?.id
            }
        }
        .onChange(of: store.entitlement) { _, newValue in
            // Dismiss the moment the entitlement actually arrives — including
            // when it arrives from another device or from a deferred purchase
            // completing, not only from a tap on this screen.
            if newValue.isPro { dismiss() }
        }
        .onDisappear { store.clearTransientState() }
        .manageSubscriptionsSheet(isPresented: $showsManageSubscriptions)
        .sheet(isPresented: $showsPrivacy) { PrivacySummarySheet() }
        .accessibilityIdentifier("paywall")
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Theme.Spacing.m) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppColor.accent.opacity(0.22), AppColor.accent.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 76, height: 76)
                Image(systemName: "cube.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(AppColor.accent)
            }
            .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Periodic Pro")
                    .font(.system(.largeTitle, weight: .bold))
                    .foregroundStyle(AppColor.primaryText)
                    .multilineTextAlignment(.center)
                Text(context.headline)
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(AppColor.primaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(context.subheadline)
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, Theme.Spacing.s)
    }

    // MARK: - Features

    private var featureList: some View {
        VStack(spacing: Theme.Spacing.m) {
            feature(
                symbol: "cube.fill",
                title: "Interactive 3D structures",
                detail: "Turn, zoom and take apart every element's structure and its atom."
            )
            feature(
                symbol: "infinity",
                title: "Unlimited study",
                detail: "As many rounds a day as you want, in every mode."
            )
            feature(
                symbol: "scope",
                title: "Smart Review",
                detail: "Rounds built from the elements you keep getting wrong."
            )
            feature(
                symbol: "square.grid.3x3.fill",
                title: "Every element in depth",
                detail: "All 118, not a sample. The table itself stays free."
            )
        }
    }

    private func feature(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: SFSymbolAllowlist.resolved(symbol))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColor.accent)
                .frame(width: 32, height: 32)
                .background { RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(AppColor.accent.opacity(0.10)) }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(AppColor.primaryText)
                Text(detail)
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Plans

    @ViewBuilder
    private var planSection: some View {
        if store.products.isEmpty {
            unavailablePlans
        } else {
            VStack(spacing: Theme.Spacing.m) {
                ForEach(store.products, id: \.id) { product in
                    planRow(product)
                }
            }
        }
    }

    private func planRow(_ product: Product) -> some View {
        let plan = SubscriptionProduct(productID: product.id)
        let isSelected = selectedProduct?.id == product.id
        let saving = SubscriptionPricing.yearlySavingPercent(
            monthly: store.products.first { $0.id == SubscriptionProduct.monthly.rawValue },
            yearly: store.products.first { $0.id == SubscriptionProduct.yearly.rawValue }
        )

        return Button {
            Haptics.tap()
            selectedProductID = product.id
        } label: {
            HStack(alignment: .center, spacing: Theme.Spacing.m) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? AppColor.accent : AppColor.hairline)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Theme.Spacing.s) {
                        Text(plan?.planName ?? product.displayName)
                            .font(.system(.body, weight: .semibold))
                            .foregroundStyle(AppColor.primaryText)
                        if plan?.isPreferred == true, let saving {
                            Text("SAVE \(saving)%")
                                .font(.system(size: 9, weight: .bold))
                                .kerning(0.5)
                                .foregroundStyle(AppColor.positive)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background { Capsule().fill(AppColor.positive.opacity(0.12)) }
                        }
                    }
                    if let monthly = SubscriptionPricing.monthlyEquivalent(for: product) {
                        Text("\(monthly) per month, billed yearly")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    } else if let period = SubscriptionPricing.periodDescription(for: product) {
                        Text("Billed \(period)")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }

                Spacer(minLength: Theme.Spacing.s)

                Text(product.displayPrice)
                    .font(.system(.body, weight: .semibold).monospacedDigit())
                    .foregroundStyle(AppColor.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: Theme.minimumTouchTarget)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(AppColor.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(
                        isSelected ? AppColor.accent : AppColor.hairline,
                        lineWidth: isSelected ? 2 : 0.8
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("paywall.plan.\(plan?.rawValue ?? product.id)")
    }

    @ViewBuilder
    private var unavailablePlans: some View {
        if !hasAttemptedLoad || store.purchaseState.isBusy {
            HStack(spacing: Theme.Spacing.m) {
                ProgressView()
                Text("Loading subscription options…")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.xl)
            .accessibilityIdentifier("paywall.loading")
        } else {
            VStack(spacing: Theme.Spacing.m) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 22))
                    .foregroundStyle(AppColor.warning)
                Text(store.purchaseState.message
                     ?? "Subscription options are not available right now.")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") {
                    Task {
                        hasAttemptedLoad = false
                        await store.loadProducts()
                        hasAttemptedLoad = true
                    }
                }
                .font(.system(.subheadline, weight: .semibold))
                .frame(minHeight: Theme.minimumTouchTarget)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.l)
            .accessibilityIdentifier("paywall.unavailable")
        }
    }

    // MARK: - Purchase bar

    private var purchaseBar: some View {
        VStack(spacing: Theme.Spacing.s) {
            if let message = store.purchaseState.message, !store.products.isEmpty {
                Text(message)
                    .font(AppFont.caption)
                    .foregroundStyle(store.purchaseState == .pending
                                     ? AppColor.secondaryText
                                     : AppColor.warning)
                    .multilineTextAlignment(.center)
                    // Capped: this bar is a safe-area inset, so an uncapped
                    // message at an accessibility text size would squeeze the
                    // plans it is describing off the screen.
                    .lineLimit(4)
                    .accessibilityIdentifier("paywall.message")
            }

            Button {
                guard let product = selectedProduct else { return }
                Haptics.tap()
                Task { await store.purchase(product) }
            } label: {
                ZStack {
                    if store.purchaseState.isBusy {
                        ProgressView().tint(.white)
                    } else {
                        Text("Continue")
                            .font(.system(.body, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                // A minimum rather than a fixed height: at an accessibility
                // text size "Continue" is taller than 52 points and a hard
                // frame clips it.
                .frame(minHeight: 52)
                .padding(.vertical, 2)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(selectedProduct == nil ? AppColor.secondaryText : AppColor.accent)
                }
            }
            .buttonStyle(.plain)
            .disabled(selectedProduct == nil || store.purchaseState.isBusy)
            .accessibilityIdentifier("paywall.continue")

            HStack(spacing: Theme.Spacing.l) {
                Button("Restore Purchases") {
                    Task { await store.restore() }
                }
                .accessibilityIdentifier("paywall.restore")

                if store.isPro {
                    Button("Manage Subscription") { showsManageSubscriptions = true }
                        .accessibilityIdentifier("paywall.manage")
                }
            }
            .font(AppFont.footnote)
            .frame(minHeight: Theme.minimumTouchTarget)
            .disabled(store.purchaseState.isBusy)
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.s)
        .background(.bar)
    }

    // MARK: - Legal

    private var legal: some View {
        VStack(spacing: Theme.Spacing.s) {
            Text(Self.renewalTerms)
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.tertiaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Spacing.l) {
                Button("Privacy") { showsPrivacy = true }
                    .accessibilityIdentifier("paywall.privacy")
                Button("Terms") {
                    if let url = Self.termsURL { openURL(url) }
                }
                .accessibilityIdentifier("paywall.terms")
            }
            .font(AppFont.caption)
            .frame(minHeight: Theme.minimumTouchTarget)
        }
    }

    /// Kept as one concatenated string rather than a multi-line literal so the
    /// source linter can balance the file's delimiters.
    private static let renewalTerms =
        "Payment is charged to your Apple Account at confirmation of purchase. "
        + "The subscription renews automatically unless it is canceled at least 24 hours "
        + "before the end of the current period, and your account is charged for renewal "
        + "within 24 hours of the end of that period. You can manage or cancel a "
        + "subscription in Settings on your device at any time."

    private var backdrop: some View {
        ZStack {
            AppColor.canvas
            LinearGradient(
                colors: [AppColor.accent.opacity(0.10), AppColor.canvas.opacity(0)],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}

/// What the app stores, shown without needing a network connection.
///
/// A hosted privacy policy is still required by App Store Connect; this sheet
/// is the in-app copy of the same statement, so the paywall's Privacy link is
/// never a dead link and works offline like the rest of the app.
struct PrivacySummarySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    Text("Periodic Pro collects nothing.")
                        .font(.system(.title3, weight: .semibold))
                        .foregroundStyle(AppColor.primaryText)

                    paragraph("There are no accounts, no sign-in and no analytics or "
                              + "tracking software of any kind in this app.")
                    paragraph("Your favorites, familiarity scores, streak and recent searches "
                              + "are stored only on this device. They are never uploaded, and "
                              + "deleting the app deletes them.")
                    paragraph("Subscriptions are handled entirely by Apple. The app is told "
                              + "whether a subscription is active; it never sees your payment "
                              + "details, your Apple Account or your name.")
                    paragraph("The element data ships inside the app, so nothing you look up "
                              + "or search for leaves your device.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.vertical, Theme.Spacing.l)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(AppColor.canvas)
            .navigationTitle("Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(AppColor.accent)
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(AppFont.callout)
            .foregroundStyle(AppColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
