import XCTest
@testable import WorkoutCore

final class TrainingMaxTests: XCTestCase {
    func testEpley() {
        XCTAssertEqual(TrainingMax.epley(weight: 185, reps: 5), 185 * (1 + 5.0 / 30), accuracy: 0.0001)
        XCTAssertEqual(TrainingMax.epley(weight: 100, reps: 1), 100)
        XCTAssertEqual(TrainingMax.epley(weight: 0, reps: 5), 0)
        XCTAssertEqual(TrainingMax.epley(weight: 100, reps: 0), 0)
    }

    /// Matches the "Starting TM" column of IOS-PLAN.
    func testStartingTrainingMaxesFromPlan() {
        XCTAssertEqual(TrainingMax.fromSet(weight: 185, reps: 5), 195) // Deadlift
        XCTAssertEqual(TrainingMax.fromSet(weight: 135, reps: 5), 145) // Back Squat
        XCTAssertEqual(TrainingMax.fromSet(weight: 120, reps: 5), 125) // Front Squat
        XCTAssertEqual(TrainingMax.fromSet(weight: 100, reps: 5), 105) // Push Press
        XCTAssertEqual(TrainingMax.fromSet(weight: 75, reps: 5), 80) // Hang Power Clean
        XCTAssertEqual(TrainingMax.fromSet(weight: 55, reps: 5), 60) // Push Jerk
    }

    func testFromSetsTakesBest() {
        let sets = [SetLog(setNumber: 1, reps: 3, weight: 150), SetLog(setNumber: 2, reps: 1, weight: 170), SetLog(setNumber: 3, reps: 0, weight: 500)]
        XCTAssertEqual(TrainingMax.fromSets(sets), max(TrainingMax.fromSet(weight: 150, reps: 3), TrainingMax.fromSet(weight: 170, reps: 1)))
        XCTAssertNil(TrainingMax.fromSets([]))
    }

    func testNextBlockIsLowerOfProgressionOrTest() {
        XCTAssertEqual(TrainingMax.nextBlock(current: 195, lift: .deadlift, testResult: nil), 205)
        XCTAssertEqual(TrainingMax.nextBlock(current: 105, lift: .pushPress, testResult: nil), 110)
        XCTAssertEqual(TrainingMax.nextBlock(current: 80, lift: .hangPowerClean, testResult: 100), 85)
        XCTAssertEqual(TrainingMax.nextBlock(current: 195, lift: .deadlift, testResult: 190), 190)
    }

    func testTwoMissesDropsTenPercent() {
        XCTAssertEqual(TrainingMax.afterTwoMisses(200), 180)
        XCTAssertEqual(TrainingMax.afterTwoMisses(125), 115)
    }

    func testResolveFallsBackToHistoryThenDefault() {
        let history = [TestData.strengthDay(LocalDate(2026, 9, 28), .backSquat, weights: [65, 80, 100, 120, 135])]
        let tms = TrainingMax.resolve(programs: [.deadlift: 200], history: history, barWeight: 45)
        XCTAssertEqual(tms[.deadlift], 200)
        XCTAssertEqual(tms[.backSquat], 140) // 90% of the 157.5 e1RM, to 5 lb
        XCTAssertEqual(tms[.frontSquat], 120, "related lift: back squat × 0.85")
        XCTAssertEqual(tms[.pushJerk], 65)
        XCTAssertEqual(tms.count, 6)
    }

    func testLiftSessionMissedRep() {
        let planned = [PlannedSet(setNumber: 1, reps: 5, weight: 100), PlannedSet(setNumber: 2, reps: 5, weight: 110)]
        let ok = LiftSession(date: LocalDate(2026, 1, 1), lift: .deadlift,
                             sets: [SetLog(setNumber: 1, reps: 5, weight: 100), SetLog(setNumber: 2, reps: 5, weight: 110)], plannedSets: planned)
        XCTAssertFalse(ok.missedRep)
        var missed = ok
        missed.sets[1].reps = 3
        XCTAssertTrue(missed.missedRep)
        var unlogged = ok
        unlogged.sets.removeLast()
        XCTAssertTrue(unlogged.missedRep)
        XCTAssertEqual(ok.volume, 1050)
    }
}

