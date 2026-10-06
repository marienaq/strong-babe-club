import XCTest
@testable import WorkoutCore

final class BenchmarkSchedulerTests: XCTestCase {
    let cal = ProgramCalendar()
    var scheduler: BenchmarkScheduler { BenchmarkScheduler(calendar: cal) }

    func testDueWeeksSpreadEveryTwoWeeks() {
        XCTAssertEqual((0..<6).map(BenchmarkScheduler.dueWeek), [1, 3, 5, 7, 9, 11])
        XCTAssertEqual(BenchmarkScheduler.dueWeek(forSlot: 6), 1)
    }

    func testNoneBeforeBlockOne() {
        let b = [TestData.benchmark(slot: 0)]
        XCTAssertNil(scheduler.due(on: LocalDate(2026, 10, 5), benchmarks: b, history: []))
        XCTAssertNil(scheduler.due(on: LocalDate(2026, 10, 14), benchmarks: b, history: []))
    }

    func testDueFromSlotWeekUntilDone() {
        let b0 = TestData.benchmark(slot: 0, name: "amrap-5-4-alpha"), b1 = TestData.benchmark(slot: 1, name: "amrap-5-4-beta")
        XCTAssertEqual(scheduler.due(on: LocalDate(2026, 10, 19), benchmarks: [b0, b1], history: [])?.id, b0.id)
        // b1 isn't due until week 3.
        let done0 = PlannedWorkout(date: LocalDate(2026, 10, 19), status: .done, sections: [b0.template])
        XCTAssertNil(scheduler.due(on: LocalDate(2026, 10, 26), benchmarks: [b0, b1], history: [done0]))
        XCTAssertEqual(scheduler.due(on: LocalDate(2026, 11, 2), benchmarks: [b0, b1], history: [done0])?.id, b1.id)
    }

    func testOncePerBlockAndBackNextQuarter() {
        let b = TestData.benchmark(slot: 0)
        let done = PlannedWorkout(date: LocalDate(2026, 10, 21), status: .done, sections: [b.template])
        XCTAssertNil(scheduler.due(on: LocalDate(2026, 12, 7), benchmarks: [b], history: [done]))
        XCTAssertEqual(scheduler.due(on: LocalDate(2027, 1, 18), benchmarks: [b], history: [done])?.id, b.id)
    }

    func testOnePerWeekExceptCatchUpWeek() {
        let b0 = TestData.benchmark(slot: 0, name: "amrap-5-4-alpha"), b1 = TestData.benchmark(slot: 1, name: "amrap-5-4-beta")
        let doneMon = PlannedWorkout(date: LocalDate(2026, 11, 2), status: .done, sections: [b0.template])
        XCTAssertNil(scheduler.due(on: LocalDate(2026, 11, 4), benchmarks: [b0, b1], history: [doneMon]))
        let doneTestMon = PlannedWorkout(date: LocalDate(2027, 1, 11), status: .done, sections: [b0.template])
        XCTAssertEqual(scheduler.due(on: LocalDate(2027, 1, 13), benchmarks: [b0, b1], history: [doneTestMon])?.id, b1.id)
    }

    func testInactiveIgnored() {
        var b = TestData.benchmark(slot: 0)
        b.active = false
        XCTAssertNil(scheduler.due(on: LocalDate(2026, 10, 19), benchmarks: [b], history: []))
    }

    func testInstantiateIsExactRepeat() {
        let b = TestData.benchmark(slot: 0)
        var rng = SeededRandom(seed: 1)
        let (s, subs) = scheduler.instantiate(b, settings: .default, library: .standard, using: &rng)
        XCTAssertTrue(subs.isEmpty)
        XCTAssertFalse(s.isModified)
        XCTAssertEqual(s.name, b.name)
        XCTAssertEqual(s.benchmarkID, b.id)
        XCTAssertEqual(s.items.map(\.movementID), b.template.items.map(\.movementID))
        XCTAssertEqual(s.workSec, 240)
        XCTAssertTrue(s.roundLogs.isEmpty)
    }

    func testLimitSubstitutionMarksModified() {
        var b = TestData.benchmark(slot: 0)
        b.template.items.append(SectionItem(letter: "C", movementID: "box-jump", movementName: "Box Jumps", reps: 5))
        var settings = PlannerSettings.default
        settings.limits.avoidJumping = true
        var rng = SeededRandom(seed: 1)
        let (s, subs) = scheduler.instantiate(b, settings: settings, library: .standard, using: &rng)
        XCTAssertTrue(s.isModified)
        XCTAssertEqual(subs, ["Box Jumps → Box Step-Ups"])
        XCTAssertEqual(s.items.last?.movementID, "box-step-up")
    }

