import Foundation
import XCTest
@testable import WorkoutCore

/// Regression and scenario tests from the metcon v2 spec (§14.2, §23).
/// Synthetic data only.
final class MetconRegressionTests: XCTestCase {
    let planner = RulesWorkoutPlanner()
    let lib = MovementLibrary.standard
    let oct12 = LocalDate(2026, 10, 12)

    func plan(_ d: LocalDate, settings: PlannerSettings = .default, history: [PlannedWorkout] = [], benchmarks: [Benchmark] = [],
              salt: UInt64 = 0) throws -> PlannedWorkout {
        var salts = SectionSalts()
        salts.metabolic = salt
        return try planner.makePlan(PlanRequest(date: d, settings: settings, history: history, benchmarks: benchmarks, salts: salts,
                                                now: TestData.now))
    }

    func assertRules(_ w: PlannedWorkout, settings: PlannerSettings = .default, file: StaticString = #filePath, line: UInt = #line) {
        let v = MetconChecks.hardRules(w) + MetconChecks.remixRules(w, settings: settings, strict: true)
        XCTAssertTrue(v.isEmpty, v.joined(separator: "\n"), file: file, line: line)
    }

    func item(_ id: String, reps: Int? = nil, weight: Double? = nil) -> SectionItem {
        SectionItem(letter: "A", movementID: id, movementName: lib[id]!.name, reps: reps, prescribedWeight: weight)
    }

    /// The MC-43 benchmark: Back Squats, Up/Downs, Plate Ground to Overhead, 5 × 3-min AMRAP, slot 0.
    func backSquatBenchmark() -> Benchmark {
        let id = UUID()
        let t = WorkoutSection(kind: .metabolic, format: .amrapWithRest, name: "amrap-5-3-squatty", instructions: "5 rounds", rounds: 5,
                               workSec: 180, restSec: 60, benchmarkID: id,
                               items: [item("back-squat", reps: 6, weight: 65), item("up-down", reps: 3), item("plate-ground-to-overhead", reps: 6, weight: 25)])
        return Benchmark(id: id, name: "amrap-5-3-squatty", template: t, quarterSlot: 0)
    }

    /// R1: Oct 12, 2026 never gets a 1-move Tabata (or anything under 3 moves / 12 min).
    func testOctober12NeverTooSmall() throws {
        for salt in UInt64(0)...50 {
            let w = try plan(oct12, salt: salt)
            let m = try XCTUnwrap(w.metabolicSection)
            XCTAssertGreaterThanOrEqual(m.items.count, 3, "salt \(salt)")
            XCTAssertGreaterThanOrEqual(m.estimatedSeconds, 720, "salt \(salt)")
            if m.format == .tabata { XCTAssertEqual([m.workSec, m.restSec], [40, 20]) }
            assertRules(w)
        }
    }

    /// R2 / MC-43: the Back Squat benchmark skips Back Squat day and runs Wednesday.
    func testBackSquatBenchmarkMovesToACompatibleDay() throws {
        let b = backSquatBenchmark()
        let mon = try plan(oct12, benchmarks: [b])
        XCTAssertEqual(mon.mainLift, .backSquat)
        XCTAssertNil(mon.metabolicSection?.benchmarkID, "remix on Back Squat day")
        assertRules(mon)
        var done = mon
        done.status = .done
        let wed = try plan(LocalDate(2026, 10, 14), history: [done], benchmarks: [b])
        XCTAssertEqual(wed.mainLift, .deadlift)
        XCTAssertEqual(wed.metabolicSection?.benchmarkID, b.id)
        let moved = try XCTUnwrap(wed.reasons.first { $0.rule == "benchmark.rescheduled" })
        XCTAssertEqual(moved.text, "amrap-5-3-squatty was due Monday but has Back Squat, and that's Back Squat day. It moved here so it doesn't clash.")
        XCTAssertTrue(MetconChecks.hardRules(wed).isEmpty)
    }

