import SwiftUI

/// A compound's page: formula hero, structure, facts, classification, the
/// elements in it, and its place in Study.
///
/// Opened from a search hit, a builder result or a shelf. A candidate that
/// the device does not yet hold in full is fetched from PubChem here, and
/// cached so the page works offline from then on.
struct CompoundDetailScreen: View {
    let candidate: CompoundMatchCandidate

    @Environment(\.elementCatalog) private var catalog
    @Environment(CompoundStore.self) private var store: CompoundStore
    @Environment(ProgressStore.self) private var progress: ProgressStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var compound: ChemicalCompound?
    @State private var loadError: String?
    @State private var style: CompoundRenderStyle = .ballAndStick
    @State private var showsExplorer = false

    private var compoundID: String { compound?.id ?? candidate.id }
    private var isFavorite: Bool { progress.isCompoundFavorite(compoundID) }

    /// The family whose colors dress the page: the heaviest element in the
    /// formula, which for a salt is the metal and for water is oxygen.
    private var tint: ElementCategory {
        let numbers = (compound?.composition ?? CompoundFormula.parse(candidate.hillFormula) ?? [:]).keys
        guard let heaviest = numbers.max(), let element = catalog.element(atomicNumber: heaviest) else {
            return .reactiveNonmetal
        }
        return element.category
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                if let compound {
                    content(compound)
                } else if let loadError {
                    EmptyStateView(
                        symbolName: "exclamationmark.triangle",
                        title: "Could not load this compound",
                        message: loadError,
                        actionTitle: "Try again",
                        action: { Task { await load() } }
                    )
                    .accessibilityIdentifier("compound.loadError")
                } else {
                    VStack(spacing: Theme.Spacing.m) {
                        ProgressView()
                        Text("Loading from PubChem…")
                            .font(AppFont.footnote)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.Spacing.xxxl)
                    .accessibilityIdentifier("compound.loading")
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .scrollIndicators(.hidden)
        .background {
            ZStack {
                AppColor.canvas
                tint.backdropGradient.opacity(0.6)
            }
            .ignoresSafeArea()
        }
        .navigationTitle(compound?.preferredName ?? candidate.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task(id: candidate.id) { await load() }
        .fullScreenCover(isPresented: $showsExplorer) {
            if let compound {
                CompoundExplorerView(compound: compound, tint: tint, initialStyle: style)
            }
        }
        .accessibilityIdentifier("compound.screen")
    }

    @ViewBuilder
    private func content(_ compound: ChemicalCompound) -> some View {
        CompoundHero(compound: compound, tint: tint)
            .padding(.bottom, Theme.Spacing.xs)
        CardContainer {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Structure diagram")
                    .font(AppFont.cardTitle)
                    .foregroundStyle(AppColor.primaryText)
                Compound2DStructureCard(compound: compound, height: 220)
            }
        }
        .softRise(enabled: !reduceMotion)
        CompoundStructureCard(
            compound: compound, style: $style, tint: tint, catalog: catalog,
            onExplore: { showsExplorer = true }
        )
        .softRise(enabled: !reduceMotion)
        CompoundFactsCard(compound: compound).softRise(enabled: !reduceMotion)
        if let summary = compound.summary {
            CardContainer {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("About")
                        .font(AppFont.cardTitle)
                        .foregroundStyle(AppColor.primaryText)
                    Text(summary)
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .softRise(enabled: !reduceMotion)
        }
        if compound.isHypothetical {
            hypotheticalNotice.softRise(enabled: !reduceMotion)
        }
        CompoundClassificationCard(compound: compound).softRise(enabled: !reduceMotion)
        CompoundElementsCard(compound: compound, catalog: catalog).softRise(enabled: !reduceMotion)
        if !compound.isHypothetical {
            CompoundStudyCard(
                compound: compound,
                snapshot: progress.compoundSnapshot(for: compound.id),
                onToggleStudy: { isOn in
                    // Cached first, then the state: a PubChem record the
                    // learner adds to Study has to still resolve next launch.
                    store.retain(compound)
                    progress.setCompoundSaved(compound.id, isOn)
                    Haptics.tap()
                }
            )
            .softRise(enabled: !reduceMotion)
        }
        attribution(compound)
    }

    private var hypotheticalNotice: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Hypothetical composition")
                    .font(AppFont.cardTitle)
                    .foregroundStyle(AppColor.primaryText)
                Text("No known PubChem match found. This composition may be hypothetical, unstable, unindexed, "
                     + "or otherwise unknown. A database miss is not evidence of a new chemical discovery.")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("compound.hypotheticalNotice")
    }

    private func attribution(_ compound: ChemicalCompound) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(compound.attribution)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
            if compound.dataSource != .hypothetical {
                Text("PubChem is a database of the National Library of Medicine. Names, formulas and structures "
                     + "shown here come from the record named above.")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.Spacing.s)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("compound.attribution")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                if let compound { store.retain(compound) }
                let nowFavorite = progress.toggleCompoundFavorite(compoundID)
                Haptics.favorited(nowFavorite)
            } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isFavorite ? tint.accentColor : AppColor.secondaryText)
                    .symbolEffect(.bounce, value: reduceMotion ? false : isFavorite)
                    .frame(width: Theme.minimumTouchTarget, height: Theme.minimumTouchTarget)
                    .contentShape(Rectangle())
            }
            .disabled(compound == nil)
            .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
            .accessibilityIdentifier("compound.favoriteButton")
        }
    }

    @MainActor
    private func load() async {
        loadError = nil
        do {
            compound = try await store.resolve(candidate)
        } catch let error as PubChemError {
            loadError = error.userMessage
        } catch {
            loadError = "The compound could not be loaded."
        }
    }
}
