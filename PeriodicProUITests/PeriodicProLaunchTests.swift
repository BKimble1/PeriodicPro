import XCTest

/// Launch-time checks across the device sizes the app must support. The
/// screenshot attachment gives the App Store screenshot pass a starting point.
final class PeriodicProLaunchTests: XCTestCase {
    override var runsForEachTargetApplicationUIConfiguration: Bool { true }

    override func setUpWithError() throws {
        continueAfterFailure = false
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
        XCTAssertTrue(hydrogen.waitForExistence(timeout: 10), "Hydrogen tile missing")
        XCTAssertTrue(oganesson.exists, "Oganesson tile missing")
        XCTAssertGreaterThanOrEqual(hydrogen.frame.minX, -1,
                                    "The table is clipped on the leading edge")
        XCTAssertLessThanOrEqual(oganesson.frame.maxX, window.maxX + 1,
                                 "The table overflows the trailing edge")
        XCTAssertGreaterThan(hydrogen.frame.width, 12,
                             "Tiles collapsed to an unusable size")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Periodic Table"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
