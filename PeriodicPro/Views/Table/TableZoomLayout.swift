import CoreGraphics
import Foundation

/// The arithmetic behind the pinch-to-zoom table.
///
/// Pure, so every rule is unit-tested rather than felt for on a device: the
/// zoom range, which tile density a size gets, how the viewport grows as the
/// learner zooms in — and above all where the content has to scroll to so that
/// the point under their fingers stays exactly where it is.
///
/// Zoom is expressed relative to the fitted layout. `1` means all eighteen
/// columns fit the viewport width; the table's physical layout is rebuilt at
/// every zoom level rather than scaled as a bitmap, so text stays crisp and the
/// scrollable area is always the real size of the table.
enum TableZoomLayout {
    static let columns = 18

    /// All eighteen columns on screen, the same as the old fitted layout.
    static let minimumZoom: CGFloat = 1
    /// About three and a half times the fitted size. On a phone that is a
    /// 60-point tile: room for the number, the symbol, the name and a badge.
    static let maximumZoom: CGFloat = 3.5
    /// Where a double tap on empty table takes the learner.
    static let doubleTapZoom: CGFloat = 2
    /// Zoom In / Zoom Out in the accessibility menu move by this factor.
    static let stepFactor: CGFloat = 1.5

    static let fittedSpacing: CGFloat = 1.5
    static let largestSpacing: CGFloat = 4
    /// A tile past this size stops being a tile and the table becomes a
    /// 3,000-point scroll in both directions, so the maximum zoom is capped
    /// wherever the fitted tile is already large (an iPad).
    static let largestTile: CGFloat = 112

    /// Below this the tile shows the symbol alone.
    static let standardDensityTile: CGFloat = 34
    /// From this size the tile also shows the element's name.
    static let detailedDensityTile: CGFloat = 56

    /// The zoom at which the table counts as zoomed at all. A pinch that
    /// ends closer than this to fitted snaps back to fitted, so the table is
    /// never left a few points wider than the screen with a scrollbar's worth
    /// of slack.
    static let zoomedThreshold: CGFloat = 1.04

    // MARK: - Rows

    /// Periods 1 to 7, the block the f-block is lifted out of.
    static let mainRows = 7
    /// The lanthanide row and the actinide row, each with its own caption.
    static let detachedRows = 2

    /// The gap between the main block and the two detached rows, and the gap
    /// between a caption and the row it names. Both are written here rather
    /// than only in `PeriodicTableGrid` so the height below is the same
    /// arithmetic the view lays out with.
    static func blockGap(forTileSize tile: CGFloat) -> CGFloat {
        max(Theme.Spacing.s, tile * 0.45)
    }

    static func captionGap(forTileSize tile: CGFloat) -> CGFloat {
        max(4, tile * 0.2)
    }

    /// The height reserved for a "Lanthanides" / "Actinides" caption.
    ///
    /// Reserved, not measured. A caption laid out by its own text would make
    /// the table's height depend on the text size the learner has chosen,
    /// which is exactly the dependency that made the fitted height an
    /// estimate; the label scales its font down inside this box instead, and
    /// the full text stays in the accessibility tree for VoiceOver.
    static func captionHeight(forTileSize tile: CGFloat) -> CGFloat {
        max(12, min(18, (tile * 0.5).rounded()))
    }

    /// The point size the caption is set at to sit inside `captionHeight`.
    static func captionFontSize(forTileSize tile: CGFloat) -> CGFloat {
        max(9, min(13, (captionHeight(forTileSize: tile) * 0.78).rounded()))
    }

    // MARK: - Content bounds

    /// The exact height `PeriodicTableGrid` lays out at a tile size.
    ///
    /// Seven periods and the gaps between them, the gap beneath that block,
    /// then the two detached rows with a caption above each and a gap between
    /// every one of those four items. Every term is a constant or a function
    /// of the tile, so this is the height, not an approximation of it.
    static func gridHeight(forTileSize tile: CGFloat) -> CGFloat {
        let gap = spacing(forTileSize: tile)
        let main = CGFloat(mainRows) * tile + CGFloat(mainRows - 1) * gap
        let caption = captionHeight(forTileSize: tile)
        let inner = captionGap(forTileSize: tile)
        // caption, row, caption, row — four items, three gaps.
        let fBlock = CGFloat(detachedRows) * (caption + tile) + 3 * inner
        return main + blockGap(forTileSize: tile) + fBlock
    }

    /// The grid plus the padding `ZoomableTableView` puts around it: the
    /// height of the scroll view's content, which at fitted zoom is also the
    /// height of the scroll view itself.
    static func contentHeight(forTileSize tile: CGFloat) -> CGFloat {
        gridHeight(forTileSize: tile) + Theme.Spacing.m * 2
    }

    /// A point of slack on the viewport so that a rounding difference between
    /// this arithmetic and the layout engine leaves dead space rather than a
    /// scrollable row of hidden elements.
    static let contentHeightCushion: CGFloat = 1

    // MARK: - Tile size

