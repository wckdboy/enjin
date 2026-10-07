import XCTest

/// Plan §8 smoke flow, on a fresh store each run (`-uiTestingFreshStore`).
@MainActor
final class SmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestingFreshStore", "-uiTestingFakeAgent", "-seedSample"]
        app.launch()
    }

    func testOpenNotebookAddCardAndUseMap() {
        let demo = app.buttons["notebook:Electric motors"].firstMatch
        XCTAssertTrue(demo.waitForExistence(timeout: 10), "demo notebook is seeded")
        demo.tap()

        // Canvas is up once the New card button is enabled (status == .ready).
        let newCard = app.buttons["New card"]
        XCTAssertTrue(newCard.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: newCard)
        waitForExpectations(timeout: 15)

        newCard.tap()
        let title = app.textFields["cardTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Stepper motors")
        app.buttons["Add"].tap()

        // The map lists every portal; the root has the new card counted.
        app.buttons["Map"].tap()
        let rootRow = app.buttons["map:Electric motors"]
        XCTAssertTrue(rootRow.waitForExistence(timeout: 5))
        XCTAssertEqual(rootRow.value as? String, "6 cards", "root portal now has 6 cards")
        XCTAssertTrue(app.buttons["map:The ESC: the motor's conductor"].exists, "map is fully expanded down to depth 3")
        app.buttons["map:How a motor spins"].tap()
        XCTAssertTrue(app.buttons["crumb:Electric motors"].waitForExistence(timeout: 5), "breadcrumb shows the path")
        XCTAssertTrue(app.staticTexts["How a motor spins"].exists, "current portal is named")
        XCTAssertFalse(app.buttons["crumb:How a motor spins"].exists, "current crumb is not a button")

        // Back to the library and in again: the card survived (persisted).
        app.buttons["Notebooks"].tap()
        let cover = app.buttons["notebook:Electric motors"].firstMatch
        XCTAssertTrue(cover.waitForExistence(timeout: 10))
        cover.tap()
        XCTAssertTrue(app.buttons["Map"].waitForExistence(timeout: 10))
        app.buttons["Map"].tap()
        let again = app.buttons["map:Electric motors"]
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        XCTAssertEqual(again.value as? String, "6 cards", "new card persisted across reopen")
    }

    /// Nothing is pre-built: a fresh install has no notebooks, and exploring a topic makes Enjin generate one.
    func testExploringATopicGeneratesItsNotebook() {
        app.terminate()
        app.launchArguments = ["-uiTestingFreshStore", "-uiTestingFakeAgent"]
        app.launch()
        let topic = app.textFields["topicField"]
        XCTAssertTrue(topic.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Nothing here yet"].exists, "no pre-built notebooks")
        app.buttons["Expert"].tap()
        topic.tap()
        topic.typeText("Quantum computers")
        app.buttons["explore"].tap()
        XCTAssertTrue(app.staticTexts["Here are two cards from the test agent."].waitForExistence(timeout: 15), "Enjin opens the topic itself")
        snap("generated-notebook")
        app.buttons["Map"].tap()
        let root = app.buttons["map:Quantum computers"]
        XCTAssertTrue(root.waitForExistence(timeout: 5))
        XCTAssertEqual(root.value as? String, "2 cards", "the cards were generated, not seeded")
    }

    private func snap(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// Enjin as a partner: it asks with tappable answers, hears the answer, and keeps notes in User.md.
    func testEnjinAsksAndRemembersHowYouLearn() {
        app.buttons["notebook:Electric motors"].firstMatch.tap()
        let ask = app.textFields["askField"]
        XCTAssertTrue(ask.waitForExistence(timeout: 15))
        ask.tap()
        ask.typeText("quiz me\n")
        let answer = app.buttons["answer:Fewer turns"]
        XCTAssertTrue(answer.waitForExistence(timeout: 10), "Enjin's question comes with answers to tap")
        XCTAssertTrue(app.staticTexts["Which spins faster: more turns of wire, or fewer?"].exists)
        snap("enjin-asks")
        answer.tap()
        XCTAssertTrue(app.staticTexts["Yes: fewer turns, less back-EMF, more speed."].waitForExistence(timeout: 10), "the answer goes back to Enjin")
        XCTAssertFalse(app.buttons["answer:Fewer turns"].exists, "the question is gone once answered")

        app.buttons["Settings"].tap()
        let profile = app.buttons["learnerProfile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        profile.tap()
        let md = app.textViews["learnerMarkdown"]
        XCTAssertTrue(md.waitForExistence(timeout: 5))
        XCTAssertTrue((md.value as? String)?.contains("Likes being quizzed before the answer") == true, "User.md has what Enjin learned")
        snap("user-md")
    }

    func testAskTheAgentThenUndo() {
        app.buttons["notebook:Electric motors"].firstMatch.tap()
        let ask = app.textFields["askField"]
        XCTAssertTrue(ask.waitForExistence(timeout: 15), "agent dock appears once the canvas is ready")
        ask.tap()
        ask.typeText("what did they eat?\n")

        XCTAssertTrue(app.staticTexts["Here are two cards from the test agent."].waitForExistence(timeout: 10))
        sleep(1) // let the picture land
        snap("after-agent-turn")
        app.buttons["Map"].tap()
        let root = app.buttons["map:Electric motors"]
        XCTAssertTrue(root.waitForExistence(timeout: 5))
        XCTAssertEqual(root.value as? String, "7 cards", "agent added two cards")
        app.buttons["Done"].tap()

        let undo = app.buttons["Undo Enjin's last change"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        snap("after-undo")
        XCTAssertTrue(app.staticTexts["Here are two cards from the test agent."].waitForNonExistence(timeout: 5), "undo clears the reply")
        app.buttons["Map"].tap()
        snap("map-after-undo")
        XCTAssertTrue(root.waitForExistence(timeout: 5))
        XCTAssertEqual(root.value as? String, "5 cards", "undo removed them")
    }
}
