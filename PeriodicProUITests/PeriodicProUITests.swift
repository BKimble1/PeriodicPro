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
        app = XCUIApplication()
        // Skips onboarding, uses an in-memory store and silences haptics.
        app.launchArguments = ["-uiTesting"]
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

    private func waitFor(_ element: XCUIElement,
                         _ timeout: TimeInterval = 10,
                         file: StaticString = #filePath,
                         line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      "Timed out waiting for \(element)", file: file, line: line)
    }

    private func openTab(_ name: String) {
        let tab = app.tabBars.buttons[name]
        waitFor(tab)
        tab.tap()
    }

    private func openElement(_ symbol: String) {
        let tile = app.buttons["element.\(symbol)"]
        waitFor(tile)
        tile.tap()
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
        XCTAssertTrue(app.buttons["element.H"].exists, "Hydrogen tile should be on screen")
        XCTAssertTrue(app.buttons["element.Og"].exists, "Oganesson tile should be on screen")
        XCTAssertTrue(app.tabBars.buttons["Table"].exists)
        XCTAssertTrue(app.tabBars.buttons["Study"].exists)
        XCTAssertTrue(app.tabBars.buttons["Progress"].exists)
    }

    func testAllOneHundredAndEighteenTilesAreReachable() {
        waitFor(app.buttons["element.H"])
        // Spot-check one element from every row of the table, including both
        // detached f-block rows.
        for symbol in ["H", "He", "Li", "Na", "K", "Rb", "Cs", "Fr", "La", "Lu", "Ac", "Lr", "Og"] {
            XCTAssertTrue(app.buttons["element.\(symbol)"].exists, "\(symbol) tile is missing")
        }
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
        let disclosure = app.buttons["detail.moreProperties"]
        waitFor(disclosure)
        disclosure.tap()
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

        // Unfavouriting removes it again.
        app.buttons["study.favorite.Au"].tap()
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
        XCTAssertTrue(el("search.emptyState").waitForExistence(timeout: 6),
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

        let row = app.buttons["filterSheet.nobleGas"]
        waitFor(row)
        row.tap()
        app.buttons["filterSheet.done"].tap()

        XCTAssertTrue(app.buttons["element.He"].waitForExistence(timeout: 5))
    }

    // MARK: - Study

    func testFlashcardRoundRevealsAndAdvances() {
        openTab("Study")
        let mode = app.buttons["study.mode.flashcards"]
        waitFor(mode)
        mode.tap()

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
        app.buttons["study.mode.flashcards"].tap()

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
        let mode = app.buttons["study.mode.quiz"]
        waitFor(mode)
        mode.tap()

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
        let mode = app.buttons["study.mode.identify"]
        waitFor(mode)
        mode.tap()

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
        app.buttons["study.mode.flashcards"].tap()
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
}
