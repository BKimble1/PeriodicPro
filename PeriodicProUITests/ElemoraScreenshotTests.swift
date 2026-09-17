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
        // The compound stub answers PubChem from the bundled catalog, so the
        // compound frames are deterministic and the tour never needs a network.
        app.launchArguments = ["-uiTesting", "-compoundNetworkStub"]
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

    /// Whether the element can take a tap right now.
    ///
    /// `isHittable` is asked only once the frame is a real rectangle with a
    /// visible part inside the window. On iOS 26 an element that is off
    /// screen or mid-transition has no usable hit point, and asking then does
    /// not answer no — it records "Failed to determine hittability" as a test
    /// failure, which is what stopped the tour on the compound page.
    private func canTap(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        guard !frame.isNull, !frame.isEmpty, frame.origin.x.isFinite, frame.origin.y.isFinite
        else { return false }
        let visible = frame.intersection(app.windows.firstMatch.frame)
        guard visible.width >= 8, visible.height >= 8 else { return false }
        // Even inside the window, an element whose every hit point lands on
        // something else — a button that has scrolled under the tab bar —
        // makes iOS 26 record "Failed to determine hittability" instead of
        // answering no. For a loop that is about to scroll and ask again,
        // that is a no; anything else XCTest records still counts.
        let options = XCTExpectedFailure.Options()
        options.isStrict = false
        options.issueMatcher = { $0.compactDescription.contains("Failed to determine hittability") }
        return XCTExpectFailure("hittability undetermined mid-scroll", options: options) {
            element.isHittable
        }
    }

    /// Whether the element is somewhere a finger could land, waiting up to
    /// `timeout` for it to get there. Existence alone is not enough: a sheet
    /// still sliding in vends its rows before they are on screen, and a tap
    /// aimed at one of them then lands on whatever is underneath.
    private func becomesHittable(_ element: XCUIElement, within timeout: TimeInterval) -> Bool {
        // A plain loop on the test thread rather than a predicate expectation:
        // `canTap` uses `XCTExpectFailure`, which belongs on the thread the
        // test runs on, not on whatever thread evaluates a predicate.
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if canTap(element) { return true }
            if Date() >= deadline { return false }
            settle(0.25)
        }
    }

    /// Scrolls while looking, rather than waiting for the element to exist and
    /// only then scrolling. SwiftUI does not vend an accessibility element for
    /// content far outside a ScrollView's viewport, so waiting for something
    /// below the fold times out before a single swipe has happened.
    ///
    /// The wait before the first swipe is deliberately generous. On the iPad
    /// runner the element picker took longer than three seconds to arrive,
    /// the tour started swiping, and the swipes scrolled the picker's own
    /// list — away from the row it was about to tap.
    @discardableResult
    private func scrollTo(_ element: XCUIElement,
                          file: StaticString = #filePath,
                          line: UInt = #line) -> XCUIElement {
        if becomesHittable(element, within: 6) { return element }

        var attempts = 0
        while attempts < 8 {
            app.swipeUp()
            attempts += 1
            // A swipe has momentum. Checking, and then tapping, before the
            // list has stopped puts the tap where the row was a moment ago.
            settle(0.6)
            if canTap(element) { return element }
        }
        for _ in 0..<attempts {
            app.swipeDown()
            settle(0.6)
            if canTap(element) { return element }
        }

        XCTAssertTrue(canTap(element),
                      "\(element) never became tappable, scrolling both ways"
                      + onScreen(),
                      file: file, line: line)
        return element
    }

    private func tap(_ element: XCUIElement,
                     file: StaticString = #filePath,
                     line: UInt = #line) {
        scrollTo(element, file: file, line: line).tap()
    }

    /// Finds a tab without assuming the shape of the tab bar.
    ///
    /// Scoping to `app.tabBars` is an iPhone assumption. On iPad the tour
    /// timed out waiting for "Study" on a screen that plainly had it: iPadOS
    /// 18 draws the floating tab bar, XCUITest does not vend that as a
    /// `tabBar` element, and the accessibility dump showed the three tab
    /// buttons outside any tab bar — listed twice each, since the bar and its
    /// sidebar representation are both in the tree.
    ///
    /// So: the tab bar first, because that is the cheapest and most specific
    /// query where it exists, then anywhere, taking the first of the
    /// duplicates. The claim being tested is unchanged — the tab is reachable
    /// and opens its screen — it is simply no longer a claim about which
    /// container iOS happened to put it in.
    private func openTab(_ name: String) {
        let inTabBar = app.tabBars.buttons[name]
        if inTabBar.waitForExistence(timeout: 5) {
            inTabBar.tap()
            return
        }
        let anywhere = app.buttons[name].firstMatch
        waitFor(anywhere)
        anywhere.tap()
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
        keep(app.screenshot(), as: name)
    }

    /// The whole screen rather than the app's window: the Home Screen is not
    /// the app.
    private func captureScreen(_ name: String) {
        keep(XCUIScreen.main.screenshot(), as: name)
    }

    private func keep(_ screenshot: XCUIScreenshot, as name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(name)-\(suffix)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func labelContaining(_ fragment: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", fragment))
            .firstMatch
    }

    /// Adds an element through the builder's picker and confirms it landed in
    /// the tray, rather than trusting that the tap on the row did anything.
    private func addElement(_ symbol: String) {
        tap(app.buttons["build.addElement"])
        // The picker slides in; its rows are tapped only once it has arrived.
        waitFor(app.navigationBars["Add an element"])
        settle(0.6)
        let row = app.buttons["build.pick.\(symbol)"]
        tap(row)
        let counted = el("build.count.\(symbol)")
        if !counted.waitForExistence(timeout: 4), canTap(row) {
            // The first tap landed while the sheet was still settling and hit
            // nothing. One more, now that it is still.
            row.tap()
        }
        waitFor(counted)
        // And the sheet is gone before the next control is asked anything:
        // a query mid-dismissal is exactly the moment iOS 26 answers with a
        // failure rather than a no.
        let gone = NSPredicate { [self] _, _ in !app.navigationBars["Add an element"].exists }
        _ = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: gone, object: nil)], timeout: 5)
        settle(0.4)
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

        // 9. The table, pinched to about 2.5×
        openTab("Table")
        waitFor(app.buttons["element.H"])
        let table = el("table.zoomView")
        waitFor(table)
        table.pinch(withScale: 2.5, velocity: 1.0)
        waitFor(el("table.fit"))
        settle(0.8)
        capture("09-table-zoomed")
        el("table.fit").tap()
        settle(0.6)

        // 10. Compound search: the bundled catalog answers at once
        let field = app.searchFields.firstMatch
        waitFor(field)
        field.tap()
        field.typeText("water")
        waitFor(app.buttons["compoundResult.962"])
        settle(0.8)
        capture("10-compound-search")

        // 11. A compound page, and 12. its 3D explorer
        app.buttons["compoundResult.962"].tap()
        waitFor(el("compound.hero"))
        settle()
        capture("11-compound-detail")
        scrollTo(app.buttons["compound.explore3D"]).tap()
        waitFor(el("compoundExplorer.viewer"))
        settle(3.0)
        capture("12-compound-3d-explorer")
        app.buttons["compoundExplorer.done"].tap()
        waitFor(el("compound.hero"))
        goBack()
        // Leaves the search, so the table is back for the next visit.
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.waitForExistence(timeout: 3) { cancel.tap() }

        // 13. Quiz setup
        openTab("Study")
        waitFor(app.navigationBars["Study"])
        tap(app.buttons["study.mode.quiz"])
        waitFor(el("quizSetup.sheet"))
        settle(0.8)
        capture("13-quiz-setup")
        app.buttons["quizSetup.cancel"].tap()
        waitFor(app.navigationBars["Study"])

        // 14. A Match round
        tap(app.buttons["study.mode.match"])
        waitFor(el("quizSetup.sheet"))
        tap(app.buttons["quizSetup.start"])
        waitFor(el("match.board"))
        settle(0.8)
        capture("14-match-round")
        app.buttons["session.exit"].tap()
        waitFor(app.navigationBars["Study"])

        // 15. My Quizzes, with one saved quiz
        tap(app.buttons["study.mode.quiz"])
        waitFor(el("quizSetup.sheet"))
        tap(app.buttons["quizSetup.save"])
        let alert = app.alerts.firstMatch
        waitFor(alert)
        let nameField = alert.textFields.firstMatch
        waitFor(nameField)
        nameField.tap()
        nameField.typeText("Halogens and noble gases")
        // iOS 26 vends the alert's button twice, so the query is not unique.
        alert.buttons["Save"].firstMatch.tap()
        tap(app.buttons["study.myQuizzes.seeAll"])
        waitFor(app.navigationBars["My Quizzes"])
        settle(0.8)
        capture("15-my-quizzes")
        goBack()

        // 16. The Build tab, empty; 17. water found; 18. C₂H₆O offering a choice
        openTab("Build")
        waitFor(el("build.header"))
        settle(0.8)
        capture("16-build-empty")
        addElement("H")
        tap(app.buttons["build.increment.H"])
        addElement("O")
        tap(app.buttons["build.lookUp"])
        waitFor(el("build.result"))
        settle()
        capture("17-build-water")
        tap(app.buttons["build.clear"])
        addElement("C")
        tap(app.buttons["build.increment.C"])
        addElement("H")
        for _ in 0..<5 { tap(app.buttons["build.increment.H"]) }
        addElement("O")
        tap(app.buttons["build.lookUp"])
        waitFor(el("build.candidates"))
        XCTAssertTrue(labelContaining("Multiple known compounds share this formula.").exists,
                      "C₂H₆O must be offered as a choice, never assumed to be ethanol" + onScreen())
        settle(0.8)
        capture("18-build-ambiguous")

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
        let unavailable = el("paywall.unavailable")

        // Both wait and scroll, because either alone is wrong here.
        //
        // The plan rows come after the header and the feature list, which is
        // more than one screenful on an iPhone SE — and SwiftUI does not vend
        // an accessibility element for content that far outside a ScrollView's
        // viewport, so a plain `waitForExistence` on a small phone waited out
        // its whole timeout on a row that could not appear without scrolling.
        // Scrolling alone is no better: the rows do not exist at all until
        // StoreKit answers, and running to the bottom of the loading state
        // before then finds nothing either.
        let deadline = Date().addingTimeInterval(80)
        var retried = false
        while !yearly.exists, Date() < deadline {
            if unavailable.exists {
                // The first StoreKit answer on a cold simulator can miss the
                // paywall's own deadline, which is what the smaller phone
                // did. A learner would see Try again, so the tour presses it
                // once. Unavailable a second time is the bug — `hasAttemptedLoad`
                // is set and the product list came back empty — and saying
                // so beats timing out with a message about scrolling.
                if !retried {
                    retried = true
                    tap(app.buttons["paywall.retry"])
                    continue
                }
                XCTFail("The paywall rendered its \"options unavailable\" state: "
                        + "StoreKit returned no products for the local "
                        + "Config/PeriodicPro.storekit configuration"
                        + onScreen())
                return
            }
            app.swipeUp()
        }

        XCTAssertTrue(yearly.exists,
                      "The paywall never loaded the yearly plan from "
                      + "Config/PeriodicPro.storekit. Check that the scheme still "
                      + "references it and that the product identifiers match."
                      + onScreen())
        XCTAssertTrue(monthly.exists,
                      "The paywall is missing the monthly plan" + onScreen())
        settle(1.0)
        capture("08-elemora-pro-paywall")

        // The close button lives in the navigation bar, which the swipes above
        // never move, but the swipes do leave the sheet scrolled — so tap it
        // through the same helper the rest of the tour uses rather than
        // assuming where the content ended up.
        tap(app.buttons["paywall.close"])

        // 19. The Home Screen icon, as iOS really draws it.
        //
        // The icon has been blurry before, and every check of the artwork
        // proved the file rather than the pixels a person sees. This is the
        // simulator's own Home Screen with the installed app on it, captured
        // through the full pipeline: asset catalog, build, install, SpringBoard.
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let icon = springboard.icons["Elemora"].firstMatch
        var pages = 0
        while !icon.waitForExistence(timeout: 4), pages < 3 {
            springboard.swipeLeft()
            pages += 1
        }
        XCTAssertTrue(icon.exists, "The Elemora icon should be on the Home Screen after install")
        settle(1.5)
        captureScreen("19-home-screen-icon")
    }
}
