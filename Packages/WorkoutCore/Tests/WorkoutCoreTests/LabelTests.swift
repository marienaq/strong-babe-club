import XCTest
@testable import WorkoutCore

final class LabelTests: XCTestCase {
    func testPluralLiftNames() {
        XCTAssertEqual(Lift(movementName: "Front Squats"), .frontSquat)
        XCTAssertEqual(Lift(movementName: "Back Squats"), .backSquat)
        XCTAssertEqual(Lift(movementName: "Deadlifts"), .deadlift)
        XCTAssertEqual(Lift(movementName: "Push Presses"), .pushPress)
        XCTAssertEqual(Lift(movementName: "Push Jerks"), .pushJerk)
        XCTAssertEqual(Lift(movementName: "Hang Power Cleans"), .hangPowerClean)
        XCTAssertNil(Lift(movementName: "Power Cleans"))
        XCTAssertNil(Lift(movementName: "DB Push Press"))
    }

    func testBlockContextLabels() {
        let cal = ProgramCalendar()
        XCTAssertEqual(cal.contextLabel(on: LocalDate(2026, 10, 5)), "block 1 starts Oct 12")
        XCTAssertEqual(cal.contextLabel(on: LocalDate(2026, 10, 14)), "block 1 · week 1 · volume")
        XCTAssertEqual(cal.contextLabel(on: LocalDate(2026, 11, 2)), "block 1 · week 4 · volume")
        XCTAssertEqual(cal.contextLabel(on: LocalDate(2027, 1, 13)), "block 1 · test week 2 of 2")
        let holiday = ProgramCalendar(deloadWeeks: [LocalDate(2026, 12, 21)])
        XCTAssertEqual(holiday.contextLabel(on: LocalDate(2026, 12, 23)), "block 1 · week 11 · deload (swapped)")
    }

    func testStrengthReasonsDontMentionWeekAB() throws {
        let w = try RulesWorkoutPlanner().makePlan(PlanRequest(date: LocalDate(2026, 10, 19), now: TestData.now))
        for r in w.reasons { XCTAssertFalse(r.text.contains("Week A") || r.text.contains("Week B"), r.text) }
    }

    func testTodayListDetails() throws {
        let w = try RulesWorkoutPlanner().makePlan(PlanRequest(date: LocalDate(2026, 10, 19), trainingMaxes: [.frontSquat: 125], now: TestData.now))
        let s = try XCTUnwrap(w.strengthSection)
        XCTAssertEqual(s.todayDetail(compact: false), "6 × 5 Front Squat")
        XCTAssertEqual(s.todayDetail(compact: true), "Front Squat")
        XCTAssertEqual(s.secondaryItems.count, 1, "the accessory isn't in the Today detail")
        let m = try XCTUnwrap(w.metabolicSection)
        XCTAssertTrue(m.todayDetail(compact: false).hasPrefix(m.format.displayName), m.todayDetail(compact: false))
        XCTAssertTrue(w.section(.cooldown)!.todayDetail(compact: false).hasSuffix("+ stretch"))
        XCTAssertTrue(w.section(.warmup)!.todayDetail(compact: false).hasPrefix("3 rounds · "))
    }
}