    /// The smallest fitted tile. Below this a tile is no longer a target, so
    /// a screen too short for the whole table at this size keeps it and lets
    /// the page scroll instead of shrinking the table into illegibility.
    static let smallestFittedTile: CGFloat = 13

    /// The fitted tile: eighteen columns in the viewport width, minus the
    /// page inset either side. Floored so the gaps stay on whole points.
    ///
    /// `availableHeight` is the vertical room the table has on screen. The
    /// tile is then stepped down until all ten rows fit that too, so "fitted"
    /// means fitted in both directions rather than fitted across. On a
    /// portrait phone the eighteen columns are the binding constraint and the
    /// height pass changes nothing; on an iPad in landscape, and on a phone
    /// turned sideways, the height is what decides.
    static func fittedTileSize(
        viewportWidth: CGFloat,
        availableHeight: CGFloat = .greatestFiniteMagnitude
    ) -> CGFloat {
        let usable = max(viewportWidth - Theme.Spacing.l * 2, 260)
        let gaps = fittedSpacing * CGFloat(columns - 1)
        var tile = max(smallestFittedTile, ((usable - gaps) / CGFloat(columns)).rounded(.down))
        // The gap between tiles grows with the tile, so on a wide screen the
        // first estimate — made with the smallest gap — can overflow by a few
        // points. Step down until the row really fits.
        while tile > smallestFittedTile,
              CGFloat(columns) * tile + CGFloat(columns - 1) * spacing(forTileSize: tile) > usable {
            tile -= 1
        }
        guard availableHeight.isFinite, availableHeight > 0 else { return tile }
        let widthFitted = tile
        while tile > smallestFittedTile, contentHeight(forTileSize: tile) > availableHeight {
            tile -= 1
        }
        // Shrinking is only worth it if it actually brings the whole table on
        // screen. A phone held sideways has room for about four periods at any
        // tile size worth tapping; making the tiles unreadable would not change
        // that, so the width-fitted table stays and the page scrolls instead.
        guard contentHeight(forTileSize: tile) <= availableHeight else { return widthFitted }
        return tile
    }

    /// The largest zoom for a given fitted tile — `maximumZoom`, or less on a
    /// screen wide enough that `maximumZoom` would exceed `largestTile`.
    /// Never below 1.5, so a pinch always does something.
    static func maximumZoom(fittedTileSize: CGFloat) -> CGFloat {
        guard fittedTileSize > 0 else { return maximumZoom }
        return min(maximumZoom, max(1.5, largestTile / fittedTileSize))
    }

    static func clampZoom(_ zoom: CGFloat, fittedTileSize: CGFloat) -> CGFloat {
        min(max(zoom, minimumZoom), maximumZoom(fittedTileSize: fittedTileSize))
    }

    /// Not rounded: rounding to whole points made the pinch step visibly.
    static func tileSize(fitted: CGFloat, zoom: CGFloat) -> CGFloat {
        fitted * zoom
    }

    /// The gap grows with the tile, from a hairline at fitted to four points
    /// at the largest sizes, so a zoomed table reads as tiles rather than as
    /// one continuous sheet.
    static func spacing(forTileSize tile: CGFloat) -> CGFloat {
        min(largestSpacing, max(fittedSpacing, tile * 0.075))
    }

    static func density(forTileSize tile: CGFloat) -> ElementTile.Density {
        if tile < standardDensityTile { return .minimal }
        if tile < detailedDensityTile { return .standard }
        return .detailed
    }

    /// Favorite and mastery badges need a tile big enough not to cover the
    /// number, which is the same size at which the number appears.
    static func showsBadges(forTileSize tile: CGFloat) -> Bool {
        tile >= standardDensityTile
    }

    /// The width the content occupies at a zoom level, exactly: the tiles,
    /// the gaps between them and the page inset either side.
    static func contentWidth(fittedTileSize: CGFloat, zoom: CGFloat) -> CGFloat {
        let tile = tileSize(fitted: fittedTileSize, zoom: zoom)
        let spacing = spacing(forTileSize: tile)
        return CGFloat(columns) * tile + CGFloat(columns - 1) * spacing + Theme.Spacing.l * 2
    }

    // MARK: - Focal point

    /// The content offset that keeps the content point under `focus` — a
    /// point in the viewport — stationary as the zoom changes.
    ///
    /// The content point under the fingers at the start is
    /// `(startOffset + focus) / startZoom` in fitted units; at the new zoom
    /// it sits at that point times `newZoom`, and the offset that puts it
    /// back under the fingers is that position minus `focus`.
    static func offsetPreservingFocus(
        startOffset: CGPoint,
        startZoom: CGFloat,
        newZoom: CGFloat,
        focus: CGPoint
    ) -> CGPoint {
        guard startZoom > 0 else { return startOffset }
        let ratio = newZoom / startZoom
        return CGPoint(
            x: (startOffset.x + focus.x) * ratio - focus.x,
            y: (startOffset.y + focus.y) * ratio - focus.y
        )
    }

    /// The content point (in the current zoom's coordinates) that sits under
    /// a viewport point.
    static func contentPoint(under viewportPoint: CGPoint, offset: CGPoint) -> CGPoint {
        CGPoint(x: offset.x + viewportPoint.x, y: offset.y + viewportPoint.y)
    }

