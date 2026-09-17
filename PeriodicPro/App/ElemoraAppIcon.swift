import SwiftUI

/// The Elemora app icon, drawn rather than loaded.
///
/// `Tools/make_app_icon.py` renders the shipped icon from exact geometry —
/// nine periodic-table tiles on a four-by-three grid, eight teal and one gold,
/// on a flat field. This is the same geometry in SwiftUI, so the mark on the
/// launch screen is the mark on the Home Screen rather than a picture of it,
/// stays sharp at any size, and costs the bundle nothing.
///
/// `Tools/check_app_icon.py` reads both sides and fails if they drift apart.
enum ElemoraIconGeometry {
    /// The canvas the generator works in, so every number below can be quoted
    /// from it directly.
    static let canvas: CGFloat = 1_024
    static let tile: CGFloat = 144
    static let gap: CGFloat = 20
    static let columns = 4
    static let rows = 3
    /// 22% of the tile, the ratio `ElementTileShape.cornerRadius(for:)` uses.
    static let tileCornerRatio: CGFloat = 0.22
    /// iOS's own icon mask, as a fraction of the icon's side.
    static let iconCornerRatio: CGFloat = 0.2237

    static var markWidth: CGFloat { CGFloat(columns) * tile + CGFloat(columns - 1) * gap }
    static var markHeight: CGFloat { CGFloat(rows) * tile + CGFloat(rows - 1) * gap }

    /// Row 0 at the top. The gap in the top row is the point of the mark: the
    /// tiles are a fragment of a periodic table, not a keypad.
    static let tealTiles: [(column: Int, row: Int)] = [
        (0, 0),
        (0, 1), (2, 1), (3, 1),
        (0, 2), (1, 2), (2, 2), (3, 2),
    ]
    /// The element you are looking at.
    static let goldTile = (column: 3, row: 0)
}

/// The icon's palette, in both appearances, exactly as the generator writes it.
enum ElemoraIconPalette {
    static let field = Color(
        light: Color(red: 247 / 255, green: 245 / 255, blue: 240 / 255),
        dark: Color(red: 18 / 255, green: 20 / 255, blue: 21 / 255)
    )
    static let teal = Color(
        light: Color(red: 27 / 255, green: 128 / 255, blue: 141 / 255),
        dark: Color(red: 52 / 255, green: 166 / 255, blue: 180 / 255)
    )
    static let gold = Color(
        light: Color(red: 213 / 255, green: 168 / 255, blue: 84 / 255),
        dark: Color(red: 226 / 255, green: 181 / 255, blue: 96 / 255)
    )
}

/// The app icon at any point size, masked the way iOS masks it.
struct ElemoraAppIcon: View {
    var size: CGFloat
    /// Whether to draw the field and the icon's corner mask. Off gives the
    /// bare mark, for placing on a surface that is already the right color.
    var showsField = true

    private var unit: CGFloat { size / ElemoraIconGeometry.canvas }
    private var tile: CGFloat { ElemoraIconGeometry.tile * unit }
    private var pitch: CGFloat { (ElemoraIconGeometry.tile + ElemoraIconGeometry.gap) * unit }
    private var tileCorner: CGFloat { tile * ElemoraIconGeometry.tileCornerRatio }

    var body: some View {
        ZStack {
            if showsField {
                RoundedRectangle(cornerRadius: size * ElemoraIconGeometry.iconCornerRatio, style: .continuous)
                    .fill(ElemoraIconPalette.field)
            }
            mark
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var mark: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(
                    width: ElemoraIconGeometry.markWidth * unit,
                    height: ElemoraIconGeometry.markHeight * unit
                )
            ForEach(ElemoraIconGeometry.tealTiles.indices, id: \.self) { index in
                let position = ElemoraIconGeometry.tealTiles[index]
                square(ElemoraIconPalette.teal, column: position.column, row: position.row)
            }
            square(
                ElemoraIconPalette.gold,
                column: ElemoraIconGeometry.goldTile.column,
                row: ElemoraIconGeometry.goldTile.row
            )
        }
    }

    private func square(_ color: Color, column: Int, row: Int) -> some View {
        RoundedRectangle(cornerRadius: tileCorner, style: .continuous)
            .fill(color)
            .frame(width: tile, height: tile)
            .offset(x: CGFloat(column) * pitch, y: CGFloat(row) * pitch)
    }
}

#Preview {
    VStack(spacing: 24) {
        ElemoraAppIcon(size: 120)
        ElemoraAppIcon(size: 60)
        ElemoraAppIcon(size: 29)
    }
    .padding()
}