    func testPlannerUsesBenchmarkAndShuffleDefersIt() throws {
        let b = TestData.benchmark(slot: 0)
        let planner = RulesWorkoutPlanner()
        let req = PlanRequest(date: LocalDate(2026, 10, 19), benchmarks: [b], now: TestData.now)
        let w = try planner.makePlan(req)
        XCTAssertEqual(w.metabolicSection?.benchmarkID, b.id)
        XCTAssertEqual(w.metabolicSection?.name, "amrap-5-4-fungi")
        XCTAssertTrue(w.reasons(for: .metabolic).contains { $0.rule == "metabolic.benchmark" })
        let s = try planner.makeShuffle(w, section: .metabolic, request: req)
        XCTAssertNil(s.metabolicSection?.benchmarkID)
        XCTAssertTrue(s.reasons(for: .metabolic).contains { $0.rule == "benchmark.deferred" })
    }

    func testBenchmarkReasonMentionsLastScore() throws {
        let b = TestData.benchmark(slot: 0)
        var last = TestData.amrapSection(benchmarkID: b.id, rounds: [(5, 1), (5, 5), (5, 3), (4, 7), (6, 0)])
        last.name = b.name
        let prev = PlannedWorkout(date: LocalDate(2026, 7, 20), status: .done, sections: [last])
        let w = try RulesWorkoutPlanner().makePlan(PlanRequest(date: LocalDate(2026, 10, 19), history: [prev], benchmarks: [b], now: TestData.now))
        let text = w.reasons(for: .metabolic).first { $0.rule == "metabolic.benchmark" }?.text ?? ""
        XCTAssertTrue(text.contains("July"), text)
        XCTAssertTrue(text.contains("25 + 16"), text)
    }

    func testProposerPicksMixedFormats() {
        var history: [PlannedWorkout] = []
        let formats: [SectionFormat] = [.amrapWithRest, .amrapWithRest, .amrapWithRest, .forTime, .interval, .amrap, .emom, .tabata]
        for (i, f) in formats.enumerated() {
            for rep in 0..<(8 - i) {
                let s = WorkoutSection(kind: .metabolic, format: f, instructions: "", rounds: 4, workSec: 180, restSec: 60,
                                       items: [SectionItem(letter: "A", movementID: "move-\(i)", movementName: "Move \(i)", reps: 5)],
                                       roundLogs: [RoundLog(roundNumber: 1, rounds: 3, reps: 2)])
                history.append(PlannedWorkout(date: LocalDate(2025, 1, 1).adding(days: i * 30 + rep), status: .done, sections: [s]))
            }
        }
        let proposed = BenchmarkProposer.propose(from: history)
        XCTAssertEqual(proposed.count, 6)
        XCTAssertEqual(proposed.map(\.quarterSlot), [0, 1, 2, 3, 4, 5])
        XCTAssertLessThanOrEqual(proposed.filter { $0.template.format == .amrapWithRest }.count, 2)
        XCTAssertEqual(Set(proposed.map(\.name)).count, 6)
        for p in proposed {
            XCTAssertTrue(WorkoutNamer.isValid(p.name), p.name)
            XCTAssertEqual(p.template.benchmarkID, p.id)
            XCTAssertTrue(p.template.roundLogs.isEmpty)
        }
        XCTAssertTrue(BenchmarkProposer.propose(from: []).isEmpty)
    }
}

final class ProgressTests: XCTestCase {
    let cal = ProgramCalendar()

    func testMetabolicScoreFromRounds() {
        let s = TestData.amrapSection(rounds: [(5, 2), (5, 4), (5, 3)])
        let score = MetabolicScore.from(s.roundLogs, format: s.format)
        XCTAssertEqual(score, .roundsReps(rounds: 15, reps: 9))
        XCTAssertEqual(score?.description, "15 + 9")
        XCTAssertEqual(score?.totalReps(repsPerRound: s.repsPerRound), 15 * 9 + 9)
        XCTAssertNil(MetabolicScore.from([], format: .amrap))
        XCTAssertEqual(MetabolicScore.from([RoundLog(roundNumber: 1, timeSec: 865)], format: .forTime)?.description, "14:25")
        XCTAssertEqual(MetabolicScore.from([RoundLog(roundNumber: 1, reps: 30), RoundLog(roundNumber: 2, reps: 28)], format: .interval), .reps(58))
    }

