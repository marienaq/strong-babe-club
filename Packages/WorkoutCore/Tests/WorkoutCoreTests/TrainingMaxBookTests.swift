import XCTest
@testable import WorkoutCore

final class TrainingMaxBookTests: XCTestCase {
    let cal = ProgramCalendar()
    let history = [
        TestData.strengthDay(LocalDate(2026, 10, 2), .deadlift, weights: [85, 110, 135, 160, 185]),
        TestData.strengthDay(LocalDate(2026, 9, 28), .backSquat, weights: [65, 80, 100, 120, 135]),
    ]

    func testPreProgramUsesHistory() {
        let p = TrainingMaxBook.programs(asOf: LocalDate(2026, 10, 5), current: [:], history: history, calendar: cal)
        XCTAssertEqual(p[.deadlift]?.trainingMax, 195)
        XCTAssertEqual(p[.backSquat]?.trainingMax, 145)
        XCTAssertEqual(p[.deadlift]?.source, .history)
        XCTAssertNil(p[.deadlift]?.blockStartDate)
    }

    func testBlockOneTakesTestWeekResult() {
        var h = history
        // Test week: deadlift heavy triple at 190 -> e1RM 209 -> 210 -> TM 190 (rounded).
        h.append(TestData.strengthDay(LocalDate(2026, 10, 14), .deadlift, weights: [95, 135, 165, 190], reps: 3))
        let p = TrainingMaxBook.programs(asOf: LocalDate(2026, 10, 19), current: [:], history: h, calendar: cal)
        XCTAssertEqual(p[.deadlift]?.trainingMax, TrainingMax.fromSet(weight: 190, reps: 3))
        XCTAssertEqual(p[.deadlift]?.source, .test)
        XCTAssertEqual(p[.deadlift]?.blockStartDate, LocalDate(2026, 10, 19))
        XCTAssertEqual(p[.deadlift]?.blockWeek, 1)
        // Untested lift keeps its history estimate.
        XCTAssertEqual(p[.backSquat]?.trainingMax, 145)
    }

    func testBlockTwoIsLowerOfIncrementOrTest() {
        let start = TrainingMaxBook.programs(asOf: LocalDate(2026, 10, 19), current: [:], history: history, calendar: cal)
        // No week-13 test: +10 lower body, +5 presses.
        let b2 = TrainingMaxBook.programs(asOf: LocalDate(2027, 1, 18), current: start, history: history, calendar: cal)
        XCTAssertEqual(b2[.deadlift]?.trainingMax, 205)
        XCTAssertEqual(b2[.deadlift]?.source, .progression)
        // A weaker week-13 test resets lower.
        var h = history
        h.append(TestData.strengthDay(LocalDate(2027, 1, 13), .deadlift, weights: [150, 175], reps: 3))
        let reset = TrainingMaxBook.programs(asOf: LocalDate(2027, 1, 18), current: start, history: h, calendar: cal)
        XCTAssertEqual(reset[.deadlift]?.trainingMax, TrainingMax.fromSet(weight: 175, reps: 3))
    }

    func testIdempotentWithinABlock() {
        let a = TrainingMaxBook.programs(asOf: LocalDate(2026, 10, 19), current: [:], history: history, calendar: cal)
        let b = TrainingMaxBook.programs(asOf: LocalDate(2026, 11, 2), current: a, history: history, calendar: cal)
        XCTAssertEqual(a[.deadlift]?.trainingMax, b[.deadlift]?.trainingMax)
        XCTAssertEqual(b[.deadlift]?.blockWeek, 3)
        // Skipping straight to block 3 rolls through block 2.
        let c = TrainingMaxBook.programs(asOf: LocalDate(2027, 4, 19), current: a, history: history, calendar: cal)
        XCTAssertEqual(c[.deadlift]?.trainingMax, 215)
    }

    func testMissedDayBackfill() {
        let existing = [TestData.simple(LocalDate(2026, 10, 19), .done)]
        let missed = MissedDays.backfill(schedule: [.monday, .wednesday, .friday], from: LocalDate(2026, 10, 19),
                                         to: LocalDate(2026, 10, 25), existing: existing)
        XCTAssertEqual(missed, [LocalDate(2026, 10, 21), LocalDate(2026, 10, 23)])
        XCTAssertTrue(MissedDays.backfill(schedule: [.monday], from: LocalDate(2026, 10, 25), to: LocalDate(2026, 10, 19), existing: []).isEmpty)
        XCTAssertTrue(MissedDays.backfill(schedule: [.monday], from: LocalDate(2020, 1, 1), to: LocalDate(2026, 1, 1), existing: []).isEmpty)
    }
}
