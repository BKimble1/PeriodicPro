import SwiftUI

/// What the learner sees while Elemora opens.
///
/// iOS shows its own launch image first — a flat field in the app's canvas
/// color, declared through `UILaunchScreen_BackgroundColor` — and this takes
/// over from it on the same color, so the handoff is invisible and the icon
/// appears to settle onto a background that was already there.
///
/// It is a real loading screen, not a timed splash: it stays until the app's
/// services have finished opening the store and reading the bundled catalog,
/// with a short floor so a fast launch does not flash, and a ceiling so a slow
/// one never becomes a wall. `RootView` handles the failure case itself, so
/// nothing here has to report one.
struct LaunchScreenView: View {
    /// Whether the app behind this is ready to be shown.
    var isReady: Bool
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hasSettled = false
    @State private var minimumElapsed = false
    @State private var showsSlowHint = false

    /// Short enough not to be felt, long enough that the icon is seen rather
    /// than flickered.
    private static var minimumDuration: Duration {
        RuntimeFlags.isUITesting ? .milliseconds(150) : .milliseconds(560)
    }

    /// After this the learner is told something is still happening rather than
    /// left looking at a still image.
    private static let slowHintDelay = Duration.seconds(2)

    /// The ceiling. Whatever has not finished by now finishes behind the app.
    private static var maximumDuration: Duration {
        RuntimeFlags.isUITesting ? .seconds(2) : .seconds(6)
    }

    var body: some View {
        ZStack {
            AppColor.canvas.ignoresSafeArea()

            VStack(spacing: Theme.Spacing.xl) {
                ElemoraAppIcon(size: 112)
                    .themeShadow(Theme.Shadow.raised)
                    .scaleEffect(hasSettled || reduceMotion ? 1 : 0.86)
                    .opacity(hasSettled || reduceMotion ? 1 : 0)

                VStack(spacing: Theme.Spacing.xs) {
                    Text("Elemora")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColor.primaryText)
                    Text("Periodic table and chemistry")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.secondaryText)
                }
                .opacity(hasSettled || reduceMotion ? 1 : 0)

                // Only if the wait becomes one worth acknowledging.
                ProgressView()
                    .controlSize(.small)
                    .tint(AppColor.tertiaryText)
                    .opacity(showsSlowHint ? 1 : 0)
                    .accessibilityHidden(!showsSlowHint)
                    .padding(.top, Theme.Spacing.s)
            }
            .padding(.horizontal, Theme.Spacing.xl)
        }
        // The element is created first and described afterwards. Applied the
        // other way round, the identifier attaches to the view underneath
        // while the label attaches to the element `children: .ignore` makes,
        // so the two end up on different elements — and a VoiceOver user, or
        // a test, finds one with an identifier and no name.
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("launch.screen")
        .accessibilityLabel("Elemora")
        .accessibilityValue(showsSlowHint ? "Loading" : "")
        // Modal, so VoiceOver treats what is behind the cover as unavailable
        // rather than as the next thing to swipe to. `accessibilityHidden` on
        // the content cannot do this job: the tabs and the navigation bar are
        // hosted by UIKit, outside the SwiftUI view the modifier applies to,
        // and they stay in the tree regardless.
        .accessibilityAddTraits([.isImage, .isModal])
        .task { await run() }
        .onChange(of: isReady) { _, ready in
            if ready, minimumElapsed { onFinished() }
        }
    }

    private func run() async {
        if RuntimeFlags.holdsLaunchScreen {
            hasSettled = true
            withAnimation(Theme.Motion.soft) { showsSlowHint = true }
            return
        }
        if reduceMotion {
            hasSettled = true
        } else {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) { hasSettled = true }
        }

        let started = ContinuousClock.now
        try? await Task.sleep(for: Self.minimumDuration)
        minimumElapsed = true
        if isReady { return onFinished() }

        // Wait for readiness, telling the learner once the wait is long
        // enough to notice, and giving up on waiting at the ceiling.
        var hintShown = false
        while started.duration(to: .now) < Self.maximumDuration {
            if isReady { return onFinished() }
            if !hintShown, started.duration(to: .now) >= Self.slowHintDelay {
                hintShown = true
                withAnimation(Theme.Motion.soft) { showsSlowHint = true }
            }
            try? await Task.sleep(for: .milliseconds(80))
        }
        onFinished()
    }
}

#Preview {
    LaunchScreenView(isReady: false) {}
}
