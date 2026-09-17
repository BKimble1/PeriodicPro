import SwiftUI

/// The 118-element table laid out on the standard 18-column grid.
///
/// Tiles are positioned absolutely inside three `ZStack`s (main block,
/// lanthanides, actinides) rather than through nested stacks or a lazy grid.
/// That means 118 leaf views, no per-tile `GeometryReader`, and an exact
/// layout at every tile size — which is what lets the pinch-to-zoom table
/// rebuild it at any size on every frame.
struct PeriodicTableGrid: View {
    let catalog: ElementCatalog
    let filter: ElementFilter
    let tileSize: CGFloat
    let spacing: CGFloat
    let density: ElementTile.Density
    let namespace: Namespace.ID
    let isFavorite: (Int) -> Bool
    let mastery: (Int) -> MasteryLevel
    let showsMastery: Bool
    let onSelect: (ChemicalElement) -> Void
    /// A double tap on empty table, with its location in
    /// `ZoomableTableView.contentSpace`. Tiles are buttons and keep their own
    /// taps; only the space between and around them reaches this.
    var onDoubleTap: ((CGPoint) -> Void)?

    static let columns = TableZoomLayout.columns

    private var step: CGFloat { tileSize + spacing }

    var totalWidth: CGFloat {
        CGFloat(Self.columns) * tileSize + CGFloat(Self.columns - 1) * spacing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TableZoomLayout.blockGap(forTileSize: tileSize)) {
            block(elements: catalog.mainTableElements, rows: TableZoomLayout.mainRows, baseRow: 1)

            VStack(alignment: .leading, spacing: TableZoomLayout.captionGap(forTileSize: tileSize)) {
                caption("Lanthanides")
                block(elements: catalog.lanthanideRow, rows: 1, baseRow: 9)
                caption("Actinides")
                block(elements: catalog.actinideRow, rows: 1, baseRow: 10)
            }
        }
        .frame(width: totalWidth, alignment: .leading)
    }

    /// The f-block captions, in a box of a height the layout already knows.
    ///
    /// The box comes from `TableZoomLayout.captionHeight`, which is also the
    /// term `TableZoomLayout.gridHeight` uses for them — so the table's height
    /// is arithmetic rather than something the view has to be measured for.
    /// The type scales down to fit rather than pushing rows off the bottom at
    /// accessibility text sizes; the caption is still a header in the
    /// accessibility tree, with its full text, so nothing is lost to
    /// VoiceOver.
    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: TableZoomLayout.captionFontSize(forTileSize: tileSize), weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(AppColor.tertiaryText)
            .frame(height: TableZoomLayout.captionHeight(forTileSize: tileSize), alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private func block(elements: [ChemicalElement], rows: Int, baseRow: Int) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(
                    width: totalWidth,
                    height: CGFloat(rows) * tileSize + CGFloat(rows - 1) * spacing
                )
                .contentShape(Rectangle())
                .onTapGesture(count: 2, coordinateSpace: .named(ZoomableTableView.contentSpace)) { location in
                    onDoubleTap?(location)
                }
                .accessibilityHidden(true)

            ForEach(elements) { element in
                tile(element)
                    // The hit area is a full grid cell, half a gap wider than
                    // the tile on every side, so the offset backs off by the
                    // same amount and the tiles still land exactly on the grid.
                    .offset(
                        x: CGFloat(element.gridX - 1) * step - spacing / 2,
                        y: CGFloat(element.gridY - baseRow) * step - spacing / 2
                    )
            }
        }
    }

    private func tile(_ element: ChemicalElement) -> some View {
        let dimmed = filter.isActive && !filter.matches(element)
        return Button {
            guard !dimmed else { return }
            Haptics.tap()
            onSelect(element)
        } label: {
            ElementTile(
                element: element,
                size: tileSize,
                density: density,
                isDimmed: dimmed,
                isFavorite: isFavorite(element.atomicNumber),
                mastery: mastery(element.atomicNumber),
                showsMastery: showsMastery
            )
            // Tiles are small in the fitted layout, so every point between them
            // belongs to one of them: the hit areas tile the grid with no dead
            // space, and a slightly-off tap still lands on what it looks like.
            .frame(width: tileSize + spacing, height: tileSize + spacing)
            .contentShape(Rectangle())
        }
        .buttonStyle(ElementTileButtonStyle())
        .disabled(dimmed)
        .zoomTransitionSource(id: element.atomicNumber, namespace: namespace)
        .accessibilityIdentifier("element.\(element.symbol)")
        .accessibilityHidden(dimmed)
    }
}
