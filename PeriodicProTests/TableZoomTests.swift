import CoreGraphics
import Foundation
import Testing
@testable import PeriodicPro

@Suite("Table zoom arithmetic")
struct TableZoomLayoutTests {
    @Test("The fitted tile matches the three device widths the layout preview asserts")
    func fittedTileSizes() {
        #expect(TableZoomLayout.fittedTileSize(viewportWidth: 375) == 17)
        #expect(TableZoomLayout.fittedTileSize(viewportWidth: 393) == 18)
        #expect(TableZoomLayout.fittedTileSize(viewportWidth: 440) == 21)
        // Eighteen fitted tiles and their gaps never exceed the width they
        // were fitted to, on any of them.
        for width in [320.0, 375.0, 393.0, 430.0, 440.0, 744.0, 820.0, 1024.0, 1366.0] {
            let content = TableZoomLayout.contentWidth(
                fittedTileSize: TableZoomLayout.fittedTileSize(viewportWidth: width), zoom: 1
            )
            #expect(content <= width + 0.5, "fitted table overflows a \(width)-point screen")
        }
    }

    @Test("Zoom is bounded: fitted at the bottom, about 3.5× at the top")
    func zoomRange() {
        let phone = TableZoomLayout.fittedTileSize(viewportWidth: 393)
        #expect(TableZoomLayout.clampZoom(0.2, fittedTileSize: phone) == 1)
        #expect(TableZoomLayout.clampZoom(99, fittedTileSize: phone) == 3.5)
        #expect(TableZoomLayout.maximumZoom(fittedTileSize: phone) == 3.5)
        // At the top of the range a phone tile is large enough for the
        // number, the symbol and a badge.
        let largest = TableZoomLayout.tileSize(fitted: phone, zoom: 3.5)
        #expect(largest >= 56)
        #expect(TableZoomLayout.density(forTileSize: largest) == .detailed)
    }

    @Test("A wide screen caps the zoom so a tile never passes the largest size")
    func wideScreensAreCapped() {
        let ipad = TableZoomLayout.fittedTileSize(viewportWidth: 1024)
        let maximum = TableZoomLayout.maximumZoom(fittedTileSize: ipad)
        #expect(maximum < 3.5)
        #expect(maximum >= 1.5, "a pinch must always do something")
        #expect(TableZoomLayout.tileSize(fitted: ipad, zoom: maximum) <= TableZoomLayout.largestTile + 0.01)
    }

    @Test("Density steps up with the tile: symbol, then number, then name")
    func densityThresholds() {
        #expect(TableZoomLayout.density(forTileSize: 17) == .minimal)
        #expect(TableZoomLayout.density(forTileSize: 33.9) == .minimal)
        #expect(TableZoomLayout.density(forTileSize: 34) == .standard)
        #expect(TableZoomLayout.density(forTileSize: 55.9) == .standard)
        #expect(TableZoomLayout.density(forTileSize: 56) == .detailed)
        #expect(!TableZoomLayout.showsBadges(forTileSize: 20))
        #expect(TableZoomLayout.showsBadges(forTileSize: 40))
    }

    @Test("Spacing grows with the tile and stays within its bounds")
    func spacingIsBounded() {
        #expect(TableZoomLayout.spacing(forTileSize: 17) == TableZoomLayout.fittedSpacing)
        #expect(TableZoomLayout.spacing(forTileSize: 40) == 3)
        #expect(TableZoomLayout.spacing(forTileSize: 112) == TableZoomLayout.largestSpacing)
    }

    /// The whole point of the feature: whatever is under the fingers stays
    /// there. For a viewport point `focus`, the content coordinate beneath it
    /// (in fitted units) must be the same before and after the zoom.
    @Test("The content under the pinch stays under the pinch")
    func focalPointIsPreserved() {
        let cases: [(offset: CGPoint, start: CGFloat, new: CGFloat, focus: CGPoint)] = [
            (CGPoint(x: 0, y: 0), 1, 2, CGPoint(x: 100, y: 60)),
            (CGPoint(x: 120, y: 40), 1.5, 3.2, CGPoint(x: 300, y: 180)),
            (CGPoint(x: 400, y: 220), 3.5, 1.2, CGPoint(x: 30, y: 200)),
            // Bottom-right of a phone screen, where gold lives.
            (CGPoint(x: 0, y: 0), 1, 3.5, CGPoint(x: 360, y: 150)),
        ]
        for testCase in cases {
            let offset = TableZoomLayout.offsetPreservingFocus(
                startOffset: testCase.offset,
                startZoom: testCase.start,
                newZoom: testCase.new,
                focus: testCase.focus
            )
            let before = CGPoint(
                x: (testCase.offset.x + testCase.focus.x) / testCase.start,
                y: (testCase.offset.y + testCase.focus.y) / testCase.start
            )
            let after = CGPoint(
                x: (offset.x + testCase.focus.x) / testCase.new,
                y: (offset.y + testCase.focus.y) / testCase.new
            )
            #expect(abs(before.x - after.x) < 0.001, "x drifted for \(testCase)")
            #expect(abs(before.y - after.y) < 0.001, "y drifted for \(testCase)")
        }
    }

