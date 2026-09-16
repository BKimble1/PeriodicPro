import SwiftUI

/// Three short pages, skippable from the first frame. No animation longer than
/// a page turn, and nothing the learner has to read to use the app.
struct OnboardingView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
            // Accurate for everybody: every element's detail page shows its
            // structure as a turning 3D model. What Pro adds is taking that
            // model apart, which is not something onboarding mentions — there
            // is no purchase screen anywhere in this flow.
            message: """
                Any element opens into its structure in 3D, plus key facts, everyday uses \
                and a hook to help you remember it.
                """,
            tint: ElementCategory.transitionMetal.accentColor
        ),
        Page(
            id: 2,
            symbolName: "graduationcap.fill",
            title: "Practice to remember",
            message: """
                Flashcards, quizzes you shape yourself, Match and identify rounds turn what \
                you have read into something you recall. Compounds join in, and the Build \
                tab lets you look up what you assemble.
                """,
            tint: ElementCategory.nobleGas.accentColor
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                // The padding has to live inside the label: a Button's hit
                // region is its label's content shape, so padding applied to
                // the Button itself only reserved space that taps fell through.
                // "Skip" alone is ~31x18pt, in the corner, on the first control
                // a new user ever sees.
                Button {
                    Haptics.tap()
                    onFinish()
                } label: {
                    Text("Skip")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.secondaryText)
                        .padding(.horizontal, Theme.Spacing.l)
                        .frame(minHeight: Theme.minimumTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, Theme.Spacing.xs)
                .accessibilityIdentifier("onboarding.skip")
            }

            // A .page TabView clips whatever does not fit and offers no way to
            // scroll, and the copy uses fixedSize so it overflows rather than
            // truncating. In landscape, and in portrait from .accessibility3
            // up, the last lines of page two were simply unreadable.
            TabView(selection: $page) {
                ForEach(pages) { item in
                    ScrollView {
                        VStack(spacing: Theme.Spacing.xl) {
                            // The decorative circle is the first thing to give
                            // up room when type or the screen gets tight.
                            if !dynamicTypeSize.isAccessibilitySize {
                                Image(systemName: item.symbolName)
                                    .font(.system(size: 46, weight: .light))
                                    .foregroundStyle(item.tint)
                                    .frame(width: 112, height: 112)
                                    .background { Circle().fill(item.tint.opacity(0.10)) }
                                    .accessibilityHidden(true)
                            }

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
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.l)
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
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
                    .multilineTextAlignment(.center)
                    // A floor, not a fixed height. `.body` is a scaling font:
                    // at the largest accessibility sizes one line of it is
                    // taller than 52 points on its own, and "Start exploring"
                    // wraps to two — so a hard height cropped the label of the
                    // button that leaves onboarding.
                    .padding(.vertical, Theme.Spacing.s)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
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
