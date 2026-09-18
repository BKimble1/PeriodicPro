import XCTest

/// Launch-time checks across the device sizes the app must support. The
/// screenshot attachment gives the App Store screenshot pass a starting point.
final class PeriodicProLaunchTests: XCTestCase {
    // XCTestCase declares this as a class property. As an instance `var` it
    // overrides nothing, which is a compile error in the UI test target — and
    // would silently not run the per-configuration launches even if it built.
    override class var runsForEachTargetApplicationUIConfiguration: Bool { true }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        // This class asks to be run in every UI configuration the app
        // supports, which rotates the simulator. The rotation outlives the
        // test, so put it back rather than leaving it for whichever class
        // runs next.
        XCUIDevice.shared.orientation = .portrait
    }

    /// The accessibility tree, attached and inlined into the failure message.
    ///
    /// This test runs once per target application UI configuration, and the
    /// configurations are chosen by Xcode rather than named here. When one of
    /// them fails, "the tile is missing" on its own does not say which
    /// configuration it was or what was on screen instead — so the tree goes
    /// into the message, where CI prints it.
    private func diagnostics(_ app: XCUIApplication) -> String {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = "Accessibility tree"
        attachment.lifetime = .keepAlways
        add(attachment)

        let described = app.descendants(matching: .any)
            .allElementsBoundByAccessibilityElement
            .filter { !$0.identifier.isEmpty }
            .map { "\($0.identifier)<\($0.elementType.rawValue)>" }
        let shown = described.prefix(40).joined(separator: " ")
        let more = described.count > 40 ? " …+\(described.count - 40)" : ""
        // The full tree goes to the attachment; the message gets one line,
        // because GitHub's error annotation keeps only the first line of a
        // multi-line assertion message and the tree is what is being looked at.
        return " | window \(app.windows.firstMatch.frame) "
            + "| \(described.count) identified: \(shown)\(more)"
    }

    func testLaunchPerformanceAndFirstFrame() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Periodic Table"].waitForExistence(timeout: 10),
                      "The app should open straight into the table")

        // The fitted table must not overflow the screen. Hydrogen sits in the
        // first column and oganesson in the eighteenth, so their frames bound
        // the whole grid — and unlike a container view, both are real
        // accessibility elements on every device size.
        let window = app.windows.firstMatch.frame
        let hydrogen = app.buttons["element.H"]
        let oganesson = app.buttons["element.Og"]

        // At an accessibility text size the screen's chrome — the large title,
        // the search field and the family filters — is tall enough to push the
        // table below the first frame, and SwiftUI does not put a view that far
        // off screen into the accessibility tree. Scrolling to it is part of
        // launching, not a workaround: the assertions below are about the
        // table's own geometry, and the table has to exist to have any.
        if !hydrogen.waitForExistence(timeout: 10) {
            var swipes = 0
            while !hydrogen.exists && swipes < 4 {
                app.swipeUp()
                swipes += 1
            }
            XCTAssertTrue(hydrogen.waitForExistence(timeout: 5),
                          "Hydrogen tile missing after \(swipes) swipes\(diagnostics(app))")
        }
        XCTAssertTrue(oganesson.exists, "Oganesson tile missing\(diagnostics(app))")

        XCTAssertGreaterThanOrEqual(hydrogen.frame.minX, -1,
                                    "The table is clipped on the leading edge")
        XCTAssertGreaterThan(hydrogen.frame.width, 12,
                             "Tiles collapsed to an unusable size")

        // Only the fitted layout promises to hold all eighteen columns. At an
        // accessibility text size the app deliberately switches to large tiles
        // that scroll sideways, and asserting oganesson is on screen there
        // would be asserting the opposite of the intended behavior.
        //
        // Which layout is on screen is derived from the tiles themselves, not
        // from a fixed width: the first version of this compared against the
        // comfortable layout's 64-point minimum, which is also roughly what a
        // *fitted* tile measures on a 13-inch iPad — so the check would have
        // quietly skipped itself on the largest device it covers. Eighteen
        // columns that were sized to fit must actually fit.
        let sizedToFit = hydrogen.frame.width * CGFloat(18) <= window.width
        if sizedToFit {
            XCTAssertLessThanOrEqual(oganesson.frame.maxX, window.maxX + 1,
                                     "The fitted table overflows the trailing edge")
        }

        // And it must use the width it has. "Does not overflow" was the only
        // thing asserted here, and a table shrunk to the 13-point floor does
        // not overflow anything — it sits in the middle of the screen at two
        // thirds of the size, which is what a wrong height budget did to it:
        // the allowance for the bars was subtracted from a height that had
        // already had the bars taken out of it.
        //
        // In portrait the eighteen columns are what the fitted size is decided
        // by, so they should reach the page margins. Measured across the
        // screens the app ships for, the columns span between 95% and 100% of
        // the room inside those margins — the gap is the remainder of dividing
        // the width by eighteen. Two thirds is the failure this catches.
        //
        // Portrait only: held sideways, a phone or an iPad has the height as
        // the binding constraint and a table narrower than the screen is the
        // correct answer rather than a bug.
        //
        // 32 is the page margin either side, `Theme.Spacing.l * 2`, which is
        // what `TableZoomLayout.fittedTileSize` takes off the width before it
        // divides.
        if sizedToFit, window.height > window.width {
            let span = oganesson.frame.maxX - hydrogen.frame.minX
            let usable = window.width - 32
            XCTAssertGreaterThan(
                span, usable * 0.85,
                "The fitted table should fill the width it is given: eighteen columns "
                + "span \(span) of \(usable) usable points, with tiles \(hydrogen.frame.width) "
                + "wide\(diagnostics(app))"
            )
        }

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Periodic Table"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// The loading screen: Elemora's own icon and name while the app opens,
    /// on the same field the system's launch image uses, then gone.
    ///
    /// Held up by a launch argument. It is meant to last about half a second,
    /// which is right for a learner and unassertable for a test — without the
    /// hold this would be racing it.
    func testLoadingScreenShowsTheAppIconAndThenGivesWayToTheTable() throws {
        let held = XCUIApplication()
        held.launchArguments = ["-uiTesting", "-holdLaunchScreen"]
        held.launch()

        let matches = held.descendants(matching: .any).matching(identifier: "launch.screen")
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 10),
                      "The app should open on its loading screen")
        // Any element carrying the identifier, not whichever one `firstMatch`
        // happens to return: SwiftUI can surface a wrapper alongside the
        // element itself, and the claim being made is that the loading screen
        // names the app, not that it does so in a particular tree position.
        let names = matches.allElementsBoundByAccessibilityElement.map(\.label)
        XCTAssertTrue(names.contains("Elemora"),
                      "The loading screen should name the app to VoiceOver; saw \(names)")
        // Hittable, not existent. The tabs, the table and the navigation bar
        // are hosted by UIKit and stay in the accessibility tree behind the
        // cover whatever the SwiftUI content says about itself — so their
        // presence proves nothing either way. What "behind, not beside"
        // actually means is that you cannot touch them, which is the one
        // thing hit-testing can answer.
        XCTAssertFalse(held.buttons["element.H"].isHittable,
                       "The table should be behind the loading screen, not beside it")

        let frame = XCTAttachment(screenshot: held.screenshot())
        frame.name = "Loading screen"
        frame.lifetime = .keepAlways
        add(frame)
        held.terminate()

        // And a normal launch passes through it to the table without the
        // learner having to do anything.
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Periodic Table"].waitForExistence(timeout: 15),
                      "The loading screen should give way to the table on its own")
        XCTAssertTrue(app.buttons["element.H"].waitForExistence(timeout: 5),
                      "and the table itself should be reachable once it has")
        XCTAssertFalse(app.descendants(matching: .any)
            .matching(identifier: "launch.screen").firstMatch.exists,
                       "The loading screen should be gone once the table is up")
    }
}
