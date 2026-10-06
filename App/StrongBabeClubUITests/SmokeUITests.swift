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

/// Round-2 fixes, exercised end to end on a fresh (empty) install.
final class RoundTwoUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-sbc-empty"] + extra
        app.launch()
        return app
    }

    /// Typing a weight and leaving the field checks the set off and starts
    /// the clock; tapping the check unchecks it; the chart then shows the lift.
    func testAutoCheckAndProgressUsesAppLoggedSets() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["new!"].waitForExistence(timeout: 15), "empty 30-day state")

        // Progress: no front squat data yet.
        app.tabBars.buttons["Progress"].tap()
        app.buttons["chip-front_squat"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'No front squat'")).firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Today"].tap()

        app.buttons["startWorkout"].tap()
        app.buttons["nextSection"].tap() // strength

        let w1 = app.textFields["weight-A-1"]
        XCTAssertTrue(w1.waitForExistence(timeout: 5))
        w1.tap()
        w1.typeText("65")
        app.textFields["weight-A-2"].tap() // focus leaves set 1
        XCTAssertTrue(app.staticTexts["logged-A-1"].waitForExistence(timeout: 5), "set 1 auto-checked")
        XCTAssertEqual(app.staticTexts["logged-A-1"].label, "65")
        XCTAssertTrue(app.buttons["Pause timer"].waitForExistence(timeout: 3), "next-set timer started")

        app.textFields["weight-A-2"].typeText("75")
        app.toolbars.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["logged-A-2"].waitForExistence(timeout: 5), "Done auto-checks too")

        // Tap-to-uncheck still works.
        app.buttons["set-A-2"].tap()
        XCTAssertTrue(app.textFields["weight-A-2"].waitForExistence(timeout: 5))
        app.buttons["set-A-2"].tap()
        XCTAssertTrue(app.staticTexts["logged-A-2"].waitForExistence(timeout: 5))

        app.buttons["finishWorkout"].tap()
        let stick = app.buttons["stickInJournal"]
        XCTAssertTrue(stick.waitForExistence(timeout: 5))
        stick.tap()
        XCTAssertTrue(app.staticTexts["done for today!"].waitForExistence(timeout: 10))

        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.buttons["chip-front_squat"].waitForExistence(timeout: 5))
        app.buttons["chip-front_squat"].tap()
        let empty = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'No front squat'")).firstMatch
        XCTAssertFalse(empty.waitForExistence(timeout: 2), "chart now has the app-logged front squat")
    }

    /// Tabata: one log row per prescribed round (8 per move x 2 moves = 16).
    func testTabataHasSixteenLogRows() {
        let app = launch(["-sbc-open", "session", "-sbc-section", "metabolic", "-sbc-metabolic", "tabata"])
        XCTAssertTrue(app.staticTexts["roundOfTotal"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["roundOfTotal"].label, "round 1 of 16")
        let last = app.descendants(matching: .any)["logRow-16"]
        for _ in 0..<8 where !last.exists { app.swipeUp() }
        XCTAssertTrue(last.exists)
        XCTAssertFalse(app.descendants(matching: .any)["logRow-17"].exists)
    }

    /// Range chips and the year toggle switch the chart and remember nothing
    /// outside test mode (test mode has its own preferences).
    func testProgressRangeChipsAndYearToggle() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-sbc-tab", "progress"]
        app.launch()
        let timeline = app.descendants(matching: .any)["chart-timeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["range-3M"].isSelected, "3M is the default")

        for r in ["1Y", "All", "6M"] {
            app.buttons["range-\(r)"].tap()
            XCTAssertTrue(app.buttons["range-\(r)"].isSelected, r)
            XCTAssertTrue(timeline.waitForExistence(timeout: 3))
            XCTAssertTrue(timeline.label.contains("\(r) view"), timeline.label)
        }

        app.buttons["yearToggle"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["chart-years"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["legend-2026"].exists)
        XCTAssertFalse(app.buttons["range-6M"].isSelected, "range chips step back in year mode")

        app.buttons["range-3M"].tap()
        XCTAssertTrue(timeline.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["yearToggle"].isSelected)
    }
}
