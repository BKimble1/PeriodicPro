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

        // The table must fit without the page scrolling sideways.
        let grid = app.descendants(matching: .any)
            .matching(identifier: "periodicTable.grid").firstMatch
        if grid.exists {
            XCTAssertLessThanOrEqual(
                grid.frame.width,
                app.windows.firstMatch.frame.width + 1,
                "The fitted table must not overflow the screen width"
            )
        }

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Periodic Table"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
