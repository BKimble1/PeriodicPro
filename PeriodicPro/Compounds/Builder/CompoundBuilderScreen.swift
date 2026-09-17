import SwiftUI

/// The Build tab: find a compound, or build one.
///
/// Two ways in, in the order people want them. The search field at the top
/// answers "what is caffeine" without any chemistry at all; the composition
/// editor under it answers "what is two hydrogens and an oxygen" and names it
/// the moment the formula is recognizable.
///
/// Nothing is invented at any point. A formula either matches a record, matches
/// several, or matches none, and the screen says which — the giant "Look up
/// this composition" button is gone because the answer now arrives by itself.
struct CompoundBuilderScreen: View {
    @Environment(\.elementCatalog) private var catalog
    @Environment(CompoundStore.self) private var store: CompoundStore
    @Environment(ProgressStore.self) private var progress: ProgressStore

    @State private var model = CompoundBuilderModel()
    @State private var search = CompoundSearchModel()
    @State private var query = ""
    @State private var path = NavigationPath()
    @State private var showsPicker = false
    @State private var explored: ChemicalCompound?
    @State private var showsHints = false

    /// The family whose colors dress the result: the heaviest element added.
    private var tint: ElementCategory {
        model.entries.map(\.element).max { $0.atomicNumber < $1.atomicNumber }?.category ?? .reactiveNonmetal
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    header
                    CompoundSearchField(query: $query)
                    if isSearching {
                        CompoundSearchSection(
                            model: search,
                            isFavorite: { progress.isCompoundFavorite($0) },
                            mastery: { progress.compoundMastery(for: $0) },
                            onSelect: { path.append($0) },
                            onRetry: { search.retry(store: store) },
                            horizontalPadding: 0
                        )
                    } else {
                        builder
                    }
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
                CompoundExplorerView(compound: compound, tint: tint, initialStyle: .ballAndStick)
            }
            .task { model.configure(store: store, catalog: catalog) }
            .onChange(of: query) { _, newValue in
                search.update(query: newValue, store: store)
            }
            .onDisappear { search.cancel() }
        }
        .tint(AppColor.accent)
        .accessibilityIdentifier("build.screen")
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.s) {
                Text("Compound Builder")
                    .font(.system(.title3, weight: .bold))
                    .foregroundStyle(AppColor.primaryText)
                BetaBadge()
                    .accessibilityIdentifier("build.beta")
            }
            Text("Search a compound, or build a composition and Elemora names it.")
                .font(AppFont.footnote)
                .foregroundStyle(AppColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("build.header")
    }

    // MARK: - Builder

    @ViewBuilder
    private var builder: some View {
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
            BuilderIdentityCard(
                formula: model.displayFormula(catalog: catalog),
                hillFormula: model.hillFormula(catalog: catalog),
                molarMass: model.molarMass(catalog: catalog),
                atomCount: model.totalAtoms,
                state: model.state,
                statusMessage: model.statusMessage,
                onChoose: { model.choose($0, store: store) },
                onOpenDetails: { path.append(CompoundMatchCandidate(local: $0)) },
                onSaveHypothetical: {
                    model.saveHypothetical(store: store, progress: progress, catalog: catalog)
                },
                onRetry: { model.lookUp(store: store, catalog: catalog) }
            )

            result

            hints
        }

        footer
    }

    @ViewBuilder
    private var result: some View {
        switch model.state {
        case .matched(let compound):
            resultCard(compound, isHypothetical: false)
        case .hypothetical(let compound):
            resultCard(compound, isHypothetical: true)
        case .idle, .searching, .choices, .noMatch, .failed:
            EmptyView()
        }
    }

    private func resultCard(_ compound: ChemicalCompound, isHypothetical: Bool) -> some View {
        BuilderResultView(
            compound: compound,
            isHypothetical: isHypothetical,
            isFavorite: progress.isCompoundFavorite(compound.id),
            isSaved: progress.isCompoundSaved(compound.id),
            onToggleFavorite: {
                // Cached before the state is written: progress stores an
                // identifier, and an identifier that resolves to nothing is
                // how a favorite disappears from Study on the next launch.
                store.retain(compound)
                Haptics.favorited(progress.toggleCompoundFavorite(compound.id))
            },
            onToggleSaved: {
                store.retain(compound)
                progress.setCompoundSaved(compound.id, !progress.isCompoundSaved(compound.id))
            },
            onOpenDetails: { path.append(CompoundMatchCandidate(local: compound)) },
            onExplore: { explored = compound }
        )
    }

    /// The oxidation-state hints, behind a disclosure. Useful, and never the
    /// first thing on the screen: they are a heuristic, and the identification
    /// above them is a record.
    private var hints: some View {
        CardContainer {
            DisclosureGroup(isExpanded: $showsHints) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    ForEach(ValenceHints.hints(for: model.composition, catalog: catalog)) { hint in
                        HStack(alignment: .top, spacing: Theme.Spacing.s) {
                            Image(systemName: symbol(for: hint.kind))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(hint.kind == .balanced
                                                 ? AppColor.positive : AppColor.secondaryText)
                                .frame(width: 18)
                                .accessibilityHidden(true)
                            Text(hint.text)
                                .font(AppFont.footnote)
                                .foregroundStyle(AppColor.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text("Hints use a short table of common oxidation states. They never decide whether "
                         + "a compound exists; the lookup does.")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Theme.Spacing.s)
            } label: {
                HStack(spacing: Theme.Spacing.s) {
                    Text("Bonding hints")
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
            }
            .tint(AppColor.accent)
        }
        .accessibilityIdentifier("build.hints")
    }

    private func symbol(for kind: ValenceHints.Kind) -> String {
        switch kind {
        case .balanced: return "checkmark.circle.fill"
        case .unbalanced, .noData: return "questionmark.circle"
        case .nobleGas, .elementalForm: return "info.circle"
        }
    }

    private var footer: some View {
        Text("Elemora checks its own catalog first. A formula it does not know is sent to PubChem "
             + "once you stop editing — nothing else is sent, and nothing about you travels with it.")
            .font(AppFont.caption2)
            .foregroundStyle(AppColor.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("build.footer")
    }
}
