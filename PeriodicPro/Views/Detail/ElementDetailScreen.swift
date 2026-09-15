import SwiftUI

/// The destination of the signature zoom transition.
///
/// Scroll choreography, all driven by native scroll APIs rather than manual
/// offset maths:
/// * the hero scales down, fades and softens as it leaves the top
///   (`scrollTransition(.interactive)`)
/// * every card below rises and fades in as it becomes visible
/// * the tinted backdrop recedes toward the page background
///   (`onScrollGeometryChange`)
/// * the element name slides into the navigation bar once the hero is gone
struct ElementDetailScreen: View {
    let element: ChemicalElement

    @Environment(ProgressStore.self) private var progress: ProgressStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showsMoreProperties = false
    @State private var scrollOffset: CGFloat = 0

    private static let heroHandoff: CGFloat = 150

    private var isFavorite: Bool { progress.isFavorite(element.atomicNumber) }

    /// 0 at the top of the page, 1 once the hero has fully handed over.
    private var handoff: CGFloat {
        guard !reduceMotion else { return scrollOffset > Self.heroHandoff ? 1 : 0 }
        return min(max(scrollOffset / Self.heroHandoff, 0), 1)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                ElementHero(element: element)
                    .padding(.top, Theme.Spacing.s)
                    .padding(.bottom, Theme.Spacing.xs)
                    .scrollTransition(.interactive, axis: .vertical) { content, phase in
                        content
                            .opacity(reduceMotion ? 1 : 1 - abs(phase.value) * 0.9)
                            .scaleEffect(reduceMotion ? 1 : 1 + phase.value * 0.07, anchor: .top)
                            .blur(radius: reduceMotion ? 0 : abs(phase.value) * 2.5)
                    }

                StructureCard(element: element).softRise(enabled: !reduceMotion)
                QuickFactsCard(element: element, showsMoreProperties: $showsMoreProperties)
                    .softRise(enabled: !reduceMotion)
                AboutCard(element: element).softRise(enabled: !reduceMotion)
                UsesCard(element: element).softRise(enabled: !reduceMotion)
                MemoryHookCard(element: element).softRise(enabled: !reduceMotion)
                FamiliarityCard(
                    element: element,
                    snapshot: progress.snapshot(for: element.atomicNumber)
                )
                .softRise(enabled: !reduceMotion)
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .background {
            backdrop
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, newValue in
            scrollOffset = newValue
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        // The bar stays transparent over the hero and gains its material once
        // the element name has taken over, so controls are always legible.
        .toolbarBackground(handoff > 0.6 ? Visibility.visible : Visibility.hidden,
                           for: .navigationBar)
        .accessibilityIdentifier("detail.screen")
    }

    private var backdrop: some View {
        ZStack {
            AppColor.canvas
            element.category.backdropGradient
                .opacity(1 - Double(handoff) * 0.8)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: handoff)
        }
        .ignoresSafeArea()
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 6) {
                Text(element.symbol)
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(element.category.onTileColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(element.category.tileFill)
                    }
                Text(element.name)
                    .font(.system(.headline, weight: .semibold))
                    .foregroundStyle(AppColor.primaryText)
            }
            .opacity(Double(handoff))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: handoff)
            .accessibilityHidden(handoff < 0.9)
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                let nowFavorite = progress.toggleFavorite(element.atomicNumber)
                Haptics.favorited(nowFavorite)
            } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isFavorite ? element.category.accentColor : AppColor.secondaryText)
                    .symbolEffect(.bounce, value: isFavorite)
                    .frame(width: Theme.minimumTouchTarget, height: Theme.minimumTouchTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(isFavorite ? "Remove \(element.name) from favorites"
                                           : "Add \(element.name) to favorites")
            .accessibilityIdentifier("detail.favoriteButton")
        }
    }
}

// MARK: - Scroll transition helper

private struct SoftRiseModifier: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.scrollTransition(.animated(.spring(response: 0.45, dampingFraction: 0.85))
                .threshold(.visible(0.08))) { view, phase in
                    view
                        .opacity(phase.isIdentity ? 1 : 0)
                        .offset(y: phase.isIdentity ? 0 : 20)
                }
        } else {
            content
        }
    }
}

extension View {
    /// Cards rise and fade in as they enter the viewport, and stay put once
    /// settled. Disabled entirely under Reduce Motion.
    func softRise(enabled: Bool) -> some View {
        modifier(SoftRiseModifier(enabled: enabled))
    }
}
