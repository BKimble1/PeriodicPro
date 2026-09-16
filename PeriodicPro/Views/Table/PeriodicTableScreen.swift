import SwiftUI

/// The app's primary screen: search, filters, the full periodic table and the
/// color key — and the source side of the signature zoom transition.
///
/// The table is pinch-to-zoom (`ZoomableTableView`). Its zoom, scroll position
/// and last offset are owned here rather than by the table view, so that
/// searching (which replaces the table with a results list) and opening an
/// element (which pushes a page over it) both return the learner to the same
/// place at the same size.
struct PeriodicTableScreen: View {
    @Environment(\.elementCatalog) private var catalog
    @Environment(ProgressStore.self) private var progress: ProgressStore
    @Environment(CompoundStore.self) private var compounds: CompoundStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var query = ""
    /// The compound half of the search: local at once, PubChem after a pause.
    @State private var compoundSearch = CompoundSearchModel()
    @State private var filter: ElementFilter = .all
    @State private var path = NavigationPath()
    @State private var showsFilterSheet = false
    @State private var screenWidth: CGFloat = 0
    @State private var screenHeight: CGFloat = 0

    /// 1 is every column on screen; up to 3.5× is a pinch away.
    @State private var zoom: CGFloat = 1
    @State private var tablePosition = ScrollPosition(edge: .top)
    @State private var savedTableOffset: CGPoint = .zero
    @State private var isPinching = false
    @State private var zoomCommand: ZoomCommand?
    /// Whether the accessibility-size default zoom has been applied. Once
    /// only: a learner who then pinches back out has made a choice.
    @State private var hasAppliedAccessibilityZoom = false

    @Namespace private var tableNamespace

    private static let horizontalInset = Theme.Spacing.l

    /// Width to lay the table out in. Until the first layout pass reports the
    /// real width, a modern iPhone's width is assumed so the table never paints
    /// a frame of undersized tiles.
    private var usableWidth: CGFloat {
        screenWidth > 0 ? screenWidth : 393
    }

    private var fittedTileSize: CGFloat {
        TableZoomLayout.fittedTileSize(viewportWidth: usableWidth)
    }

    /// At accessibility text sizes the fitted tiles are too small to read,
    /// so the table opens already zoomed to standard density. It is still a
    /// pinch, a double tap or the Fit button away from fitted.
    private var accessibilityStartZoom: CGFloat {
        TableZoomLayout.clampZoom(
            TableZoomLayout.standardDensityTile / max(fittedTileSize, 1) * 1.05,
            fittedTileSize: fittedTileSize
        )
    }

    private var searchResults: [ChemicalElement] {
        catalog.search(query)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                TableScreenContent(
                    catalog: catalog,
                    filter: $filter,
                    query: query,
                    results: searchResults,
                    compoundSearch: compoundSearch,
                    recentSearches: progress.recentSearches,
                    namespace: tableNamespace,
                    viewportWidth: usableWidth,
                    screenHeight: screenHeight > 0 ? screenHeight : 700,
                    zoom: $zoom,
                    tablePosition: $tablePosition,
                    savedTableOffset: $savedTableOffset,
                    isPinching: $isPinching,
                    zoomCommand: $zoomCommand,
                    isFavorite: { progress.isFavorite($0) },
                    mastery: { progress.mastery(for: $0) },
                    isCompoundFavorite: { progress.isCompoundFavorite($0) },
                    compoundMastery: { progress.compoundMastery(for: $0) },
                    onSelect: open,
                    onSelectCompound: openCompound,
                    onRetryCompounds: { compoundSearch.retry(store: compounds) },
                    onSelectRecent: { query = $0 },
                    onClearRecents: { progress.clearRecentSearches() },
                    onOpenFilters: { showsFilterSheet = true }
                )
            }
            .scrollIndicators(.hidden)
            // The page must not scroll while two fingers are zooming the table.
            .scrollDisabled(isPinching)
            .scrollDismissesKeyboard(.immediately)
            .background(AppColor.canvas)
            .navigationTitle("Periodic Table")
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Element, symbol, or number"
            )
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onSubmit(of: .search) { progress.recordSearch(query) }
            .onChange(of: query) { _, newValue in
                compoundSearch.update(query: newValue, store: compounds)
            }
            .toolbar { toolbarContent }
            .navigationDestination(for: ChemicalElement.self) { element in
                ElementDetailScreen(element: element)
                    .zoomTransition(id: element.atomicNumber, namespace: tableNamespace)
            }
            .navigationDestination(for: CompoundMatchCandidate.self) { candidate in
                CompoundDetailScreen(candidate: candidate)
            }
            .sheet(isPresented: $showsFilterSheet) {
                CategoryFilterSheet(filter: $filter, catalog: catalog)
            }
            // The safe width, not the raw frame width: in landscape the sensor
            // housing eats 60-odd points on one side, and a vertical ScrollView
            // lays its content out inside those insets.
            .onGeometryChange(for: CGSize.self) { proxy in
                CGSize(
                    width: proxy.size.width - proxy.safeAreaInsets.leading - proxy.safeAreaInsets.trailing,
                    height: proxy.size.height
                )
            } action: { size in
                screenWidth = size.width
                screenHeight = size.height
            }
            .onAppear(perform: applyAccessibilityZoomIfNeeded)
            .onChange(of: dynamicTypeSize) { _, _ in applyAccessibilityZoomIfNeeded() }
        }
        .tint(AppColor.accent)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            // The pinch's accessible twin: three plain commands that reach
            // every zoom level two fingers can, for VoiceOver, Switch Control
            // and anyone using one hand.
            Menu {
                Button {
                    zoomCommand = .zoomIn
                } label: {
                    Label("Zoom in", systemImage: "plus.magnifyingglass")
                }
                .accessibilityIdentifier("table.zoomIn")
                Button {
                    zoomCommand = .zoomOut
                } label: {
                    Label("Zoom out", systemImage: "minus.magnifyingglass")
                }
                .disabled(zoom <= 1)
                .accessibilityIdentifier("table.zoomOut")
                Button {
                    zoomCommand = .fit
                } label: {
                    Label("Fit table", systemImage: "arrow.down.right.and.arrow.up.left")
                }
                .disabled(zoom <= 1)
                .accessibilityIdentifier("table.fitTable")
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .accessibilityLabel("Zoom")
            .accessibilityIdentifier("table.zoomMenu")
        }
    }

    private func applyAccessibilityZoomIfNeeded() {
        guard dynamicTypeSize.isAccessibilitySize, !hasAppliedAccessibilityZoom else { return }
        hasAppliedAccessibilityZoom = true
        zoom = max(zoom, accessibilityStartZoom)
    }

    private func open(_ element: ChemicalElement) {
        if !query.isEmpty { progress.recordSearch(query) }
        path.append(element)
    }

    private func openCompound(_ candidate: CompoundMatchCandidate) {
        if !query.isEmpty { progress.recordSearch(query) }
        path.append(candidate)
    }
}

