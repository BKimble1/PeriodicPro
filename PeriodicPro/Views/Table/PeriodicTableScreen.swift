import SwiftUI

/// The app's primary screen: search, filters, the full periodic table and the
/// families card — and the source side of the signature zoom transition.
///
/// The table is pinch-to-zoom (`ZoomableTableView`). Its zoom, scroll position
/// and last offset are owned here rather than by the table view, so that
/// searching (which replaces the table with a results list) and opening an
/// element (which pushes a page over it) both return the learner to the same
/// place at the same size.
///
/// There is no zoom control in the toolbar and no filter button: the table is
/// pinched, and the only detailed filter is the Families card beneath it.
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
    @State private var screenWidth: CGFloat = 0
    @State private var screenHeight: CGFloat = 0

    /// 1 is every column on screen; up to 3.5× is a pinch away.
    @State private var zoom: CGFloat = 1
    @State private var tablePosition = ScrollPosition(edge: .top)
    @State private var savedTableOffset: CGPoint = .zero
    @State private var isPinching = false
    /// Whether the accessibility-size default zoom has been applied. Once
    /// only: a learner who then pinches back out has made a choice.
    @State private var hasAppliedAccessibilityZoom = false

    @Namespace private var tableNamespace

    /// The anchor the page scrolls to when the table first becomes zoomed, so
    /// the taller window is entirely on screen rather than half of it under
    /// the tab bar.
    private static let tableAnchor = "periodicTable.section"

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
    /// so the table opens already zoomed to standard density. A pinch, a
    /// double tap or the VoiceOver Fit action still returns it to fitted.
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
            ScrollViewReader { proxy in
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
                        tableAnchor: Self.tableAnchor,
                        zoom: $zoom,
                        tablePosition: $tablePosition,
                        savedTableOffset: $savedTableOffset,
                        isPinching: $isPinching,
                        isFavorite: { progress.isFavorite($0) },
                        mastery: { progress.mastery(for: $0) },
                        isCompoundFavorite: { progress.isCompoundFavorite($0) },
                        compoundMastery: { progress.compoundMastery(for: $0) },
                        onSelect: open,
                        onSelectCompound: openCompound,
                        onRetryCompounds: { compoundSearch.retry(store: compounds) },
                        onSelectRecent: { query = $0 },
                        onClearRecents: { progress.clearRecentSearches() }
                    )
                }
                .scrollIndicators(.hidden)
                // The page must not scroll while two fingers are zooming the table.
                .scrollDisabled(isPinching)
                .scrollDismissesKeyboard(.immediately)
                // The zoomed window is taller than the fitted one. Left where
                // it was, its lower half ends up under the tab bar — visible,
                // apparently tappable, and not. Bringing the table's top to
                // the top of the page keeps every tile reachable.
                .onChange(of: zoom >= TableZoomLayout.zoomedThreshold) { wasZoomed, isZoomed in
                    guard isZoomed, !wasZoomed else { return }
                    withAnimation(Theme.Motion.reveal) {
                        proxy.scrollTo(Self.tableAnchor, anchor: .top)
                    }
                }
            }
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
            .navigationDestination(for: ChemicalElement.self) { element in
                ElementDetailScreen(element: element)
                    .zoomTransition(id: element.atomicNumber, namespace: tableNamespace)
            }
            .navigationDestination(for: CompoundMatchCandidate.self) { candidate in
                CompoundDetailScreen(candidate: candidate)
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
    let tableAnchor: String
    @Binding var zoom: CGFloat
    @Binding var tablePosition: ScrollPosition
    @Binding var savedTableOffset: CGPoint
    @Binding var isPinching: Bool
    let isFavorite: (Int) -> Bool
    let mastery: (Int) -> MasteryLevel
    let isCompoundFavorite: (String) -> Bool
    let compoundMastery: (String) -> MasteryLevel
    let onSelect: (ChemicalElement) -> Void
    let onSelectCompound: (CompoundMatchCandidate) -> Void
    let onRetryCompounds: () -> Void
    let onSelectRecent: (String) -> Void
    let onClearRecents: () -> Void

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

            CategoryFilterBar(filter: $filter)

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
                isFavorite: isFavorite,
                mastery: mastery,
                onSelect: onSelect
            )
            .padding(.top, Theme.Spacing.xs)
            .id(tableAnchor)

            CardContainer {
                TableLegend(catalog: catalog, filter: $filter)
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