final class ProgramCalendarTests: XCTestCase {
    let cal = ProgramCalendar()

    /// The owner: block 1 starts Mon Oct 12 2026 with no test week.
    func testNoTestWeekBeforeBlockOne() {
        XCTAssertEqual(cal.position(on: LocalDate(2026, 10, 5)).phase, .preProgram)
        let w1 = cal.position(on: LocalDate(2026, 10, 12))
        XCTAssertEqual(w1.block, 1)
        XCTAssertEqual(w1.week, 1)
        XCTAssertEqual(w1.phase, .volume)
        XCTAssertEqual(cal.block1Start, LocalDate(2026, 10, 12))
    }

    /// New users who choose "test": two test weeks, then block 1.
    func testInitialTwoWeekTest() {
        let c = ProgramCalendar(testWeekStart: LocalDate(2026, 10, 12), initialTestWeeks: 2)
        XCTAssertEqual(c.block1Start, LocalDate(2026, 10, 26))
        let t1 = c.position(on: LocalDate(2026, 10, 14)), t2 = c.position(on: LocalDate(2026, 10, 23))
        XCTAssertEqual([t1.phase, t2.phase], [.test, .test])
        XCTAssertEqual([t1.week, t2.week], [13, 14])
        XCTAssertEqual(t1.block, 0)
        XCTAssertEqual(c.position(on: LocalDate(2026, 10, 26)).block, 1)
        XCTAssertEqual(c.contextLabel(on: LocalDate(2026, 10, 5)), "test weeks start Oct 12")
        XCTAssertEqual(c.contextLabel(on: LocalDate(2026, 10, 23)), "test week 2 of 2")
    }

    /// A quarter = 12 training weeks + 2 test weeks.
    func testBlockOneDates() {
        XCTAssertEqual(cal.position(on: LocalDate(2026, 11, 9)).phase, .strength) // week 5
        XCTAssertEqual(cal.position(on: LocalDate(2026, 12, 7)).phase, .peak) // week 9
        let deload = cal.position(on: LocalDate(2027, 1, 1))
        XCTAssertEqual(deload.week, 12)
        XCTAssertEqual(deload.phase, .deload)
        let test1 = cal.position(on: LocalDate(2027, 1, 4)), test2 = cal.position(on: LocalDate(2027, 1, 15))
        XCTAssertEqual([test1.week, test2.week], [13, 14])
        XCTAssertEqual([test1.phase, test2.phase], [.test, .test])
        let b2 = cal.position(on: LocalDate(2027, 1, 18))
        XCTAssertEqual(b2.block, 2)
        XCTAssertEqual(b2.week, 1)
    }

    func testBlockRanges() {
        XCTAssertEqual(cal.dateRange(ofBlock: 1), LocalDate(2026, 10, 12)...LocalDate(2027, 1, 17))
        XCTAssertEqual(cal.startOfBlock(2), LocalDate(2027, 1, 18))
        XCTAssertEqual(cal.startOfWeek(block: 1, week: 13), LocalDate(2027, 1, 4))
        XCTAssertEqual(TrainingMaxBook.testWeekRange(beforeBlock: 2, calendar: cal), LocalDate(2027, 1, 4)...LocalDate(2027, 1, 17))
        XCTAssertNil(TrainingMaxBook.testWeekRange(beforeBlock: 1, calendar: cal))
    }

    func testPhaseTable() {
        XCTAssertEqual((1...14).map(BlockPhase.forBlockWeek),
                       [.volume, .volume, .volume, .volume, .strength, .strength, .strength, .strength, .peak, .peak, .peak, .deload, .test, .test])
    }

    func testHolidayDeloadOverride() {
        let c = ProgramCalendar(deloadWeeks: [LocalDate(2026, 12, 21)])
        let p = c.position(on: LocalDate(2026, 12, 23))
        XCTAssertEqual(p.phase, .deload)
        XCTAssertTrue(p.isDeloadOverride)
        XCTAssertEqual(c.position(on: LocalDate(2026, 12, 14)).phase, .peak)
    }
}

final class RotationTests: XCTestCase {
    let rot = PlannerSettings.default.rotation

