import Foundation
import XCTest
@testable import WorkoutCore

/// Movement tags, aliases and substitutions (spec §4, MC-1-MC-5, MC-54).
final class MetconTagTests: XCTestCase {
    let lib = MovementLibrary.standard

    /// MC-1: every metcon move is fully tagged.
    func testTagCompleteness() {
        for m in lib.movements where m.has(.metabolic) || m.has(.benchmarkOnly) {
            XCTAssertFalse(m.fills.isEmpty, m.id)
            if !m.metconTimedOnly { XCTAssertGreaterThan(m.secondsPerRep, 0, m.id) }
            XCTAssertGreaterThanOrEqual(m.repRange.lowerBound, 1, m.id)
            if m.fills.contains(.legs) { XCTAssertNotNil(m.legKind, m.id) }
            if m.fills.contains(.arms) { XCTAssertNotNil(m.armKind, m.id) }
        }
    }

    /// One row per move: id | fills | leg kind | arm kinds (+oh) | s/rep | reps | flags | conflicts.
    /// s/rep is the athlete-calibrated value of §17.2 (MC-54).
    static let table = """
    jumping-jack|heart|||1.1|10-30|HI|
    toe-tap|heart|||0.6|10-40|2|
    burpee|heart|||4.6|3-10|HI|
    up-down|heart|||2.5|3-10||
    squat-thrust-hold|heart,legs|squat||2.6|4-12||
    high-knees|heart|||0.5|20-50|HI,2|
    marching-knees|heart|||0.5|20-50|2|
    mountain-climber|heart,core|||0.6|10-40|2|
    bike-cal|heart|||4.2|5-20||
    box-jump|heart,legs|squat||2.8|3-10|HI,T|
    air-squat|legs|squat||1.6|6-20||
    goblet-squat|legs|squat||2.5|5-15|G|sq
    lunge|legs|lunge||1.7|6-20|2|
    db-reverse-lunge|legs|lunge||2.3|6-16|2,G|
    bench-step-up|legs|lunge||1.9|6-20|2|
    box-step-up|legs|lunge||1.9|6-20|2|
    db-split-squat|legs|lunge||2.6|6-12|2,G|
    glute-bridge|legs|hinge||1.6|8-20||
    db-glute-bridge|legs|hinge||1.9|8-20||hp
    kb-deadlift|legs|hinge||1.9|6-15|G|hp
    db-rdl|legs|hinge||2.3|6-12|G|hp
    kb-swing|legs,heart|hinge||1.8|6-20|G|
    db-snatch|legs,arms,heart|hinge|pull,oh|1.6|6-16|2,G,S,T|
    db-hang-squat-clean|legs,arms|squat|pull|2.5|4-10|G,T|sq,hp
    db-thruster|legs,arms,heart|squat|push,oh|2.5|5-12|S|sq,oh
    plate-ground-to-overhead|legs,arms|hinge|push,oh|2.1|5-12|S|
    kb-high-pull|legs,arms|hinge|pull|2.1|6-15|G|hp
    med-ball-slam|heart,core|||2.1|6-15||
    push-up|arms||push|2.5|3-12||
    db-floor-press|arms||push|2.1|6-15||
    db-bench-press|arms||push|2.1|6-15||
    db-push-press|arms||push,oh|1.7|5-12|S|oh
    db-strict-press|arms||push,oh|2.1|5-12|S|oh
    tricep-dip|arms||push|1.9|6-15||
    wall-walk|arms,core||push,oh|12.6|1-5|S,T|oh
    db-row|arms||pull|2.1|6-16|2,G|
    australian-pull-up|arms||pull|3.2|3-12|G|
    sit-up|core|||1.6|6-20||
    v-up|core|||2.1|5-15||
    leg-raise|core|||2.1|6-15||
    lemon-squeezer|core|||1.9|6-15||
    russian-twist|core|||0.8|10-30|2|
    flutter-kick|core|||0.5|10-40|2|
    bear-crawl|agility,core|||0.8|10-30|S|
    kb-farmer-carry|core|||0.8|10-40|2,G|
    db-front-squat|legs|squat||2.5|5-15|G|sq
    db-step-up|legs|lunge||2.1|6-16|2,G|
    db-front-rack-lunge|legs|lunge||2.3|6-16|2,G|
    overhead-plate-lunge|legs,arms|lunge|push,oh|2.3|6-12|2,S|oh
    db-deadlift|legs|hinge||1.9|6-15|G|hp
    db-ground-to-overhead|legs,arms|hinge|push,oh|2.3|5-12|S|
    db-curl-press|arms||pull,push,oh|2.5|5-12|S|oh
    db-hang-clean-push-press|legs,arms|hinge|push,oh|2.7|4-10|G,S,T|hp,oh
    db-bent-over-row|arms||pull|2.1|6-15|G|
    prone-swimmer|arms||pull|1.6|6-16||
    hand-release-push-up|arms||push|3.7|3-10||
    lateral-bench-step-over|agility,heart|||1.6|6-20||
    skater|agility,heart|||0.8|10-30|HI,2|
    skater-step|agility|||1.1|10-30|2|
    lateral-shuffle-touch|agility,heart|||1.6|6-20|2|
    kb-overhead-swing|legs,heart,arms|hinge|push,oh|2.0|6-15|G,S|oh
    """

