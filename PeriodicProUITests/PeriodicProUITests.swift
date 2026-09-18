import XCTest

/// End-to-end flows through the shipping UI.
///
/// Every query goes through an accessibility identifier — no pixel coordinates,
/// no index-based taps into unnamed elements — so these stay green through
/// layout changes.
final class PeriodicProUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Portrait, explicitly. `PeriodicProLaunchTests` runs each of its
        // checks once per target application UI configuration, and those
        // include landscape — the simulator keeps that rotation, and the next
        // class to run inherits it. The Study tab in landscape then reported
        // "Activation point invalid" for controls it could not resolve, which
        // reads as a broken screen rather than a rotated device. Landscape is
        // still covered, by the launch tests that deliberately ask for it.
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        // Skips onboarding, uses an in-memory store and silences haptics. The
        // compound stub answers PubChem's endpoints from the bundled catalog,
        // so the compound flows below are deterministic and offline.
        app.launchArguments = ["-uiTesting", "-compoundNetworkStub"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// Matches by accessibility identifier regardless of the element type
    /// SwiftUI happens to expose, so these tests survive layout changes.
    private func el(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Matches by label fragment. Several views combine their children into a
    /// single accessibility element, so an exact-string lookup for the visible
    /// text would never match.
    private func labelContaining(_ fragment: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", fragment))
            .firstMatch
    }

    /// What is actually on screen, in one line.
    ///
    /// "Timed out waiting for X" is not a diagnosis — it cannot distinguish a
    /// control that is missing from one that is merely off screen, and telling
    /// those apart from a CI log was worth a whole round trip. This lists the
    /// identifiers the app is currently vending, which answers it directly.
    private func onScreen() -> String {
        var described: [String] = []
        for node in Self.walk(app) where !node.identifier.isEmpty {
            described.append("\(node.identifier)<\(node.elementType.rawValue)>")
        }
        let shown = described.prefix(40).joined(separator: " ")
        let more = described.count > 40 ? " …+\(described.count - 40)" : ""
        // One line, deliberately. A multi-line assertion message is collapsed
        // to its first line in GitHub's error annotation, which is where this
        // is read — a tree spread over forty lines arrives as nothing at all.
        // The type in angle brackets is XCUIElement.ElementType's raw value:
        // 9 is a button, 48 a static text, 6 a generic "other".
        return " | window \(app.windows.firstMatch.frame) "
            + "| \(described.count) identified: \(shown)\(more)"
    }

    private func waitFor(_ element: XCUIElement,
                         _ timeout: TimeInterval = 10,
                         file: StaticString = #filePath,
                         line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      "Timed out waiting for \(element)\(onScreen())",
                      file: file, line: line)
    }

    /// Finds a tab without assuming the shape of the tab bar.
    ///
    /// Scoping to `app.tabBars` is an iPhone assumption: iPadOS 18 draws the
    /// floating tab bar, XCUITest does not vend that as a `tabBar` element,
    /// and the tab buttons appear twice in the tree — once for the bar and
    /// once for its sidebar representation. Tab bar first where it exists,
    /// then anywhere, taking the first of the duplicates.
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

    /// Whether a tab is reachable at all, wherever iOS filed it.
    private func tabExists(_ name: String) -> Bool {
        app.tabBars.buttons[name].exists || app.buttons[name].firstMatch.exists
    }

    /// Scrolls until the element can actually be tapped.
    ///
    /// Scroll *while* looking, rather than waiting for the element to exist and
    /// only then scrolling. SwiftUI does not vend an accessibility element for
    /// content far outside a ScrollView's viewport, so waiting for something
    /// below the fold to exist times out before anything has scrolled — which
    /// is exactly how a reachable control reads as a missing feature.
    ///
    /// The short wait first matters too: most targets are already on screen,
    /// and swiping past one that simply had not rendered yet is how a test
    /// starts scrolling away from what it was looking for.
    ///
    /// That first wait is on hittability, not existence, and it is generous:
    /// a sheet still sliding in vends its rows before they are on screen, and
    /// swiping at that point scrolls the sheet's own list away from the row.
    @discardableResult
    private func scrollTo(_ element: XCUIElement,
                          file: StaticString = #filePath,
                          line: UInt = #line) -> XCUIElement {
        if becomesHittable(element, within: 6) { return element }

        var attempts = 0
        while attempts < 8 {
            app.swipeUp()
            attempts += 1
            // A swipe has momentum; checking and tapping before the list has
            // stopped puts the tap where the row was a moment ago.
            settle(0.6)
            if canTap(element) { return element }
        }

        // It may have been above the starting position rather than below it.
        for _ in 0..<attempts {
            app.swipeDown()
            settle(0.6)
            if canTap(element) { return element }
        }

        XCTAssertTrue(element.exists,
                      "\(element) never appeared, scrolling in both directions\(onScreen())",
                      file: file, line: line)
        XCTAssertTrue(canTap(element),
                      "\(element) exists but never became tappable\(onScreen())",
                      file: file, line: line)
        return element
    }

    private func tap(_ element: XCUIElement,
                     file: StaticString = #filePath,
                     line: UInt = #line) {
        scrollTo(element, file: file, line: line).tap()
    }

    /// Whether the element can take a tap right now.
    ///
    /// `isHittable` is asked only once the frame is a real rectangle with a
    /// visible part inside the window. On iOS 26 an element that is off
    /// screen or mid-transition has no usable hit point, and asking then does
    /// not answer no — it records "Failed to determine hittability" as a test
    /// failure, which is what stopped the builder and explorer tests.
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
    /// `timeout` for it to get there.
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

    /// Lets a scroll's momentum run out. The app is a separate process, so
    /// this blocks only the test runner.
    private func settle(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Asserts the control is reachable — present, and scrollable into view.
    ///
    /// The distinction from `exists` is deliberate. A screen taller than the
    /// display is not a defect, so "reachable" is the claim these tests are
    /// actually making; only the launch test asserts the stronger "on the first
    /// screenful", and only for the table, which is the one screen that
    /// promises it.
    private func assertReachable(_ element: XCUIElement,
                                 _ what: String,
                                 file: StaticString = #filePath,
                                 line: UInt = #line) {
        _ = scrollTo(element, file: file, line: line)
        XCTAssertTrue(element.exists, "\(what) is missing\(onScreen())",
                      file: file, line: line)
    }

    /// Relaunches with Pro entitled. StoreKit is never contacted in a UI test —
    /// a sandbox purchase sheet cannot be driven reliably — so the entitlement
    /// comes from a launch argument instead.
    private func relaunchAsPro() {
        app.terminate()
        app.launchArguments = ["-uiTesting", "-proEntitled", "-compoundNetworkStub"]
        app.launch()
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

    // MARK: - Launch

    func testLaunchesIntoThePeriodicTable() {
        waitFor(app.navigationBars["Periodic Table"])
        // The one place the stronger claim is made on purpose: the table is the
        // app's first screen and the fitted layout exists so that all of it is
        // there without scrolling. If this fails, the table has been pushed
        // below the fold and that is the bug, not the assertion.
        XCTAssertTrue(app.buttons["element.H"].waitForExistence(timeout: 10),
                      "Hydrogen tile should be on screen at launch\(onScreen())")
        XCTAssertTrue(app.buttons["element.Og"].exists,
                      "Oganesson tile should be on screen at launch\(onScreen())")
        XCTAssertTrue(tabExists("Table"), "Table tab missing\(onScreen())")
        XCTAssertTrue(tabExists("Study"), "Study tab missing\(onScreen())")
        XCTAssertTrue(tabExists("Build"), "Build tab missing\(onScreen())")
        XCTAssertTrue(tabExists("Progress"), "Progress tab missing\(onScreen())")
    }

    /// Every tile addressable on its own.
    ///
    /// The regression this exists for: `PeriodicTableScreen` put an
    /// `accessibilityIdentifier` on the whole grid. SwiftUI applies an
    /// accessibility identifier to every descendant element when the view it is
    /// attached to is not an element itself, so all 118 tiles came back named
    /// after the container and not one of them could be addressed. Nothing
    /// caught it, because a spot check for a single tile is not what fails —
    /// the clobbered identifier still matches *something*. Distinctness is.
    func testElementTilesAreIndividuallyAddressable() {
        waitFor(app.buttons["element.H"])
        var tiles: [String] = []
        for node in Self.walk(app) where node.identifier.hasPrefix("element.") {
            tiles.append(node.identifier)
        }

        XCTAssertGreaterThan(tiles.count, 100,
                             "The fitted table should vend a button per element\(onScreen())")
        XCTAssertEqual(Set(tiles).count, tiles.count,
                       "Element tiles share identifiers, so something above them is "
                       + "overwriting their own\(onScreen())")
    }

    func testAllOneHundredAndEighteenTilesAreReachable() {
        // One element from every row of the table, including both detached
        // f-block rows.
        for symbol in ["H", "He", "Li", "Na", "K", "Rb", "Cs", "Fr", "La", "Lu", "Ac", "Lr", "Og"] {
            assertReachable(app.buttons["element.\(symbol)"], "the \(symbol) tile")
        }
    }

    /// Build 5's central claim about the Table screen: when it appears, the
    /// whole table is there.
    ///
    /// Not "reachable" and not "scrollable into view" — on screen, on the
    /// first frame, with no gesture of any kind first. All eighteen columns,
    /// all seven periods, the lanthanides and the actinides.
    func testTheWholeTableIsOnScreenAtLaunchWithoutScrolling() {
        waitFor(app.buttons["element.H"])
        let table = el("table.zoomView")
        waitFor(table)

        // Deliberately no swipe, no pinch and no scrollTo before this point.
        var tiles: [String: CGRect] = [:]
        for node in Self.walk(app) where node.identifier.hasPrefix("element.") {
            tiles[node.identifier] = node.frame
        }
        XCTAssertEqual(tiles.count, 118,
                       "The table opened with \(tiles.count) of 118 tiles on screen\(onScreen())")

        // Every row, named, so a failure says which part of the table was cut
        // off rather than only that a count was short.
        for symbol in ["H", "He", "Li", "Ne", "Na", "Ar", "K", "Kr", "Rb", "Xe",
                       "Cs", "Rn", "Fr", "Og", "La", "Lu", "Ac", "Lr"] {
            XCTAssertNotNil(tiles["element.\(symbol)"],
                            "the \(symbol) tile was not on screen at launch\(onScreen())")
        }

        // And every one of them is inside the table's own window, which is
        // what makes the fitted table unscrollable: there is no content
        // outside the viewport for a scroll to reveal.
        let viewport = table.frame
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(viewport.insetBy(dx: 0, dy: 1)),
                      "the table's own viewport \(viewport) is not inside the window \(window)")
        for (identifier, frame) in tiles {
            XCTAssertGreaterThanOrEqual(frame.minY, viewport.minY - 1,
                                        "\(identifier) sits above the table's viewport")
            XCTAssertLessThanOrEqual(frame.maxY, viewport.maxY + 1,
                                     "\(identifier) is below the fold of the table's viewport — "
                                     + "the fitted table is vertically scrollable")
            XCTAssertGreaterThanOrEqual(frame.minX, viewport.minX - 1,
                                        "\(identifier) is off the leading edge of the table")
            XCTAssertLessThanOrEqual(frame.maxX, viewport.maxX + 1,
                                     "\(identifier) is off the trailing edge of the table — "
                                     + "the fitted table is horizontally scrollable")
        }

        // The f-block rows are the ones a width-driven fit loses first, so
        // they get the explicit claim: they are below the main block and
        // still inside the viewport.
        guard let radon = tiles["element.Rn"], let lawrencium = tiles["element.Lr"] else {
            return XCTFail("the seventh period or the actinide row is missing\(onScreen())")
        }
        XCTAssertGreaterThan(lawrencium.minY, radon.minY,
                             "the actinide row should sit below the main block")
        XCTAssertLessThanOrEqual(lawrencium.maxY, viewport.maxY + 1,
                                 "the actinide row is cut off by the table's viewport")
    }

    // MARK: - Zoom

    /// The table is pinch-to-zoom. XCUITest's pinch is a real two-finger
    /// gesture on the simulator, so this is the interaction itself, not a
    /// stand-in: the tiles must grow, and a tile that is actually on screen
    /// afterwards must still open its page.
    ///
    /// What it deliberately does *not* claim is that one named element stays
    /// put. Zooming in on the middle of the table moves most of it off screen
    /// — that is the feature — so asserting on a particular symbol was
    /// asserting on the focal-point arithmetic and the phone's aspect ratio,
    /// which is how this test failed on a table that worked. The claim is that
    /// the tiles grew and that whatever is on screen is still live.
    func testPinchZoomsTheTableAndTilesStayTappable() {
        waitFor(app.buttons["element.H"])
        let table = el("table.zoomView")
        waitFor(table)

        let hydrogen = app.buttons["element.H"]
        let before = hydrogen.frame.width
        XCTAssertGreaterThan(before, 12, "the fitted table should have real tiles\(onScreen())")

        table.pinch(withScale: 2.5, velocity: 1.0)

        // Wait for the layout to settle at the new size rather than asserting
        // mid-animation. Every tile grows, so any tile still vended will do.
        XCTAssertTrue(waitForWidestTile(atLeast: before * 1.5, within: 8),
                      "Pinching out should make the tiles larger; they were \(before) wide "
                      + "and are \(Self.largestTileWidth(in: app)) wide now" + onScreen())

        // A tile in the zoomed window must still open its page: the pinch
        // guard swallows only the pinch's own lift, not a tap that follows.
        settle(0.6)
        guard let tappable = Self.tappableTile(in: app, canTap: canTap) else {
            XCTFail("no element tile was tappable while zoomed\(onScreen())")
            return
        }
        tappable.tap()
        waitFor(app.buttons["detail.favoriteButton"])
        goBack()

        // Coming back, the table is still zoomed: the position survived the
        // push. Measured on whatever tile is on screen, not a named one.
        XCTAssertTrue(waitForWidestTile(atLeast: before * 1.5, within: 8),
                      "Returning from a detail page should keep the table's zoom; tiles are "
                      + "\(Self.largestTileWidth(in: app)) wide against \(before) fitted"
                      + onScreen())

        // And pinching back in returns the table to fitted, with every column
        // on screen again — the zoom does not go below the fitted state.
        //
        // Deliberately a pinch rather than a double tap: XCUITest taps the
        // middle of the element, the middle of a zoomed table is a tile, and a
        // tile is a button — the double tap would open an element's page
        // rather than exercise the gesture.
        //
        // Measured on the widest tile rather than on hydrogen: a zoomed table
        // that has been panned may have hydrogen off screen entirely, and a
        // tile that is not on screen has no width to compare.
        //
        // And pinched more than once. XCUITest cannot synthesize an arbitrary
        // scale — the two fingers have to start and finish inside the element
        // — so one pinch closed from 2.5x lands around 1.26x, which the app is
        // right to leave alone: the snap-to-fitted floor is 1.04, and 1.26 is
        // a zoom the learner chose. A person pinches again. Asserting the
        // table was fitted after a single gesture was asserting on how far
        // XCUITest can move two fingers, not on anything the app does.
        var pinches = 0
        while pinches < 4, Self.largestTileWidth(in: app) > before * 1.2 {
            table.pinch(withScale: 0.35, velocity: -2.0)
            pinches += 1
            settle(0.8)
        }
        XCTAssertTrue(
            waitForWidestTile(atMost: before * 1.2, within: 8),
            "Pinching in should return the table to its fitted size; tiles were "
            + "\(before) wide fitted and are \(Self.largestTileWidth(in: app)) wide "
            + "after \(pinches) pinches" + onScreen()
        )
        XCTAssertTrue(app.buttons["element.Og"].waitForExistence(timeout: 5),
                      "every column should be back on screen\(onScreen())")
    }

    /// Waits for some tile to be at least `width` wide, which is what says a
    /// pinch open landed — whichever tiles the zoom leaves on screen.
    private func waitForWidestTile(atLeast width: CGFloat, within timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if Self.largestTileWidth(in: app) >= width { return true }
            if Date() >= deadline { return false }
            settle(0.25)
        }
    }

    /// Waits for every tile to be no wider than `width`, which is what says a
    /// pinch closed landed.
    private func waitForWidestTile(atMost width: CGFloat, within timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let widest = Self.largestTileWidth(in: app)
            if widest > 0, widest <= width { return true }
            if Date() >= deadline { return false }
            settle(0.25)
        }
    }

    /// Every node under `element`, depth first, from one snapshot.
    ///
    /// Reading `identifier`, `elementType` or `frame` from an `XCUIElement`
    /// re-resolves that element's query against the app, so measuring a
    /// hundred and eighteen tiles is a hundred and eighteen round trips — and
    /// inside a polling predicate, that many again on every tick. XCUITest
    /// answers that with "Failed to resolve query: Timed out while evaluating
    /// UI query" and the test never gets its answer at all. A snapshot is a
    /// single round trip carrying every attribute.
    private static func walk(_ element: XCUIElement) -> [XCUIElementSnapshot] {
        guard let root = try? element.snapshot() else { return [] }
        var found: [XCUIElementSnapshot] = []
        var stack: [XCUIElementSnapshot] = [root]
        while let node = stack.popLast() {
            found.append(node)
            stack.append(contentsOf: node.children)
        }
        return found
    }

    /// Every element tile the table currently vends, with its frame.
    private static func tileFrames(in app: XCUIApplication) -> [String: CGRect] {
        var frames: [String: CGRect] = [:]
        for node in walk(app) where node.identifier.hasPrefix("element.") {
            frames[node.identifier] = node.frame
        }
        return frames
    }

    /// The widest element tile currently vended, or zero. Used instead of a
    /// named symbol so the measurement survives panning.
    private static func largestTileWidth(in app: XCUIApplication) -> CGFloat {
        var widest: CGFloat = 0
        for frame in tileFrames(in: app).values where frame.width > widest {
            widest = frame.width
        }
        return widest
    }

    /// A tile that is on screen and will take a tap.
    ///
    /// The snapshot narrows the field to tiles with a real share of the window
    /// first, so `canTap` — which does cost a query each time — is asked about
    /// a handful of candidates rather than all of them.
    private static func tappableTile(in app: XCUIApplication,
                                     canTap: (XCUIElement) -> Bool) -> XCUIElement? {
        // Written out rather than chained: the same work as a map, filter,
        // sort and map over a dictionary of tuples defeated the type checker
        // outright — "unable to type-check this expression in reasonable time".
        let window: CGRect = app.windows.firstMatch.frame
        var ranked: [(identifier: String, area: CGFloat)] = []
        for (identifier, frame) in tileFrames(in: app) {
            let visible: CGRect = frame.intersection(window)
            guard visible.width >= 8, visible.height >= 8 else { continue }
            ranked.append((identifier: identifier, area: visible.width * visible.height))
        }
        // Most fully on screen first, so the tile that is asked about is the
        // one most likely to answer yes — a tile clipped by the tab bar is
        // exactly the one that is not hittable.
        ranked.sort { $0.area > $1.area }
        for entry in ranked.prefix(8) where canTap(app.buttons[entry.identifier]) {
            return app.buttons[entry.identifier]
        }
        return nil
    }

    /// Dragging a zoomed table moves it. Without this the pinch test alone
    /// could pass on a table that grew its tiles and then refused to pan.
    func testAZoomedTableCanBePanned() {
        waitFor(app.buttons["element.H"])
        let table = el("table.zoomView")
        waitFor(table)
        table.pinch(withScale: 2.5, velocity: 1.0)
        settle(1.0)

        let before = Self.visibleTileSymbols(in: app)
        XCTAssertFalse(before.isEmpty, "the zoomed table should still vend tiles\(onScreen())")

        table.swipeLeft()
        settle(1.0)
        let after = Self.visibleTileSymbols(in: app)
        XCTAssertFalse(after.isEmpty, "panning should not empty the table\(onScreen())")
        XCTAssertNotEqual(before, after,
                          "dragging a zoomed table should show a different part of it; "
                          + "\(before.count) tiles on screen before, \(after.count) after"
                          + onScreen())
    }

    /// The symbols on screen, as a set.
    ///
    /// On screen, not merely built: the table keeps all hundred and eighteen
    /// tiles in the tree whatever the zoom, so comparing everything it vends
    /// before and after a drag compares two identical sets and proves nothing.
    /// What a pan changes is which of them the window actually contains.
    private static func visibleTileSymbols(in app: XCUIApplication) -> Set<String> {
        let window = app.windows.firstMatch.frame
        var symbols: Set<String> = []
        for (identifier, frame) in tileFrames(in: app) {
            let visible: CGRect = frame.intersection(window)
            guard visible.width >= 4, visible.height >= 4 else { continue }
            symbols.insert(identifier)
        }
        return symbols
    }

    /// There is no zoom control on the table, and there must not be one.
    ///
    /// The pinch is the interface. A Fit chip, a plus/minus zoom menu and a
    /// filter button were three pieces of chrome that existed because the
    /// gestures were not trusted; all three are gone, and this fails if any of
    /// them comes back.
    func testTheTableHasNoVisibleZoomOrFilterControls() {
        waitFor(app.buttons["element.H"])
        for identifier in ["table.fit", "table.zoomMenu", "table.zoomIn", "table.zoomOut",
                           "table.fitTable", "table.filterButton"] {
            XCTAssertFalse(el(identifier).exists,
                           "\(identifier) should no longer exist\(onScreen())")
        }
        for label in ["Fit", "Fit table", "Zoom in", "Zoom out"] {
            XCTAssertFalse(app.buttons[label].exists,
                           "a \u{201C}\(label)\u{201D} button should not be on the table")
        }

        // Still zoomable without two fingers. The table's own container is
        // what VoiceOver and Switch Control adjust, and it draws nothing: the
        // value it reports is the proof there is something there to drive.
        let table = el("table.zoomView")
        XCTAssertTrue(table.exists, "the table must stay adjustable for assistive technology")
        let spoken = (table.value as? String) ?? ""
        XCTAssertTrue(spoken.contains("\u{00D7}"),
                      "the table should tell assistive technology what the zoom is, and reads "
                      + "\u{201C}\(spoken)\u{201D}" + onScreen())
    }

    // MARK: - Detail

    /// Scan is reachable from the app's first screen, in one tap, and asks
    /// for the camera only when it is opened.
    ///
    /// A simulator has no camera and cannot run VisionKit's live text
    /// recognition, so what this drives is the path that matters most for App
    /// Review and for a learner who says no: the screen appears, explains
    /// itself, and offers a way forward that does not need a camera. The
    /// recognition itself is unit-tested against fixtures in `ScannerTests`;
    /// it cannot be exercised here, and a test that pretended otherwise would
    /// be testing nothing.
    func testScanIsOneTapFromTheTableAndFallsBackWithoutACamera() {
        waitFor(app.buttons["element.H"])
        let scan = el("table.scan")
        waitFor(scan)
        // And it costs the table none of its height: every tile is still on
        // screen with the button there.
        var tiles = 0
        for node in Self.walk(app) where node.identifier.hasPrefix("element.") { tiles += 1 }
        XCTAssertEqual(tiles, 118, "the scan button pushed the table off screen\(onScreen())")

        scan.tap()
        waitFor(el("scanner.screen"))

        // No camera here, so the screen says so rather than showing black.
        let unavailable = el("scanner.unavailable")
        XCTAssertTrue(unavailable.waitForExistence(timeout: 10),
                      "the scanner should explain itself when it cannot run\(onScreen())")
        assertReachable(el("scanner.manualSearch"), "the manual search fallback")
        // And it is honest about what it does not read.
        assertReachable(el("scanner.structureNote"), "the note about structure diagrams")

        tap(el("scanner.done"))
        waitFor(app.navigationBars["Periodic Table"])
    }

    func testTappingAnElementOpensItsDetailPage() {
        openElement("Na")
        XCTAssertTrue(labelContaining("Sodium").waitForExistence(timeout: 6),
                      "The detail page should identify itself as Sodium")
        XCTAssertTrue(labelContaining("Alkali Metal").exists, "The family badge should be present")
        XCTAssertTrue(app.buttons["detail.favoriteButton"].exists)
        goBack()
        waitFor(app.navigationBars["Periodic Table"])
    }

    func testDetailShowsMorePropertiesOnDemand() {
        openElement("Fe")
        tap(app.buttons["detail.moreProperties"])
        XCTAssertTrue(labelContaining("Melting point").waitForExistence(timeout: 6),
                      "Expanded properties should include the melting point")
        XCTAssertTrue(labelContaining("Electronegativity").exists)
    }

    func testFavoritingAnElementPersistsIntoStudy() {
        openElement("Au")
        let favorite = app.buttons["detail.favoriteButton"]
        waitFor(favorite)
        favorite.tap()

        goBack()
        openTab("Study")
        XCTAssertTrue(app.buttons["study.favorite.Au"].waitForExistence(timeout: 6),
                      "Gold should appear in the Favorites carousel")

        // Unfavoriting removes it again.
        tap(app.buttons["study.favorite.Au"])
        let favoriteAgain = app.buttons["detail.favoriteButton"]
        waitFor(favoriteAgain)
        favoriteAgain.tap()
        goBack()
        XCTAssertFalse(app.buttons["study.favorite.Au"].waitForExistence(timeout: 3),
                       "Unfavoriting should remove Gold from the carousel")
    }

    // MARK: - Search

    func testSearchingByNameOpensTheElement() {
        let field = app.searchFields.firstMatch
        waitFor(field)
        field.tap()
        field.typeText("oxygen")

        let result = app.buttons["searchResult.O"]
        waitFor(result)
        result.tap()
        waitFor(app.buttons["detail.favoriteButton"])
        XCTAssertTrue(labelContaining("Oxygen").exists)
    }

    func testSearchingBySymbolAndAtomicNumber() {
        let field = app.searchFields.firstMatch
        waitFor(field)
        field.tap()
        field.typeText("26")
        XCTAssertTrue(app.buttons["searchResult.Fe"].waitForExistence(timeout: 5),
                      "Atomic number 26 should find Iron")
    }

    func testSearchWithNoMatchesShowsAnEmptyState() {
        let field = app.searchFields.firstMatch
        waitFor(field)
        field.tap()
        field.typeText("zzzzzz")
        XCTAssertTrue(labelContaining("No matches").waitForExistence(timeout: 6),
                      "An unmatched query should explain itself rather than show nothing")
    }

    // MARK: - Filters

    func testFilteringByFamily() {
        waitFor(app.buttons["element.H"])
        // All four primary controls are on screen at once, with no sideways
        // scrolling and no filter button beside them.
        for title in ["All", "Metals", "Nonmetals", "Metalloids"] {
            let chip = app.buttons["filter.\(title)"]
            XCTAssertTrue(chip.waitForExistence(timeout: 6),
                          "the \(title) filter should be on screen\(onScreen())")
            XCTAssertTrue(canTap(chip),
                          "the \(title) filter should be tappable without scrolling\(onScreen())")
        }

        tap(app.buttons["filter.Nonmetals"])
        // Oxygen is a nonmetal and stays; iron is a metal and is dimmed out of
        // the accessibility tree entirely.
        XCTAssertTrue(app.buttons["element.O"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["element.Fe"].exists,
                       "a filtered-out element should leave the accessibility tree")

        tap(app.buttons["filter.All"])
        XCTAssertTrue(app.buttons["element.Fe"].waitForExistence(timeout: 5),
                      "clearing the filter should bring every element back")
    }

    /// The Families card under the table is the only detailed filter, and it
    /// is a real one: rows are buttons, several can be on at once, and the
    /// table follows.
    ///
    /// The card is below the table, so every check on the table itself comes
    /// after scrolling back to it. A tile that is merely off screen does not
    /// exist as far as XCUITest is concerned, and asserting "filtered out" on
    /// that would pass for the wrong reason.
    func testFamiliesCardFiltersTheTable() {
        waitFor(app.buttons["element.H"])

        tap(app.buttons["legend.nobleGas"])
        XCTAssertTrue(app.buttons["legend.nobleGas"].isSelected,
                      "a tapped family should read as selected\(onScreen())")
        scrollToTable()
        XCTAssertTrue(app.buttons["element.Ne"].exists,
                      "neon should survive a noble-gas filter\(onScreen())")
        XCTAssertFalse(app.buttons["element.Fe"].exists,
                       "iron is not a noble gas and should be filtered out")

        // A second family joins the first rather than replacing it.
        tap(app.buttons["legend.transitionMetal"])
        scrollToTable()
        XCTAssertTrue(app.buttons["element.Fe"].exists,
                      "adding transition metals should bring iron back\(onScreen())")
        XCTAssertTrue(app.buttons["element.Ne"].exists, "and neon should still be there")
        XCTAssertFalse(app.buttons["element.Na"].exists,
                       "sodium is in neither selected family")

        // Tapping a selected family removes it.
        tap(app.buttons["legend.transitionMetal"])
        scrollToTable()
        XCTAssertFalse(app.buttons["element.Fe"].exists,
                       "removing transition metals should filter iron out again")

        tap(app.buttons["legend.clear"])
        scrollToTable()
        XCTAssertTrue(app.buttons["element.Na"].exists,
                      "clearing should restore every element\(onScreen())")
    }

    /// Brings the periodic table back onto the screen after something below it
    /// has been tapped.
    private func scrollToTable() {
        for _ in 0..<6 {
            if canTap(app.buttons["element.H"]) { return }
            app.swipeDown()
            settle(0.5)
        }
        settle(0.4)
    }

    // MARK: - Study

    func testFlashcardRoundRevealsAndAdvances() {
        openTab("Study")
        tap(app.buttons["study.mode.flashcards"])

        let reveal = app.buttons["session.reveal"]
        waitFor(reveal)
        reveal.tap()

        XCTAssertTrue(app.buttons["session.knewThis"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["session.reviewAgain"].exists)
        app.buttons["session.knewThis"].tap()

        // The next card starts hidden again.
        XCTAssertTrue(app.buttons["session.reveal"].waitForExistence(timeout: 5))
        app.buttons["session.exit"].tap()
        XCTAssertTrue(app.navigationBars["Study"].waitForExistence(timeout: 5))
    }

    func testCompletingAFlashcardRoundShowsASummary() {
        openTab("Study")
        tap(app.buttons["study.mode.flashcards"])

        for _ in 0..<10 {
            let reveal = app.buttons["session.reveal"]
            guard reveal.waitForExistence(timeout: 6) else { break }
            reveal.tap()
            let knew = app.buttons["session.knewThis"]
            guard knew.waitForExistence(timeout: 6) else { break }
            knew.tap()
        }

        XCTAssertTrue(app.buttons["summary.done"].waitForExistence(timeout: 10),
                      "Finishing every card should show the summary")
        XCTAssertTrue(app.buttons["summary.again"].exists)
        app.buttons["summary.done"].tap()
    }

    func testQuizQuestionAcceptsAnAnswerAndAdvances() {
        openTab("Study")
        tap(app.buttons["study.mode.quiz"])
        waitFor(el("quizSetup.sheet"))
        tap(app.buttons["quizSetup.start"])

        waitFor(el("quiz.prompt"))
        let option = app.buttons["quiz.option.0"]
        waitFor(option)
        option.tap()

        let next = app.buttons["quiz.next"]
        waitFor(next)
        XCTAssertTrue(next.isEnabled, "Answering should enable the next button")
        next.tap()
        XCTAssertTrue(el("quiz.prompt").waitForExistence(timeout: 6))

        app.buttons["session.exit"].tap()
    }

    func testIdentifyRoundRuns() {
        openTab("Study")
        tap(app.buttons["study.mode.identify"])

        let reveal = app.buttons["session.reveal"]
        waitFor(reveal)
        reveal.tap()
        XCTAssertTrue(app.buttons["session.knewThis"].waitForExistence(timeout: 6),
                      "Revealing should offer the self-rating buttons")
        app.buttons["session.exit"].tap()
    }

    // MARK: - Progress

    func testProgressScreenReflectsAnsweredCards() {
        openTab("Study")
        tap(app.buttons["study.mode.flashcards"])
        let reveal = app.buttons["session.reveal"]
        waitFor(reveal)
        reveal.tap()
        app.buttons["session.knewThis"].tap()
        app.buttons["session.exit"].tap()

        openTab("Progress")
        waitFor(app.navigationBars["Progress"])
        // `progress.hero` is the ring, the mastery line and the rank in one
        // card. It replaced the bare `progress.ring` when the Progress tab was
        // rebuilt this build: the ring is now hidden from VoiceOver because
        // its two numbers are read out in the line under it, so the card is
        // the element that exists to be found.
        waitFor(el("progress.hero"), 6)
        XCTAssertTrue(el("progress.streak").exists,
                      "The day-streak tile should be on the Progress tab\(onScreen())")
        XCTAssertTrue(el("progress.answered").exists,
                      "The cards-answered tile should be on the Progress tab\(onScreen())")
        // The breakdown by its row's own identifier rather than by hunting the
        // screen for the words: a label search takes the first element whose
        // label happens to contain them, and scrolling towards the wrong one
        // is how a present feature reads as missing.
        let family = app.buttons["progress.family.alkaliMetal"]
        assertReachable(family, "the per-family breakdown")
        XCTAssertTrue(family.label.contains("Alkali Metals"),
                      "the family row should name its family; it reads \(family.label)")
    }

    // MARK: - Study layout

    func testStudyScreenShowsTheRedesignedHierarchy() {
        openTab("Study")
        waitFor(app.navigationBars["Study"])

        // Greeting, two status cards, then the strongest card on the page.
        XCTAssertTrue(el("study.greeting").exists, "The greeting should head the Study tab")
        XCTAssertTrue(el("study.streakCard").exists)
        XCTAssertTrue(el("study.masteryCard").exists)
        XCTAssertTrue(el("study.heroCard").exists, "Flashcards should be the hero card")

        // Five practice tiles, Smart Review included. Scrolled to rather than
        // asserted on the first screenful: the Study tab is taller than the
        // display by design, which is why `scrollTo` exists at all.
        for mode in ["flashcards", "quiz", "match", "identify", "smartReview"] {
            assertReachable(app.buttons["study.mode.\(mode)"], "the \(mode) tile")
        }
    }

    func testStatusCardsShowRealValuesForANewLearner() {
        openTab("Study")
        // A brand new in-memory store: no invented streak, no invented mastery.
        XCTAssertTrue(labelContaining("0 Day streak").waitForExistence(timeout: 6),
                      "A new learner should see a zero streak, not a demo value")
        XCTAssertTrue(labelContaining("0% Elements mastered").exists)
    }

    func testStatusCardOpensProgress() {
        openTab("Study")
        tap(el("study.streakCard"))
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 6),
                      "The streak card should lead to Progress")
    }

    func testHeroCardStartsAFlashcardRound() {
        openTab("Study")
        tap(el("study.heroCard"))
        XCTAssertTrue(app.buttons["session.reveal"].waitForExistence(timeout: 6))
        app.buttons["session.exit"].tap()
    }

    func testFreeAllowanceIsShownAndCountsDown() {
        openTab("Study")
        XCTAssertTrue(labelContaining("3 free rounds left today").waitForExistence(timeout: 6),
                      "A free learner should be told how much study is left")

        tap(app.buttons["study.mode.flashcards"])
        for _ in 0..<10 {
            let reveal = app.buttons["session.reveal"]
            guard reveal.waitForExistence(timeout: 6) else { break }
            reveal.tap()
            let knew = app.buttons["session.knewThis"]
            guard knew.waitForExistence(timeout: 6) else { break }
            knew.tap()
        }
        waitFor(app.buttons["summary.done"])
        app.buttons["summary.done"].tap()

        XCTAssertTrue(labelContaining("2 free rounds left today").waitForExistence(timeout: 6),
                      "Finishing a round should consume exactly one of the free rounds")
    }

    func testAbandoningARoundDoesNotConsumeTheAllowance() {
        openTab("Study")
        tap(app.buttons["study.mode.flashcards"])
        let reveal = app.buttons["session.reveal"]
        waitFor(reveal)
        reveal.tap()
        app.buttons["session.knewThis"].tap()
        // Leave part way through.
        app.buttons["session.exit"].tap()

        XCTAssertTrue(labelContaining("3 free rounds left today").waitForExistence(timeout: 6),
                      "Quitting part way through must not cost a free round")
    }

    // MARK: - Pro

    func testSmartReviewIsMarkedProAndOpensThePaywall() {
        openTab("Study")
        let smartReview = app.buttons["study.mode.smartReview"]
        scrollTo(smartReview)
        XCTAssertTrue(smartReview.label.contains("Elemora Pro"),
                      "Smart Review should be marked as a Pro feature for a free learner")

        smartReview.tap()
        waitFor(el("paywall"))
        XCTAssertTrue(app.buttons["paywall.restore"].exists,
                      "The paywall must offer Restore Purchases")
        XCTAssertTrue(app.buttons["paywall.close"].exists)
        app.buttons["paywall.close"].tap()
        XCTAssertTrue(app.navigationBars["Study"].waitForExistence(timeout: 6),
                      "Closing the paywall should return to Study")
    }

    func testPaywallShowsItsLegalLinks() {
        openTab("Study")
        tap(app.buttons["study.mode.smartReview"])
        waitFor(el("paywall"))
        XCTAssertTrue(app.buttons["paywall.privacy"].exists)
        XCTAssertTrue(app.buttons["paywall.terms"].exists)
        XCTAssertTrue(labelContaining("renews automatically").exists,
                      "Auto-renewal terms must be stated on the paywall")
        app.buttons["paywall.close"].tap()
    }

    func testSmartReviewIsNotMarkedProForASubscriber() {
        relaunchAsPro()
        openTab("Study")
        let smartReview = app.buttons["study.mode.smartReview"]
        scrollTo(smartReview)
        XCTAssertFalse(smartReview.label.contains("Elemora Pro"),
                       "A subscriber should not see a Pro badge")
        XCTAssertFalse(el("study.allowance").exists,
                       "A subscriber should not see a free-round counter")
    }

    // MARK: - 3D structures

    func testDemoElementOpensTheStructureExplorer() {
        // Gold is one of the six elements that are free to explore.
        openElement("Au")
        let explore = app.buttons["detail.explore3D"]
        scrollTo(explore)
        XCTAssertFalse(explore.label.contains("Elemora Pro"),
                       "Gold is a free demo element and must not be marked Pro")
        explore.tap()

        waitFor(el("explorer.viewer"))
        XCTAssertTrue(el("explorer.parts").exists,
                      "The explorer should list selectable parts for accessibility")
        app.buttons["explorer.done"].tap()
        XCTAssertTrue(app.buttons["detail.favoriteButton"].waitForExistence(timeout: 6))
    }

    func testNonDemoElementShowsThePaywallInstead() {
        openElement("Ne")
        let explore = app.buttons["detail.explore3D"]
        scrollTo(explore)
        XCTAssertTrue(explore.label.contains("Elemora Pro"),
                      "Neon is not a demo element, so its explorer should be marked Pro")
        explore.tap()

        waitFor(el("paywall"))
        app.buttons["paywall.close"].tap()
    }

    func testSubscriberCanExploreAnyElement() {
        relaunchAsPro()
        openElement("Ne")
        tap(app.buttons["detail.explore3D"])
        waitFor(el("explorer.viewer"))
        XCTAssertTrue(el("explorer.summary").exists,
                      "The explorer should describe what is being shown")
        app.buttons["explorer.done"].tap()
    }

    func testStructureExplorerSelectsAPart() {
        openElement("O")
        tap(app.buttons["detail.explore3D"])
        waitFor(el("explorer.parts"))

        // Selecting from the parts row is the accessible equivalent of tapping
        // the model, and drives exactly the same selection.
        let atom = app.buttons["Atom 1"]
        if atom.waitForExistence(timeout: 5) {
            atom.tap()
            XCTAssertTrue(el("explorer.inspector").waitForExistence(timeout: 6),
                          "Selecting a part should open the inspector")
        }
        app.buttons["explorer.done"].tap()
    }

    // MARK: - Recent searches

    func testRecentSearchesAppearOnStudy() {
        let field = app.searchFields.firstMatch
        waitFor(field)
        field.tap()
        field.typeText("sodium")
        waitFor(app.buttons["searchResult.Na"])
        app.buttons["searchResult.Na"].tap()
        waitFor(app.buttons["detail.favoriteButton"])
        goBack()

        openTab("Study")
        let section = el("study.recentSearches")
        scrollTo(section)
        XCTAssertTrue(labelContaining("Searched for sodium").exists,
                      "A search should be recorded on the Study tab")

        tap(app.buttons["study.clearSearches"])
        XCTAssertFalse(labelContaining("Searched for sodium").waitForExistence(timeout: 3),
                       "Clear should empty the recent searches list")
    }

    // MARK: - Settings

    /// Progress opens Settings from a gear, and Settings holds everything
    /// there is to set or to read.
    func testSettingsOpensFromProgressAndHoldsEverything() {
        openTab("Progress")
        waitFor(app.navigationBars["Progress"])
        XCTAssertFalse(el("progress.menu").exists,
                       "the ellipsis menu has been replaced by a gear\(onScreen())")
        tap(app.buttons["progress.settings"])
        waitFor(app.navigationBars["Settings"])

        // Elemora Pro: status, Apple's own management flow, and Restore.
        assertReachable(el("settings.plan"), "the current plan")
        assertReachable(app.buttons["settings.manageSubscription"], "Manage Subscription")
        assertReachable(app.buttons["settings.restore"], "Restore Purchases")

        // The links, with their exact destinations. The value is asserted
        // rather than the tap: tapping opens Safari, which is not this app.
        let destinations = [
            "settings.privacy": "https://elemora.idlery.com/privacy",
            "settings.terms": "https://elemora.idlery.com/terms",
            "settings.support": "https://elemora.idlery.com/support",
            "settings.website": "https://elemora.idlery.com",
        ]
        for (identifier, expected) in destinations {
            let row = app.buttons[identifier]
            assertReachable(row, identifier)
            XCTAssertEqual(row.value as? String, expected,
                           "\(identifier) points at the wrong page")
        }
        assertReachable(app.buttons["settings.contactSupport"], "Contact Support")
        XCTAssertTrue(labelContaining("support@idlery.com").exists,
                      "the support address should be readable in Settings\(onScreen())")

        // About moved here from the ellipsis menu, and still opens.
        tap(app.buttons["settings.about"])
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 6))
        app.navigationBars["About"].buttons["Done"].tap()
        waitFor(app.navigationBars["Settings"])
    }

    /// The appearance choice applies at once and survives leaving the screen.
    func testAppearanceSelectionPersists() {
        openTab("Progress")
        tap(app.buttons["progress.settings"])
        waitFor(app.navigationBars["Settings"])

        let system = app.buttons["settings.appearance.system"]
        assertReachable(system, "the System appearance row")
        XCTAssertTrue(system.isSelected, "System is the default")

        tap(app.buttons["settings.appearance.dark"])
        XCTAssertTrue(app.buttons["settings.appearance.dark"].isSelected,
                      "Dark should become the selection\(onScreen())")
        XCTAssertFalse(app.buttons["settings.appearance.system"].isSelected)

        // Leave and come back: the choice is stored, not held in the view.
        goBack()
        waitFor(app.navigationBars["Progress"])
        tap(app.buttons["progress.settings"])
        waitFor(app.navigationBars["Settings"])
        assertReachable(app.buttons["settings.appearance.dark"], "the Dark appearance row")
        XCTAssertTrue(app.buttons["settings.appearance.dark"].isSelected,
                      "the appearance should survive leaving Settings\(onScreen())")

        tap(app.buttons["settings.appearance.light"])
        XCTAssertTrue(app.buttons["settings.appearance.light"].isSelected)
        tap(app.buttons["settings.appearance.system"])
        XCTAssertTrue(app.buttons["settings.appearance.system"].isSelected,
                      "System should restore the device's own appearance")
    }

    /// Reset Progress moved into Settings and kept its confirmation.
    func testResetProgressKeepsItsConfirmation() {
        openTab("Study")
        tap(app.buttons["study.mode.flashcards"])
        waitFor(app.buttons["session.reveal"])
        app.buttons["session.reveal"].tap()
        app.buttons["session.knewThis"].tap()
        app.buttons["session.exit"].tap()

        openTab("Progress")
        tap(app.buttons["progress.settings"])
        waitFor(app.navigationBars["Settings"])
        tap(app.buttons["settings.resetProgress"])

        // The destructive button is the confirmation, and it is the one thing
        // here the app names itself. Waiting on a button labeled "Cancel" was
        // waiting on something iOS does not always draw: this sheet comes with
        // a dismiss region instead, and backing out means tapping outside it.
        let confirm = app.buttons["settings.confirmReset"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 6),
                      "Reset must ask before it does anything\(onScreen())")
        XCTAssertTrue(labelContaining("Favorites are kept").exists,
                      "the confirmation should say what survives a reset\(onScreen())")

        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.exists {
            cancel.tap()
        } else {
            app.otherElements["PopoverDismissRegion"].firstMatch.tap()
        }

        // Backed out, and nothing happened: Settings is still there and the
        // day that was studied a moment ago is still counted.
        waitFor(app.navigationBars["Settings"])
        goBack()
        waitFor(app.navigationBars["Progress"])
        let answered = el("progress.answered")
        scrollTo(answered)
        XCTAssertTrue(answered.label.contains("1"),
                      "backing out of the confirmation must not clear progress; "
                      + "the answered tile reads \u{201C}\(answered.label)\u{201D}"
                      + onScreen())
    }

    // MARK: - Compounds

    func testCompoundSearchFindsWaterAndOpensItsPage() {
        let field = app.searchFields.firstMatch
        waitFor(field)
        field.tap()
        field.typeText("water")

        let result = app.buttons["compoundResult.962"]
        waitFor(result)
        result.tap()
        waitFor(el("compound.hero"))
        XCTAssertTrue(labelContaining("Water").exists)
        let attribution = el("compound.attribution")
        scrollTo(attribution)
        XCTAssertTrue(attribution.label.contains("PubChem"),
                      "A compound page must name its data source\(onScreen())")
        XCTAssertTrue(el("compound.structureStyle").exists, "The structure card offers Ball & Stick / Space Fill")

        app.buttons["compound.favoriteButton"].tap()
        goBack()
        openTab("Study")
        XCTAssertTrue(app.buttons["study.favoriteCompound.962"].waitForExistence(timeout: 6),
                      "A favorited compound should appear on the Study tab's Favorites shelf"
                      + onScreen())
        // And only once. The Compounds shelf is study material, and a favorite
        // that also appeared there would be the same tile twice on one screen.
        XCTAssertFalse(app.buttons["study.compound.962"].exists,
                       "a favorite should not be repeated on the study-material shelf")
    }

    func testNumericSearchNeverAsksPubChem() {
        let field = app.searchFields.firstMatch
        waitFor(field)
        field.tap()
        field.typeText("26")
        XCTAssertTrue(app.buttons["searchResult.Fe"].waitForExistence(timeout: 5))
        XCTAssertFalse(el("search.compounds.searching").waitForExistence(timeout: 2),
                       "An atomic-number query must not start an online compound search")
    }

    func testCompoundExplorerOpensForEveryone() {
        let field = app.searchFields.firstMatch
        waitFor(field)
        field.tap()
        field.typeText("water")
        tap(app.buttons["compoundResult.962"])
        waitFor(el("compound.hero"))
        let explore = app.buttons["compound.explore3D"]
        scrollTo(explore)
        XCTAssertFalse(explore.label.contains("Elemora Pro"), "Compound features are free for everyone")
        explore.tap()
        waitFor(el("compoundExplorer.viewer"))
        XCTAssertTrue(el("compoundExplorer.parts").exists)
        app.buttons["compoundExplorer.done"].tap()
        waitFor(el("compound.hero"))
    }

    // MARK: - Build

    /// Adds an element through the picker and confirms it reached the tray.
    private func addElement(_ symbol: String, searching name: String? = nil) {
        tap(app.buttons["build.addElement"])
        // The picker slides in; its rows are tapped only once it has arrived.
        waitFor(app.navigationBars["Add an element"])
        settle(0.6)
        if let name {
            let field = app.searchFields.firstMatch
            waitFor(field)
            field.tap()
            field.typeText(name)
        }
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

    func testBuildTabShowsTheCompoundBuilderBeta() {
        openTab("Build")
        waitFor(el("build.header"))
        XCTAssertTrue(el("build.beta").exists, "The builder must be marked as a beta\(onScreen())")
        XCTAssertTrue(app.buttons["build.addElement"].exists)
        XCTAssertTrue(el("build.empty").exists)
        XCTAssertTrue(el("build.search").exists, "Build opens with a search field\(onScreen())")
        XCTAssertFalse(app.buttons["build.lookUp"].exists,
                       "the giant lookup button is gone; identification is automatic")
    }

    /// The search field at the top of Build finds a bundled compound and opens
    /// its page, with no chemistry required.
    func testBuildSearchFindsWaterAndOpensIt() {
        openTab("Build")
        let field = el("build.search")
        waitFor(field)
        field.tap()
        field.typeText("water")

        let result = app.buttons["compoundResult.962"]
        waitFor(result)
        result.tap()
        waitFor(el("compound.hero"))
        XCTAssertTrue(labelContaining("Water").exists)
        goBack()
        // Clearing the field puts the builder back.
        tap(app.buttons["build.searchClear"])
        waitFor(el("build.tray"))
    }

    /// H₂O names itself: no button, no wait, and the name is a record's name.
    func testBuildingWaterIdentifiesItAutomatically() {
        openTab("Build")
        addElement("H")
        tap(app.buttons["build.increment.H"])
        addElement("O")
        XCTAssertTrue(el("build.formula").waitForExistence(timeout: 5))
        XCTAssertTrue(el("build.hints").exists, "Hints are still available, labeled as heuristics")

        // No lookup was tapped, and no lookup button exists to tap.
        XCTAssertFalse(app.buttons["build.lookUp"].exists)
        waitFor(el("build.result"))
        XCTAssertTrue(labelContaining("Water").exists, "H2O should resolve to water\(onScreen())")

        // The result carries a real 2D structure, labeled honestly.
        assertReachable(el("compound2D.view"), "the 2D structure")
        XCTAssertTrue(labelContaining("2D structure for Water").exists,
                      "the drawing should describe itself\(onScreen())")

        // Saving and favoriting are separate, and both stick.
        tap(app.buttons["build.result.save"])
        XCTAssertTrue(app.buttons["build.result.save"].isSelected,
                      "Save should read as on once it is\(onScreen())")
        tap(app.buttons["build.result.favorite"])
        XCTAssertTrue(app.buttons["build.result.favorite"].isSelected)

        tap(app.buttons["build.result.details"])
        waitFor(el("compound.hero"))
        goBack()

        // And the favorite is on Study, under Favorites rather than buried.
        openTab("Study")
        let shelf = el("study.favoriteCompound.962")
        assertReachable(shelf, "the favorited compound on the Study tab")
    }

    /// Counts past thirty are ordinary, and they are typed rather than
    /// tapped up to: cholesterol is C₂₇H₄₆O, and forty-six taps is not an
    /// interface.
    func testCountsPastThirtyAreTypedRatherThanTapped() {
        openTab("Build")
        addElement("C")
        setCount("C", to: "27")
        addElement("H")
        setCount("H", to: "46")
        addElement("O")

        XCTAssertEqual(app.buttons["build.count.C"].label, "27 Carbon",
                       "the typed carbon count did not take\(onScreen())")
        XCTAssertEqual(app.buttons["build.count.H"].label, "46 Hydrogen",
                       "the typed hydrogen count did not take\(onScreen())")

        let formula = el("build.formula")
        waitFor(formula)
        // The subscripted formula, as it is written.
        XCTAssertTrue(formula.label.contains("27") || formula.label.contains("₂₇")
                      || formula.label.contains("2 7"),
                      "the formula should carry the twenty-seven carbons; it reads "
                      + "\(formula.label)\(onScreen())")

        // And the cap is a clamp with a visible answer, not a silent refusal.
        setCount("O", to: "100000")
        XCTAssertEqual(app.buttons["build.count.O"].label, "999 Oxygen",
                       "typing past the cap should land on the cap\(onScreen())")
    }

    /// Types a count into the tray's number field.
    private func setCount(_ symbol: String, to value: String) {
        let count = app.buttons["build.count.\(symbol)"]
        tap(count)
        // The alert's own field, found by being the only one rather than by an
        // identifier. SwiftUI hands an alert's contents to a
        // UIAlertController, which carries a button's accessibility identifier
        // across and drops a text field's: `build.countConfirm` arrives,
        // `build.countField` never did, and the modifier that set it has been
        // removed from the app because it was doing nothing.
        let field = app.alerts.textFields.firstMatch
        waitFor(field)
        field.tap()
        // The field opens with the current count selected for replacement on
        // iOS; clearing it explicitly makes the test independent of that.
        if let existing = field.value as? String, !existing.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        field.typeText(value)
        let confirm = app.alerts.buttons["build.countConfirm"].firstMatch
        waitFor(confirm)
        confirm.tap()
        settle(0.4)
    }

    /// The formula is live: it changes with the tray, before anything is
    /// looked up.
    func testFormulaUpdatesAsTheCompositionChanges() {
        openTab("Build")
        addElement("O")
        let formula = el("build.formula")
        waitFor(formula)
        let single = formula.label
        tap(app.buttons["build.increment.O"])
        let changed = NSPredicate { _, _ in formula.exists && formula.label != single }
        XCTAssertEqual(
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: changed, object: nil)],
                             timeout: 5),
            .completed,
            "adding an atom should change the formula at once\(onScreen())"
        )
    }

    func testBuildingC2H6OOffersAChoiceRatherThanAssumingEthanol() {
        openTab("Build")
        addElement("C")
        tap(app.buttons["build.increment.C"])
        addElement("H")
        for _ in 0..<5 { tap(app.buttons["build.increment.H"]) }
        addElement("O")
        waitFor(el("build.candidates"))
        XCTAssertTrue(labelContaining("2 known compounds share this formula").exists,
                      "an ambiguous formula must say so rather than pick one\(onScreen())")
        XCTAssertFalse(el("build.identity.match").exists,
                       "C2H6O must not be auto-named\(onScreen())")
        XCTAssertTrue(app.buttons["build.candidate.702"].exists, "Ethanol is offered")
        XCTAssertTrue(app.buttons["build.candidate.8254"].exists, "Dimethyl ether is offered")
        tap(app.buttons["build.candidate.8254"])
        waitFor(el("build.result"))
        XCTAssertTrue(labelContaining("Dimethyl ether").exists)
        // An organic molecule is drawn in line-angle notation and called that.
        assertReachable(el("compound2D.label"), "the representation label")
        XCTAssertTrue(labelContaining("Skeletal formula for Dimethyl ether").exists,
                      "an organic molecule gets a skeletal formula\(onScreen())")
    }

    func testUnknownCompositionIsAMissNotADiscovery() {
        openTab("Build")
        addElement("Au", searching: "gold")
        addElement("He")
        waitFor(el("build.noMatch"))
        XCTAssertTrue(labelContaining("No known match found").exists)
        XCTAssertTrue(labelContaining("not evidence of a new chemical discovery").exists)
        tap(app.buttons["build.saveHypothetical"])
        waitFor(el("build.result"))
        XCTAssertTrue(labelContaining("Hypothetical").exists)
        // Nothing is drawn for a composition nobody has recorded, and it is
        // never called a skeletal formula or a formula unit.
        assertReachable(el("compound2D.label"), "the representation label")
        XCTAssertTrue(labelContaining("Composition for").exists,
                      "an unmatched composition gets no structural claim\(onScreen())")
    }

    // MARK: - Quiz setup, Match and My Quizzes

    /// The redesigned setup: four plain questions, large answers, and nothing
    /// advanced on screen until it is asked for.
    func testQuizSetupIsUnderstandableWithoutOpeningAnything() {
        openTab("Study")
        tap(app.buttons["study.mode.quiz"])
        waitFor(el("quizSetup.sheet"))

        // What to study, as three large choices rather than a segmented row.
        for content in ["elements", "compounds", "both"] {
            let card = app.buttons["quizSetup.content.\(content)"]
            XCTAssertTrue(card.waitForExistence(timeout: 6),
                          "the \(content) choice should be on screen\(onScreen())")
            XCTAssertTrue(canTap(card), "the \(content) choice should be tappable\(onScreen())")
        }
        XCTAssertTrue(app.buttons["quizSetup.content.elements"].isSelected,
                      "Elements is the default\(onScreen())")
        tap(app.buttons["quizSetup.content.both"])
        XCTAssertTrue(app.buttons["quizSetup.content.both"].isSelected)

        // Difficulty, count and scope are each a row of real controls.
        for difficulty in ["easy", "medium", "hard", "mixed"] {
            assertReachable(app.buttons["quizSetup.difficulty.\(difficulty)"], difficulty)
        }
        assertReachable(app.buttons["quizSetup.length.10"], "the ten-question choice")
        assertReachable(app.buttons["quizSetup.length.custom"], "the custom length choice")
        for scope in ["all", "favorites", "recentlyMissed", "notMastered", "custom"] {
            assertReachable(app.buttons["quizSetup.scope.\(scope)"], scope)
        }

        // Everything advanced is behind Customize, and stays there until it is
        // opened. The families chips are the tell: eighteen group chips and
        // seven period chips used to be the first thing on this screen.
        XCTAssertFalse(app.buttons["quizSetup.family.alkaliMetal"].exists,
                       "advanced filters must start collapsed\(onScreen())")
        XCTAssertFalse(app.buttons["quizSetup.group.5"].exists)
        assertReachable(el("quizSetup.customize"), "the Customize section")
        assertReachable(el("quizSetup.poolCount"), "the footer that says how big the selection is")

        app.buttons["quizSetup.cancel"].tap()
        XCTAssertTrue(app.navigationBars["Study"].waitForExistence(timeout: 5))
    }

    /// Customize keeps every advanced control the old form had.
    func testQuizSetupCustomizeStillHoldsEveryAdvancedFilter() {
        openTab("Study")
        tap(app.buttons["study.mode.quiz"])
        waitFor(el("quizSetup.sheet"))
        tap(app.buttons["quizSetup.content.both"])
        tap(el("quizSetup.customize"))

        // `ChipGrid` names each chip after the case, not the title.
        for identifier in ["quizSetup.family.alkaliMetal", "quizSetup.phase.gas",
                           "quizSetup.period.3", "quizSetup.group.17",
                           "quizSetup.minimumZ", "quizSetup.maximumZ",
                           "quizSetup.bonding.ionic", "quizSetup.onlySaved",
                           "quizSetup.timer", "quizSetup.shuffle"] {
            assertReachable(el(identifier), identifier)
        }
    }

    /// Match uses the same screen and the same visual language.
    func testMatchSetupUsesTheSameDesign() {
        openTab("Study")
        tap(app.buttons["study.mode.match"])
        waitFor(el("quizSetup.sheet"))
        XCTAssertTrue(app.navigationBars["Create a Match"].exists,
                      "Match should open its own titled setup\(onScreen())")
        assertReachable(app.buttons["quizSetup.content.elements"], "the content choice")
        assertReachable(app.buttons["quizSetup.length.8"], "the eight-pair choice")
        assertReachable(app.buttons["quizSetup.start"], "Start Match")
        app.buttons["quizSetup.cancel"].tap()
    }

    func testMatchRoundPairsUpAndFinishes() {
        openTab("Study")
        tap(app.buttons["study.mode.match"])
        waitFor(el("quizSetup.sheet"))
        tap(app.buttons["quizSetup.start"])
        waitFor(el("match.board"))
        // The board is dealt with pair ids 0..<n; matching each prompt to its
        // own answer finishes the round whatever the shuffled order is.
        for id in 0..<8 {
            let prompt = app.buttons["match.prompt.\(id)"]
            guard prompt.waitForExistence(timeout: 3) else { break }
            tap(prompt)
            tap(app.buttons["match.answer.\(id)"])
        }
        XCTAssertTrue(app.buttons["summary.done"].waitForExistence(timeout: 10),
                      "Matching every pair should end the round\(onScreen())")
        app.buttons["summary.done"].tap()
    }

    func testSavedQuizAppearsUnderMyQuizzes() {
        openTab("Study")
        tap(app.buttons["study.mode.quiz"])
        waitFor(el("quizSetup.sheet"))
        tap(app.buttons["quizSetup.save"])
        // The name prompt is a system alert, whose text field XCUITest vends
        // under the alert rather than under the app's own identifiers.
        let alert = app.alerts.firstMatch
        waitFor(alert)
        let nameField = alert.textFields.firstMatch
        waitFor(nameField)
        nameField.tap()
        nameField.typeText("Halogens")
        // iOS 26 vends the alert's button twice, so the query is not unique.
        alert.buttons["Save"].firstMatch.tap()
        XCTAssertTrue(labelContaining("Halogens").waitForExistence(timeout: 6),
                      "The saved quiz should appear on the Study tab\(onScreen())")
        tap(app.buttons["study.myQuizzes.seeAll"])
        waitFor(app.navigationBars["My Quizzes"])
        XCTAssertTrue(el("myQuizzes.list").exists)
        XCTAssertTrue(labelContaining("Halogens").exists)

        // There is no importer, no file picker and no JSON anywhere in here.
        XCTAssertFalse(app.buttons["myQuizzes.import"].exists,
                       "the quiz-file importer has been removed\(onScreen())")
        XCTAssertFalse(labelContaining("Import a quiz file").exists)
        XCTAssertFalse(labelContaining(".elemoraquiz").exists)
        XCTAssertFalse(labelContaining(".json").exists)
        XCTAssertTrue(app.buttons["myQuizzes.new"].exists,
                      "New quiz is now a plain button rather than a menu")
    }

    // MARK: - Study layout details

    /// Every practice tile is the same size, and the tiles sharing a row start
    /// on the same line.
    ///
    /// The test used to require one line for all five, which the Study tab has
    /// never drawn and does not claim to: `StudyScreen` lays the modes out
    /// three across at normal text sizes and two at accessibility sizes, so
    /// five modes make a row of three and a row of two. Asserting one row read
    /// as a layout bug and was a test bug.
    ///
    /// What the layout does promise is the thing `PracticeModeTile` was
    /// rebuilt to keep: a two-line label like "Smart Review" never makes its
    /// tile taller than "Quiz", and never lifts its colored square above its
    /// neighbors'. That is one size for every tile, and one baseline within a
    /// row — which is what this now measures, without assuming how many rows
    /// there are.
    func testPracticeTilesShareOneSizeAndLineUpInTheirRows() {
        openTab("Study")
        let modes = ["flashcards", "quiz", "match", "identify", "smartReview"]
        // Bring the whole grid on screen first, then measure it in one go.
        assertReachable(app.buttons["study.mode.smartReview"], "the Smart Review tile")
        settle(0.5)

        let frames = modes.map { app.buttons["study.mode.\($0)"].frame }
        for (index, frame) in frames.enumerated() {
            XCTAssertFalse(frame.isNull || frame.isEmpty,
                           "the \(modes[index]) tile has no frame\(onScreen())")
        }
        guard let first = frames.first else { return }
        for (index, frame) in frames.enumerated() {
            XCTAssertEqual(frame.height, first.height, accuracy: 1.0,
                           "the \(modes[index]) tile is a different height")
            XCTAssertEqual(frame.width, first.width, accuracy: 1.0,
                           "the \(modes[index]) tile is a different width")
        }

        // Rows are found rather than assumed, because the column count moves
        // with Dynamic Type. Two tiles belong to the same row when their tops
        // are within half a tile of each other, which cannot merge two rows:
        // a row sits a whole tile plus the grid's spacing below the one above
        // it. The assertion inside a row is then the strict one, to the point.
        var rows: [[(name: String, frame: CGRect)]] = []
        for (index, frame) in frames.enumerated() {
            let tile = (name: modes[index], frame: frame)
            if let slot = rows.firstIndex(where: {
                abs($0[0].frame.minY - frame.minY) < first.height / 2
            }) {
                rows[slot].append(tile)
            } else {
                rows.append([tile])
            }
        }
        for row in rows {
            guard let head = row.first else { continue }
            for tile in row {
                XCTAssertEqual(tile.frame.minY, head.frame.minY, accuracy: 1.0,
                               "the \(tile.name) tile does not start on the same line "
                               + "as the \(head.name) tile beside it")
            }
            let names = row.map { $0.name }.joined(separator: ", ")
            XCTAssertLessThanOrEqual(row.count, 3,
                                     "the practice grid is at most three across; this row "
                                     + "holds \(names)")
        }

        XCTAssertTrue(app.buttons["study.mode.smartReview"].label.contains("Elemora Pro"),
                      "Smart Review is still marked as a Pro feature")
    }
}
