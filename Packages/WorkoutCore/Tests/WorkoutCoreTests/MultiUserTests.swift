import XCTest
@testable import WorkoutCore

final class GeneralRotationTests: XCTestCase {
    let anchor = LocalDate(2026, 9, 28)

    func testClassicIsUnchanged() {
        let r = LiftRotation(anchor: anchor, schedule: [.monday, .wednesday, .friday])
        XCTAssertTrue(r.isClassic)
        XCTAssertEqual(r.lift(for: LocalDate(2026, 10, 5)), .frontSquat)
        XCTAssertEqual(r.lift(for: LocalDate(2026, 9, 30)), .deadlift)
    }

    func testTwoDaysCyclesAllSixOverThreeWeeks() {
        let r = LiftRotation(anchor: anchor, schedule: [.tuesday, .friday])
        XCTAssertFalse(r.isClassic)
        var d = anchor, seen: [Lift] = []
        while seen.count < 6 { if r.isScheduled(d) { seen.append(r.lift(for: d)) }; d = d.adding(days: 1) }
        XCTAssertEqual(seen, Lift.allCases)
        XCTAssertEqual(d, anchor.adding(days: 19), "six sessions = three weeks")
    }

    func testFourAndFiveDaysNeverRepeatWithinSevenDays() {
        for schedule: [Weekday] in [[.monday, .tuesday, .thursday, .friday], [.monday, .tuesday, .wednesday, .thursday, .friday]] {
            let r = LiftRotation(anchor: anchor, schedule: schedule)
            var last: [Lift: LocalDate] = [:]
            var d = anchor
            while d < anchor.adding(days: 120) {
                if r.isScheduled(d) {
                    let l = r.lift(for: d)
                    if let prev = last[l] { XCTAssertGreaterThanOrEqual(prev.days(until: d), 7, "\(schedule) \(l) \(d)") }
                    last[l] = d
                }
                d = d.adding(days: 1)
            }
        }
    }

    func testCustomLiftsAndDatesBeforeAnchor() {
        let r = LiftRotation(anchor: anchor, schedule: [.monday, .thursday], lifts: [.deadlift, .pushPress, .backSquat])
        XCTAssertEqual(r.lift(for: anchor), .deadlift)
        XCTAssertEqual(r.lift(for: LocalDate(2026, 10, 1)), .pushPress)
        XCTAssertEqual(r.lift(for: LocalDate(2026, 10, 5)), .backSquat)
        XCTAssertEqual(r.lift(for: LocalDate(2026, 9, 24)), .backSquat, "Thursday before the anchor wraps backwards")
        XCTAssertTrue(r.testLifts(for: anchor) == (.deadlift, .pushPress))
        XCTAssertTrue(r.testLifts(for: LocalDate(2026, 10, 1)) == (.backSquat, .deadlift))
    }

    func testCleanedLifts() {
        XCTAssertEqual(LiftRotation.cleaned([.deadlift, .deadlift]), Lift.allCases, "fewer than two unique: back to the six")
        XCTAssertEqual(LiftRotation.cleaned([.pushJerk, .deadlift, .pushJerk]), [.pushJerk, .deadlift])
    }

    func testPlannerFollowsCustomRotation() throws {
        var s = PlannerSettings.default
        s.schedule = [.tuesday, .saturday]
        s.lifts = [.backSquat, .pushPress]
        let p = RulesWorkoutPlanner()
        let a = try p.makePlan(PlanRequest(date: LocalDate(2026, 10, 20), settings: s, now: TestData.now))
        let b = try p.makePlan(PlanRequest(date: LocalDate(2026, 10, 24), settings: s, now: TestData.now))
        XCTAssertEqual(Set([a.mainLift, b.mainLift]), Set([.backSquat, .pushPress]))
        XCTAssertTrue(a.reasons.contains { $0.text.contains("Next in your rotation") })
    }

    func testSettingsDefaultsAndOnboardedFlag() throws {
        XCTAssertFalse(PlannerSettings().onboarded, "fresh installs onboard")
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(PlannerSettings.default)) as! [String: Any]
        json.removeValue(forKey: "onboarded")
        json.removeValue(forKey: "lifts")
        let old = try JSONDecoder().decode(PlannerSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(old.onboarded, "settings saved by older versions skip onboarding")
        XCTAssertEqual(old.lifts, Lift.allCases)
    }
}

final class CSVHistoryImporterTests: XCTestCase {
    func testTemplateImport() throws {
        let csv = """
        date,lift,set,reps,weight,unit,notes
        2026-09-28,Back Squat,1,5,135,lb,easy
        2026-09-28,Back Squats,2,5,145,lb,
        2026-09-28,Push Press,1,3,40,kg,
        2026-09-30,Deadlift,1,5,185,
        2026-10-02,Zumba,1,5,10,lb,
        2026-13-01,Deadlift,1,5,185,lb,
        """
        XCTAssertTrue(CSVHistoryImporter.looksLikeTemplate(Data(csv.utf8)))
        let r = try CSVHistoryImporter.importCSV(Data(csv.utf8), now: TestData.now)
        XCTAssertEqual(r.workouts.map(\.date.iso), ["2026-09-28", "2026-09-30"])
        XCTAssertEqual(r.skipped, 2)
        XCTAssertEqual(r.skippedReasons, ["row with an unknown lift": 1, "row with an invalid date": 1])
        let first = r.workouts[0]
        XCTAssertEqual(first.status, .done)
        XCTAssertEqual(first.strengthSection?.items.map(\.movementName), ["Back Squat", "Push Press"])
        XCTAssertEqual(first.strengthSection?.items[0].setLogs.map(\.weight), [135, 145])
        XCTAssertEqual(first.strengthSection!.items[1].setLogs[0].weight, WeightUnit.kg.toPounds(40), accuracy: 1e-9)
        XCTAssertEqual(ProgressSeries.lift(.deadlift, workouts: r.workouts).map(\.topWeight), [185])
    }

    func testRejectsBadFiles() {
        XCTAssertThrowsError(try CSVHistoryImporter.importCSV(Data()))
        XCTAssertThrowsError(try CSVHistoryImporter.importCSV(Data("a,b,c\n1,2,3".utf8)))
        XCTAssertFalse(CSVHistoryImporter.looksLikeTemplate(Data("[{\"date\": 1}]".utf8)))
        let mostlyBad = "date,lift,reps,weight\n2026-01-01,Nope,5,10\n2026-01-02,Nope,5,10\n2026-01-03,Deadlift,5,100"
        XCTAssertThrowsError(try CSVHistoryImporter.importCSV(Data(mostlyBad.utf8)))
        let huge = "date,lift,reps,weight\n2026-01-01,Deadlift,5,99999"
        XCTAssertThrowsError(try CSVHistoryImporter.importCSV(Data(huge.utf8)))
    }
}