    func testImprovement() {
        let a = MetabolicScore.roundsReps(rounds: 26, reps: 9), b = MetabolicScore.roundsReps(rounds: 25, reps: 16)
        // 9 reps per round: 26*9+9 = 243 vs 25*9+16 = 241.
        XCTAssertEqual(a.improvement(over: b, repsPerRound: 9), 2)
        XCTAssertEqual(MetabolicScore.time(seconds: 600).improvement(over: .time(seconds: 650), repsPerRound: 0), 50)
        XCTAssertNil(MetabolicScore.time(seconds: 600).improvement(over: .reps(5), repsPerRound: 0))
    }

    func testStrengthPR() {
        let old = TestData.strengthDay(LocalDate(2026, 9, 21), .frontSquat, weights: [95, 115])
        let today = TestData.strengthDay(LocalDate(2026, 10, 5), .frontSquat, weights: [95, 125])
        XCTAssertEqual(PRDetector.strengthPRs(in: today, history: [old]), [.frontSquat: 125])
        let same = TestData.strengthDay(LocalDate(2026, 10, 5), .frontSquat, weights: [95, 115])
        XCTAssertTrue(PRDetector.strengthPRs(in: same, history: [old]).isEmpty)
        // A first-ever session is not a PR.
        XCTAssertTrue(PRDetector.strengthPRs(in: today, history: []).isEmpty)
        XCTAssertTrue(PRDetector.isPRDay(today, history: [old], calendar: cal))
    }

    func testBenchmarkPRRequiresLikeForLike() {
        let id = UUID()
        let prev = PlannedWorkout(date: LocalDate(2026, 7, 20), status: .done,
                                  sections: [TestData.amrapSection(benchmarkID: id, rounds: [(5, 0), (5, 0)])])
        let better = TestData.amrapSection(benchmarkID: id, rounds: [(5, 2), (5, 0)])
        XCTAssertTrue(PRDetector.isBenchmarkPR(section: better, date: LocalDate(2026, 10, 19), history: [prev], calendar: cal))
        let modified = TestData.amrapSection(benchmarkID: id, rounds: [(6, 0), (6, 0)], modified: true)
        XCTAssertFalse(PRDetector.isBenchmarkPR(section: modified, date: LocalDate(2026, 10, 19), history: [prev], calendar: cal))
        let worse = TestData.amrapSection(benchmarkID: id, rounds: [(4, 0), (5, 0)])
        XCTAssertFalse(PRDetector.isBenchmarkPR(section: worse, date: LocalDate(2026, 10, 19), history: [prev], calendar: cal))
    }

    func testSeriesAndBenchmarkRows() {
        let id = UUID()
        let b = Benchmark(id: id, name: "amrap-5-4-fungi", template: TestData.amrapSection(benchmarkID: id, rounds: []), quarterSlot: 0)
        let w = [
            TestData.strengthDay(LocalDate(2026, 10, 19), .frontSquat, weights: [95, 100]),
            TestData.strengthDay(LocalDate(2026, 11, 2), .frontSquat, weights: [95, 105]),
            PlannedWorkout(date: LocalDate(2026, 10, 21), status: .done, sections: [TestData.amrapSection(benchmarkID: id, rounds: [(5, 1)])]),
            PlannedWorkout(date: LocalDate(2027, 1, 20), status: .done, sections: [TestData.amrapSection(benchmarkID: id, rounds: [(6, 1)])]),
        ]
        let series = ProgressSeries.lift(.frontSquat, workouts: w)
        XCTAssertEqual(series.map(\.topWeight), [100, 105])
        XCTAssertEqual(series.first?.volume, 5 * 95 + 5 * 100)
        let rows = ProgressSeries.benchmarks([b], workouts: w, calendar: cal)
        XCTAssertEqual(rows.first?.byBlock.keys.sorted(), [1, 2])
    }

    func testGoalProgress() {
        let w = [TestData.strengthDay(LocalDate(2026, 10, 2), .deadlift, weights: [185])]
        let g = ProgressSeries.goal(Goal(lift: .deadlift, targetWeight: 200), workouts: w)
        XCTAssertEqual(g.fraction, 0.925, accuracy: 0.0001)
        XCTAssertFalse(g.reached)
        XCTAssertTrue(ProgressSeries.goal(Goal(lift: .deadlift, targetWeight: 185), workouts: w).reached)
        XCTAssertEqual(ProgressSeries.goal(Goal(lift: .deadlift, targetWeight: 0), workouts: w).fraction, 0)
    }

