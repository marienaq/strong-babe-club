import XCTest
@testable import WorkoutCore

final class PlateCalculatorTests: XCTestCase {
    let calc = PlateCalculator()

    func testCeilingAndStep() {
        XCTAssertEqual(calc.maxLoadable, 230)
        XCTAssertEqual(calc.smallestStep, 5)
        XCTAssertEqual(calc.loadableTotals.first, 45)
    }

    func testEveryFivePoundStepIsLoadable() {
        for w in stride(from: 45.0, through: 230.0, by: 5.0) {
            let l = calc.loadout(for: w)
            XCTAssertNotNil(l, "\(w)")
            if let l { XCTAssertEqual(l.barWeight + 2 * l.perSide.reduce(0, +), w, accuracy: 0.001) }
        }
        XCTAssertEqual(calc.loadableTotals.count, 38)
    }

    func testUnloadableWeights() {
        XCTAssertNil(calc.loadout(for: 47.5))
        XCTAssertNil(calc.loadout(for: 235))
        XCTAssertNil(calc.loadout(for: 40))
    }

    func testMockupLoadoutDescription() {
        XCTAssertEqual(calc.loadout(for: 105)?.description, "bar + 25 + 5 each side")
        XCTAssertEqual(calc.loadout(for: 105)?.sentence, "105 lb = bar + 25 + 5 each side")
        XCTAssertEqual(calc.loadout(for: 45)?.description, "bar only")
        XCTAssertEqual(calc.loadout(for: 230)?.perSide, [25, 25, 15, 10, 10, 5, 2.5])
    }

    func testFewestPlates() {
        // 95 = 25 per side (one plate), not 15 + 10.
        XCTAssertEqual(calc.loadout(for: 95)?.perSide, [25])
        // 85 = 20 per side: 15 + 5 or 10 + 10 (both two plates); heavier first.
        XCTAssertEqual(calc.loadout(for: 85)?.perSide.count, 2)
    }

    func testRoundingModes() {
        XCTAssertEqual(calc.round(102.4).weight, 100)
        XCTAssertEqual(calc.round(102.6).weight, 105)
        XCTAssertEqual(calc.round(47.5).weight, 45, "ties round down")
        XCTAssertEqual(calc.round(101, .up).weight, 105)
        XCTAssertEqual(calc.round(104, .down).weight, 100)
    }

    func testOutOfRangeRequests() {
        let high = calc.round(260)
        XCTAssertEqual(high.weight, 230)
        XCTAssertTrue(high.cappedAtMax)
        let low = calc.round(20)
        XCTAssertEqual(low.weight, 45)
        XCTAssertTrue(low.belowBar)
        XCTAssertEqual(calc.round(.nan).weight, 45)
        XCTAssertEqual(calc.round(.infinity).weight, 45)
    }

    func testStepUp() {
        XCTAssertEqual(calc.step(up: 100), 105)
        XCTAssertEqual(calc.step(up: 100, by: 2), 110)
        XCTAssertEqual(calc.step(up: 230), 230)
    }

    func testCustomBarAndPlates() {
        let c = PlateCalculator(barWeight: 35, platePairs: [10, 5])
        XCTAssertEqual(c.loadableTotals, [35, 45, 55, 65])
        XCTAssertEqual(c.maxLoadable, 65)
        let none = PlateCalculator(barWeight: 45, platePairs: [])
        XCTAssertEqual(none.loadableTotals, [45])
        XCTAssertEqual(none.smallestStep, 0)
        XCTAssertEqual(none.round(100).weight, 45)
    }

    func testCeilingForecast() {
        // Deadlift TM 195 -> e1RM ~217 now, ~239 after 2 blocks: warn.
        let warnings = PlateCeilingWarning.forecast(trainingMaxes: [.deadlift: 195, .pushJerk: 60], calculator: calc, horizonBlocks: 2)
        XCTAssertEqual(warnings.map(\.lift), [.deadlift])
        XCTAssertEqual(warnings.first?.blocksAway, 2)
        XCTAssertTrue(warnings.first?.message.contains("230 lb") ?? false)
        XCTAssertEqual(PlateCeilingWarning.forecast(trainingMaxes: [.deadlift: 210], calculator: calc, horizonBlocks: 2).first?.blocksAway, 0)
        XCTAssertTrue(PlateCeilingWarning.forecast(trainingMaxes: [.deadlift: 150], calculator: calc, horizonBlocks: 2).isEmpty)
    }
}

final class ImplementSnapperTests: XCTestCase {
    let snap = ImplementSnapper()