    func testMockupDayIsWeekBFrontSquat() {
        XCTAssertEqual(rot.week(for: LocalDate(2026, 10, 5)), .b)
        XCTAssertEqual(rot.lift(for: LocalDate(2026, 10, 5)), .frontSquat)
        XCTAssertEqual(rot.lift(for: LocalDate(2026, 10, 7)), .hangPowerClean)
        XCTAssertEqual(rot.lift(for: LocalDate(2026, 10, 9)), .pushJerk)
    }

    func testWeekA() {
        XCTAssertEqual(rot.lift(for: LocalDate(2026, 9, 28)), .backSquat)
        XCTAssertEqual(rot.lift(for: LocalDate(2026, 9, 30)), .deadlift)
        XCTAssertEqual(rot.lift(for: LocalDate(2026, 10, 2)), .pushPress)
        // Before the anchor still alternates correctly.
        XCTAssertEqual(rot.week(for: LocalDate(2026, 9, 21)), .b)
        XCTAssertEqual(rot.week(for: LocalDate(2026, 9, 14)), .a)
    }

    func testEveryLiftOnceEveryTwoWeeksAndNeverWithinSevenDays() {
        var lastSeen: [Lift: LocalDate] = [:]
        var d = LocalDate(2026, 10, 19)
        var counts: [Lift: Int] = [:]
        while d < LocalDate(2027, 10, 19) {
            if rot.isScheduled(d) {
                let lift = rot.lift(for: d)
                if let prev = lastSeen[lift] { XCTAssertGreaterThanOrEqual(prev.days(until: d), 14) }
                lastSeen[lift] = d
                counts[lift, default: 0] += 1
            }
            d = d.adding(days: 1)
        }
        XCTAssertEqual(Set(counts.keys), Set(Lift.allCases))
        XCTAssertLessThanOrEqual((counts.values.max() ?? 0) - (counts.values.min() ?? 0), 1)
    }

    func testEachWeekCoversSquatHipAndOverhead() {
        for weekStart in stride(from: 0, to: 70, by: 7) {
            let monday = LocalDate(2026, 10, 19).adding(days: weekStart)
            let slots = [0, 2, 4].map { rot.lift(for: monday.adding(days: $0)).slot }
            XCTAssertEqual(slots, [.squat, .hipPull, .overhead])
        }
    }

    func testCustomScheduleAndUnscheduledDays() {
        let r = LiftRotation(anchor: LocalDate(2026, 9, 28), schedule: [.thursday, .tuesday, .saturday])
        XCTAssertEqual(r.lift(for: LocalDate(2026, 9, 29)), .backSquat) // Tue
        XCTAssertEqual(r.lift(for: LocalDate(2026, 10, 1)), .deadlift) // Thu
        XCTAssertEqual(r.lift(for: LocalDate(2026, 10, 3)), .pushPress) // Sat
        XCTAssertFalse(r.isScheduled(LocalDate(2026, 9, 28)))
        XCTAssertEqual(r.nextScheduledDate(onOrAfter: LocalDate(2026, 9, 28)), LocalDate(2026, 9, 29))
        // An unscheduled Wednesday takes the slot after Tuesday.
        XCTAssertEqual(r.slotIndex(for: LocalDate(2026, 9, 30)), 1)
        // An empty schedule falls back to Mon/Wed/Fri.
        XCTAssertEqual(LiftRotation(anchor: LocalDate(2026, 9, 28), schedule: []).schedule, [.monday, .wednesday, .friday])
    }
}

final class StrengthProgramTests: XCTestCase {
    let plates = PlateCalculator()

    func pos(_ week: Int, block: Int = 1) -> BlockPosition {
        BlockPosition(block: block, week: week, phase: BlockPhase.forBlockWeek(week))
    }