    func testStrengthSummary() {
        let w = TestData.strengthDay(LocalDate(2026, 10, 5), .frontSquat, weights: [65, 80, 95, 105, 115, 125])
        let sum = ProgressSeries.strengthSummary(w.strengthSection)
        XCTAssertEqual(sum?.top, 125)
        XCTAssertEqual(sum?.total, 2925) // matches the Finish mockup
        XCTAssertEqual(ProgressSeries.blockStrip().count, 13)
    }
}

final class TimerTests: XCTestCase {
    func testEveryIntervalPlan() {
        let p = IntervalPlan.everyInterval(seconds: 120, sets: 6)
        XCTAssertEqual(p.totalDuration, 720)
        let s = p.snapshot(at: 312)
        XCTAssertEqual(s.phase?.round, 3)
        XCTAssertEqual(s.remainingInPhase, 48)
        XCTAssertFalse(s.isFinished)
        XCTAssertTrue(p.snapshot(at: 720).isFinished)
        XCTAssertEqual(p.snapshot(at: -5).phaseIndex, 0)
    }

    func testWorkRestHasNoTrailingRest() {
        let p = IntervalPlan.workRest(rounds: 5, work: 240, rest: 60)
        XCTAssertEqual(p.phases.count, 9)
        XCTAssertEqual(p.totalDuration, 5 * 240 + 4 * 60)
        XCTAssertEqual(p.snapshot(at: 250).phase?.kind, .rest)
        XCTAssertEqual(p.snapshot(at: 300).phase?.kind, .work)
        XCTAssertEqual(p.snapshot(at: 300).phase?.round, 2)
        XCTAssertEqual(p.snapshot(at: 120).phaseProgress, 0.5, accuracy: 0.0001)
    }

    func testTransitionsForHaptics() {
        let p = IntervalPlan.workRest(rounds: 2, work: 30, rest: 10)
        XCTAssertEqual(p.phaseStarts, [0, 30, 40])
        XCTAssertEqual(p.transitions(from: 29, to: 31), [1])
        XCTAssertEqual(p.transitions(from: 0, to: 70), [1, 2, 3])
        XCTAssertEqual(p.transitions(from: 10, to: 10), [])
    }

    func testForSection() {
        let tabata = WorkoutSection(kind: .metabolic, format: .tabata, instructions: "", rounds: 8, workSec: 20, restSec: 10,
                                    items: [SectionItem(letter: "A", movementID: "a", movementName: "A"),
                                            SectionItem(letter: "B", movementID: "b", movementName: "B")])
        XCTAssertEqual(IntervalPlan.forSection(tabata)?.totalDuration, 16 * 20 + 15 * 10)
        let amrap = WorkoutSection(kind: .metabolic, format: .amrap, instructions: "", durationMin: 12)
        XCTAssertEqual(IntervalPlan.forSection(amrap)?.totalDuration, 720)
        let strength = WorkoutSection(kind: .strength, format: .everyNMin, instructions: "", intervalSec: 120,
                                      items: [SectionItem(letter: "A", movementID: "deadlift", movementName: "Deadlift",
                                                          plannedSets: (1...6).map { PlannedSet(setNumber: $0, reps: 5, weight: 100) })])
        XCTAssertEqual(IntervalPlan.forSection(strength)?.phases.count, 6)
        XCTAssertNil(IntervalPlan.forSection(WorkoutSection(kind: .warmup, format: .rounds, instructions: "")))
    }

    func testClockPauseResume() {
        var c = TimerClock()
        let t0 = Date(timeIntervalSince1970: 1000)
        c.start(at: t0)
        XCTAssertTrue(c.isRunning)
        c.pause(at: t0.addingTimeInterval(30))
        XCTAssertEqual(c.elapsed(at: t0.addingTimeInterval(500)), 30, accuracy: 0.001)
        c.start(at: t0.addingTimeInterval(100))
        XCTAssertEqual(c.elapsed(at: t0.addingTimeInterval(110)), 40, accuracy: 0.001)
        let upcoming = c.upcomingTransitions(.workRest(rounds: 2, work: 30, rest: 10), now: t0.addingTimeInterval(110))
        XCTAssertEqual(upcoming.map(\.phaseIndex), [3])
        c.reset()
        XCTAssertEqual(c.elapsed(at: t0), 0)
        XCTAssertFalse(c.isRunning)
        XCTAssertEqual(formatClock(161), "2:41")
        XCTAssertEqual(formatClock(-3), "0:00")
    }
}
