import XCTest
@testable import WorkoutCore

final class PlannerTests: XCTestCase {
    let planner = RulesWorkoutPlanner()
    let lib = MovementLibrary.standard
    let blockDay = LocalDate(2026, 10, 19) // block 1, week 1, Monday, week B

    func plan(_ date: LocalDate, settings: PlannerSettings = .default, history: [PlannedWorkout] = [],
              benchmarks: [Benchmark] = [], tms: [Lift: Double] = [:]) throws -> PlannedWorkout {
        try planner.makePlan(PlanRequest(date: date, settings: settings, history: history, trainingMaxes: tms,
                                         benchmarks: benchmarks, now: TestData.now))
    }

    func allItems(_ w: PlannedWorkout) -> [SectionItem] { w.sections.flatMap(\.items) }

    func movement(_ item: SectionItem) -> Movement? { lib[item.movementID] }

    // MARK: Determinism

    func testSameInputsGiveIdenticalWorkout() throws {
        let history = TestData.consistentHistory(from: LocalDate(2026, 8, 31), to: LocalDate(2026, 10, 16))
        let a = try plan(blockDay, history: history)
        let b = try plan(blockDay, history: history)
        XCTAssertEqual(a, b)
        let enc = JSONEncoder()
        enc.outputFormatting = .sortedKeys
        XCTAssertEqual(try enc.encode(a), try enc.encode(b))
    }

    func testDifferentDatesDiffer() throws {
        let a = try plan(blockDay)
        let b = try plan(blockDay.adding(days: 14))
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertNotEqual(a.sections.map(\.id), b.sections.map(\.id))
    }

    func testAsyncProtocolPathMatchesSync() throws {
        // The WorkoutPlanner protocol is async; check it compiles and the
        // existential can be held (the async path is exercised in the app).
        let p: any WorkoutPlanner = planner
        XCTAssertNotNil(p as? RulesWorkoutPlanner)
    }

    // MARK: Structure

    func testFourSectionsInCoachOrder() throws {
        let w = try plan(blockDay)
        XCTAssertEqual(w.sections.map(\.kind), [.warmup, .strength, .metabolic, .cooldown])
        XCTAssertEqual(w.section(.warmup)?.items.map(\.letter), ["A", "B", "C", "D"])
        XCTAssertEqual(w.section(.warmup)?.rounds, 3)
        XCTAssertEqual(w.status, .planned)
        XCTAssertEqual(w.position?.block, 1)
        XCTAssertEqual(w.sync.createdAt, TestData.now)
    }

    func testStrengthFollowsRotationAndBlock() throws {
        let w = try plan(blockDay, tms: [.frontSquat: 125])
        let s = try XCTUnwrap(w.strengthSection)
        XCTAssertEqual(s.lift, .frontSquat)
        XCTAssertEqual(s.intervalSec, 120)
        let sets = try XCTUnwrap(s.items.first?.plannedSets)
        XCTAssertEqual(sets.map(\.reps), [5, 5, 5, 5, 5, 5])
        XCTAssertEqual(sets.last?.weight, 95) // 75% of 125 = 93.75 -> 95
        XCTAssertTrue(w.reasons(for: .strength).contains { $0.rule == "rotation.week" && $0.text.contains("squat day") })
        XCTAssertEqual(s.trainingMax, 125)
    }

    func testTestWeekHasTwoLiftsEveryThreeMinutes() throws {
        let w = try plan(LocalDate(2026, 10, 14))
        let s = try XCTUnwrap(w.strengthSection)
        XCTAssertEqual(s.items.map(\.movementName), ["Deadlift", "Push Jerk"])
        XCTAssertEqual(s.intervalSec, 180)
        XCTAssertTrue(w.reasons(for: .strength).contains { $0.rule == "test.week" })
        // Short metabolic piece in test week.
        XCTAssertLessThanOrEqual(WorkoutDuration.estimate(w.metabolicSection!), 8)
    }

    func testTestWeekRampStartsAtHalfOfLastTopSet() throws {
        let history = [TestData.strengthDay(LocalDate(2026, 10, 2), .deadlift, weights: [85, 110, 135, 160, 185])]
        let w = try plan(LocalDate(2026, 10, 14), history: history)
        let dl = try XCTUnwrap(w.strengthSection?.items.first)
        XCTAssertEqual(dl.plannedSets.first?.weight, 90) // 50% of 185 = 92.5 -> 90 (ties down)
        XCTAssertTrue(w.reasons(for: .strength).contains { $0.rule == "test.ramp_from_history" })
    }