    func testPhaseTableSetsAndReps() {
        XCTAssertEqual(StrengthProgram.prescription(for: .backSquat, position: pos(1)).setReps, [5, 5, 5, 5, 5, 5])
        XCTAssertEqual(StrengthProgram.prescription(for: .hangPowerClean, position: pos(1)).setReps, [3, 3, 3, 3, 3, 3])
        XCTAssertEqual(StrengthProgram.prescription(for: .deadlift, position: pos(6)).setReps, [3, 3, 3, 3, 3, 3])
        XCTAssertEqual(StrengthProgram.prescription(for: .pushJerk, position: pos(6)).setReps, [2, 2, 2, 2, 2, 2])
        XCTAssertEqual(StrengthProgram.prescription(for: .pushPress, position: pos(10)).setReps, [2, 2, 2, 2, 2, 1])
        let deload = StrengthProgram.prescription(for: .frontSquat, position: pos(12))
        XCTAssertEqual(deload.setReps, [5, 5, 5, 5, 5])
        XCTAssertTrue(deload.flat)
        XCTAssertEqual(deload.topFraction, 0.6, accuracy: 0.0001)
        XCTAssertEqual(StrengthProgram.prescription(for: .hangPowerClean, position: pos(12)).setReps, [2, 2, 2, 2, 2])
    }

    func testOlympicLiftsNeverExceedThreeReps() {
        for week in 0...13 {
            for lift in [Lift.hangPowerClean, .pushJerk] {
                let p = week == 0 ? BlockPosition(block: 0, week: 0, phase: .preProgram) : pos(week)
                XCTAssertLessThanOrEqual(StrengthProgram.prescription(for: lift, position: p).setReps.max() ?? 0, 3)
            }
        }
    }

    func testTopPercentProgressesThroughPhase() {
        let w1 = StrengthProgram.prescription(for: .backSquat, position: pos(1)).topFraction
        let w4 = StrengthProgram.prescription(for: .backSquat, position: pos(4)).topFraction
        XCTAssertEqual(w1, 0.75, accuracy: 0.0001)
        XCTAssertEqual(w4, 0.80, accuracy: 0.0001)
        let s = StrengthProgram.prescription(for: .backSquat, position: pos(8)).topFraction
        XCTAssertEqual(s, 0.90, accuracy: 0.0001)
        let peak = StrengthProgram.prescription(for: .pushJerk, position: pos(9)).topRange
        XCTAssertEqual(peak.lowerBound, 0.85, accuracy: 0.0001)
        XCTAssertEqual(peak.upperBound, 0.90, accuracy: 0.0001)
    }

    func testRampClimbsEvenlyAndEndsAtTop() {
        let sets = StrengthProgram.ramp(setReps: Array(repeating: 5, count: 6), top: 150, start: 97.5, calculator: plates)
        XCTAssertEqual(sets.count, 6)
        XCTAssertEqual(sets.last?.weight, 150)
        XCTAssertEqual(sets.first?.weight, 95)
        for (a, b) in zip(sets, sets.dropFirst()) { XCTAssertGreaterThan(b.weight, a.weight) }
        for s in sets { XCTAssertNotNil(plates.loadout(for: s.weight), "\(s.weight) not loadable") }
        XCTAssertEqual(sets.map(\.setNumber), [1, 2, 3, 4, 5, 6])
    }

    func testRampWithNarrowRangeNeverGoesDown() {
        let sets = StrengthProgram.ramp(setReps: Array(repeating: 3, count: 6), top: 55, start: 30, calculator: plates)
        XCTAssertEqual(sets.first?.weight, 45)
        XCTAssertEqual(sets.last?.weight, 55)
        for (a, b) in zip(sets, sets.dropFirst()) { XCTAssertGreaterThanOrEqual(b.weight, a.weight) }
    }

    func testFlatRampForDeload() {
        let sets = StrengthProgram.ramp(setReps: [5, 5, 5, 5, 5], top: 117, start: 50, calculator: plates, flat: true, trainingMax: 195)
        XCTAssertEqual(Set(sets.map(\.weight)), [115])
    }

    func testPlanUsesBlockPercent() {
        let plan = StrengthPlanner.plan(lift: .deadlift, position: pos(1), trainingMax: 195, calculator: plates, input: StrengthAdjustmentInput())
        XCTAssertEqual(plan.sets.last?.weight, 145) // 75% of 195 = 146.25 -> 145
        XCTAssertEqual(plan.ruleIDs, ["block.percent"])
        XCTAssertFalse(plan.reasons.isEmpty)
    }

