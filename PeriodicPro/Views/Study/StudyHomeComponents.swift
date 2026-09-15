import SwiftUI

/// The compact status card: a flame and a streak, or a ring and a percentage.
///
/// Two of these sit side by side under the greeting. Both lead to Progress,
/// where the same numbers are shown in full — the chevron is a real
/// destination, not decoration.
struct StudyStatusCard<Leading: View>: View {
    let title: String
    let caption: String
    let action: () -> Void
    @ViewBuilder var leading: () -> Leading

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    leading()
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColor.tertiaryText)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(.title2, weight: .bold).monospacedDigit())
                        .foregroundStyle(AppColor.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(caption)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(AppColor.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(AppColor.hairline, lineWidth: 0.7)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(caption)")
        .accessibilityHint("Opens Progress")
        .accessibilityAddTraits(.isButton)
    }
}

/// A small ring, for the mastery status card. Deliberately not `ProgressRing`,
/// which is the large centerpiece on Progress and carries its own label.
struct MiniProgressRing: View {
    let progress: Double
    var diameter: CGFloat = 28
    var tint: Color = AppColor.positive

    private var clamped: Double { min(max(progress, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppColor.hairline, lineWidth: diameter * 0.16)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(tint, style: StrokeStyle(lineWidth: diameter * 0.16, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

/// The strongest card on the Study tab: the one-tap way into a round.
///
/// Concept F's blue gradient hero. Everything on it is white on the accent,
/// which is a contrast pairing the design system already checks.
struct StudyHeroCard: View {
    let title: String
    let message: String
    let symbolName: String
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(alignment: .center, spacing: Theme.Spacing.l) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: symbolName)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.white.opacity(0.18))
                        }
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(.title3, weight: .bold))
                        .foregroundStyle(.white)
                    Text(message)
                        .font(AppFont.footnote)
                        .foregroundStyle(.white.opacity(0.88))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Theme.Spacing.s)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .accessibilityHidden(true)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppColor.accent,
                                AppColor.accent.opacity(0.82),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .themeShadow(Theme.Shadow.card)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(message)")
        .accessibilityAddTraits(.isButton)
    }
}

/// One of the four pastel practice tiles.
///
/// The icon is drawn in the family's ink color on the family's pastel fill —
/// the one pairing the contrast gate already proves for this palette. A tinted
/// icon on a tinted background would look like the reference concept but would
/// measure around 2:1, which is not a trade this app makes.
struct PracticeModeTile: View {
    let mode: StudyMode
    let tint: ElementCategory
    let showsProBadge: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: Theme.Spacing.s) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(tint.tileFill)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            Image(systemName: mode.symbolName)
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(tint.onTileColor)
                        }
                    if showsProBadge {
                        ProBadge(isCompact: true)
                            .padding(5)
                    }
                }
                Text(mode.title)
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(AppColor.primaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ElementTileButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showsProBadge
                            ? "\(mode.title), Periodic Pro feature. \(mode.subtitle)"
                            : "\(mode.title). \(mode.subtitle)")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("study.mode.\(mode.rawValue)")
    }
}

/// A section heading with something useful on the right.
///
/// Used for "Practice" with the remaining free rounds, and for "Recent
/// searches" with Clear. The trailing slot is only ever filled with a real
/// control or a real number — never a link to a screen that does not exist.
struct StudySectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(AppFont.sectionTitle)
                .foregroundStyle(AppColor.primaryText)
            Spacer(minLength: Theme.Spacing.s)
            trailing()
        }
    }
}

/// One row in the recent-searches list.
///
/// Deliberately not a control. It is a record of what was looked up, which is
/// what the trailing clock says, and the only action in the section is Clear.
/// Making the row tappable would mean driving the table's `.searchable` field
/// from another tab; a row that looked tappable and was not would be worse than
/// either.
struct RecentSearchRow: View {
    let term: String

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColor.secondaryText)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(term)
                .font(AppFont.body)
                .foregroundStyle(AppColor.primaryText)
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.s)
            Image(systemName: "clock")
                .font(.system(size: 12))
                .foregroundStyle(AppColor.tertiaryText)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .frame(minHeight: Theme.minimumTouchTarget)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Searched for \(term)")
    }
}
