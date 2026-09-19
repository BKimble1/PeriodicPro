import XCTest

/// What happens to a learner who is sent a quiz.
///
/// The link itself is a Universal Link, and XCUITest cannot hand one to the app
/// without driving Safari — which is slow, flaky, and tests Safari rather than
/// Elemora. So the link is passed in with `-incomingQuizLink` and `RootView`
/// routes it through exactly the handler `onOpenURL` uses. What is under test
/// here is everything after the tap: the decode, the save, the confirmation,
/// and the two things it offers to do next.
///
/// Whether iOS hands the app the link in the first place is a property of the
/// signed build's Associated Domains entitlement and of the
/// apple-app-site-association file on elemora.idlery.com. That cannot be
/// asserted from a simulator and has to be checked on a real device against
/// the deployed site.
final class SharedQuizLinkUITests: XCTestCase {
    private var app: XCUIApplication!

    /// The quiz name the app builds a real link for. Anything that is not an
    /// https URL is read as a name; see `RuntimeFlags.incomingQuizLink`.
    private let sharedName = "Shared sample"

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    private func launch(link: String, pro: Bool = false) {
        app.launchArguments = ["-uiTesting", "-compoundNetworkStub"]
            + (pro ? ["-proEntitled"] : [])
            + ["-incomingQuizLink", link]
        app.launch()
    }

    private func el(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func waitFor(_ element: XCUIElement,
                         _ timeout: TimeInterval = 12,
                         file: StaticString = #filePath,
                         line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      "Timed out waiting for \(element)", file: file, line: line)
    }

    /// Every piece of text currently on screen, joined — used to prove that
    /// something is *absent*, which is most of what a recipient must never be
    /// shown. `descendants` is already the whole tree, so there is no walk.
    private func visibleText() -> String {
        let texts = app.descendants(matching: .staticText).allElementsBoundByIndex
        let buttons = app.descendants(matching: .button).allElementsBoundByIndex
        return (texts + buttons).map(\.label).filter { !$0.isEmpty }.joined(separator: " | ")
    }

    // MARK: - The quiz arrives

    func testAColdLaunchFromASharedLinkSavesTheQuizAndSaysSo() {
        launch(link: sharedName)

        waitFor(el("sharedQuiz.screen"))
        XCTAssertEqual(el("sharedQuiz.title").label, "Quiz saved",
                       "the recipient is told the quiz was saved, in those words")
        XCTAssertEqual(el("sharedQuiz.name").label, sharedName,
                       "and is shown the quiz's own title")
        XCTAssertTrue(el("sharedQuiz.start").exists, "Start Quiz is offered")
        XCTAssertTrue(el("sharedQuiz.viewAll").exists, "View in My Quizzes is offered")
    }

    func testTheRecipientIsNeverShownThePayloadOrAnythingTechnical() {
        launch(link: sharedName)
        waitFor(el("sharedQuiz.screen"))

        let text = visibleText()
        for jargon in ["http", "base64", "JSON", "payload", "decode", "schema", "import file"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(jargon),
                           "the confirmation shows \(jargon), which means nothing to a learner")
        }
        // The one summary line it does show is the quiz's configuration, in
        // words: "5 questions · Both · Medium · Custom selection".
        XCTAssertTrue(text.contains("questions"),
                      "the confirmation summarizes what the quiz contains")
    }

    func testStartQuizFromTheConfirmationDealsARound() {
        launch(link: sharedName, pro: true)
        waitFor(el("sharedQuiz.screen"))

        el("sharedQuiz.start").tap()
        waitFor(el("quiz.prompt"), 20)
        XCTAssertTrue(el("quiz.option.0").waitForExistence(timeout: 10),
                      "an imported quiz deals real questions")
    }

    func testViewInMyQuizzesShowsTheImportedQuiz() {
        launch(link: sharedName)
        waitFor(el("sharedQuiz.screen"))

        el("sharedQuiz.viewAll").tap()
        waitFor(el("myQuizzes.list"), 20)
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS[c] %@", sharedName))
                .firstMatch.waitForExistence(timeout: 10),
            "the quiz that arrived is in My Quizzes"
        )
    }

    func testDismissingTheConfirmationLeavesTheQuizSaved() {
        launch(link: sharedName)
        waitFor(el("sharedQuiz.screen"))

        el("sharedQuiz.done").tap()
        XCTAssertTrue(el("study.greeting").waitForExistence(timeout: 10),
                      "dismissing lands on the Study tab, where the quiz now lives")
        XCTAssertFalse(el("sharedQuiz.screen").exists, "and the confirmation is gone")
    }

    // MARK: - The quiz does not arrive

    func testAMalformedLinkIsRefusedInPlainWords() {
        launch(link: "https://elemora.idlery.com/quiz/1zzzzzzzz")

        waitFor(el("sharedQuiz.failed"))
        let text = visibleText()
        XCTAssertTrue(text.localizedCaseInsensitiveContains("could not be opened"),
                      "the refusal is a sentence, not an error code")
        for jargon in ["base64", "JSON", "zlib", "Error Domain", "NSError"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(jargon),
                           "the refusal leaks \(jargon)")
        }
    }

    func testAQuizFromANewerElemoraSaysToUpdate() {
        // A format version this build does not know. The marker is the first
        // character of the payload, so this is all it takes.
        launch(link: "https://elemora.idlery.com/quiz/9abcdefgh")

        waitFor(el("sharedQuiz.failed"))
        XCTAssertTrue(visibleText().localizedCaseInsensitiveContains("update the app"),
                      "a newer format tells the recipient what to do about it")
    }

    func testALinkThatIsNotAQuizIsLeftAlone() {
        // The privacy policy is an ordinary page on the same domain. It must
        // not be claimed by the app, and it must not produce a confirmation.
        launch(link: "https://elemora.idlery.com/privacy")

        waitFor(el("root.tabView"))
        XCTAssertFalse(el("sharedQuiz.screen").waitForExistence(timeout: 3),
                       "a link that is not a quiz shows nothing")
        XCTAssertFalse(el("sharedQuiz.failed").exists,
                       "and is not reported as a broken quiz either")
    }
}
