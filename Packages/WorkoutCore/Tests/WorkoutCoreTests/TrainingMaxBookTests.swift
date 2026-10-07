import XCTest
@testable import WorkoutCore

final class TrainingMaxBookTests: XCTestCase {
    let cal = ProgramCalendar()
    let history = [
        TestData.strengthDay(LocalDate(2026, 10, 2), .deadlift, weights: [85, 110, 135, 160, 185]),
        TestData.strengthDay(LocalDate(2026, 9, 28), .backSquat, weights: [65, 80, 100, 120, 135]),
    ]

    // History (5-rep ramps): deadlift 185 × 5 -> e1RM 215.8 -> TM 195; back squat 135 × 5 -> 157.5 -> 140.

    func testPreProgramUsesBestRecentE1RM() {
        let p = TrainingMaxBook.programs(asOf: LocalDate(2026, 10, 5), current: [:], history: history, calendar: cal)
        XCTAssertEqual(p[.deadlift]?.trainingMax, 195)
        XCTAssertEqual(p[.backSquat]?.trainingMax, 140)
        XCTAssertEqual(p[.deadlift]?.source, .history)
        XCTAssertEqual(p[.frontSquat]?.trainingMax, 120, "back squat × 0.85")
        XCTAssertEqual(p[.frontSquat]?.source, .calibrating)
        XCTAssertNil(p[.deadlift]?.blockStartDate)
    }

    /// The owner: block 1 starts Oct 12 straight from history, no test week.
    func testBlockOneStartsFromHistoryWithoutTestWeek() {
        var h = history
        h.append(TestData.strengthDay(LocalDate(2026, 10, 9), .deadlift, weights: [135, 165, 200]))   // logged before the block
        h.append(TestData.strengthDay(LocalDate(2026, 10, 14), .deadlift, weights: [135, 155, 300]))  // inside block 1: ignored
        let p = TrainingMaxBook.programs(asOf: LocalDate(2026, 10, 19), current: [:], history: h, calendar: cal)
        XCTAssertEqual(p[.deadlift]?.trainingMax, 210, "200 × 5 -> 233.3 -> 210; block logs don't move it")
        XCTAssertEqual(p[.deadlift]?.blockStartDate, LocalDate(2026, 10, 12))
        XCTAssertEqual(p[.deadlift]?.blockWeek, 2)
    }

    /// A user who chose "test": the 2-week test's heavy triples set block 1.
    func testBlockOneTakesInitialTestResult() {
        let c = ProgramCalendar(testWeekStart: LocalDate(2026, 10, 12), initialTestWeeks: 2)
        var h = history
        h.append(TestData.strengthDay(LocalDate(2026, 10, 14), .deadlift, weights: [95, 135, 165, 190], reps: 3))
        let p = TrainingMaxBook.programs(asOf: LocalDate(2026, 10, 26), current: [:], history: h, calendar: c)
        XCTAssertEqual(p[.deadlift]?.trainingMax, TrainingMax.fromE1RM(TrainingMax.epley(weight: 190, reps: 3)))
        XCTAssertEqual(p[.deadlift]?.source, .test)
        XCTAssertEqual(p[.deadlift]?.blockStartDate, LocalDate(2026, 10, 26))
        XCTAssertEqual(p[.backSquat]?.trainingMax, 140, "untested: history")
    }

    func testBlockTwoIsLowerOfIncrementOrTest() {
        let start = TrainingMaxBook.programs(asOf: LocalDate(2026, 10, 12), current: [:], history: history, calendar: cal)
        // No weeks 13-14 test: +10 lower body, +5 presses.
        let b2 = TrainingMaxBook.programs(asOf: LocalDate(2027, 1, 18), current: start, history: history, calendar: cal)
        XCTAssertEqual(b2[.deadlift]?.trainingMax, 205)
        XCTAssertEqual(b2[.deadlift]?.source, .progression)
        // A weaker test in weeks 13-14 (Jan 4-17) resets lower.
        var h = history
        h.append(TestData.strengthDay(LocalDate(2027, 1, 13), .deadlift, weights: [150, 175], reps: 3))
        let reset = TrainingMaxBook.programs(asOf: LocalDate(2027, 1, 18), current: start, history: h, calendar: cal)
        XCTAssertEqual(reset[.deadlift]?.trainingMax, TrainingMax.fromE1RM(TrainingMax.epley(weight: 175, reps: 3)))
    }