    /// R3 / MC-44: a Front Squat benchmark never lands on a squat day across block 1.
    func testFrontSquatBenchmarkNeverOnSquatDay() throws {
        let id = UUID()
        let t = WorkoutSection(kind: .metabolic, format: .amrap, name: "amrap-1-18-fronty", instructions: "", rounds: 1, durationMin: 18,
                               benchmarkID: id, items: [item("front-squat", reps: 5, weight: 65), item("push-up", reps: 5), item("kb-swing", reps: 8)])
        let b = Benchmark(id: id, name: "amrap-1-18-fronty", template: t, quarterSlot: 0)
        var history: [PlannedWorkout] = []
        var ran: [LocalDate] = []
        var d = oct12
        while d < LocalDate(2027, 1, 18) {
            defer { d = d.adding(days: 1) }
            guard PlannerSettings.default.rotation.isScheduled(d) else { continue }
            var w = try plan(d, history: history, benchmarks: [b])
            if w.metabolicSection?.benchmarkID == b.id {
                ran.append(d)
                XCTAssertNotEqual(w.mainLift?.slot, .squat, "\(d)")
            }
            w.status = .done
            history.append(w)
        }
        XCTAssertEqual(ran.count, 1, "once in block 1")
    }

    /// R4 / MC-41 / MC-42: a 2-move benchmark is never proposed; a stored
    /// one is retired with its template untouched and never scheduled.
    func testTwoMoveBenchmarkIsRetiredNotAltered() throws {
        // Most-done history piece has 2 moves; the next one is valid.
        var history: [PlannedWorkout] = []
        let two = WorkoutSection(kind: .metabolic, format: .amrapWithRest, instructions: "", rounds: 5, workSec: 240, restSec: 60,
                                 items: [item("kb-swing", reps: 10), item("push-up", reps: 5)], roundLogs: [RoundLog(roundNumber: 1, rounds: 4, reps: 0)])
        let three = BenchmarkSchedulerTests.validPiece(.amrap, 0)
        for i in 0..<6 { history.append(PlannedWorkout(date: LocalDate(2025, 1, 6).adding(days: i * 7), status: .done, sections: [two])) }
        for i in 0..<4 { history.append(PlannedWorkout(date: LocalDate(2025, 1, 8).adding(days: i * 7), status: .done, sections: [three])) }
        let proposed = BenchmarkProposer.propose(from: history)
        XCTAssertEqual(proposed.count, 1)
        XCTAssertEqual(proposed.first?.template.items.count, 3)

        let stored = TestData.amrapSection(rounds: [])
        let old = Benchmark(name: "amrap-5-4-twosie", template: stored, quarterSlot: 0)
        let enc = JSONEncoder()
        enc.outputFormatting = .sortedKeys
        let refreshed = BenchmarkMaintenance.refresh([old], history: history)
        let retired = try XCTUnwrap(refreshed.first { $0.id == old.id })
        XCTAssertEqual(retired.retiredReason, "Only 2 moves; metcons need 3–5.")
        XCTAssertFalse(retired.active)
        XCTAssertEqual(try enc.encode(retired.template), try enc.encode(old.template), "template byte for byte")
        XCTAssertEqual(BenchmarkMaintenance.retiredText(retired), "amrap-5-4-twosie was retired: Only 2 moves; metcons need 3–5. Its old scores are kept.")
        // Q5: a replacement from history takes the slot, marked as new.
        let replacement = try XCTUnwrap(refreshed.first { $0.replacesID == old.id })
        XCTAssertEqual(replacement.quarterSlot, 0)
        XCTAssertEqual(replacement.template.items.count, 3)
        XCTAssertEqual(BenchmarkMaintenance.refresh(refreshed, history: history), refreshed, "stable")
        var off = PlannerSettings.default
        off.autoReplaceRetiredBenchmarks = false
        XCTAssertEqual(BenchmarkMaintenance.refresh([old], history: history, settings: off).count, 1)
        // Even if still marked active, it's never scheduled.
        let scheduler = BenchmarkScheduler(calendar: ProgramCalendar())
        XCTAssertTrue(scheduler.dueList(on: LocalDate(2026, 10, 19), benchmarks: [old], history: []).isEmpty)
        XCTAssertNil(try plan(LocalDate(2026, 10, 19), benchmarks: [old]).metabolicSection?.benchmarkID)
    }