    func testDumbbellNearestTiesLower() {
        XCTAssertEqual(snap.snapDumbbell(14)?.weight, 15)
        XCTAssertEqual(snap.snapDumbbell(12.5)?.weight, 10)
        XCTAssertEqual(snap.snapDumbbell(5)?.weight, 10)
        XCTAssertEqual(snap.snapDumbbell(22)?.weight, 20)
        XCTAssertNil(snap.snapDumbbell(22)?.note)
    }

    func testHeavyDumbbellBecomesMoreReps() {
        let s = snap.snapDumbbell(30, reps: 10)
        XCTAssertEqual(s?.implement, .dumbbell)
        XCTAssertEqual(s?.weight, 20)
        XCTAssertEqual(s?.reps, 15)
        XCTAssertNotNil(s?.note)
    }

    func testHeavyDumbbellBecomesKettlebellWhenAllowed() {
        let s = snap.snapDumbbell(25, reps: 10, kettlebellAlternative: true)
        XCTAssertEqual(s?.implement, .kettlebell)
        XCTAssertEqual(s?.weight, 26)
        XCTAssertEqual(s?.reps, 10)
        // No close KB: falls back to reps.
        let far = snap.snapDumbbell(45, reps: 10, kettlebellAlternative: true)
        XCTAssertEqual(far?.implement, .dumbbell)
        XCTAssertEqual(far?.reps, 23)
    }

    func testKettlebellSnapping() {
        XCTAssertEqual(snap.snapKettlebell(24)?.weight, 22)
        XCTAssertEqual(snap.snapKettlebell(30)?.weight, 26)
        XCTAssertEqual(snap.snapKettlebell(33)?.weight, 35)
        let heavy = snap.snapKettlebell(53, reps: 10)
        XCTAssertEqual(heavy?.weight, 35)
        XCTAssertEqual(heavy?.reps, 16)
    }

    func testLabelsAndShift() {
        let s = snap.snapDumbbell(20)!
        XCTAssertEqual(s.label(pair: true), "2 × 20 lb")
        XCTAssertEqual(snap.snapKettlebell(35)!.label(pair: false), "35 lb KB")
        XCTAssertEqual(snap.shift(s, by: -1).weight, 15)
        XCTAssertEqual(snap.shift(s, by: 3).weight, 20)
        XCTAssertEqual(snap.shift(snap.snapKettlebell(22)!, by: -1).weight, 22)
    }

    func testEmptyInventory() {
        let empty = ImplementSnapper(dumbbells: [], kettlebells: [])
        XCTAssertNil(empty.snapDumbbell(20))
        XCTAssertNil(empty.snapKettlebell(20))
        let kbOnly = ImplementSnapper(dumbbells: [], kettlebells: [26])
        XCTAssertEqual(kbOnly.snapDumbbell(20, kettlebellAlternative: true)?.implement, .kettlebell)
    }
}

final class LibraryTests: XCTestCase {
    let lib = MovementLibrary.standard

    func testIdsAreUniqueAndSubstitutesExist() {
        XCTAssertEqual(Set(lib.movements.map(\.id)).count, lib.movements.count)
        for m in lib.movements {
            for s in [m.noJumpSubstitute, m.jointSubstitute].compactMap({ $0 }) {
                XCTAssertNotNil(lib[s], "\(m.id) -> \(s)")
            }
            XCTAssertFalse(m.roles.isEmpty)
        }
    }

    func testNoWallBallsOrOverheadThrows() {
        for m in lib.movements {
            XCTAssertFalse(m.name.lowercased().contains("wall ball"))
            XCTAssertFalse(m.name.lowercased().contains("pull-up") && !m.name.contains("Australian"), m.name)
        }
    }

    func testEveryRoleHasLowImpactOptions() {
        let limits = TrainingLimits(avoidJumping: true, easyOnKnee: true, easyOnWrist: true)
        let eq = EquipmentInventory.homeGym.available
        for role in [MovementRole.warmupCardio, .warmupPrimer, .metabolic, .core, .stretch] {
            XCTAssertFalse(lib.movements(with: role).filter { $0.isAllowed(equipment: eq, limits: limits) }.isEmpty, role.rawValue)
        }
    }

    func testNoJumpingSubstitutesBoxJumpWithStepUp() throws {
        let boxJump = try XCTUnwrap(lib["box-jump"])
        let r = try XCTUnwrap(lib.resolve(boxJump, equipment: EquipmentInventory.homeGym.available, limits: TrainingLimits(avoidJumping: true)))
        XCTAssertEqual(r.movement.id, "box-step-up")
        XCTAssertTrue(r.substituted)
        // With knees protected too, step-ups are out and glute bridges come in.
        let r2 = try XCTUnwrap(lib.resolve(boxJump, equipment: EquipmentInventory.homeGym.available,
                                           limits: TrainingLimits(avoidJumping: true, easyOnKnee: true)))
        XCTAssertEqual(r2.movement.id, "glute-bridge")
    }