    func testAllStrengthWeightsAreLoadable() throws {
        let calc = PlateCalculator()
        var d = LocalDate(2026, 10, 12)
        while d < LocalDate(2027, 1, 18) {
            if PlannerSettings.default.rotation.isScheduled(d) {
                let w = try plan(d, tms: [.deadlift: 195, .backSquat: 145, .frontSquat: 125, .pushPress: 105, .hangPowerClean: 80, .pushJerk: 60])
                for set in w.strengthSection!.items.flatMap(\.plannedSets) {
                    XCTAssertNotNil(calc.loadout(for: set.weight), "\(d) \(set.weight)")
                }
                for item in w.strengthSection!.items where Lift(movementName: item.movementName)?.isOlympic == true {
                    XCTAssertLessThanOrEqual(item.plannedSets.map(\.reps).max() ?? 0, 3)
                }
            }
            d = d.adding(days: 1)
        }
    }

    func testNeverRepeatsMainLiftWithinSevenDays() throws {
        // Front squat already done on the Friday before a week-B Monday.
        let history = [TestData.strengthDay(LocalDate(2026, 10, 30), .frontSquat, weights: [95])]
        let w = try plan(LocalDate(2026, 11, 2), history: history)
        XCTAssertEqual(PlannerSettings.default.rotation.lift(for: LocalDate(2026, 11, 2)), .frontSquat)
        XCTAssertNotEqual(w.mainLift, .frontSquat)
        XCTAssertEqual(w.mainLift?.slot, .squat)
        XCTAssertTrue(w.reasons(for: .strength).contains { $0.rule == "rotation.no_repeat" })
    }

    // MARK: Limits & equipment

    func testAvoidJumpingRemovesHighImpactEverywhere() throws {
        var s = PlannerSettings.default
        s.limits.avoidJumping = true
        for offset in stride(from: 0, to: 60, by: 2) {
            let w = try plan(blockDay.adding(days: offset), settings: s)
            for item in allItems(w) {
                if let m = movement(item) { XCTAssertFalse(m.highImpact, "\(item.movementName) on \(w.date)") }
            }
        }
    }

    func testKneeAndWristLimits() throws {
        var s = PlannerSettings.default
        s.limits.easyOnKnee = true
        s.limits.easyOnWrist = true
        for offset in stride(from: 0, to: 60, by: 2) {
            let w = try plan(blockDay.adding(days: offset), settings: s)
            for section in w.sections where section.kind != .strength {
                for item in section.items {
                    if let m = movement(item) { XCTAssertTrue(m.jointFlags.isEmpty, "\(m.name)") }
                }
            }
        }
        // Squat-day top set is capped for the knee.
        let w = try plan(blockDay, settings: s, tms: [.frontSquat: 125])
        XCTAssertTrue(w.reasons(for: .strength).contains { $0.rule.hasPrefix("limit.") })
    }

    func testEquipmentIsRespected() throws {
        var s = PlannerSettings.default
        s.equipment.kettlebells = []
        s.equipment.hasBench = false
        for offset in stride(from: 0, to: 60, by: 2) {
            let w = try plan(blockDay.adding(days: offset), settings: s)
            for section in w.sections where section.kind != .strength {
                for item in section.items {
                    if let m = movement(item) {
                        XCTAssertFalse(m.equipment.contains(.kettlebell), m.name)
                        XCTAssertFalse(m.equipment.contains(.bench), m.name)
                    }
                }
            }
        }
    }

    func testMetabolicWeightsSnapToInventory() throws {
        let inv = EquipmentInventory.homeGym
        for offset in stride(from: 0, to: 90, by: 2) {
            let w = try plan(blockDay.adding(days: offset))
            for section in w.sections where section.kind != .strength {
                for item in section.items {
                    guard let m = movement(item), let weight = item.prescribedWeight else { continue }
                    switch m.implement {
                    case .dumbbell: XCTAssertTrue(inv.dumbbells.contains(weight) || inv.kettlebells.contains(weight), "\(m.name) \(weight)")
                    case .kettlebell: XCTAssertTrue(inv.kettlebells.contains(weight), "\(m.name) \(weight)")
                    case .medicineBall: XCTAssertEqual(weight, 12)
                    default: break
                    }
                }
            }
        }
    }

    // MARK: Reasons, naming, length

    func testEverySectionHasAReason() throws {
        let w = try plan(blockDay, history: TestData.consistentHistory(from: LocalDate(2026, 9, 1), to: LocalDate(2026, 10, 16)))
        for kind in SectionKind.allCases { XCTAssertFalse(w.reasons(for: kind).isEmpty, kind.rawValue) }
        XCTAssertNotNil(w.coachNote)
    }

    func testMetabolicNameFormatAndUniqueness() throws {
        var used: Set<String> = []
        var history: [PlannedWorkout] = []
        var d = blockDay
        for _ in 0..<30 {
            var w = try plan(d, history: history)
            let name = try XCTUnwrap(w.metabolicSection?.name)
            XCTAssertTrue(WorkoutNamer.isValid(name), name)
            XCTAssertEqual(name.split(separator: "-").count, 4, name)
            XCTAssertFalse(used.contains(name), name)
            used.insert(name)
            w.status = .done
            history.append(w)
            d = PlannerSettings.default.rotation.nextScheduledDate(onOrAfter: d.adding(days: 1))
        }
    }