    /// Intrinsic issues of §11.1.
    func testBenchmarkValidation() {
        let six = WorkoutSection(kind: .metabolic, format: .amrap, instructions: "", durationMin: 6,
                                 items: [item("air-squat", reps: 10), item("push-up", reps: 5), item("burpee", reps: 3)])
        XCTAssertEqual(BenchmarkValidator.retiredReason(six), "About 6 min; metcons are 12–24 min.")
        var unknown = six
        unknown.durationMin = 15
        unknown.items[0] = SectionItem(letter: "A", movementID: "x", movementName: "Plate Squat")
        XCTAssertEqual(BenchmarkValidator.intrinsicIssues(unknown).first, "\"Plate Squat\" isn't a move the app knows")
        var noArms = six
        noArms.durationMin = 15
        noArms.items = [item("air-squat"), item("burpee"), item("sit-up")]
        XCTAssertEqual(BenchmarkValidator.intrinsicIssues(noArms), ["No arm move"])
        var blocked = noArms
        blocked.items = [item("back-squat"), item("deadlift"), item("push-press")]
        XCTAssertEqual(BenchmarkValidator.intrinsicIssues(blocked), ["It clashes with every lift day in your rotation"])
        XCTAssertTrue(BenchmarkValidator.intrinsicIssues(backSquatBenchmark().template).isEmpty)
    }

    /// MC-45: a benchmark not done by week 12 is caught up in the test weeks, on a compatible day.
    func testTestWeekCatchUp() throws {
        var b = backSquatBenchmark()
        b.quarterSlot = 5 // due from week 11
        var history: [PlannedWorkout] = []
        var ranOn: LocalDate?
        var d = LocalDate(2027, 1, 4) // week 13
        while d < LocalDate(2027, 1, 18) {
            defer { d = d.adding(days: 1) }
            guard PlannerSettings.default.rotation.isScheduled(d) else { continue }
            var w = try plan(d, history: history, benchmarks: [b])
            XCTAssertTrue(w.position!.isTestWeek)
            if w.metabolicSection?.benchmarkID == b.id {
                ranOn = ranOn ?? d
                XCTAssertNotEqual(w.mainLift?.slot, .squat)
            }
            w.status = .done
            history.append(w)
        }
        XCTAssertNotNil(ranOn)
    }

    /// MC-46: a benchmark repeats exactly; only limit swaps change it (marked modified).
    func testBenchmarkIsAnExactRepeat() throws {
        let b = backSquatBenchmark()
        var rng = SeededRandom(seed: 3)
        let (s, subs) = BenchmarkScheduler(calendar: ProgramCalendar()).instantiate(b, settings: .default, library: lib, using: &rng)
        XCTAssertTrue(subs.isEmpty)
        XCTAssertFalse(s.isModified)
        for k in [\WorkoutSection.rounds, \.workSec, \.restSec, \.roundRestSec, \.durationMin] { XCTAssertEqual(s[keyPath: k], b.template[keyPath: k]) }
        XCTAssertEqual(s.name, b.template.name)
        XCTAssertEqual(s.format, b.template.format)
        XCTAssertEqual(s.items.map(\.movementID), b.template.items.map(\.movementID))
        XCTAssertEqual(s.items.map(\.reps), b.template.items.map(\.reps))
        XCTAssertEqual(s.items.map(\.repsScheme), b.template.items.map(\.repsScheme))
        XCTAssertEqual(s.items.map(\.prescribedWeight), b.template.items.map(\.prescribedWeight))
        XCTAssertEqual(s.stimulus, .repeat)
        XCTAssertNotNil(s.expectedScore)
        var knee = PlannerSettings.default
        knee.limits.easyOnWrist = true
        let (m, msubs) = BenchmarkScheduler(calendar: ProgramCalendar()).instantiate(b, settings: knee, library: lib, using: &rng)
        XCTAssertEqual(msubs, ["Up/Downs → Squat to Stand"])
        XCTAssertTrue(m.isModified)
    }

    func roughHistory(before d: LocalDate) -> [PlannedWorkout] {
        let rough = WorkoutFeedback(energy: .sleepy, strengthDifficulty: 5, metabolicDifficulty: 5)
        return (1...3).map { TestData.simple(d.adding(days: -2 * $0), .done, feedback: rough) }
    }

