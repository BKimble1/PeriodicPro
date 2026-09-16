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
        return "\nWindow: \(app.windows.firstMatch.frame)\n\(app.debugDescription)"
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
        // would be asserting the opposite of the intended behavior. Fitted is
        // the case worth pinning, and it is the one identified by tiles that
        // are narrower than the comfortable layout's minimum of 64 points.
        let isFittedLayout = hydrogen.frame.width < 64
        if isFittedLayout {
            XCTAssertLessThanOrEqual(oganesson.frame.maxX, window.maxX + 1,
                                     "The fitted table overflows the trailing edge")
        }

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Periodic Table"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