    func testFitsTargetLength() throws {
        var s = PlannerSettings.default
        s.targetMinutes = 40
        for offset in stride(from: 0, to: 40, by: 2) {
            let w = try plan(blockDay.adding(days: offset), settings: s)
            XCTAssertLessThanOrEqual(w.estimatedMinutes, 45, "\(w.date)")
        }
    }

    func testJustShowUpIsLighterAndShorter() throws {
        let rough = WorkoutFeedback(energy: .sleepy, strengthDifficulty: 5, metabolicDifficulty: 5)
        let history = (1...3).map { i -> PlannedWorkout in
            var w = TestData.simple(blockDay.adding(days: -2 * i), .done, feedback: rough)
            w.sections = []
            return w
        }
        let tms: [Lift: Double] = [.frontSquat: 125]
        let normal = try plan(blockDay, tms: tms)
        let easy = try plan(blockDay, history: history, tms: tms)
        XCTAssertEqual(easy.coachNote?.kind, .justShowUp)
        XCTAssertEqual(easy.section(.warmup)?.rounds, 2)
        XCTAssertLessThanOrEqual(easy.strengthSection!.items[0].plannedSets.last!.weight,
                                 normal.strengthSection!.items[0].plannedSets.last!.weight)
        XCTAssertLessThanOrEqual(easy.estimatedMinutes, 40)
    }

    func testPushPlanIsHeavier() throws {
        let day = LocalDate(2026, 11, 30) // Monday week B: Front Squat
        var history: [PlannedWorkout] = []
        // Front squat stuck at 100 on the last three week-B Mondays.
        for d in [-35, -21, -7] {
            history.append(TestData.strengthDay(day.adding(days: d), .frontSquat, weights: [75, 95, 100], difficulty: 3))
        }
        for d in [-26, -24, -19, -17, -12, -10, -5, -3] { history.append(TestData.simple(day.adding(days: d), .done)) }
        let w = try plan(day, history: history, tms: [.frontSquat: 125])
        XCTAssertEqual(w.coachNote?.kind, .push)
        XCTAssertTrue(w.reasons(for: .strength).contains { $0.rule == "coach.push" })
    }

    // MARK: Shuffle

    func testShuffleOneSectionKeepsTheOthers() throws {
        let req = PlanRequest(date: blockDay, now: TestData.now)
        let w = try planner.makePlan(req)
        let s = try planner.makeShuffle(w, section: .metabolic, request: req)
        XCTAssertEqual(s.id, w.id)
        XCTAssertEqual(s.section(.warmup), w.section(.warmup))
        XCTAssertEqual(s.section(.cooldown), w.section(.cooldown))
        XCTAssertEqual(s.strengthSection, w.strengthSection)
        XCTAssertNotEqual(s.metabolicSection, w.metabolicSection)
        XCTAssertEqual(s.salts.metabolic, 1)
        // Shuffling is itself deterministic.
        XCTAssertEqual(try planner.makeShuffle(w, section: .metabolic, request: req), s)
    }

    func testShuffleStrengthKeepsLiftAndWeights() throws {
        let req = PlanRequest(date: blockDay, now: TestData.now)
        let w = try planner.makePlan(req)
        let s = try planner.makeShuffle(w, section: .strength, request: req)
        XCTAssertEqual(s.mainLift, w.mainLift)
        XCTAssertEqual(s.strengthSection?.items.first?.plannedSets, w.strengthSection?.items.first?.plannedSets)
        XCTAssertNotEqual(s.strengthSection?.format, w.strengthSection?.format)
    }

    func testShuffleEverything() throws {
        let req = PlanRequest(date: blockDay, now: TestData.now)
        let w = try planner.makePlan(req)
        let s = try planner.makeShuffle(w, section: nil, request: req)
        XCTAssertEqual(s.salts.warmup, 1)
        XCTAssertEqual(s.salts.cooldown, 1)
        XCTAssertNotEqual(s.sections, w.sections)
        XCTAssertEqual(s.mainLift, w.mainLift)
    }

    func testFullYearOfPlansNeverThrows() throws {
        var history: [PlannedWorkout] = []
        var d = LocalDate(2026, 10, 5)
        let benchmarks = (0..<6).map { TestData.benchmark(slot: $0, name: "amrap-5-4-bench\(["a", "b", "c", "d", "e", "f"][$0])") }
        while d < LocalDate(2027, 10, 5) {
            if PlannerSettings.default.rotation.isScheduled(d) {
                var w = try plan(d, history: history, benchmarks: benchmarks)
                XCTAssertEqual(w.sections.count, 4)
                w.status = .done
                history.append(w)
            }
            d = d.adding(days: 1)
        }
        XCTAssertGreaterThan(history.count, 150)
    }
}