    /// R7 / MC-37: "just show up" is 12-14 min, 3-4 moves, 2 warm-up rounds, lighter, no benchmark.
    func testJustShowUp() throws {
        let d = LocalDate(2026, 10, 19)
        let b = TestData.benchmark(slot: 0)
        for salt in UInt64(0)..<10 {
            let w = try plan(d, history: roughHistory(before: d), benchmarks: [b], salt: salt)
            XCTAssertEqual(w.coachNote?.kind, .justShowUp)
            let m = try XCTUnwrap(w.metabolicSection)
            XCTAssertNil(m.benchmarkID)
            XCTAssertTrue((720...840).contains(m.estimatedSeconds), "\(m.estimatedSeconds)")
            XCTAssertTrue((3...4).contains(m.items.count))
            XCTAssertEqual(w.section(.warmup)?.rounds, 2)
            XCTAssertTrue(w.reasons.contains { $0.rule == "metabolic.lighter" })
            XCTAssertTrue(w.reasons.first { $0.rule == "metabolic.length" }!.text.contains("showing up is the win"))
            if salt == 0 { XCTAssertTrue(w.reasons.contains { $0.rule == "benchmark.deferred" }) }
            assertRules(w)
        }
    }

    /// MC-38: lighter days never go under 12 min or 3 moves.
    func testLighterNeverShorterThanTwelve() throws {
        let d = LocalDate(2026, 11, 2)
        let sleepy = [TestData.simple(d.adding(days: -3), .done, feedback: WorkoutFeedback(energy: .sleepy))]
        let missed = [TestData.simple(d.adding(days: -12), .done)] + [-10, -7, -5, -3].map { TestData.simple(d.adding(days: $0), .skipped) }
        for history in [sleepy, missed, roughHistory(before: d)] {
            let w = try plan(d, history: history)
            XCTAssertGreaterThanOrEqual(w.metabolicSection!.estimatedSeconds, 720)
            XCTAssertGreaterThanOrEqual(w.metabolicSection!.items.count, 3)
        }
    }

    /// R8 / MC-47: test-week metcons are 12-16 min.
    func testTestWeekIsShort() throws {
        for d in [LocalDate(2027, 1, 4), LocalDate(2027, 1, 6), LocalDate(2027, 1, 13)] {
            let w = try plan(d)
            XCTAssertTrue(w.position!.isTestWeek)
            let m = try XCTUnwrap(w.metabolicSection)
            XCTAssertTrue((720...1019).contains(m.estimatedSeconds), "\(d) \(m.estimatedSeconds)")
            XCTAssertTrue([MetconStimulus.grind, .intervals].contains(m.stimulus!))
            assertRules(w)
        }
    }

    /// R9 / MC-33 / MC-34 / MC-35 / MC-36: session targets.
    func testSessionTargets() throws {
        for target in [20, 30, 40, 50, 60] {
            var s = PlannerSettings.default
            s.targetMinutes = target
            var d = LocalDate(2026, 10, 19)
            for _ in 0..<12 {
                defer { d = s.rotation.nextScheduledDate(onOrAfter: d.adding(days: 1)) }
                let w = try plan(d, settings: s)
                let m = try XCTUnwrap(w.metabolicSection)
                XCTAssertGreaterThanOrEqual(m.estimatedSeconds, 720)
                XCTAssertGreaterThanOrEqual(m.items.count, 3)
                XCTAssertGreaterThanOrEqual(w.section(.warmup)!.rounds!, 2)
                let nonMetcon = 9 + WorkoutDuration.estimate(w.strengthSection!) + 6
                XCTAssertLessThanOrEqual(m.estimatedSeconds, max(720, (target - nonMetcon) * 60), "\(target) \(d)")
                XCTAssertEqual(w.durationMin, w.sections.map(WorkoutDuration.estimate).reduce(0, +))
                if w.estimatedMinutes > target {
                    XCTAssertEqual(w.section(.warmup)?.rounds, 2, "warm-up is trimmed first")
                    XCTAssertTrue(w.reasons.contains { $0.rule == "length.over_target" })
                }
                if w.section(.warmup)?.rounds == 2 { XCTAssertTrue(w.reasons.contains { $0.rule == "length.warmup_trimmed" }) }
                assertRules(w, settings: s)
            }
        }
        var tight = PlannerSettings.default
        tight.targetMinutes = 20
        let w = try plan(LocalDate(2026, 10, 19), settings: tight)
        XCTAssertTrue(w.reasons.contains { $0.rule == "length.over_target" && $0.text.contains("12 minutes") })
        XCTAssertEqual(w.section(.warmup)?.rounds, 2)
    }

