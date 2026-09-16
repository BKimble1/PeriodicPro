import SwiftUI

/// A square tile for a compound, the sibling of `ElementTile`: the formula
/// with real subscripts on a soft fill.
struct CompoundTile: View {
    let formula: String
    var size: CGFloat = 52
    var tint: Color = AppColor.accent

    var body: some View {
        Text(CompoundFormula.subscripted(formula))
            .font(.system(size: size * 0.30, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .minimumScaleFactor(0.45)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(size * 0.08)
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: ElementTileShape.cornerRadius(for: size), style: .continuous)
                    .fill(tint.opacity(0.12))
            }
            .overlay {
                RoundedRectangle(cornerRadius: ElementTileShape.cornerRadius(for: size), style: .continuous)
                    .strokeBorder(tint.opacity(0.22), lineWidth: 0.6)
            }
            .accessibilityHidden(true)
    }
}

/// One compound in a list: tile, name, formula and where it came from.
struct CompoundRow: View {
    let candidate: CompoundMatchCandidate
    var isFavorite = false
    var mastery: MasteryLevel = .notStarted

    private var sourceLabel: String? {
        guard let local = candidate.local else { return "PubChem" }
        switch local.dataSource {
        case .curated: return nil
        case .pubChem: return "Saved from PubChem"
        case .hypothetical: return "Hypothetical composition"
        }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            CompoundTile(formula: candidate.local?.formula ?? candidate.hillFormula)

            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.name)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(AppColor.primaryText)
                    .lineLimit(2)
                HStack(spacing: Theme.Spacing.s) {
                    Text(candidate.displayFormula)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                    if let mass = candidate.local?.molarMassDisplay ?? candidate.molarMass.map({
                        "\((($0 * 100).rounded()) / 100) g/mol"
                    }) {
                        Text(mass)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.tertiaryText)
                    }
                    if let sourceLabel {
                        Text(sourceLabel)
                            .font(AppFont.caption2)
                            .foregroundStyle(AppColor.tertiaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background { Capsule().fill(AppColor.surfaceMuted) }
                    }
                }
            }

            Spacer(minLength: 0)

            if isFavorite {
                Image(systemName: "heart.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.accent)
            }
            if mastery == .mastered {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColor.positive)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColor.tertiaryText)
        }
        .padding(Theme.Spacing.m)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(AppColor.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .strokeBorder(AppColor.hairline, lineWidth: 0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: String {
        var parts = ["\(candidate.name), formula \(CompoundFormula.spoken(candidate.hillFormula))"]
        if let sourceLabel { parts.append(sourceLabel) }
        if isFavorite { parts.append("favorite") }
        return parts.joined(separator: ", ")
    }
}

/// The small capsule that marks a feature as a beta.
struct BetaBadge: View {
    var body: some View {
        Text("BETA")
            .font(.system(size: 10, weight: .bold))
            .kerning(0.8)
            .foregroundStyle(AppColor.warning)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background { Capsule().fill(AppColor.warning.opacity(0.12)) }
            .overlay { Capsule().strokeBorder(AppColor.warning.opacity(0.35), lineWidth: 0.7) }
            .accessibilityLabel("Beta")
    }
}
