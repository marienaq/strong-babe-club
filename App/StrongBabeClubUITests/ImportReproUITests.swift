import XCTest

/// Opt-in, manual reproduction of "import through Settings" with a real file
/// the developer placed in the simulator's Files ("On My iPhone/history.json").
/// Uses the app's REAL on-disk store, so it is skipped unless the test runner
/// gets SBC_REPRO=1 (xcodebuild: TEST_RUNNER_SBC_REPRO=1). Never run it on a
/// simulator someone is using by hand.
final class ImportReproUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SBC_REPRO"] == "1", "manual repro only")
    }

    func testImportThroughFilesPicker() throws {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        let importButton = app.buttons["Import history or backup (JSON)…"]
        for _ in 0..<10 where !importButton.isHittable { app.swipeUp() }
        importButton.tap()

        // Document picker: find history.json (Recents or On My iPhone).
        let file = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'history'")).firstMatch
        if !file.waitForExistence(timeout: 8) {
            if app.buttons["Browse"].exists { app.buttons["Browse"].tap() }
            let onPhone = app.descendants(matching: .any)["On My iPhone"]
            if onPhone.waitForExistence(timeout: 5) { onPhone.tap() }
        }
        XCTAssertTrue(file.waitForExistence(timeout: 10), app.debugDescription)
        file.tap()
        if app.buttons["Open"].waitForExistence(timeout: 2) { app.buttons["Open"].tap() }

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 60))
        let summary = alert.label + " " + alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | ")
        print("IMPORT-SUMMARY: \(summary)")
        alert.buttons.firstMatch.tap()

        // Relaunch: the data must have been persisted.
        app.terminate()
        app.launch()
        app.tabBars.buttons["Journal"].tap()
        let count = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'workouts'")).firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        print("JOURNAL-COUNT: \(count.label)")
        let n = Int(count.label.split(separator: " ").first ?? "") ?? 0
        XCTAssertGreaterThan(n, 1, "the import was persisted: \(count.label)")
    }
}