    /// MC-2 and MC-54: tags match the spec tables exactly.
    func testTagValuesMatchTheTables() throws {
        let slots: [String: LiftSlot] = ["sq": .squat, "hp": .hipPull, "oh": .overhead]
        for row in Self.table.split(separator: "\n") {
            let f = row.trimmingCharacters(in: .whitespaces).split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            let m = try XCTUnwrap(lib[f[0]], f[0])
            XCTAssertEqual(m.fills, Set(f[1].split(separator: ",").compactMap { MetconSlot(rawValue: String($0)) }), m.id)
            XCTAssertEqual(m.legKind, LegKind(rawValue: f[2]), m.id)
            let arms = f[3].split(separator: ",").map(String.init)
            XCTAssertEqual(m.armKinds, arms.compactMap(ArmKind.init(rawValue:)), m.id)
            XCTAssertEqual(m.overhead, arms.contains("oh"), m.id)
            XCTAssertEqual(m.secondsPerRep, Double(f[4])!, accuracy: 1e-9, m.id)
            let r = f[5].split(separator: "-").map { Int($0)! }
            XCTAssertEqual(m.repRange, r[0]...r[1], m.id)
            let flags = Set(f[6].split(separator: ",").map(String.init))
            XCTAssertEqual(m.highImpact, flags.contains("HI"), m.id)
            XCTAssertEqual(m.gripHeavy, flags.contains("G"), m.id)
            XCTAssertEqual(m.shoulderHeavy, flags.contains("S"), m.id)
            XCTAssertEqual(m.technical, flags.contains("T"), m.id)
            XCTAssertEqual(m.countsEachSide, flags.contains("2"), m.id)
            XCTAssertEqual(m.conflictsWith, Set(f[7].split(separator: ",").compactMap { slots[String($0)] }), m.id)
        }
        for id in ["plank-hold", "hollow-hold"] {
            XCTAssertEqual(lib[id]?.fills, [.core])
            XCTAssertTrue(lib[id]!.metconTimedOnly)
        }
    }

    /// MC-3 (tags) and Q1: the main lifts are tagged with their own slot;
    /// barbell lifts are loaded from a training max; two moves stay benchmark-only.
    func testMainLiftsAndBarbellMoves() {
        let expected: [String: (Set<MetconSlot>, LegKind?, ArmKind?, LiftSlot)] = [
            "back-squat": ([.legs], .squat, nil, .squat), "front-squat": ([.legs], .squat, nil, .squat),
            "deadlift": ([.legs], .hinge, nil, .hipPull), "hang-power-clean": ([.legs, .arms], .hinge, .pull, .hipPull),
            "push-press": ([.arms], nil, .push, .overhead), "push-jerk": ([.arms], nil, .push, .overhead),
            "power-clean": ([.legs, .arms], .hinge, .pull, .hipPull), "barbell-shoulder-press": ([.arms], nil, .push, .overhead),
            "db-curl": ([.arms], nil, .pull, .squat),
        ]
        for (id, e) in expected {
            let m = lib[id]!
            XCTAssertEqual(m.fills, e.0, id)
            XCTAssertEqual(m.legKind, e.1, id)
            XCTAssertEqual(m.armKind, e.2, id)
            if id != "db-curl" { XCTAssertEqual(m.conflictsWith, [e.3], id) }
        }
        for lift in Lift.allCases {
            XCTAssertTrue(lib[lift.movementID]!.has(.mainLift))
            XCTAssertEqual(lib[lift.movementID]!.metcon.barbell?.fraction, lift.slot == .squat || lift == .deadlift ? 0.5 : 0.55)
        }
        XCTAssertTrue(lib["kb-overhead-swing"]!.has(.benchmarkOnly))
        XCTAssertTrue(lib["db-curl"]!.has(.benchmarkOnly))
        XCTAssertEqual(lib["bear-crawl"]?.jointSubstitute, "skater-step")
    }

