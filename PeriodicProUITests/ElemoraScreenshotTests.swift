import XCTest

/// Captures real screenshots of the compiled app, from the simulator.
///
/// This is not a rendering of what the app is meant to look like — every image
/// here comes out of the running build, so a missing SF Symbol, a clipped
/// label or a blank 3D viewer shows up as itself rather than as a diagram of
/// itself.
///
/// The images are attached to the test result bundle rather than written to the
/// repository. `Tools/export_screenshots.sh` pulls them out of the `.xcresult`
/// afterwards, and CI publishes them as the `elemora-simulator-screenshots`
/// artifact. Committing a folder of 3× PNGs to git on every run is how a
/// repository gets to a gigabyte.
///
/// Light and dark are not separate tests: the appearance is set on the
/// simulator before the run (`xcrun simctl ui <udid> appearance dark`), and the
/// suffix comes in through `SCREENSHOT_SUFFIX` so the two runs cannot overwrite
/// each other.
///
/// These are assertions as well as pictures. A screenshot of a screen that
/// never appeared is worse than no screenshot, so every step waits for
/// something specific and fails if it does not arrive.
final class ElemoraScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    /// "light" or "dark", supplied by the CI step that set the simulator's
    /// appearance. Defaults to light so a local run still works.
    private var suffix: String {
        ProcessInfo.processInfo.environment["SCREENSHOT_SUFFIX"] ?? "light"
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Screenshots are portrait. The launch tests rotate the simulator and
        // the rotation persists, so without this the tour photographs whatever
        // orientation the previous class happened to leave behind.
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    private func el(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// What is on screen, in one line — GitHub's error annotation keeps only
    /// the first line of a multi-line assertion message.
    private func onScreen() -> String {
        let described = app.descendants(matching: .any)
            .allElementsBoundByAccessibilityElement
            .filter { !$0.identifier.isEmpty }
            .map { "\($0.identifier)<\($0.elementType.rawValue)>" }
        let shown = described.prefix(40).joined(separator: " ")
        let more = described.count > 40 ? " …+\(described.count - 40)" : ""
        return " | window \(app.windows.firstMatch.frame) "
            + "| \(described.count) identified: \(shown)\(more)"
    }

    private func waitFor(_ element: XCUIElement,
                         _ timeout: TimeInterval = 15,
                         file: StaticString = #filePath,
                         line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      "Timed out waiting for \(element)\(onScreen())",
                      file: file, line: line)
    }

    /// Scrolls while looking, rather than waiting for the element to exist and
    /// only then scrolling. SwiftUI does not vend an accessibility element for
    /// content far outside a ScrollView's viewport, so waiting for something
    /// below the fold times out before a single swipe has happened.
    @discardableResult
    private func scrollTo(_ element: XCUIElement,
                          file: StaticString = #filePath,
                          line: UInt = #line) -> XCUIElement {
        if element.waitForExistence(timeout: 3), element.isHittable { return element }

        var attempts = 0
        while attempts < 8 {
            app.swipeUp()
            attempts += 1
            if element.exists, element.isHittable { return element }
        }
        for _ in 0..<attempts {
            app.swipeDown()
            if element.exists, element.isHittable { return element }
        }

        XCTAssertTrue(element.exists && element.isHittable,
                      "\(element) never became tappable, scrolling both ways",
                      file: file, line: line)
        return element
    }

    private func tap(_ element: XCUIElement,
                     file: StaticString = #filePath,
                     line: UInt = #line) {
        scrollTo(element, file: file, line: line).tap()
    }

    private func openTab(_ name: String) {
        let tab = app.tabBars.buttons[name]
        waitFor(tab)
        tab.tap()
    }

    private func openElement(_ symbol: String) {
        tap(app.buttons["element.\(symbol)"])
        waitFor(app.buttons["detail.favoriteButton"])
    }

    private func goBack() {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        waitFor(back)
        back.tap()
    }

    /// Lets the frame settle before the shutter. The table fades its tiles in,
    /// the 3D explorer eases into its opening pose, and a screenshot taken mid
    /// transition is a picture of nothing in particular.
    ///
    /// Sleeping is right here and wrong almost everywhere else: there is no
    /// element whose appearance means "the animation has finished", which is
    /// exactly the case `waitForExistence` cannot express. The app is a
    /// separate process, so this blocks only the test runner.
    private func settle(_ seconds: TimeInterval = 1.2) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Names, attaches and keeps one screenshot.
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "\(name)-\(suffix)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - The tour

    /// One test rather than ten, on purpose: each one would pay the app's launch
    /// and first-frame cost again, and the order below is itself the check —
    /// Study reads differently after a round has been played than before.
    func testCaptureTheAppStoreTour() throws {
        // 1. Table
        waitFor(app.navigationBars["Periodic Table"])
        waitFor(app.buttons["element.Au"])
        settle()
        capture("01-table")

        // 2. Element detail — Gold, top of the page
        openElement("Au")
        settle()
        capture("02-gold-detail-top")

        // 3. Element detail — Gold, scrolled to the cards
        let explore = scrollTo(app.buttons["detail.explore3D"])
        settle(0.6)
        capture("03-gold-detail-scrolled")

        // 4. The 3D explorer, on a free demo element
        scrollTo(explore).tap()
        waitFor(el("explorer.viewer"))
        // Longer than elsewhere: this one waits for RealityKit to have a frame
        // on screen, not merely for the hosting view to exist.
        settle(3.0)
        capture("04-gold-3d-explorer")
        app.buttons["explorer.done"].tap()
        waitFor(app.buttons["detail.favoriteButton"])
        goBack()

        // 5. Study
        openTab("Study")
        waitFor(app.navigationBars["Study"])
        waitFor(app.buttons["study.mode.flashcards"])
        settle()
        capture("05-study")

        // 6. An Identify round
        tap(app.buttons["study.mode.identify"])
        waitFor(app.buttons["session.reveal"])
        settle(0.8)
        capture("06-identify-session")
        app.buttons["session.exit"].tap()
        waitFor(app.navigationBars["Study"])

        // 7. Progress
        openTab("Progress")
        waitFor(app.navigationBars["Progress"])
        settle()
        capture("07-progress")

        // 8. The Elemora Pro paywall, with real prices.
        //
        // Relaunched against the local StoreKit configuration, because the
        // default UI-testing launch stubs StoreKit out entirely and the paywall
        // then draws its "options unavailable" state. A screenshot of that is a
        // picture of a bug that is not there, and it would hide the one thing
        // worth checking: that the prices, the per-month line and the savings
        // badge all come out of `Product.displayPrice` and render.
        app.terminate()
        app.launchArguments = ["-uiTesting", "-storeKitLocal"]
        app.launch()
        openTab("Study")
        tap(app.buttons["study.mode.smartReview"])
        waitFor(el("paywall"))

        let yearly = el("paywall.plan.periodicpro.pro.yearly")
        let monthly = el("paywall.plan.periodicpro.pro.monthly")
        XCTAssertTrue(yearly.waitForExistence(timeout: 30),
                      "The paywall never loaded the yearly plan from "
                      + "Config/PeriodicPro.storekit. Check that the scheme still "
                      + "references it and that the product identifiers match.")
        XCTAssertTrue(monthly.exists, "The paywall is missing the monthly plan")
        settle(1.0)
        capture("08-elemora-pro-paywall")
        app.buttons["paywall.close"].tap()
    }
}
