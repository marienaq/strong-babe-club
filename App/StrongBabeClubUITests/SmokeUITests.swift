import XCTest

/// Snapshot-free smoke test: launches with in-memory sample data and walks
/// Today -> workout -> finish -> journal -> progress -> settings.
final class SmokeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testMainFlow() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        let start = app.buttons["startWorkout"]
        XCTAssertTrue(start.waitForExistence(timeout: 15), "Let's lift! button")
        XCTAssertTrue(app.staticTexts["Hey, friend"].exists)

        // Why this? sheet opens and closes.
        app.buttons["whyThis"].tap()
        XCTAssertTrue(app.staticTexts["why this workout?"].waitForExistence(timeout: 5))
        app.buttons["shuffleAll"].tap()
        app.buttons["done"].tap()

        start.tap()
        let next = app.buttons["nextSection"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap() // strength
        let firstSet = app.buttons["set-A-1"]
        XCTAssertTrue(firstSet.waitForExistence(timeout: 5))
        firstSet.tap()
        app.buttons["finishWorkout"].tap()

        let stick = app.buttons["stickInJournal"]
        XCTAssertTrue(stick.waitForExistence(timeout: 5))
        stick.tap()

        XCTAssertTrue(app.staticTexts["done for today!"].waitForExistence(timeout: 10))

        app.tabBars.buttons["Journal"].tap()
        XCTAssertTrue(app.staticTexts["my journal"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["progress"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }
}