    /// §19.2 metcon default loads (warm-up weights are unchanged).
    func testDefaultLoads() {
        let loads: [String: Double] = [
            "kb-swing": 35, "goblet-squat": 35, "plate-ground-to-overhead": 25, "db-thruster": 20, "db-push-press": 20, "db-snatch": 20,
            "db-bench-press": 20, "db-floor-press": 20, "db-hang-squat-clean": 20, "db-rdl": 20, "db-row": 20, "db-bent-over-row": 20,
            "db-front-squat": 20, "db-deadlift": 20, "db-hang-clean-push-press": 20, "db-front-rack-lunge": 20, "db-curl-press": 15,
            "db-ground-to-overhead": 15, "db-step-up": 10, "db-strict-press": 10, "db-reverse-lunge": 15, "db-split-squat": 15,
            "overhead-plate-lunge": 15, "kb-deadlift": 35, "kb-farmer-carry": 35, "kb-high-pull": 26, "med-ball-slam": 12,
        ]
        for (id, w) in loads { XCTAssertEqual(lib[id]?.metcon.load, w, id) }
        XCTAssertEqual(lib["kb-swing"]?.defaultWeight, 26, "warm-up weight unchanged")
        XCTAssertEqual(lib["goblet-squat"]?.defaultWeight, 26, "accessory weight unchanged")
    }

    /// MC-4: every coach-style name resolves.
    func testAliases() {
        let names: [String: String] = [
            "Up/Down": "up-down", "Push Up": "push-up", "KB Swing": "kb-swing", "Russian KB Swing": "kb-swing", "Burpee": "burpee",
            "Deadlift": "deadlift", "Back Squat": "back-squat", "Front Squat": "front-squat", "Hang Power Clean": "hang-power-clean",
            "Push Press": "push-press", "Push Jerk": "push-jerk", "Sit Up": "sit-up", "Strict Sit Up": "sit-up",
            "DB Push Press": "db-push-press", "Plate Ground To Overhead": "plate-ground-to-overhead", "Goblet Squat": "goblet-squat",
            "KB Goblet Squat": "goblet-squat", "DB Goblet Squat": "goblet-squat", "Single Arm DB Power Snatch": "db-snatch",
            "DB Power Snatch": "db-snatch", "Jumping Jack": "jumping-jack", "Lunge": "lunge", "Forward Lunge": "lunge",
            "Reverse Lunge": "lunge", "Bench Step Up": "bench-step-up", "Step Up": "bench-step-up", "Air Squat": "air-squat",
            "V-Up": "v-up", "DB Curl + DB Press": "db-curl-press", "Power Clean": "power-clean", "DB Bench Press": "db-bench-press",
            "DB Front Squat": "db-front-squat", "Bench Jump": "box-jump", "Overhead KB Swing": "kb-overhead-swing",
            "DB Front Rack Lunge": "db-front-rack-lunge", "DB Lunge": "db-front-rack-lunge", "Shoulder Press": "barbell-shoulder-press",
            "Overhead Plate Lunge": "overhead-plate-lunge", "DB Hang Squat Clean": "db-hang-squat-clean",
            "DB Ground To Overhead": "db-ground-to-overhead", "DB Step Up": "db-step-up", "DB Bench Step Up": "db-step-up",
            "Australian Pull Up": "australian-pull-up", "DB Hang Power Clean + Push Press": "db-hang-clean-push-press",
            "DB Deadlift": "db-deadlift", "DB Thruster": "db-thruster", "Lemon Squeezer": "lemon-squeezer", "DB Curl": "db-curl",
            "Toe Tap": "toe-tap", "Leg Raise": "leg-raise", "Wall Walk": "wall-walk",
        ]
        for (name, id) in names { XCTAssertEqual(lib.lookup(name: name)?.id, id, name) }
        // Plural forms and display names still work.
        XCTAssertEqual(lib.lookup(name: "Push Ups")?.id, "push-up")
        XCTAssertEqual(lib.lookup(name: "Front Squats")?.id, "front-squat")
        XCTAssertNil(lib.lookup(name: "Underwater Basket Weaving"))
    }

    /// MC-5: every substitution keeps a slot of the original, for every
    /// limit combination and equipment set.
    func testSubstituteChainsKeepASlot() {
        for m in lib.movements where m.has(.metabolic) {
            for limits in MetconYearHarness.limitCombos {
                for (name, eq) in MetconYearHarness.equipments {
                    guard let r = lib.resolve(m, equipment: eq.available, limits: limits) else { continue }
                    XCTAssertTrue(r.movement.isAllowed(equipment: eq.available, limits: limits), "\(m.id) \(name)")
                    XCTAssertFalse(r.movement.fills.isDisjoint(with: m.fills), "\(m.id) → \(r.movement.id)")
                }
            }
        }
    }
}
