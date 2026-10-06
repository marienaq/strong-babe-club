import XCTest
@testable import WorkoutCore

/// Log rows must match the prescription for every metabolic format.
final class PrescribedRoundsTests: XCTestCase {
    func section(_ f: SectionFormat, rounds: Int? = nil, work: Int? = nil, rest: Int? = nil, minutes: Int? = nil,
                 moves: Int = 2, scheme: String? = nil) -> WorkoutSection {
        WorkoutSection(kind: .metabolic, format: f, instructions: "", rounds: rounds, workSec: work, restSec: rest, durationMin: minutes,
                       items: (0..<moves).map { SectionItem(letter: "ABCD".map(String.init)[$0], movementID: "m\($0)", movementName: "M\($0)",
                                                            repsScheme: scheme) })
    }

    func workPhases(_ s: WorkoutSection) -> Int? {
        IntervalPlan.forSection(s)?.phases.filter { $0.kind == .work }.count
    }

    func testTabataIsRoundsTimesMoves() {
        let s = section(.tabata, rounds: 8, work: 20, rest: 10, minutes: 8, moves: 2)
        XCTAssertEqual(s.prescribedRounds, 16)
        XCTAssertEqual(workPhases(s), 16)
    }

    func testIntervalAmrapWithRestAndEmom() {
        let interval = section(.interval, rounds: 6, work: 40, rest: 20, moves: 3)
        XCTAssertEqual(interval.prescribedRounds, 6)
        XCTAssertEqual(workPhases(interval), 6)
        let amrap = section(.amrapWithRest, rounds: 5, work: 240, rest: 60, moves: 3)
        XCTAssertEqual(amrap.prescribedRounds, 5)
        XCTAssertEqual(workPhases(amrap), 5)
        let emom = section(.emom, rounds: 12, work: 60, minutes: 12, moves: 3)
        XCTAssertEqual(emom.prescribedRounds, 12)
        XCTAssertEqual(workPhases(emom), 12)
    }

    func testSingleAmrapAndLadders() {
        XCTAssertEqual(section(.amrap, rounds: 1, minutes: 12).prescribedRounds, 1)
        XCTAssertEqual(section(.forTime, minutes: 15, scheme: "21-15-9").prescribedRounds, 3)
        XCTAssertEqual(section(.forTime, minutes: 15, scheme: "10-8-6-4-2").prescribedRounds, 5)
        XCTAssertEqual(section(.ladder, scheme: "10-9-8-7-6-5-4-3-2-1").prescribedRounds, 10)
        XCTAssertEqual(section(.forTime).prescribedRounds, 1)
    }

    /// Every planner-built metabolic piece: log rows == timer work rounds
    /// (or ladder rungs / a single AMRAP row).
    func testPlannerSectionsAgreeWithTimer() throws {
        let planner = RulesWorkoutPlanner()
        var seen: Set<SectionFormat> = []
        var d = LocalDate(2026, 10, 19)
        for _ in 0..<120 {
            if PlannerSettings.default.rotation.isScheduled(d) {
                let w = try planner.makePlan(PlanRequest(date: d, now: TestData.now))
                let m = try XCTUnwrap(w.metabolicSection)
                seen.insert(m.format)
                switch m.format {
                case .interval, .tabata, .emom, .amrapWithRest:
                    XCTAssertEqual(m.prescribedRounds, workPhases(m), "\(m.format) on \(d)")
                    if m.format == .tabata { XCTAssertEqual(m.prescribedRounds, (m.rounds ?? 0) * m.items.count) }
                case .forTime:
                    XCTAssertEqual(m.prescribedRounds, m.items.first?.repsScheme?.split(separator: "-").count)
                case .amrap:
                    XCTAssertEqual(m.prescribedRounds, 1)
                default:
                    XCTFail("unexpected format \(m.format)")
                }
            }
            d = d.adding(days: 1)
        }
        XCTAssertTrue(seen.isSuperset(of: [.tabata, .interval, .amrapWithRest]), "\(seen)")
    }

    func testTabataInstructionsMatch() {
        let t = FormatLibrary.metabolic.first { $0.format == .tabata }!
        XCTAssertTrue(t.instructions.contains("per move"), t.instructions)
    }
}

final class TimerCueTests: XCTestCase {
    func testWorkRestCues() {
        let p = IntervalPlan.workRest(rounds: 2, work: 30, rest: 10)
        XCTAssertEqual((0...p.phases.count).map { p.cue(enteringPhase: $0) }, [.workStart, .roundEndRest, .workStart, .finished])
    }

    func testEveryIntervalCues() {
        let p = IntervalPlan.everyInterval(seconds: 120, sets: 3)
        XCTAssertEqual((0...3).map { p.cue(enteringPhase: $0) }, [.workStart, .roundEndWork, .roundEndWork, .finished])
        XCTAssertNil(p.cue(enteringPhase: -1))
        XCTAssertNil(IntervalPlan(phases: []).cue(enteringPhase: 0))
    }

    func testCuesAreDistinctFiles() {
        let files = SoundPack.allCases.flatMap { p in TimerCue.allCases.map { $0.soundFile(pack: p) } }
        XCTAssertEqual(Set(files).count, 20)
        XCTAssertEqual(TimerCue.roundEndRest.soundFile(pack: .arcade), "arcade_bell_rest.wav")
        XCTAssertEqual(TimerCue.workStart.soundFile(), "boxing_work.wav")
    }
}