    @Test("Zooming in from fitted at the top-left corner keeps the origin still")
    func originStaysAtOrigin() {
        let offset = TableZoomLayout.offsetPreservingFocus(
            startOffset: .zero, startZoom: 1, newZoom: 2.5, focus: .zero
        )
        #expect(offset == .zero)
    }

    @Test("Offsets are clamped to the scrollable range")
    func offsetClamping() {
        let content = CGSize(width: 1000, height: 600)
        let viewport = CGSize(width: 400, height: 300)
        #expect(TableZoomLayout.clampOffset(CGPoint(x: -50, y: -50), contentSize: content, viewportSize: viewport)
                == .zero)
        #expect(TableZoomLayout.clampOffset(CGPoint(x: 5_000, y: 5_000), contentSize: content, viewportSize: viewport)
                == CGPoint(x: 600, y: 300))
        // Content smaller than the viewport can only sit at zero.
        let small = CGSize(width: 300, height: 200)
        #expect(TableZoomLayout.clampOffset(CGPoint(x: 40, y: 40), contentSize: small, viewportSize: viewport)
                == .zero)
    }

    @Test("Centering a point puts it in the middle of the viewport")
    func centering() {
        let offset = TableZoomLayout.offsetCentering(
            contentPoint: CGPoint(x: 500, y: 300), viewportSize: CGSize(width: 400, height: 200)
        )
        #expect(offset == CGPoint(x: 300, y: 200))
    }

    @Test("The viewport is the table's own height when fitted and grows as the learner zooms")
    func viewportHeightGrows() {
        #expect(TableZoomLayout.viewportHeight(fittedHeight: 240, expandedHeight: 500, zoom: 1) == 240)
        #expect(TableZoomLayout.viewportHeight(fittedHeight: 240, expandedHeight: 500, zoom: 1.25) == 370)
        #expect(TableZoomLayout.viewportHeight(fittedHeight: 240, expandedHeight: 500, zoom: 2) == 500)
        #expect(TableZoomLayout.viewportHeight(fittedHeight: 240, expandedHeight: 500, zoom: 3.5) == 500)
        // Never shorter than fitted, whatever the screen says.
        #expect(TableZoomLayout.viewportHeight(fittedHeight: 400, expandedHeight: 200, zoom: 3) == 400)
    }

    @Test("The zoomed window never grows past what is actually on screen")
    func expandedViewportIsBoundedByTheScreen() {
        // A window taller than the screen minus its chrome would put its own
        // bottom rows under the tab bar, where they look tappable and are not.
        for height in [667.0, 812.0, 852.0, 932.0, 1_180.0, 1_366.0] {
            let expanded = TableZoomLayout.expandedViewportHeight(screenHeight: height)
            #expect(expanded <= height - TableZoomLayout.screenChromeAllowance + 0.001,
                    "the zoomed window overflows a \(height)-point screen")
            #expect(expanded >= 280, "a zoomed table needs a window worth panning")
        }
        // On anything phone-sized and up the fraction is what binds; the
        // chrome allowance only takes over on a very short window, and the
        // floor keeps even that usable.
        #expect(TableZoomLayout.expandedViewportHeight(screenHeight: 852) == 852 * 0.62)
        #expect(TableZoomLayout.expandedViewportHeight(screenHeight: 600) == 360)
        #expect(TableZoomLayout.expandedViewportHeight(screenHeight: 480) == 280)
    }

    @Test("Content size scales linearly with zoom")
    func contentScaling() {
        let scaled = TableZoomLayout.scaledContentSize(CGSize(width: 393, height: 240), from: 1, to: 2)
        #expect(scaled == CGSize(width: 786, height: 480))
        #expect(TableZoomLayout.scaledContentSize(CGSize(width: 10, height: 10), from: 0, to: 2)
                == CGSize(width: 10, height: 10))
    }
}