    func testIdempotentWithinABlock() {
        let a = TrainingMaxBook.programs(asOf: LocalDate(2026, 10, 12), current: [:], history: history, calendar: cal)
        let b = TrainingMaxBook.programs(asOf: LocalDate(2026, 10, 26), current: a, history: history, calendar: cal)
        XCTAssertEqual(a[.deadlift]?.trainingMax, b[.deadlift]?.trainingMax)
        XCTAssertEqual(b[.deadlift]?.blockWeek, 3)
        // Skipping straight to block 3 rolls through block 2.
        let c = TrainingMaxBook.programs(asOf: LocalDate(2027, 4, 26), current: a, history: history, calendar: cal)
        XCTAssertEqual(c[.deadlift]?.trainingMax, 215)
    }

    func testRecomputedUntilFixed() {
        let stale: [Lift: LiftProgram] = Dictionary(uniqueKeysWithValues: Lift.allCases.map { ($0, LiftProgram(lift: $0, trainingMax: 65, source: .history)) })
        let p = TrainingMaxBook.programs(asOf: LocalDate(2026, 10, 5), current: stale, history: history, calendar: cal)
        XCTAssertEqual(p[.deadlift]?.trainingMax, 195)
        XCTAssertEqual(p[.pushJerk]?.trainingMax, 65, "no history: default")
        var manual = stale
        manual[.deadlift] = LiftProgram(lift: .deadlift, trainingMax: 150, source: .manual)
        XCTAssertEqual(TrainingMaxBook.programs(asOf: LocalDate(2026, 10, 5), current: manual, history: history, calendar: cal)[.deadlift]?.trainingMax, 150)
    }