    /// R12 / MC-39 / MC-40: shuffles keep every rule and the day's length window, and change something.
    func testShuffleKeepsTheRules() throws {
        var d = LocalDate(2026, 10, 19)
        var days = 0
        while days < 30 {
            defer { d = d.adding(days: 3) }
            guard PlannerSettings.default.rotation.isScheduled(d) else { continue }
            days += 1
            let base = try plan(d)
            guard let window = MetconWeekPlan.day(d, settings: .default)?.window else { continue }
            for salt in UInt64(1)...20 {
                let w = try plan(d, salt: salt)
                assertRules(w)
                XCTAssertTrue(window.contains(w.metabolicSection!.estimatedSeconds), "\(d) salt \(salt)")
            }
            let one = try plan(d, salt: 1)
            let a = base.metabolicSection!, b = one.metabolicSection!
            XCTAssertTrue(a.format != b.format || Set(a.items.map(\.movementID)) != Set(b.items.map(\.movementID)), "\(d)")
        }
    }

    /// MC-28: fewer than 3 metcon moves throws a clear error.
    func testTinyPoolThrows() {
        let keep: Set<String> = ["air-squat", "push-up"]
        let moves = MovementLibrary.seed.map { m -> Movement in
            var m = m
            if !keep.contains(m.id) { m.roles.removeAll { $0 == .metabolic } }
            return m
        }
        let small = RulesWorkoutPlanner(library: MovementLibrary(moves))
        XCTAssertThrowsError(try small.makePlan(PlanRequest(date: LocalDate(2026, 10, 19), now: TestData.now))) { e in
            XCTAssertEqual(e as? PlannerError, .metconPoolTooSmall(available: 2))
            XCTAssertEqual((e as? PlannerError)?.userMessage,
                           "Your equipment and limits leave fewer than 3 metcon moves. Add equipment or relax a limit in Settings.")
        }
    }

    /// MC-27: on the pull day the arms move is a pull, whatever the equipment.
    func testPullDay() throws {
        for (name, eq) in MetconYearHarness.equipments {
            var s = PlannerSettings.default
            s.equipment = eq
            let fri = try plan(LocalDate(2026, 10, 23), settings: s)
            XCTAssertTrue(fri.metabolicSection!.items.contains { lib.movement(for: $0)?.armKinds.contains(.pull) == true }, name)
        }
    }

    /// MC-32: deload weeks are one weight step lighter, with "Easy, steady pace."
    func testDeloadWeightsAreLighter() throws {
        let snapper = ImplementSnapper(inventory: .homeGym)
        let plates = Array(Set(EquipmentInventory.homeGym.platePairs)).sorted()
        var d = LocalDate(2026, 12, 28) // block 1 week 12
        var checked = 0
        while d < LocalDate(2027, 1, 2) {
            defer { d = d.adding(days: 1) }
            guard PlannerSettings.default.rotation.isScheduled(d) else { continue }
            let w = try plan(d)
            XCTAssertEqual(w.position?.phase, .deload)
            let m = try XCTUnwrap(w.metabolicSection)
            XCTAssertTrue(m.instructions.contains("Easy, steady pace."))
            XCTAssertTrue(w.reasons.contains { $0.rule == "metabolic.lighter" && $0.text.contains("deload week") })
            for item in m.items {
                guard let mv = lib.movement(for: item), let load = mv.metcon.load, let weight = item.prescribedWeight else { continue }
                checked += 1
                switch mv.implement {
                case .dumbbell:
                    let normal = snapper.snapDumbbell(load, kettlebellAlternative: mv.kettlebellAlternative)!
                    XCTAssertEqual(weight, snapper.shift(normal, by: -1).weight, mv.name)
                case .kettlebell: XCTAssertEqual(weight, snapper.shift(snapper.snapKettlebell(load)!, by: -1).weight, mv.name)
                case .barbell: XCTAssertEqual(weight, plates[max(0, plates.firstIndex(of: load)! - 1)], mv.name)
                default: break
                }
            }
        }
        XCTAssertGreaterThan(checked, 0)
    }

