import SwiftUI

/// Three short pages, skippable from the first frame. No animation longer than
/// a page turn, and nothing the learner has to read to use the app.
struct OnboardingView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0

    private struct Page: Identifiable {
        let id: Int
        let symbolName: String
        let title: String
        let message: String
        let tint: Color
    }

    private let pages: [Page] = [
        Page(
            id: 0,
            symbolName: "square.grid.3x3.fill",
            title: "Explore the table",
            message: "All 118 elements, color-coded by family and laid out exactly as the periodic table should be.",
            tint: ElementCategory.reactiveNonmetal.accentColor
        ),
        Page(
            id: 1,
            symbolName: "hand.tap.fill",
            title: "Tap to learn",
            message: """
                Any element opens into its structure, key facts, everyday uses and a hook \
                to help you remember it.
                """,
            tint: ElementCategory.transitionMetal.accentColor
        ),
        Page(
            id: 2,
            symbolName: "graduationcap.fill",
            title: "Practice to remember",
            message: """
                Flashcards, a quick quiz and identify rounds turn what you have read into \
                something you recall.
                """,
            tint: ElementCategory.nobleGas.accentColor
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") {
                    Haptics.tap()
                    onFinish()
                }
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.secondaryText)
                .padding(Theme.Spacing.l)
                .accessibilityIdentifier("onboarding.skip")
            }

            TabView(selection: $page) {
                ForEach(pages) { item in
                    VStack(spacing: Theme.Spacing.xl) {
                        Image(systemName: item.symbolName)
                            .font(.system(size: 46, weight: .light))
                            .foregroundStyle(item.tint)
                            .frame(width: 112, height: 112)
                            .background { Circle().fill(item.tint.opacity(0.10)) }

                        VStack(spacing: Theme.Spacing.m) {
                            Text(item.title)
                                .font(.system(.title, weight: .bold))
                                .foregroundStyle(AppColor.primaryText)
                                .multilineTextAlignment(.center)
                            Text(item.message)
                                .font(AppFont.callout)
                                .foregroundStyle(AppColor.secondaryText)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, Theme.Spacing.xxl)
                        }
                    }
                    .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                Haptics.tap()
                if page < pages.count - 1 {
                    withAnimation(reduceMotion ? nil : Theme.Motion.reveal) { page += 1 }
                } else {
                    onFinish()
                }
            } label: {
                Text(page < pages.count - 1 ? "Continue" : "Start exploring")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background {
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .fill(AppColor.accent)
                    }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.bottom, Theme.Spacing.xxl)
            .accessibilityIdentifier("onboarding.primaryButton")
        }
        .background(AppColor.canvas)
        .interactiveDismissDisabled()
    }
}
