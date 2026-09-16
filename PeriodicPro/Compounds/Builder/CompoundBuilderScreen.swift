import SwiftUI

/// The Build tab: Compound Builder, in beta.
///
/// Combine elements, watch the formula and molar mass update, read the
/// heuristic hints, then look the composition up — in the bundled catalog
/// first, then PubChem. Nothing is invented: a formula either matches a known
/// compound, matches several, or matches none, and the screen says which.
struct CompoundBuilderScreen: View {
    @Environment(\.elementCatalog) private var catalog
    @Environment(CompoundStore.self) private var store: CompoundStore
    @Environment(ProgressStore.self) private var progress: ProgressStore

    @State private var model = CompoundBuilderModel()
    @State private var path = NavigationPath()
    @State private var showsPicker = false
    @State private var style: CompoundRenderStyle = .ballAndStick
    @State private var explored: ChemicalCompound?

    /// The family whose colors dress the result: the heaviest element added.
    private var tint: ElementCategory {
        model.entries.map(\.element).max { $0.atomicNumber < $1.atomicNumber }?.category ?? .reactiveNonmetal
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    header
                    CompositionTray(
                        entries: model.entries,
                        canAddElement: model.canAddElement,
                        onIncrement: model.increment,
                        onDecrement: model.decrement,
                        onRemove: model.remove,
                        onAdd: { showsPicker = true },
                        onClear: model.clear
                    )
                    if !model.isEmpty {
                        formulaCard
                        hintsCard
                        lookUpButton
                    }
                    BuilderResultView(
                        state: model.state,
                        tint: tint,
                        catalog: catalog,
                        isFavorite: { progress.isCompoundFavorite($0) },
                        isSaved: { progress.isCompoundSaved($0) },
                        style: $style,
                        onChoose: { model.choose($0, store: store) },
                        onSaveHypothetical: {
                            model.saveHypothetical(store: store, progress: progress, catalog: catalog)
                        },
                        onRetry: { model.lookUp(store: store, catalog: catalog) },
                        onOpenDetails: { path.append(CompoundMatchCandidate(local: $0)) },
                        onExplore: { explored = $0 },
                        onToggleFavorite: { compound in
                            Haptics.favorited(progress.toggleCompoundFavorite(compound.id))
                        },
                        onToggleSaved: { compound in
                            progress.setCompoundSaved(compound.id, !progress.isCompoundSaved(compound.id))
                        }
                    )
                    footer
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.top, Theme.Spacing.s)
                .padding(.bottom, Theme.Spacing.xxxl)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .background(AppColor.canvas)
            .navigationTitle("Build")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: CompoundMatchCandidate.self) { candidate in
                CompoundDetailScreen(candidate: candidate)
            }
            .navigationDestination(for: ChemicalElement.self) { element in
                ElementDetailScreen(element: element)
            }
            .sheet(isPresented: $showsPicker) {
                ElementPickerSheet(catalog: catalog) { element in
                    model.add(element)
                    Haptics.tap()
                }
            }
            .fullScreenCover(item: $explored) { compound in
                CompoundExplorerView(compound: compound, tint: tint, initialStyle: style)
            }
        }
        .tint(AppColor.accent)
        .accessibilityIdentifier("build.screen")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                Text("Compound Builder")
                    .font(.system(.title2, weight: .bold))
                    .foregroundStyle(AppColor.primaryText)
                BetaBadge()
                    .accessibilityIdentifier("build.beta")
            }
            Text("Combine elements and look the composition up in the Elemora catalog and PubChem. "
                 + "The builder is in beta and is free for everyone.")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("build.header")
    }

    private var formulaCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Formula")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
                Text(model.displayFormula(catalog: catalog))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.primaryText)
                    .minimumScaleFactor(0.4)
                    .lineLimit(2)
                    .accessibilityLabel("Formula " + CompoundFormula.spoken(model.hillFormula(catalog: catalog)))
                    .accessibilityIdentifier("build.formula")
                HStack(spacing: Theme.Spacing.l) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hill formula")
                            .font(AppFont.caption2)
                            .foregroundStyle(AppColor.tertiaryText)
                        Text(model.hillFormula(catalog: catalog))
                            .font(.system(.footnote, design: .monospaced, weight: .medium))
                            .foregroundStyle(AppColor.secondaryText)
                    }
                    if let mass = model.molarMass(catalog: catalog) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Molar mass")
                                .font(AppFont.caption2)
                                .foregroundStyle(AppColor.tertiaryText)
                            Text("\((mass * 100).rounded() / 100) g/mol")
                                .font(.system(.footnote, weight: .medium).monospacedDigit())
                                .foregroundStyle(AppColor.secondaryText)
                                .accessibilityIdentifier("build.molarMass")
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Atoms")
                            .font(AppFont.caption2)
                            .foregroundStyle(AppColor.tertiaryText)
                        Text("\(model.totalAtoms)")
                            .font(.system(.footnote, weight: .medium).monospacedDigit())
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var hintsCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.s) {
                    Text("Heuristic hints")
                        .font(AppFont.cardTitle)
                        .foregroundStyle(AppColor.primaryText)
                    Text("NOT A VERIFICATION")
                        .font(.system(size: 9, weight: .semibold))
                        .kerning(0.6)
                        .foregroundStyle(AppColor.secondaryText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background { Capsule().fill(AppColor.surfaceMuted) }
                }
                ForEach(ValenceHints.hints(for: model.composition, catalog: catalog)) { hint in
                    HStack(alignment: .top, spacing: Theme.Spacing.s) {
                        Image(systemName: symbol(for: hint.kind))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(hint.kind == .balanced ? AppColor.positive : AppColor.secondaryText)
                            .frame(width: 18)
                            .accessibilityHidden(true)
                        Text(hint.text)
                            .font(AppFont.footnote)
                            .foregroundStyle(AppColor.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Hints use a short table of common oxidation states. They never decide whether a "
                     + "compound exists; the lookup does.")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("build.hints")
    }

    private func symbol(for kind: ValenceHints.Kind) -> String {
        switch kind {
        case .balanced: return "checkmark.circle.fill"
        case .unbalanced, .noData: return "questionmark.circle"
        case .nobleGas, .elementalForm: return "info.circle"
        }
    }

    private var lookUpButton: some View {
        Button {
            Haptics.tap()
            model.lookUp(store: store, catalog: catalog)
        } label: {
            Label("Look up this composition", systemImage: "magnifyingglass")
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.vertical, Theme.Spacing.s)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(AppColor.accent)
                }
        }
        .buttonStyle(.plain)
        .disabled(model.state == .searching)
        .accessibilityIdentifier("build.lookUp")
    }

    private var footer: some View {
        Text("Elemora looks a composition up in its bundled catalog first. If nothing matches, the Hill "
             + "formula is sent to PubChem. That is the only thing sent, and only when you tap Look up.")
            .font(AppFont.caption2)
            .foregroundStyle(AppColor.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("build.footer")
    }
}