/// The claim Build 5 is built on: when the Table screen appears, the whole
/// periodic table is on screen — all eighteen columns, all seven periods, and
/// both f-block rows — with nothing hidden behind a scroll the learner has to
/// discover.
@Suite("The fitted table is the whole table")
struct FittedTableTests {
    /// The screens the app ships for: width, and the room the page has
    /// between the navigation bar and the tab bar at rest.
    private static let devices: [(name: String, width: CGFloat, visible: CGFloat)] = [
        ("iPhone SE (3rd generation)", 375, 450),
        ("iPhone 16e", 390, 540),
        ("iPhone 17", 393, 562),
        ("iPhone 17 Pro", 402, 570),
        ("iPhone 17 Pro Max", 440, 666),
        ("iPad (A16) portrait", 820, 950),
        ("iPad Pro 11 portrait", 834, 968),
        ("iPad Pro 13 portrait", 1_024, 1_180),
        ("iPad Pro 11 landscape", 1_210, 592),
        ("iPad Pro 13 landscape", 1_366, 720),
    ]

    /// The hint line and the families filter bar, plus the constants the
    /// screen adds to them. Measured at 375 points, where the hint wraps to
    /// two lines and the header is at its tallest.
    private static let headerHeight: CGFloat = 110

    @Test("Every row fits the room the table has, on every screen the app ships for")
    func theWholeTableFits() {
        for device in Self.devices {
            let available = TableZoomLayout.availableTableHeight(
                pageViewportHeight: device.visible, headerHeight: Self.headerHeight
            )
            let tile = TableZoomLayout.fittedTileSize(
                viewportWidth: device.width, availableHeight: available
            )
            let height = TableZoomLayout.contentHeight(forTileSize: tile)
            #expect(height <= available,
                    "\(device.name): the table needs \(height) points and has \(available)")
            let width = TableZoomLayout.contentWidth(fittedTileSize: tile, zoom: 1)
            #expect(width <= device.width + 0.5,
                    "\(device.name): the table is \(width) points wide in \(device.width)")
            #expect(tile >= TableZoomLayout.smallestFittedTile)
        }
    }

    @Test("At fitted zoom there is nothing to scroll, in either direction")
    func fittedZoomHasNoScrollRange() {
        for device in Self.devices {
            let available = TableZoomLayout.availableTableHeight(
                pageViewportHeight: device.visible, headerHeight: Self.headerHeight
            )
            let tile = TableZoomLayout.fittedTileSize(
                viewportWidth: device.width, availableHeight: available
            )
            let content = CGSize(
                width: TableZoomLayout.contentWidth(fittedTileSize: tile, zoom: 1),
                height: TableZoomLayout.contentHeight(forTileSize: tile)
            )
            let viewport = CGSize(
                width: device.width,
                height: TableZoomLayout.viewportHeight(
                    fittedHeight: content.height + TableZoomLayout.contentHeightCushion,
                    expandedHeight: TableZoomLayout.expandedViewportHeight(screenHeight: device.visible),
                    zoom: 1
                )
            )
            #expect(content.height <= viewport.height,
                    "\(device.name): the fitted table can be scrolled vertically inside its own window")
            #expect(content.width <= viewport.width + 0.5,
                    "\(device.name): the fitted table can be scrolled sideways")
            // The only offset the fitted table can be at is the top-left one.
            let clamped = TableZoomLayout.clampOffset(
                CGPoint(x: 400, y: 400), contentSize: content, viewportSize: viewport
            )
            #expect(clamped == .zero, "\(device.name): the fitted table has somewhere to scroll to")
        }
    }

    @Test("The height of the table is arithmetic, not an estimate")
    func gridHeightIsTheSumOfItsParts() {
        for tile in stride(from: CGFloat(13), through: 112, by: 1) {
            let gap = TableZoomLayout.spacing(forTileSize: tile)
            let expected =
                CGFloat(TableZoomLayout.mainRows) * tile
                + CGFloat(TableZoomLayout.mainRows - 1) * gap
                + TableZoomLayout.blockGap(forTileSize: tile)
                + 2 * TableZoomLayout.captionHeight(forTileSize: tile)
                + 2 * tile
                + 3 * TableZoomLayout.captionGap(forTileSize: tile)
            #expect(abs(TableZoomLayout.gridHeight(forTileSize: tile) - expected) < 0.001)
            #expect(TableZoomLayout.contentHeight(forTileSize: tile)
                    == TableZoomLayout.gridHeight(forTileSize: tile) + Theme.Spacing.m * 2)
        }
    }

    @Test("All ten rows are accounted for: seven periods, the lanthanides and the actinides")
    func everyRowIsInTheHeight() {
        // Ten rows of tiles, whatever else the height contains.
        let tile: CGFloat = 20
        let rows = CGFloat(TableZoomLayout.mainRows + TableZoomLayout.detachedRows)
        #expect(TableZoomLayout.mainRows + TableZoomLayout.detachedRows == 10)
        #expect(TableZoomLayout.gridHeight(forTileSize: tile) > rows * tile)
        // And the captions are really reserved for, not rounded away.
        #expect(TableZoomLayout.captionHeight(forTileSize: tile) >= 12)
        #expect(TableZoomLayout.captionFontSize(forTileSize: tile)
                <= TableZoomLayout.captionHeight(forTileSize: tile))
    }

    @Test("A portrait phone is bound by its eighteen columns, not by its height")
    func phonesAreWidthBound() {
        // Which is the point of doing the height pass second: on the screens
        // most learners hold, it changes nothing, so nothing moves.
        for device in Self.devices.prefix(5) {
            let available = TableZoomLayout.availableTableHeight(
                pageViewportHeight: device.visible, headerHeight: Self.headerHeight
            )
            #expect(TableZoomLayout.fittedTileSize(viewportWidth: device.width, availableHeight: available)
                    == TableZoomLayout.fittedTileSize(viewportWidth: device.width),
                    "\(device.name) lost tile size to the height pass")
        }
    }

    @Test("A wide, short window shrinks the tile until the whole table fits")
    func landscapeTabletsAreHeightBound() {
        let available = TableZoomLayout.availableTableHeight(
            pageViewportHeight: 592, headerHeight: Self.headerHeight
        )
        let widthOnly = TableZoomLayout.fittedTileSize(viewportWidth: 1_210)
        let fitted = TableZoomLayout.fittedTileSize(viewportWidth: 1_210, availableHeight: available)
        #expect(fitted < widthOnly, "the height pass did nothing on a landscape tablet")
        #expect(TableZoomLayout.contentHeight(forTileSize: fitted) <= available)
    }

    @Test("Shrinking that would not achieve a fit is not done at all")
    func aHopelesslyShortWindowKeepsTheWidthFittedTable() {
        // A phone held sideways has room for about four periods at any tile
        // size worth tapping. Shrinking to the floor would not bring the last
        // row on screen, so the table stays legible and the page scrolls.
        let available = TableZoomLayout.availableTableHeight(
            pageViewportHeight: 244, headerHeight: Self.headerHeight
        )
        #expect(TableZoomLayout.contentHeight(forTileSize: TableZoomLayout.smallestFittedTile) > available)
        #expect(TableZoomLayout.fittedTileSize(viewportWidth: 852, availableHeight: available)
                == TableZoomLayout.fittedTileSize(viewportWidth: 852))
    }

    @Test("Before anything has been measured the table is still fitted, not guessed at")
    func theAssumedRoomIsEnough() {
        for device in Self.devices.prefix(5) {
            let assumed = TableZoomLayout.availableTableHeight(
                pageViewportHeight: TableZoomLayout.assumedPageViewportHeight(screenHeight: device.visible + 290),
                headerHeight: TableZoomLayout.assumedHeaderHeight
            )
            let measured = TableZoomLayout.availableTableHeight(
                pageViewportHeight: device.visible, headerHeight: Self.headerHeight
            )
            // The first frame and the measured one pick the same tile, so the
            // measurement replacing the assumption moves nothing on screen.
            #expect(TableZoomLayout.fittedTileSize(viewportWidth: device.width, availableHeight: assumed)
                    == TableZoomLayout.fittedTileSize(viewportWidth: device.width, availableHeight: measured),
                    "\(device.name) resizes its tiles once the page is measured")
        }
    }

    @Test("An unmeasured page falls back to fitting the width alone")
    func noMeasurementMeansNoHeightConstraint() {
        #expect(TableZoomLayout.availableTableHeight(pageViewportHeight: 0, headerHeight: 0)
                == .greatestFiniteMagnitude)
        #expect(TableZoomLayout.fittedTileSize(viewportWidth: 393, availableHeight: .greatestFiniteMagnitude)
                == TableZoomLayout.fittedTileSize(viewportWidth: 393))
        // And the room never collapses to nothing, however the page is laid out.
        #expect(TableZoomLayout.availableTableHeight(pageViewportHeight: 100, headerHeight: 900)
                == TableZoomLayout.smallestTableRegion)
    }
}
