import XCTest

/// Plan §8 smoke flow, on a fresh store each run (`-uiTestingFreshStore`).
@MainActor
final class SmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestingFreshStore"]
        app.launch()
    }

    func testOpenNotebookAddCardAndUseMap() {
        let demo = app.staticTexts["Roman Empire"].firstMatch
        XCTAssertTrue(demo.waitForExistence(timeout: 10), "demo notebook is seeded")
        demo.tap()

        // Canvas is up once the New card button is enabled (status == .ready).
        let newCard = app.buttons["New card"]
        XCTAssertTrue(newCard.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: newCard)
        waitForExpectations(timeout: 15)

        newCard.tap()
        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Aqueducts")
        app.buttons["Add"].tap()

        // The map lists every portal; the root has the new card counted.
        app.buttons["Map"].tap()
        let rootRow = app.buttons["map:Roman Empire"]
        XCTAssertTrue(rootRow.waitForExistence(timeout: 5))
        XCTAssertEqual(rootRow.value as? String, "5 cards", "root portal now has 5 cards")
        XCTAssertTrue(app.buttons["map:Logistics"].exists, "map is fully expanded down to depth 3")
        app.buttons["map:Legions"].tap()
        XCTAssertTrue(app.buttons["Roman Empire"].waitForExistence(timeout: 5), "breadcrumb shows the path")
        XCTAssertFalse(app.buttons["Legions"].isEnabled, "current crumb is not tappable")

        // Back to the library and in again: the card survived (persisted).
        app.buttons["Notebooks"].tap()
        app.staticTexts["Roman Empire"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Map"].waitForExistence(timeout: 10))
        app.buttons["Map"].tap()
        let again = app.buttons["map:Roman Empire"]
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        XCTAssertEqual(again.value as? String, "5 cards", "new card persisted across reopen")
    }
}
