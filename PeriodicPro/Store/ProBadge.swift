import SwiftUI

/// The small "PRO" marker.
///
/// Deliberately quiet, and deliberately a word rather than a padlock: a lock
/// icon on every gated control makes an app feel like a demo, and color alone
/// would not read for someone who cannot distinguish it. One short word does
/// both jobs.
struct ProBadge: View {
    var isCompact: Bool = false

    var body: some View {
        Text("PRO")
            .font(.system(size: isCompact ? 8 : 9, weight: .bold))
            .kerning(0.5)
            // Ink rather than accent. Accent text on a faint accent capsule
            // measures between 3.5 and 4.6 to 1 depending on the surface and
            // the appearance, and nine points bold is small text, which needs
            // 4.5. The capsule keeps the Pro tint; the word stays readable.
            .foregroundStyle(AppColor.primaryText)
            .padding(.horizontal, isCompact ? 5 : 6)
            .padding(.vertical, isCompact ? 2 : 3)
            .background {
                Capsule().fill(AppColor.accent.opacity(0.12))
            }
            .accessibilityLabel("Periodic Pro feature")
    }
}

/// Why the paywall was opened. Drives one line of the header so the learner is
/// told what they were reaching for rather than being shown a generic pitch.
enum PaywallContext: String, Identifiable, Hashable, Sendable {
    case dailyLimit
    case structureExplorer
    case smartReview
    case general

    var id: String { rawValue }

    var headline: String {
        switch self {
        case .dailyLimit: return "You have used today's free rounds"
        case .structureExplorer: return "Explore every element in 3D"
        case .smartReview: return "Review what you keep missing"
        case .general: return "Explore deeper. Remember faster."
        }
    }

    var subheadline: String {
        switch self {
        case .dailyLimit:
            return "Free study is three rounds a day. Periodic Pro removes the limit."
        case .structureExplorer:
            return "Hydrogen, carbon, oxygen, sodium, iron and gold are free to explore. "
                + "Pro opens the other 112."
        case .smartReview:
            return "Smart Review builds rounds from the elements you get wrong most."
        case .general:
            return "Everything in Periodic Pro, for one subscription."
        }
    }
}