    func testEquipmentFiltering() throws {
        var inv = EquipmentInventory.homeGym
        inv.kettlebells = []
        let swing = try XCTUnwrap(lib["kb-swing"])
        XCTAssertFalse(swing.isAllowed(equipment: inv.available, limits: TrainingLimits()))
        XCTAssertNil(lib.resolve(swing, equipment: inv.available, limits: TrainingLimits()))
        XCTAssertFalse(EquipmentInventory.homeGym.available.contains(.bike))
    }

    func testSlugAndLookup() {
        XCTAssertEqual(MovementLibrary.slug("KB Swing"), "kb-swing")
        XCTAssertEqual(MovementLibrary.slug("  Up/Down!! "), "up-down")
        XCTAssertEqual(MovementLibrary.slug("Box Jumps (24\")"), "box-jumps-24")
        XCTAssertEqual(MovementLibrary.slug("Ñandú"), "and")
        XCTAssertEqual(lib.lookup(name: "Push Up")?.id, "push-up")
        XCTAssertEqual(lib.lookup(name: "Deadlift")?.id, "deadlift")
        XCTAssertEqual(Lift(movementName: "hang power clean"), .hangPowerClean)
        XCTAssertNil(Lift(movementName: "DB Deadlift"))
    }

    func testInventorySanitizing() {
        var inv = EquipmentInventory.homeGym
        inv.dumbbells = [20, 10, -5, .nan, 10]
        inv.barWeight = 5000
        inv.boxHeights = [24, 400]
        let s = inv.sanitized()
        XCTAssertEqual(s.dumbbells, [10, 20])
        XCTAssertEqual(s.barWeight, 100)
        XCTAssertEqual(s.boxHeights, [24])
    }

    func testSettingsGreeting() {
        XCTAssertEqual(PlannerSettings.default.greetingName, "friend")
        var s = PlannerSettings.default
        s.displayName = "  Sam  "
        XCTAssertEqual(s.greetingName, "Sam")
    }
}

final class NamerTests: XCTestCase {
    func testFormatAndValidity() {
        var rng = SeededRandom(seed: 1)
        let n = WorkoutNamer.name(format: .amrapWithRest, rounds: 5, minutes: 4, using: &rng)
        XCTAssertTrue(n.hasPrefix("amrap-5-4-"), n)
        XCTAssertTrue(WorkoutNamer.isValid(n))
        XCTAssertTrue(WorkoutNamer.isValid("amrap-5-4-fungi"))
        XCTAssertFalse(WorkoutNamer.isValid("AMRAP 5"))
        XCTAssertFalse(WorkoutNamer.isValid("x"))
        XCTAssertFalse(WorkoutNamer.isValid("<script>"))
    }

    func testDeterministicAndAvoidsUsedNames() {
        var a = SeededRandom(seed: 3), b = SeededRandom(seed: 3)
        let n1 = WorkoutNamer.name(format: .tabata, rounds: 8, minutes: 8, using: &a)
        XCTAssertEqual(n1, WorkoutNamer.name(format: .tabata, rounds: 8, minutes: 8, using: &b))
        var c = SeededRandom(seed: 3)
        let n2 = WorkoutNamer.name(format: .tabata, rounds: 8, minutes: 8, using: &c, avoiding: [n1])
        XCTAssertNotEqual(n1, n2)
    }

    func testAllWordsTakenAddsCounter() {
        let all = Set(WorkoutNamer.words.map { "emom-12-12-\($0)" })
        var rng = SeededRandom(seed: 1)
        let n = WorkoutNamer.name(format: .emom, rounds: 12, minutes: 12, using: &rng, avoiding: all)
        XCTAssertTrue(n.hasSuffix("-2"), n)
        XCTAssertFalse(all.contains(n))
    }

    func testWordListIsCurated() {
        XCTAssertGreaterThanOrEqual(WorkoutNamer.words.count, 100)
        XCTAssertEqual(Set(WorkoutNamer.words).count, WorkoutNamer.words.count)
        XCTAssertTrue(WorkoutNamer.words.contains("fungi"))
        XCTAssertTrue(WorkoutNamer.words.allSatisfy { $0.allSatisfy { $0.isLetter && $0.isLowercase } })
    }
}