    func session(top: Double, missed: Bool = false, rating: Int? = nil) -> LiftSession {
        let planned = [PlannedSet(setNumber: 1, reps: 5, weight: top)]
        return LiftSession(date: LocalDate(2026, 10, 19), lift: .deadlift,
                           sets: [SetLog(setNumber: 1, reps: missed ? 3 : 5, weight: top)], plannedSets: planned,
                           strengthDifficulty: rating, energy: nil)
    }

    func testEasyRatingStepsUp() {
        let plan = StrengthPlanner.plan(lift: .deadlift, position: pos(3), trainingMax: 195, calculator: plates,
                                        input: StrengthAdjustmentInput(lastSessions: [session(top: 150, rating: 2)]))
        XCTAssertTrue(plan.ruleIDs.contains("adjust.step_up"))
        XCTAssertGreaterThanOrEqual(plan.sets.last!.weight, 155)
    }

    func testBrutalOrMissedRepeatsWeight() {
        let brutal = StrengthPlanner.plan(lift: .deadlift, position: pos(3), trainingMax: 195, calculator: plates,
                                          input: StrengthAdjustmentInput(lastSessions: [session(top: 140, rating: 5)]))
        XCTAssertEqual(brutal.sets.last?.weight, 140)
        XCTAssertTrue(brutal.ruleIDs.contains("adjust.repeat"))
        let missed = StrengthPlanner.plan(lift: .deadlift, position: pos(3), trainingMax: 195, calculator: plates,
                                          input: StrengthAdjustmentInput(lastSessions: [session(top: 140, missed: true)]))
        XCTAssertEqual(missed.sets.last?.weight, 140)
    }

    func testTwoMissesInARowDropTM() {
        let plan = StrengthPlanner.plan(lift: .deadlift, position: pos(3), trainingMax: 200, calculator: plates,
                                        input: StrengthAdjustmentInput(lastSessions: [session(top: 160, missed: true), session(top: 160, missed: true)]))
        XCTAssertEqual(plan.trainingMax, 180)
        XCTAssertTrue(plan.ruleIDs.contains("tm.two_misses"))
    }

    func testCapAndPush() {
        let base = StrengthPlanner.plan(lift: .backSquat, position: pos(4), trainingMax: 145, calculator: plates, input: StrengthAdjustmentInput())
        let capped = StrengthPlanner.plan(lift: .backSquat, position: pos(4), trainingMax: 145, calculator: plates,
                                          input: StrengthAdjustmentInput(capAtLowEnd: true))
        let pushed = StrengthPlanner.plan(lift: .backSquat, position: pos(4), trainingMax: 145, calculator: plates,
                                          input: StrengthAdjustmentInput(push: true))
        XCTAssertEqual(capped.sets.last?.weight, plates.round(145 * 0.75).weight)
        XCTAssertLessThan(capped.sets.last!.weight, base.sets.last!.weight)
        XCTAssertEqual(pushed.sets.last!.weight, base.sets.last!.weight + 5)
        let knee = StrengthPlanner.plan(lift: .backSquat, position: pos(4), trainingMax: 145, calculator: plates,
                                        input: StrengthAdjustmentInput(jointLimit: .knee))
        XCTAssertTrue(knee.ruleIDs.contains("limit.knee"))
        XCTAssertEqual(knee.sets.last?.weight, capped.sets.last?.weight)
    }

    func testPlateCeilingCapsTopSet() {
        let plan = StrengthPlanner.plan(lift: .deadlift, position: pos(11), trainingMax: 260, calculator: plates, input: StrengthAdjustmentInput())
        XCTAssertEqual(plan.sets.last?.weight, 230)
        XCTAssertTrue(plan.cappedAtPlateMax)
        XCTAssertTrue(plan.ruleIDs.contains("plates.ceiling"))
    }

    func testInstructionsMatchCoachFormat() {
        let rx = StrengthProgram.prescription(for: .frontSquat, position: pos(1))
        XCTAssertEqual(rx.instructions, "Every 2 min for 12 min\n5 reps · go up each set")
        XCTAssertTrue(StrengthProgram.prescription(for: .pushJerk, position: pos(13)).instructions.contains("heavy 3"))
    }
}