// MARK: - Scroll content

/// Split out so it can read `\.isSearching`, which is only published to views
/// inside the `.searchable` modifier.
private struct TableScreenContent: View {
    @Environment(\.isSearching) private var isSearching

    let catalog: ElementCatalog
    @Binding var filter: ElementFilter
    let query: String
    let results: [ChemicalElement]
    let compoundSearch: CompoundSearchModel
    let recentSearches: [String]
    let namespace: Namespace.ID
    let viewportWidth: CGFloat
    let screenHeight: CGFloat
    @Binding var zoom: CGFloat
    @Binding var tablePosition: ScrollPosition
    @Binding var savedTableOffset: CGPoint
    @Binding var isPinching: Bool
    @Binding var zoomCommand: ZoomCommand?
    let isFavorite: (Int) -> Bool
    let mastery: (Int) -> MasteryLevel
    let isCompoundFavorite: (String) -> Bool
    let compoundMastery: (String) -> MasteryLevel
    let onSelect: (ChemicalElement) -> Void
    let onSelectCompound: (CompoundMatchCandidate) -> Void
    let onRetryCompounds: () -> Void
    let onSelectRecent: (String) -> Void
    let onClearRecents: () -> Void
    let onOpenFilters: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            if !query.isEmpty {
                SearchResultsView(
                    results: results,
                    query: query,
                    namespace: namespace,
                    hasCompoundResults: !compoundSearch.isEmpty,
                    isFavorite: isFavorite,
                    mastery: mastery,
                    onSelect: onSelect
                )
                .padding(.top, Theme.Spacing.s)
                // Compounds sit under the elements. A bare number is an atomic
                // number and never reaches PubChem; the section still shows
                // the bundled catalog's own matches.
                if !compoundSearch.isEmpty || compoundSearch.askedRemote {
                    CompoundSearchSection(
                        model: compoundSearch,
                        isFavorite: isCompoundFavorite,
                        mastery: compoundMastery,
                        onSelect: onSelectCompound,
                        onRetry: onRetryCompounds
                    )
                }
            } else if isSearching {
                RecentSearchesView(
                    terms: recentSearches,
                    onSelect: onSelectRecent,
                    onClear: onClearRecents
                )
                .padding(.top, Theme.Spacing.s)
            } else {
                tableSection
            }
        }
        .padding(.bottom, Theme.Spacing.xxxl)
        .animation(Theme.Motion.soft, value: query.isEmpty)
    }

    private var tableSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text("Tap an element to explore it. Pinch to zoom the table, and drag to look around.")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Spacing.screenMargin)

            CategoryFilterBar(filter: $filter, onOpenDetailedFilters: onOpenFilters)

            // No accessibility identifier on the grid itself, deliberately.
            // SwiftUI propagates an accessibility identifier down to every
            // descendant element, replacing theirs — so naming the container
            // renamed all 118 tiles to "periodicTable.grid" and there was no
            // longer any way to address one. The zoom view names itself as a
            // container, which does not.
            ZoomableTableView(
                catalog: catalog,
                filter: filter,
                namespace: namespace,
                viewportWidth: viewportWidth,
                screenHeight: screenHeight,
                zoom: $zoom,
                position: $tablePosition,
                savedOffset: $savedTableOffset,
                isPinching: $isPinching,
                command: $zoomCommand,
                isFavorite: isFavorite,
                mastery: mastery,
                onSelect: onSelect
            )
            .padding(.top, Theme.Spacing.xs)

            CardContainer {
                TableLegend(catalog: catalog)
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.top, Theme.Spacing.s)

            Text("""
                Standard atomic weights follow IUPAC 2021. Elements without a stable isotope \
                show the mass number of their most stable form.
                """)
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Spacing.screenMargin)
        }
    }
}