    /// Calibrating lifts settle after their first rated session: 1-2 up, 4-5 down.
    func testCalibrationAdjustsAfterFirstRatedSession() {
        func after(_ rating: Int) -> LiftProgram? {
            var h = history // front squat calibrating at 120 (from back squat)
            h.append(TestData.strengthDay(LocalDate(2026, 10, 19), .frontSquat, weights: [60, 75, 90], difficulty: rating))
            return TrainingMaxBook.programs(asOf: LocalDate(2026, 10, 21), current: [:], history: h, calendar: cal)[.frontSquat]
        }
        XCTAssertEqual(after(1)?.trainingMax, 130)
        XCTAssertEqual(after(2)?.trainingMax, 125)
        XCTAssertEqual(after(3)?.trainingMax, 120)
        XCTAssertEqual(after(5)?.trainingMax, 115)
        XCTAssertEqual(after(2)?.source, .progression, "settled")
        let unrated = TrainingMaxBook.programs(asOf: LocalDate(2026, 10, 21), current: [:], history: history, calendar: cal)
        XCTAssertEqual(unrated[.frontSquat]?.source, .calibrating)
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

final class TrainingMaxEstimateTests: XCTestCase {
    func day(_ d: LocalDate, _ name: String, _ sets: [(Double, Int)], status: WorkoutStatus = .done) -> PlannedWorkout {
        let logs = sets.enumerated().map { SetLog(setNumber: $0.offset + 1, reps: $0.element.1, weight: $0.element.0) }
        return PlannedWorkout(date: d, status: status, sections: [WorkoutSection(kind: .strength, format: .everyNMin, instructions: "",
                              items: [SectionItem(letter: "A", movementID: MovementLibrary.slug(name), movementName: name, setLogs: logs)])])
    }

    /// The owner's case, with synthetic numbers shaped like her last month.
    func testRecentLadderAndRampEstimates() throws {
        let asOf = LocalDate(2026, 10, 12)
        let h = [
            day(LocalDate(2026, 10, 2), "Deadlift", [(85, 10), (110, 8), (135, 6), (160, 4), (185, 2)]),
            day(LocalDate(2026, 9, 18), "Deadlift", [(140, 5), (155, 5), (170, 5)]),
            day(LocalDate(2026, 9, 25), "Power Clean", [(85, 5), (100, 5)]),
            day(LocalDate(2026, 9, 23), "Split Jerks", [(110, 5)]),
            day(LocalDate(2026, 9, 30), "Push Press", [(90, 4), (100, 2)]),
            day(LocalDate(2026, 8, 24), "Hang Power Clean", [(75, 5)]),       // outside the 28-day window
            day(LocalDate(2026, 10, 9), "Deadlift", [(300, 5)], status: .skipped), // not done: ignored
        ]
        let dl = try XCTUnwrap(TrainingMax.estimate(.deadlift, history: h, asOf: asOf))
        XCTAssertEqual(dl.trainingMax, 180) // 170 × 5 = 198.3 / 185 × 2 = 197.3 -> 178.5 -> 180
        XCTAssertFalse(dl.calibrating)
        let hpc = try XCTUnwrap(TrainingMax.estimate(.hangPowerClean, history: h, asOf: asOf))
        XCTAssertEqual(hpc.trainingMax, 95) // 100 × 5 = 116.7 × 0.9 = 105 -> 94.5 -> 95
        XCTAssertTrue(hpc.calibrating)
        let pj = try XCTUnwrap(TrainingMax.estimate(.pushJerk, history: h, asOf: asOf))
        // Split jerk 110 × 5 × 0.9 = 115.5 vs push press 106.7 × 1.05 = 112: lower wins -> 100.8 -> 100
        XCTAssertEqual(pj.trainingMax, 100)
        XCTAssertTrue(pj.basis.contains("Push Press"))
        XCTAssertEqual(TrainingMax.estimate(.pushPress, history: h, asOf: asOf)?.trainingMax, 95)
        XCTAssertNil(TrainingMax.estimate(.backSquat, history: h, asOf: asOf))
    }

    func testRelatedTableAndCalibration() {
        XCTAssertEqual(RelatedLift.table.filter { $0.target == .pushJerk }.count, 2)
        XCTAssertEqual(TrainingMax.estimate(.backSquat, history: [day(LocalDate(2026, 10, 1), "Front Squat", [(100, 5)])],
                                            asOf: LocalDate(2026, 10, 12))?.trainingMax, 125) // 116.7 / 0.85 = 137.3 -> 123.5 -> 125
        let h = [TestData.strengthDay(LocalDate(2026, 10, 14), .deadlift, weights: [100], difficulty: 4)]
        XCTAssertEqual(TrainingMax.calibrated(200, lift: .deadlift, history: h, from: LocalDate(2026, 10, 12)).tm, 190)
        XCTAssertFalse(TrainingMax.calibrated(200, lift: .deadlift, history: [], from: LocalDate(2026, 10, 12)).adjusted)
    }
}

final class OwnerMigrationTests: XCTestCase {
    /// Settings saved before round 6 (test week Oct 12, then block 1 Oct 19)
    /// load with the test week dropped: block 1 starts Mon Oct 12.
    func testOldSettingsDropTheTestWeek() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(PlannerSettings.default)) as! [String: Any]
        json.removeValue(forKey: "initialTestWeeks")
        let s = try JSONDecoder().decode(PlannerSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(s.initialTestWeeks, 0)
        XCTAssertEqual(s.calendar.block1Start, LocalDate(2026, 10, 12))
        XCTAssertEqual(s.calendar.position(on: LocalDate(2026, 10, 14)).phase, .volume)
        XCTAssertEqual(s.calendar.contextLabel(on: LocalDate(2026, 10, 6)), "block 1 starts Oct 12")
        // Stored history-based TMs are recomputed by the new rule.
        let old: [Lift: LiftProgram] = [.deadlift: LiftProgram(lift: .deadlift, trainingMax: 195, source: .history)]
        let h = [TestData.strengthDay(LocalDate(2026, 10, 2), .deadlift, weights: [170], reps: 5)]
        XCTAssertEqual(TrainingMaxBook.programs(asOf: LocalDate(2026, 10, 6), current: old, history: h, calendar: s.calendar)[.deadlift]?.trainingMax, 180)
    }
}
