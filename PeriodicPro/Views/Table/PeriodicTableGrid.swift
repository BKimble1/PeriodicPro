import SwiftUI

/// The 118-element table laid out on the standard 18-column grid.
///
/// Tiles are positioned absolutely inside three `ZStack`s (main block,
/// lanthanides, actinides) rather than through nested stacks or a lazy grid.
/// That means 118 leaf views, no per-tile `GeometryReader`, and an exact
/// layout at every tile size.
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

    static let columns = 18

    private var step: CGFloat { tileSize + spacing }

    var totalWidth: CGFloat {
        CGFloat(Self.columns) * tileSize + CGFloat(Self.columns - 1) * spacing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: max(Theme.Spacing.s, tileSize * 0.45)) {
            block(elements: catalog.mainTableElements, rows: 7, baseRow: 1)

            VStack(alignment: .leading, spacing: max(4, tileSize * 0.2)) {
                caption("Lanthanides")
                block(elements: catalog.lanthanideRow, rows: 1, baseRow: 9)
                caption("Actinides")
                block(elements: catalog.actinideRow, rows: 1, baseRow: 10)
            }
        }
        .frame(width: totalWidth, alignment: .leading)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: max(9, min(11, tileSize * 0.5)), weight: .medium))
            .foregroundStyle(AppColor.tertiaryText)
            .accessibilityAddTraits(.isHeader)
    }

    private func block(elements: [ChemicalElement], rows: Int, baseRow: Int) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(
                    width: totalWidth,
                    height: CGFloat(rows) * tileSize + CGFloat(rows - 1) * spacing
                )
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
