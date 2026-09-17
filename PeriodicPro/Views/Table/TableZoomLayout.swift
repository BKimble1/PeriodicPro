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

    // MARK: - Tile size

    /// The fitted tile: eighteen columns in the viewport width, minus the
    /// page inset either side. Floored so the gaps stay on whole points.
    static func fittedTileSize(viewportWidth: CGFloat) -> CGFloat {
        let usable = max(viewportWidth - Theme.Spacing.l * 2, 260)
        let gaps = fittedSpacing * CGFloat(columns - 1)
        var tile = max(13, ((usable - gaps) / CGFloat(columns)).rounded(.down))
        // The gap between tiles grows with the tile, so on a wide screen the
        // first estimate — made with the smallest gap — can overflow by a few
        // points. Step down until the row really fits.
        while tile > 13, CGFloat(columns) * tile + CGFloat(columns - 1) * spacing(forTileSize: tile) > usable {
            tile -= 1
        }
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
}
