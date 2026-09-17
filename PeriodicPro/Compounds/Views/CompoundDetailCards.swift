import SwiftUI

/// The formula, large, with the name beneath it.
struct CompoundHero: View {
    let compound: ChemicalCompound
    let tint: ElementCategory

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                    .fill(tint.heroGradient)
                RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                    .strokeBorder(tint.accentColor.opacity(0.16), lineWidth: 1)
                Text(compound.displayFormula)
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(tint.onTileColor)
                    .minimumScaleFactor(0.4)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(Theme.Spacing.xl)
            }
            .frame(height: 176)
            .frame(maxWidth: .infinity)
            .themeShadow(Theme.Shadow.raised)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(compound.accessibilityDescription)
            .accessibilityIdentifier("compound.hero")

            VStack(spacing: Theme.Spacing.s) {
                Text(compound.preferredName)
                    .font(.system(.title, weight: .bold))
                    .foregroundStyle(AppColor.primaryText)
                    .multilineTextAlignment(.center)
                if let iupac = compound.iupacName, iupac.lowercased() != compound.preferredName.lowercased() {
                    Text(iupac)
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: Theme.Spacing.s) {
                    if compound.bondingClass != .unknown {
                        chip(compound.bondingClass.displayName)
                    }
                    ForEach(compound.tags, id: \.self) { tag in
                        chip(tag.displayName)
                    }
                    if compound.isHypothetical {
                        chip("Hypothetical")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, weight: .semibold))
            .foregroundStyle(tint.onTileColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background { Capsule(style: .continuous).fill(tint.tileFill) }
    }
}

/// The structure: a glossy preview, the honesty label, a style switch and the
/// way into the 3D explorer. For a compound with no drawn structure it says
/// so instead of drawing something.
struct CompoundStructureCard: View {
    let compound: ChemicalCompound
    @Binding var style: CompoundRenderStyle
    let tint: ElementCategory
    let catalog: ElementCatalog
    let onExplore: () -> Void

    private var scene: StructureScene? {
        guard compound.structure?.isRenderable ?? false else { return nil }
        return CompoundStructureScene.scene(for: compound, style: style)
    }

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Structure")
                    .font(AppFont.cardTitle)
                    .foregroundStyle(AppColor.primaryText)

                if let scene {
                    StructurePreview(scene: scene, accent: tint.accentColor)
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .background {
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .fill(tint.tileFill.opacity(0.5))
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(CompoundFactsBuilder.summary(of: scene, compound: compound,
                                                                         catalog: catalog))
                        .accessibilityIdentifier("compound.preview")

                    Picker("Style", selection: $style) {
                        ForEach(CompoundRenderStyle.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("compound.structureStyle")

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: Theme.Spacing.s) {
                            Text(scene.representationLabel)
                                .font(.system(.caption, weight: .semibold))
                                .foregroundStyle(AppColor.secondaryText)
                                .textCase(.uppercase)
                                .kerning(0.5)
                            if scene.isSimplified { SimplifiedBadge() }
                        }
                        Text(scene.caption)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        provenanceNote
                    }

                    Button(action: onExplore) {
                        HStack(spacing: Theme.Spacing.s) {
                            Image(systemName: "cube.fill")
                            Text("Explore in 3D")
                        }
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, Theme.Spacing.s)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .background {
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .fill(AppColor.accent)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("compound.explore3D")
                } else {
                    Text(missingStructureNote)
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("compound.noStructure")
                }
            }
        }
    }

    /// Where the coordinates came from, and when.
    ///
    /// Said out loud rather than left to be inferred: a conformer is a
    /// computed geometry, a depiction is a drawing, and a layout generated
    /// from connectivity is the app's own arrangement of somebody else's
    /// molecule. All three are honest; they are not the same claim.
    @ViewBuilder
    private var provenanceNote: some View {
        if let structure = compound.structure {
            let provenance = structure.resolvedProvenance
            VStack(alignment: .leading, spacing: 1) {
                if let source = provenance.threeDSource {
                    Text("3D: \(source.displayName)")
                } else {
                    Text("3D conformer not available. The structure below is the published "
                         + "connectivity, drawn flat.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let source = provenance.twoDSource {
                    Text("2D: \(source.displayName)")
                }
                if let cid = provenance.pubChemCID ?? compound.pubChemCID {
                    Text("PubChem CID \(cid)\(provenance.retrieved.map { ", retrieved \($0)" } ?? "")")
                }
            }
            .font(AppFont.caption2)
            .foregroundStyle(AppColor.tertiaryText)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("compound.structureProvenance")
        }
    }

    private var missingStructureNote: String {
        if let structure = compound.structure, !structure.isRenderable, !structure.atoms.isEmpty {
            // A limit of the renderer, described as one. The molecule is
            // known; drawing this many spheres at once is what is not
            // practical.
            return "This molecule has \(structure.atoms.count) atoms, which is more than Elemora "
                + "draws one at a time. Its formula, composition and molar mass are all exact; only "
                + "the atom-by-atom picture is left out."
        }
        if compound.isHypothetical {
            return "No structure is drawn. This composition matched nothing in PubChem, and Elemora does not "
                + "invent a structure for it."
        }
        if compound.bondingClass == .networkSolid {
            return "No molecular picture is drawn: this is a network solid, an extended structure with no "
                + "separate molecules. Its formula gives the ratio of atoms, not a molecule."
        }
        return "No structure record is available for this compound."
    }
}

