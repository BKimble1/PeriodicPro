import SwiftUI

/// What the lookup found, in the builder's own words.
///
/// Four honest outcomes: a match, several matches to choose between, a
/// confirmed miss with the option of keeping the composition as
/// hypothetical, and a failure to ask at all.
struct BuilderResultView: View {
    let state: CompoundBuilderModel.LookupState
    let tint: ElementCategory
    let catalog: ElementCatalog
    let isFavorite: (String) -> Bool
    let isSaved: (String) -> Bool
    @Binding var style: CompoundRenderStyle
    let onChoose: (CompoundMatchCandidate) -> Void
    let onSaveHypothetical: () -> Void
    let onRetry: () -> Void
    let onOpenDetails: (ChemicalCompound) -> Void
    let onExplore: (ChemicalCompound) -> Void
    let onToggleFavorite: (ChemicalCompound) -> Void
    let onToggleSaved: (ChemicalCompound) -> Void

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .searching:
            CardContainer {
                HStack(spacing: Theme.Spacing.m) {
                    ProgressView()
                    Text("Looking this composition up…")
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.secondaryText)
                }
            }
            .accessibilityIdentifier("build.searching")
        case .matched(let compound):
            resultCard(compound, title: "Known compound")
        case .hypothetical(let compound):
            resultCard(compound, title: "Hypothetical composition")
        case .choices(let candidates):
            choicesCard(candidates)
        case .noMatch:
            noMatchCard
        case .failed(let message):
            CardContainer {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Could not check PubChem")
                        .font(AppFont.cardTitle)
                        .foregroundStyle(AppColor.primaryText)
                    Text(message)
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Nothing has been decided about this composition: the catalog has no match and "
                         + "PubChem could not be asked.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try again", action: onRetry)
                        .buttonStyle(.borderedProminent)
                        .tint(AppColor.accent)
                        .accessibilityIdentifier("build.retry")
                }
            }
            .accessibilityIdentifier("build.failed")
        }
    }

    private func choicesCard(_ candidates: [CompoundMatchCandidate]) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Multiple known compounds share this formula.")
                    .font(AppFont.cardTitle)
                    .foregroundStyle(AppColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("A formula gives the atoms, not how they are joined. Choose the compound you mean.")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: Theme.Spacing.s) {
                    ForEach(candidates) { candidate in
                        Button {
                            Haptics.tap()
                            onChoose(candidate)
                        } label: {
                            CompoundRow(candidate: candidate, isFavorite: isFavorite(candidate.id))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("build.candidate.\(candidate.cid)")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build.candidates")
    }

    private var noMatchCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("No known PubChem match found.")
                    .font(AppFont.cardTitle)
                    .foregroundStyle(AppColor.primaryText)
                Text("This composition may be hypothetical, unstable, unindexed, or otherwise unknown. "
                     + "A database miss is not evidence of a new chemical discovery.")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Haptics.tap()
                    onSaveHypothetical()
                } label: {
                    Text("Save as hypothetical composition")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(AppColor.accent)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .background {
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .fill(AppColor.accent.opacity(0.10))
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("build.saveHypothetical")
                Text("Saved with its formula and molar mass only. No name, structure or property is invented.")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build.noMatch")
    }

    private func resultCard(_ compound: ChemicalCompound, title: String) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(AppFont.cardTitle)
                        .foregroundStyle(AppColor.primaryText)
                    Spacer()
                    Text(compound.dataSource.displayName)
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.tertiaryText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background { Capsule().fill(AppColor.surfaceMuted) }
                }

                HStack(spacing: Theme.Spacing.m) {
                    CompoundTile(formula: compound.formula, size: 64, tint: tint.accentColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(compound.preferredName)
                            .font(.system(.title3, weight: .semibold))
                            .foregroundStyle(AppColor.primaryText)
                            .lineLimit(2)
                        if let mass = compound.molarMassDisplay {
                            Text(mass)
                                .font(AppFont.footnote)
                                .foregroundStyle(AppColor.secondaryText)
                        }
                        if compound.bondingClass != .unknown {
                            Text(compound.bondingClass.displayName)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.secondaryText)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(compound.accessibilityDescription)
                .accessibilityIdentifier("build.result.summary")

                if let scene = CompoundStructureScene.scene(for: compound, style: style) {
                    StructurePreview(scene: scene, accent: tint.accentColor)
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                        .background {
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .fill(tint.tileFill.opacity(0.5))
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(CompoundFactsBuilder.summary(of: scene, compound: compound,
                                                                         catalog: catalog))
                        .accessibilityIdentifier("build.result.preview")
                    Picker("Style", selection: $style) {
                        ForEach(CompoundRenderStyle.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("build.result.style")
                    Text(scene.representationLabel + " · " + scene.caption)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(4)
                    Button {
                        Haptics.tap()
                        onExplore(compound)
                    } label: {
                        Label("Explore in 3D", systemImage: "cube.fill")
                            .font(.system(.body, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                            .background {
                                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                    .fill(AppColor.accent)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("build.result.explore3D")
                } else if compound.isHypothetical {
                    Text("No structure is shown because none is known.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }

                HStack(spacing: Theme.Spacing.s) {
                    secondaryButton(isFavorite(compound.id) ? "Favorited" : "Favorite",
                                    symbol: isFavorite(compound.id) ? "heart.fill" : "heart",
                                    identifier: "build.result.favorite") { onToggleFavorite(compound) }
                    if !compound.isHypothetical {
                        secondaryButton(isSaved(compound.id) ? "In Study" : "Add to Study",
                                        symbol: isSaved(compound.id) ? "checkmark" : "graduationcap.fill",
                                        identifier: "build.result.addToStudy") { onToggleSaved(compound) }
                    }
                    secondaryButton("Details", symbol: "arrow.up.right",
                                    identifier: "build.result.details") { onOpenDetails(compound) }
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

    private func secondaryButton(_ title: String, symbol: String, identifier: String,
                                 action: @escaping () -> Void) -> some View {
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
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(AppColor.accent)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(AppColor.accent.opacity(0.08))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
