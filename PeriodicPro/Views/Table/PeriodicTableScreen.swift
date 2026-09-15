import SwiftUI

/// The app's primary screen: search, filters, the full periodic table and the
/// color key — and the source side of the signature zoom transition.
struct PeriodicTableScreen: View {
    /// Fitted mode keeps all 118 tiles on screen. Comfortable mode trades
    /// horizontal scrolling for full-size, easily tappable tiles and is chosen
    /// automatically at accessibility text sizes.
    enum LayoutMode: String, CaseIterable {
        case fitted
        case comfortable

        var symbolName: String {
            self == .fitted
                ? "arrow.up.left.and.arrow.down.right"
                : "arrow.down.right.and.arrow.up.left"
        }

        var accessibilityLabel: String {
            self == .fitted ? "Switch to large tiles" : "Fit the whole table on screen"
        }
    }

    @Environment(\.elementCatalog) private var catalog
    @Environment(ProgressStore.self) private var progress: ProgressStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var query = ""
    @State private var filter: ElementFilter = .all
    @State private var path: [ChemicalElement] = []
    @State private var showsFilterSheet = false
    @State private var screenWidth: CGFloat = 0
    @State private var preferredLayout: LayoutMode = .fitted

    @Namespace private var tableNamespace

    private static let fittedSpacing: CGFloat = 1.5
    private static let comfortableSpacing: CGFloat = 4
    private static let comfortableTileSize: CGFloat = 64
    private static let horizontalInset = Theme.Spacing.l

    private var layout: LayoutMode {
        dynamicTypeSize.isAccessibilitySize ? .comfortable : preferredLayout
    }

    /// Width to lay the table out in. Until the first layout pass reports the
    /// real width, a modern iPhone's width is assumed so the table never paints
    /// a frame of undersized tiles.
    private var usableWidth: CGFloat {
        let width = screenWidth > 0 ? screenWidth : 393
        return max(width - Self.horizontalInset * 2, 260)
    }

    private var tileSize: CGFloat {
        guard layout == .fitted else { return Self.comfortableTileSize }
        let columns = CGFloat(PeriodicTableGrid.columns)
        let gaps = Self.fittedSpacing * (columns - 1)
        return max(13, ((usableWidth - gaps) / columns).rounded(.down))
    }

    private var tileSpacing: CGFloat {
        layout == .fitted ? Self.fittedSpacing : Self.comfortableSpacing
    }

    /// In landscape the fitted table gets ~44-point tiles, which is plenty of
    /// room for the atomic number as well as the symbol. Density follows the
    /// tile size rather than the layout mode so that space is never wasted.
    private var tileDensity: ElementTile.Density {
        guard layout == .fitted else { return .detailed }
        return tileSize >= 38 ? .standard : .minimal
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
                    recentSearches: progress.recentSearches,
                    namespace: tableNamespace,
                    tileSize: tileSize,
                    tileSpacing: tileSpacing,
                    density: tileDensity,
                    showsMastery: tileDensity != .minimal,
                    scrollsHorizontally: layout == .comfortable,
                    isFavorite: { progress.isFavorite($0) },
                    mastery: { progress.mastery(for: $0) },
                    onSelect: open,
                    onSelectRecent: { query = $0 },
                    onClearRecents: { progress.clearRecentSearches() },
                    onOpenFilters: { showsFilterSheet = true }
                )
            }
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
            .toolbar { toolbarContent }
            .navigationDestination(for: ChemicalElement.self) { element in
                ElementDetailScreen(element: element)
                    .zoomTransition(id: element.atomicNumber, namespace: tableNamespace)
            }
            .sheet(isPresented: $showsFilterSheet) {
                CategoryFilterSheet(filter: $filter, catalog: catalog)
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                screenWidth = width
            }
        }
        .tint(AppColor.accent)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Haptics.tap()
                withAnimation(Theme.Motion.reveal) {
                    preferredLayout = preferredLayout == .fitted ? .comfortable : .fitted
                }
            } label: {
                Image(systemName: layout.symbolName)
            }
            .disabled(dynamicTypeSize.isAccessibilitySize)
            .accessibilityLabel(layout.accessibilityLabel)
            .accessibilityIdentifier("table.layoutToggle")
        }
    }

    private func open(_ element: ChemicalElement) {
        if !query.isEmpty { progress.recordSearch(query) }
        path.append(element)
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
    let recentSearches: [String]
    let namespace: Namespace.ID
    let tileSize: CGFloat
    let tileSpacing: CGFloat
    let density: ElementTile.Density
    let showsMastery: Bool
    let scrollsHorizontally: Bool
    let isFavorite: (Int) -> Bool
    let mastery: (Int) -> MasteryLevel
    let onSelect: (ChemicalElement) -> Void
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
                    isFavorite: isFavorite,
                    mastery: mastery,
                    onSelect: onSelect
                )
                .padding(.top, Theme.Spacing.s)
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
            Text("Tap an element to explore its structure, key facts and everyday uses.")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Spacing.screenMargin)

            CategoryFilterBar(filter: $filter, onOpenDetailedFilters: onOpenFilters)

            tableView
                .padding(.top, Theme.Spacing.xs)

            CardContainer {
                TableLegend(filter: $filter, catalog: catalog)
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

    @ViewBuilder
    private var tableView: some View {
        let grid = PeriodicTableGrid(
            catalog: catalog,
            filter: filter,
            tileSize: tileSize,
            spacing: tileSpacing,
            density: density,
            namespace: namespace,
            isFavorite: isFavorite,
            mastery: mastery,
            showsMastery: showsMastery,
            onSelect: onSelect
        )
        .accessibilityIdentifier("periodicTable.grid")

        if scrollsHorizontally {
            ScrollView(.horizontal) {
                grid
                    .padding(.horizontal, Theme.Spacing.screenMargin)
                    .padding(.vertical, 2)
            }
            .scrollIndicators(.visible)
        } else {
            grid.frame(maxWidth: .infinity)
        }
    }
}