    /// The offset that puts a content point at the middle of the viewport.
    static func offsetCentering(contentPoint: CGPoint, viewportSize: CGSize) -> CGPoint {
        CGPoint(
            x: contentPoint.x - viewportSize.width / 2,
            y: contentPoint.y - viewportSize.height / 2
        )
    }

    /// Keeps an offset inside the scrollable range. A content smaller than the
    /// viewport on an axis can only sit at zero on that axis.
    static func clampOffset(_ offset: CGPoint, contentSize: CGSize, viewportSize: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(offset.x, 0), max(0, contentSize.width - viewportSize.width)),
            y: min(max(offset.y, 0), max(0, contentSize.height - viewportSize.height))
        )
    }

    /// The content size at a new zoom, from the size measured at another.
    /// Linear in zoom: the row captions and insets are fixed, so this is a
    /// few points off at most, which the clamp above absorbs.
    static func scaledContentSize(_ size: CGSize, from startZoom: CGFloat, to newZoom: CGFloat) -> CGSize {
        guard startZoom > 0 else { return size }
        let ratio = newZoom / startZoom
        return CGSize(width: size.width * ratio, height: size.height * ratio)
    }

    // MARK: - Viewport

    /// The height of the scrolling window onto the table.
    ///
    /// At fitted zoom it is exactly the table's own height, so the page
    /// scrolls as one piece. As the learner zooms in it grows toward
    /// `expandedHeight`, reaching it at 1.5×, so a zoomed table is a window
    /// worth panning around rather than a letterbox.
    static func viewportHeight(fittedHeight: CGFloat, expandedHeight: CGFloat, zoom: CGFloat) -> CGFloat {
        let progress = min(max((zoom - 1) / 0.5, 0), 1)
        let expanded = max(expandedHeight, fittedHeight)
        return fittedHeight + (expanded - fittedHeight) * progress
    }

    /// How tall the zoomed window may grow on a screen of this height.
    ///
    /// Bounded by what is actually on screen, not by a bare fraction. A
    /// navigation bar, a tab bar and two safe areas take a little over two
    /// hundred points between them, and a window taller than what is left
    /// puts its own bottom rows under the tab bar — where they are visible,
    /// look tappable, and are not.
    static let screenChromeAllowance: CGFloat = 240

    static func expandedViewportHeight(screenHeight: CGFloat) -> CGFloat {
        max(280, min(screenHeight * 0.62, screenHeight - screenChromeAllowance))
    }

    // MARK: - The room the table has on screen

    /// The least room the table is ever fitted into. Below this the tile has
    /// bottomed out anyway, so squeezing further only shrinks the tiles
    /// without bringing another row on screen.
    static let smallestTableRegion: CGFloat = 170

    /// A little air under the last row, so the table does not finish flush
    /// against the bottom of the window with the Families card cut in half
    /// behind it.
    static let tableRegionBreathingRoom: CGFloat = Theme.Spacing.s

    /// Everything above and below the table on the Table screen, as a
    /// constant rather than a measurement.
    ///
    /// Top to bottom: the status bar or Dynamic Island, the navigation bar
    /// with its large title, the search field, the hint line, the families
    /// filter bar, and the tab bar with the home indicator under it.
    ///
    /// **This is deliberately not measured.** It used to be, and the table
    /// changed size while the learner scrolled. A large navigation title and
    /// a `.searchable` field both collapse as the page scrolls, and both are
    /// reported as safe-area insets — so the room "between the bars" grew by
    /// something like fifty points on the way down and shrank again on the way
    /// back up. Fitting the tiles to that meant all 118 of them resized under
    /// the thumb, which is not something a periodic table should do. A
    /// constant cannot move, so the table's size is now a pure function of the
    /// window and the zoom, and nothing a finger does to the page can change
    /// it.
    ///
    /// Measured across the screens the app ships for, the collapsing parts
    /// (large title 96, search field 52) plus the page header (the hint line
    /// and the families bar, 110) plus the window's own insets come to at most
    /// about 352. 360 covers that with a little to spare.
    ///
    /// It is a slight over-estimate on purpose: too large costs a point of
    /// tile on one device and nothing on any other — every phone and every
    /// iPad in portrait is bound by its eighteen columns long before height
    /// matters — while too small would let a row fall off the bottom.
    /// `Tools/check_table_fit.py` proves the whole table still fits on every
    /// screen, against each one's real chrome rather than this allowance.
    static let pageChromeAllowance: CGFloat = 360

    /// How much vertical room the table has on the Table screen.
    ///
    /// A function of the window height alone. `screenHeight` changes when the
    /// device is turned or the window is resized, and at no other time.
    static func availableTableHeight(screenHeight: CGFloat) -> CGFloat {
        guard screenHeight > 0 else { return .greatestFiniteMagnitude }
        return max(
            smallestTableRegion,
            screenHeight - pageChromeAllowance - tableRegionBreathingRoom
        )
    }
}
