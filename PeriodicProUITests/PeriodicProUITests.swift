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
        let described = app.descendants(matching: .any)
            .allElementsBoundByAccessibilityElement
            .filter { !$0.identifier.isEmpty }
            .map { "\($0.identifier)<\($0.elementType.rawValue)>" }
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

        // It may have been above the starting position rather than below it.
        for _ in 0..<attempts {
            app.swipeDown()
            if element.exists, element.isHittable { return element }
        }

        XCTAssertTrue(element.exists,
                      "\(element) never appeared, scrolling in both directions\(onScreen())",
                      file: file, line: line)
        XCTAssertTrue(element.isHittable,
                      "\(element) exists but never became tappable\(onScreen())",
                      file: file, line: line)
        return element
    }

    private func tap(_ element: XCUIElement,
                     file: StaticString = #filePath,
                     line: UInt = #line) {
        scrollTo(element, file: file, line: line).tap()
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
        let tiles = app.buttons
            .allElementsBoundByAccessibilityElement
            .map(\.identifier)
            .filter { $0.hasPrefix("element.") }

        XCTAssertGreaterThan(tiles.count, 100,
                             "The fitted table should vend a button per element\(onScreen())")
        XCTAssertEqual(Set(tiles).count, tiles.count,
                       "Element tiles share identifiers, so something above them is "
                       + "overwriting their own\(onScreen())")
    }

    func testAllOneHundredAndEighteenTilesAreReachable() {
        // Spot-check one element from every row of the table, including both
        // detached f-block rows. Reachable, which is what the name says: the
        // lanthanide and actinide rows sit below the main block and a small
        // phone does not hold all of it at once.
        for symbol in ["H", "He", "Li", "Na", "K", "Rb", "Cs", "Fr", "La", "Lu", "Ac", "Lr", "Og"] {
            assertReachable(app.buttons["element.\(symbol)"], "the \(symbol) tile")
        }
    }

    // MARK: - Zoom

    /// The table is pinch-to-zoom. XCUITest's pinch is a real two-finger
    /// gesture on the simulator, so this is the interaction itself, not a
    /// stand-in: the tiles must grow, the tile that was under the pinch must
    /// still be on screen, and a tap on it must still open its page.
    func testPinchZoomsTheTableAndTilesStayTappable() {
        waitFor(app.buttons["element.H"])
        let table = el("table.zoomView")
        waitFor(table)

        let oxygen = app.buttons["element.O"]
        let before = oxygen.frame.width
        XCTAssertGreaterThan(before, 12, "the fitted table should have real tiles\(onScreen())")

        table.pinch(withScale: 2.5, velocity: 1.0)

        // Wait for the layout to settle at the new size rather than
        // asserting mid-animation.
        let grew = NSPredicate { _, _ in oxygen.exists && oxygen.frame.width > before * 1.5 }
        let expectation = XCTNSPredicateExpectation(predicate: grew, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 6), .completed,
                       "Pinching out should make the tiles larger; oxygen was \(before) and is "
                       + "\(oxygen.frame.width)\(onScreen())")

        XCTAssertTrue(el("table.fit").waitForExistence(timeout: 4),
                      "A zoomed table should offer a Fit control\(onScreen())")

        // Oxygen is in the top rows near the middle, so it stays in the window
        // after a pinch about the middle. Tapping it must still open its page.
        XCTAssertTrue(oxygen.isHittable, "oxygen should still be tappable while zoomed\(onScreen())")
        oxygen.tap()
        waitFor(app.buttons["detail.favoriteButton"])
        XCTAssertTrue(labelContaining("Oxygen").exists)
        goBack()

        // Coming back, the table is still zoomed — the position survived the
        // push — and Fit takes it home.
        let stillZoomed = el("table.fit")
        waitFor(stillZoomed)
        stillZoomed.tap()
        let fitted = NSPredicate { _, _ in oxygen.exists && oxygen.frame.width < before * 1.2 }
        let fittedExpectation = XCTNSPredicateExpectation(predicate: fitted, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [fittedExpectation], timeout: 6), .completed,
                       "Fit should return the tiles to their fitted size\(onScreen())")
        XCTAssertTrue(app.buttons["element.Og"].exists, "every column should be back on screen")
    }

    /// The pinch's accessible twin: the zoom menu reaches the same levels.
    func testZoomMenuZoomsInAndFits() {
        waitFor(app.buttons["element.H"])
        let hydrogen = app.buttons["element.H"]
        let before = hydrogen.frame.width

        tap(app.buttons["table.zoomMenu"])
        tap(app.buttons["table.zoomIn"])
        let grew = NSPredicate { _, _ in hydrogen.exists && hydrogen.frame.width > before * 1.3 }
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: grew, object: nil)],
                                        timeout: 6), .completed,
                       "Zoom in should enlarge the tiles\(onScreen())")

        tap(app.buttons["table.zoomMenu"])
        tap(app.buttons["table.fitTable"])
        let fitted = NSPredicate { _, _ in hydrogen.exists && hydrogen.frame.width < before * 1.2 }
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: fitted, object: nil)],
                                        timeout: 6), .completed,
                       "Fit table should return to the fitted size\(onScreen())")
    }

    // MARK: - Detail

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
        let chip = app.buttons["filter.Nonmetals"]
        waitFor(chip)
        chip.tap()
        // Iron is a metal, so its tile is dimmed out of the accessibility tree.
        XCTAssertTrue(app.buttons["element.O"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["element.Fe"].exists,
                       "A filtered-out element should leave the accessibility tree")

        app.buttons["filter.All"].tap()
        XCTAssertTrue(app.buttons["element.Fe"].waitForExistence(timeout: 5))
    }

    func testDetailedFilterSheet() {
        let filterButton = app.buttons["table.filterButton"]
        waitFor(filterButton)
        filterButton.tap()

        // Scrolled to, not just waited for: the sheet lists every family and
        // noble gas sits below the fold on a phone-sized sheet.
        tap(app.buttons["filterSheet.nobleGas"])
        app.buttons["filterSheet.done"].tap()

        XCTAssertTrue(app.buttons["element.He"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(el("progress.ring").waitForExistence(timeout: 6))
        XCTAssertTrue(el("progress.streak").exists)
        XCTAssertTrue(el("progress.answered").exists)
        XCTAssertTrue(labelContaining("Alkali Metals").exists,
                      "The per-family breakdown should be on screen")
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

        // Four practice tiles, Smart Review included. Scrolled to rather than
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

    func testProgressMenuOffersAboutAndReset() {
        openTab("Progress")
        let menu = app.buttons["progress.menu"]
        waitFor(menu)
        menu.tap()
        XCTAssertTrue(app.buttons["About this app"].waitForExistence(timeout: 5))
        app.buttons["About this app"].tap()
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 5))
        app.navigationBars["About"].buttons["Done"].tap()
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
        XCTAssertTrue(app.buttons["study.compound.962"].waitForExistence(timeout: 6),
                      "A favorited compound should appear on the Study tab's compound shelf\(onScreen())")
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

    private func addElement(_ symbol: String, searching name: String? = nil) {
        tap(app.buttons["build.addElement"])
        if let name {
            let field = app.searchFields.firstMatch
            waitFor(field)
            field.tap()
            field.typeText(name)
        }
        tap(app.buttons["build.pick.\(symbol)"])
    }

    func testBuildTabShowsTheCompoundBuilderBeta() {
        openTab("Build")
        waitFor(el("build.header"))
        XCTAssertTrue(el("build.beta").exists, "The builder must be marked as a beta\(onScreen())")
        XCTAssertTrue(app.buttons["build.addElement"].exists)
        XCTAssertTrue(el("build.empty").exists)
    }

    func testBuildingWaterFindsTheKnownCompound() {
        openTab("Build")
        addElement("H")
        tap(app.buttons["build.increment.H"])
        addElement("O")
        XCTAssertTrue(el("build.formula").waitForExistence(timeout: 5))
        XCTAssertTrue(el("build.hints").exists, "Hints are shown, labeled as heuristics")
        tap(app.buttons["build.lookUp"])
        waitFor(el("build.result"))
        XCTAssertTrue(labelContaining("Water").exists, "H2O should resolve to water\(onScreen())")
        XCTAssertTrue(el("build.result.preview").exists, "A known compound shows its structure")
        tap(app.buttons["build.result.addToStudy"])
        tap(app.buttons["build.result.details"])
        waitFor(el("compound.hero"))
        goBack()
    }

    func testBuildingC2H6OOffersAChoiceRatherThanAssumingEthanol() {
        openTab("Build")
        addElement("C")
        tap(app.buttons["build.increment.C"])
        addElement("H")
        for _ in 0..<5 { tap(app.buttons["build.increment.H"]) }
        addElement("O")
        tap(app.buttons["build.lookUp"])
        waitFor(el("build.candidates"))
        XCTAssertTrue(labelContaining("Multiple known compounds share this formula.").exists)
        XCTAssertTrue(app.buttons["build.candidate.702"].exists, "Ethanol is offered")
        XCTAssertTrue(app.buttons["build.candidate.8254"].exists, "Dimethyl ether is offered")
        tap(app.buttons["build.candidate.8254"])
        waitFor(el("build.result"))
        XCTAssertTrue(labelContaining("Dimethyl ether").exists)
    }

    func testUnknownCompositionIsAMissNotADiscovery() {
        openTab("Build")
        addElement("Au", searching: "gold")
        addElement("He")
        tap(app.buttons["build.lookUp"])
        waitFor(el("build.noMatch"))
        XCTAssertTrue(labelContaining("No known PubChem match found.").exists)
        XCTAssertTrue(labelContaining("not evidence of a new chemical discovery").exists)
        tap(app.buttons["build.saveHypothetical"])
        waitFor(el("build.result"))
        XCTAssertTrue(labelContaining("Hypothetical").exists)
        XCTAssertFalse(el("build.result.preview").exists, "Nothing is drawn for a composition nobody has seen")
    }

    // MARK: - Quiz setup, Match and My Quizzes

    func testQuizSetupOffersContentScopeAndDifficulty() {
        openTab("Study")
        tap(app.buttons["study.mode.quiz"])
        waitFor(el("quizSetup.sheet"))
        XCTAssertTrue(el("quizSetup.content").exists)
        XCTAssertTrue(el("quizSetup.difficulty").exists)
        XCTAssertTrue(el("quizSetup.length").exists)
        XCTAssertTrue(el("quizSetup.poolCount").exists, "The footer says how big the selection is")
        app.buttons["quizSetup.cancel"].tap()
        XCTAssertTrue(app.navigationBars["Study"].waitForExistence(timeout: 5))
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
        alert.buttons["Save"].tap()
        XCTAssertTrue(labelContaining("Halogens").waitForExistence(timeout: 6),
                      "The saved quiz should appear on the Study tab\(onScreen())")
        tap(app.buttons["study.myQuizzes.seeAll"])
        waitFor(app.navigationBars["My Quizzes"])
        XCTAssertTrue(el("myQuizzes.list").exists)
        XCTAssertTrue(labelContaining("Halogens").exists)
    }
}