    /// MC-65: back after 30 days off: middle length, lighter, welcome back, for 2 weeks.
    func testComebackMetcon() throws {
        var history = TestData.consistentHistory(from: LocalDate(2026, 8, 3), to: LocalDate(2026, 9, 25))
        var s = PlannerSettings.default
        s.breaks = [TrainingBreak(label: "trip", from: LocalDate(2026, 9, 26), to: LocalDate(2026, 10, 25))]
        var d = LocalDate(2026, 10, 26)
        while d < LocalDate(2026, 11, 20) {
            defer { d = d.adding(days: 1) }
            guard s.rotation.isScheduled(d) else { continue }
            var w = try plan(d, settings: s, history: history)
            let comeback = w.reasons.contains { $0.rule == "metabolic.comeback" }
            let firstTwoWeeks = d < LocalDate(2026, 11, 9)
            XCTAssertEqual(comeback, firstTwoWeeks, "\(d)")
            if firstTwoWeeks {
                XCTAssertLessThanOrEqual(w.metabolicSection!.estimatedSeconds, 1259)
                XCTAssertTrue(w.reasons.contains { $0.rule == "metabolic.lighter" && $0.text.contains("coming back") })
            }
            w.status = .done
            history.append(w)
        }
    }

    /// Owner decision Q1: barbell lifts appear, light, never the day's lift, at most one.
    func testBarbellLiftsInMetcons() throws {
        let tms: [Lift: Double] = [.backSquat: 135, .frontSquat: 120, .deadlift: 180, .hangPowerClean: 95, .pushPress: 95, .pushJerk: 95]
        var seen = 0
        var d = LocalDate(2026, 10, 19)
        while d < LocalDate(2027, 3, 1) {
            defer { d = d.adding(days: 1) }
            guard PlannerSettings.default.rotation.isScheduled(d) else { continue }
            let w = try planner.makePlan(PlanRequest(date: d, trainingMaxes: tms, now: TestData.now))
            let bars = w.metabolicSection!.items.filter { lib.movement(for: $0)?.isBarbellLift == true }
            XCTAssertLessThanOrEqual(bars.count, 1)
            for item in bars {
                seen += 1
                let bb = lib.movement(for: item)!.metcon.barbell!
                XCTAssertNotEqual(item.movementID, w.mainLift?.movementID)
                let target = tms[bb.lift]! * bb.fraction
                XCTAssertEqual(item.prescribedWeight!, target, accuracy: 10, "\(item.movementName) \(item.prescribedWeight!)")
                XCTAssertEqual(PlateCalculator().loadout(for: item.prescribedWeight!) != nil, true)
            }
        }
        XCTAssertGreaterThan(seen, 5)
    }

    /// MC-49 / MC-50 on a sample day: the "Why this?" copy.
    func testWhyThisCopy() throws {
        let w = try plan(LocalDate(2026, 10, 19))
        let texts = Dictionary(w.reasons(for: .metabolic).map { ($0.rule, $0.text) }, uniquingKeysWith: { a, _ in a })
        let m = w.metabolicSection!
        XCTAssertTrue(texts["metabolic.stimulus"]!.hasPrefix(m.stimulus!.title + ": "))
        XCTAssertTrue(texts["metabolic.length"]!.hasPrefix("\(WorkoutDuration.estimate(m)) min today: "))
        XCTAssertTrue(texts["metabolic.slots"]!.hasPrefix("Covers "))
        XCTAssertEqual(texts["metabolic.avoids_lift"], "No loaded squats in here: today is Front Squat day.")
        assertRules(w)
    }
}
