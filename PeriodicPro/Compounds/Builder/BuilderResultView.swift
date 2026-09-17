import SwiftUI

/// The builder's result card: a known compound, drawn and named.
///
/// Concise on purpose. The structure, the name, the formula, what kind of
/// compound it is, and the three things there are to do with it. Everything
/// else — properties, classification, the elements in it, the 3D explorer —
/// lives on `CompoundDetailScreen`, which View Details opens.
///
/// Saving and favoriting are separate, and labeled as such: the heart is a
/// favorite, the bookmark is study material. Both cache the record first, so
/// a compound fetched from PubChem is still there next launch.
struct BuilderResultView: View {
    let compound: ChemicalCompound
    /// True for a composition the learner kept with no database match.
    let isHypothetical: Bool
    let isFavorite: Bool
    let isSaved: Bool
    let onToggleFavorite: () -> Void
    let onToggleSaved: () -> Void
    let onOpenDetails: () -> Void
    let onExplore: () -> Void

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Compound2DStructureCard(compound: compound, height: 210, showsCaption: false)

                VStack(alignment: .leading, spacing: 4) {
                    Text(compound.preferredName)
                        .font(.system(.title2, weight: .bold))
                        .foregroundStyle(AppColor.primaryText)
                        .lineLimit(2)
                        .accessibilityIdentifier("build.result.name")
                    HStack(spacing: Theme.Spacing.s) {
                        Text(compound.displayFormula)
                            .font(.system(.body, design: .rounded, weight: .medium))
                            .foregroundStyle(AppColor.secondaryText)
                        if let mass = compound.molarMassDisplay {
                            Text(mass)
                                .font(AppFont.footnote)
                                .foregroundStyle(AppColor.tertiaryText)
                        }
                    }
                    if compound.bondingClass != .unknown {
                        Text(compound.bondingClass.displayName)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(compound.accessibilityDescription)
                .accessibilityIdentifier("build.result.summary")

                HStack(spacing: Theme.Spacing.s) {
                    if !isHypothetical {
                        action(
                            title: isSaved ? "Saved" : "Save",
                            symbol: isSaved ? "bookmark.fill" : "bookmark",
                            isOn: isSaved,
                            label: isSaved ? "Remove from study material" : "Save to study material",
                            identifier: "build.result.save",
                            action: onToggleSaved
                        )
                    }
                    action(
                        title: isFavorite ? "Favorited" : "Favorite",
                        symbol: isFavorite ? "heart.fill" : "heart",
                        isOn: isFavorite,
                        label: isFavorite ? "Remove from favorites" : "Add to favorites",
                        identifier: "build.result.favorite",
                        action: onToggleFavorite
                    )
                    action(
                        title: "Details",
                        symbol: "arrow.up.right",
                        isOn: false,
                        label: "View full details for \(compound.preferredName)",
                        identifier: "build.result.details",
                        action: onOpenDetails
                    )
                }

                if compound.hasStructure, !isHypothetical {
                    Button {
                        Haptics.tap()
                        onExplore()
                    } label: {
                        Label("Explore in 3D", systemImage: "cube.fill")
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(AppColor.accent)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 46)
                            .background {
                                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                    .fill(AppColor.accent.opacity(0.10))
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("build.result.explore3D")
                }

                Text(compound.attribution)
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("build.result.attribution")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build.result")
    }

    private func action(
        title: String,
        symbol: String,
        isOn: Bool,
        label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.system(.caption, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(isOn ? Color.white : AppColor.accent)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 54)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(isOn ? AppColor.accent : AppColor.accent.opacity(0.08))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(identifier)
    }
}