/// Formula, molar mass, and the identifiers behind the record.
struct CompoundFactsCard: View {
    let compound: ChemicalCompound

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Key facts")
                    .font(AppFont.cardTitle)
                    .foregroundStyle(AppColor.primaryText)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.s) {
                    FactRow(label: "Formula", value: compound.displayFormula)
                    FactRow(label: "Hill formula", value: compound.hillFormula, monospacedValue: true)
                    if let mass = compound.molarMassDisplay {
                        FactRow(label: "Molar mass", value: mass,
                                footnote: compound.isLocalCurated ? "From IUPAC 2021 atomic weights" : nil)
                    }
                    FactRow(label: "Atoms per formula unit", value: "\(compound.composition.values.reduce(0, +))")
                    if compound.charge != 0 {
                        FactRow(label: "Charge",
                                value: compound.charge > 0 ? "+\(compound.charge)" : "\(compound.charge)")
                    }
                    if let cid = compound.pubChemCID {
                        FactRow(label: "PubChem CID", value: "\(cid)", monospacedValue: true)
                    }
                }
            }
        }
    }
}

/// Bonding class and tags, with the source of the classification, or an
/// honest "not classified".
struct CompoundClassificationCard: View {
    let compound: ChemicalCompound

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Classification")
                    .font(AppFont.cardTitle)
                    .foregroundStyle(AppColor.primaryText)
                if compound.bondingClass == .unknown {
                    Text(compound.isHypothetical
                         ? "Not classified. Nothing is known about this composition."
                         : "Not classified. Elemora only classifies the bundled compounds, where the constituents "
                           + "make the bonding type clear; PubChem records are shown as they are.")
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(compound.bondingClass.displayName)
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(AppColor.primaryText)
                    if !compound.tags.isEmpty {
                        Text(compound.tags.map(\.displayName).joined(separator: " · "))
                            .font(AppFont.footnote)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                    if let source = compound.classificationSource {
                        Text("Basis: \(source)")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.tertiaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// The elements in the formula, each a link to its own page.
struct CompoundElementsCard: View {
    let compound: ChemicalCompound
    let catalog: ElementCatalog

    private var rows: [(element: ChemicalElement, count: Int)] {
        compound.composition.keys.sorted().compactMap { number in
            guard let element = catalog.element(atomicNumber: number), let count = compound.composition[number] else {
                return nil
            }
            return (element, count)
        }
    }

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Elements")
                    .font(AppFont.cardTitle)
                    .foregroundStyle(AppColor.primaryText)
                VStack(spacing: Theme.Spacing.s) {
                    ForEach(rows, id: \.element.atomicNumber) { row in
                        NavigationLink(value: row.element) {
                            HStack(spacing: Theme.Spacing.m) {
                                ElementTile(element: row.element, size: 44, density: .standard)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.element.name)
                                        .font(.system(.body, weight: .medium))
                                        .foregroundStyle(AppColor.primaryText)
                                    Text(row.element.category.displayName)
                                        .font(AppFont.caption)
                                        .foregroundStyle(AppColor.secondaryText)
                                }
                                Spacer(minLength: 0)
                                Text("× \(row.count)")
                                    .font(.system(.body, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(AppColor.secondaryText)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(AppColor.tertiaryText)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(row.count) \(row.element.name)")
                        .accessibilityIdentifier("compound.element.\(row.element.symbol)")
                    }
                }
            }
        }
    }
}

/// Add to Study, and how familiar the compound is so far.
struct CompoundStudyCard: View {
    let compound: ChemicalCompound
    let snapshot: CompoundProgressSnapshot
    let onToggleStudy: (Bool) -> Void

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Study")
                    .font(AppFont.cardTitle)
                    .foregroundStyle(AppColor.primaryText)
                Toggle(isOn: Binding(get: { snapshot.isSaved }, set: onToggleStudy)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add to Study")
                            .font(.system(.body, weight: .medium))
                            .foregroundStyle(AppColor.primaryText)
                        Text("Include this compound in quizzes and Match rounds.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }
                .tint(AppColor.accent)
                .accessibilityIdentifier("compound.addToStudy")
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: snapshot.mastery.symbolName)
                        .foregroundStyle(snapshot.mastery.tint)
                    Text(snapshot.mastery.displayName)
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.secondaryText)
                    if snapshot.attempts > 0 {
                        Text("· \(snapshot.correctCount) of \(snapshot.attempts) correct")
                            .font(AppFont.footnote)
                            .foregroundStyle(AppColor.tertiaryText)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
