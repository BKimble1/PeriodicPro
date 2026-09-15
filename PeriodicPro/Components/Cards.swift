import SwiftUI

/// The single card surface used across the whole app: soft fill, hairline
/// border, and a shadow light enough that stacked cards never look heavy.
struct CardContainer<Content: View>: View {
    var padding: CGFloat = Theme.Spacing.l
    var cornerRadius: CGFloat = Theme.Radius.card
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppColor.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(AppColor.hairline, lineWidth: 0.7)
            }
            .themeShadow(Theme.Shadow.card)
    }
}

/// Heading above a card or a horizontal carousel.
///
/// There is deliberately no trailing "See All" slot: every list in this app is
/// already complete on screen, and a control that does nothing is worse than no
/// control at all.
struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(AppFont.sectionTitle)
                .foregroundStyle(AppColor.primaryText)
            if let subtitle {
                Text(subtitle)
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A labeled key/value pair used by the quick-facts grid.
struct FactRow: View {
    let label: String
    let value: String
    var footnote: String?
    var monospacedValue: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
            Text(value)
                .font(monospacedValue
                      ? .system(.subheadline, design: .monospaced, weight: .medium)
                      : .system(.subheadline, weight: .semibold))
                .foregroundStyle(AppColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let footnote {
                Text(footnote)
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.Spacing.s)
        .padding(.horizontal, Theme.Spacing.m)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(AppColor.surfaceMuted)
        }
        .accessibilityElement(children: .combine)
        // The footnote is the qualifier that makes the value correct ("mass
        // number of the most stable isotope"), so it has to reach VoiceOver.
        .accessibilityLabel(footnote.map { "\(label): \(value). \($0)" } ?? "\(label): \(value)")
    }
}

/// One of the three-to-five "Common Uses" cards on the detail screen.
struct UseCard: View {
    let use: ElementUse
    let tint: Color

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            Image(systemName: SFSymbolAllowlist.resolved(use.symbolName))
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(tint)
                .frame(height: 24)
            VStack(spacing: 2) {
                Text(use.title)
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(AppColor.primaryText)
                    .multilineTextAlignment(.center)
                Text(use.detail)
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, Theme.Spacing.m)
        .padding(.horizontal, Theme.Spacing.m)
        .frame(maxWidth: .infinity)
        // Two per row means the copy rarely wraps, so the card no longer needs
        // to reserve height for three lines of title.
        .frame(minHeight: 92)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(tint.opacity(0.08))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(use.title). \(use.detail)")
    }
}

/// Colored pill showing an element's family.
struct CategoryBadge: View {
    let category: ElementCategory
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: category.glyph)
                .font(.system(compact ? .caption2 : .caption, weight: .semibold))
            Text(compact ? category.shortName : category.displayName)
                .font(.system(compact ? .caption2 : .caption, weight: .semibold))
        }
        .foregroundStyle(category.onTileColor)
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 4 : 6)
        .background {
            Capsule(style: .continuous).fill(category.tileFill)
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(category.accentColor.opacity(0.22), lineWidth: 0.6)
        }
        // One element, not two. Labeling the HStack without collapsing it
        // pushes the same label onto both children, so VoiceOver reads the
        // family name once for the glyph and again for the text. `.ignore` is
        // safe here in a way it would not be on a Button: there is no action to
        // discard, only a decorative symbol beside its own caption.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(category.displayName)
    }
}

/// Small statistic block used on Study and Progress.
struct StatTile: View {
    let value: String
    let caption: String
    let symbolName: String
    let tint: Color

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: symbolName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background { Circle().fill(tint.opacity(0.12)) }
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(.title3, weight: .semibold).monospacedDigit())
                    .foregroundStyle(AppColor.primaryText)
                    // A statistic that wraps mid-number reads as two numbers.
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(caption)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(AppColor.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .strokeBorder(AppColor.hairline, lineWidth: 0.7)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(caption)")
    }
}

/// Neutral, friendly empty state. Used for no results, no favorites and
/// no study history so the app never shows a blank region.
struct EmptyStateView: View {
    let symbolName: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            // Only the static part is combined. Folding the button in as well
            // would strip its button trait and leave it reachable only as a
            // rotor action.
            VStack(spacing: Theme.Spacing.m) {
                Image(systemName: symbolName)
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(AppColor.tertiaryText)
                    .padding(.bottom, 2)
                Text(title)
                    .font(AppFont.cardTitle)
                    .foregroundStyle(AppColor.primaryText)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(AppColor.accent)
                    .padding(.top, Theme.Spacing.xs)
            }
        }
        .padding(.vertical, Theme.Spacing.xxl)
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}
