import Foundation
import XCTest
@testable import WorkoutCore

/// The week plan (spec §6.2 with owner decision Q7).
final class MetconWeekPlanTests: XCTestCase {
    let settings = PlannerSettings.default

    func weeks(_ s: PlannerSettings = .default) -> [[DayMetconPlan]] {
        stride(from: 0, to: 52 * 7, by: 7).map { off in
            MetconWeekPlan.make(weekStart: LocalDate(2026, 10, 12).adding(days: off), settings: s).values.sorted { $0.date < $1.date }
        }
    }

    /// MC-13: same week and settings give the same plan; it never reads history.
    func testDeterministic() {
        let a = MetconWeekPlan.make(weekStart: LocalDate(2026, 10, 19), settings: settings)
        let b = MetconWeekPlan.make(weekStart: LocalDate(2026, 10, 21), settings: settings)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, MetconWeekPlan.make(weekStart: LocalDate(2026, 10, 19), settings: settings, lookBack: true))
        XCTAssertEqual(a.keys.sorted(), [LocalDate(2026, 10, 19), LocalDate(2026, 10, 21), LocalDate(2026, 10, 23)])
    }

    /// Q7: one 3-minute window per week, heaviest day in the lower half,
    /// a lighter last day about 1 week in 4, and one format per day.
    func testLengthsAreAboutEqual() {
        for schedule in MetconYearHarness.schedules {
            var s = settings
            s.schedule = schedule.1
            var light = 0
            let ws = weeks(s)
            for week in ws {
                let normal = week.filter { $0.lightDay != .short }
                let lo = normal.map(\.window.lowerBound).min()!, hi = normal.map(\.window.upperBound).max()!
                XCTAssertLessThanOrEqual(hi - lo, MetconWeekPlan.spread, "\(week[0].date)")
                if let heavy = normal.first(where: \.isHeaviest) {
                    for d in normal where d.date != heavy.date { XCTAssertLessThanOrEqual(heavy.window.upperBound, d.window.lowerBound) }
                    XCTAssertEqual(MetconWeekPlan.load(heavy.lift), week.map { MetconWeekPlan.load($0.lift) }.max())
                }
                if week.contains(where: { $0.lightDay != nil }) {
                    light += 1
                    XCTAssertNotNil(week.last?.lightDay, "the last day is the lighter one")
                }
                if week.count >= 3 && week.count <= week[0].allowedFormats.count {
                    XCTAssertEqual(Set(week.map(\.format)).count, week.count, "\(week[0].date)")
                }
                for d in week { XCTAssertTrue(MetconCatalog.hasShape(d.format, in: d.window), "\(d.date) \(d.format)") }
            }
            let share = Double(light) / Double(ws.count)
            XCTAssertTrue((0.12...0.38).contains(share), "\(schedule.0): light weeks \(share)")
        }
    }

    /// The default rotation: Monday is the heaviest day both weeks; Friday is the pull day.
    func testDefaultWeekShape() {
        for monday in [LocalDate(2026, 10, 19), LocalDate(2026, 10, 26)] {
            let plan = MetconWeekPlan.make(weekStart: monday, settings: settings)
            XCTAssertEqual(plan[monday]?.isHeaviest, true)
            XCTAssertEqual(plan[monday.adding(days: 4)]?.isPullDay, true)
            XCTAssertEqual(plan[monday]?.isPullDay, false)
        }
    }

    /// §8 phase windows: test weeks short, peak never long, deload never short.
    func testPhaseWindows() {
        for week in weeks() {
            for d in week {
                switch d.phase {
                case .test:
                    XCTAssertTrue(MetconBand.short.range.contains(d.window.lowerBound) && d.window.upperBound <= 1019)
                    XCTAssertFalse([SectionFormat.forTime, .amrapWithRest, .stations].contains(d.format))
                case .peak:
                    XCTAssertLessThan(d.window.upperBound, 1260)
                    if d.isHeaviest { XCTAssertNotEqual(d.format, .forTime) }
                case .deload:
                    if d.lightDay != .short { XCTAssertGreaterThanOrEqual(d.window.lowerBound, 1020) }
                    XCTAssertNotEqual(d.format, .forTime)
                default:
                    if d.lightDay != .short { XCTAssertTrue((1020...1260).contains(d.window.lowerBound)) }
                }
            }
        }
    }
}

/// Pace, reps and quality score (spec §17, §20, §22).
final class MetconPaceQualityTests: XCTestCase {
    let lib = MovementLibrary.standard

    func section(_ shapeID: String, _ ids: [String], reps: [Int]? = nil) -> WorkoutSection {
        var s = MetconCatalog.shapes.first { $0.id == shapeID }!.section()
        s.items = ids.enumerated().map { i, id in
            SectionItem(letter: ["A", "B", "C", "D", "E"][i], movementID: id, movementName: lib[id]!.name, reps: reps?[i])
        }
        return s
    }

    /// MC-51 / R11: 5 × 3-min AMRAP with push-ups, KB swings and up/downs gives 4 / 6 / 4.
    func testRepsGolden() {
        let s = section("rest-5x3", ["push-up", "kb-swing", "up-down"])
        XCTAssertEqual(PaceModel.neutral.targetFreshRoundSec(s)!, 180 / 3.7, accuracy: 0.01)
        let reps = RulesWorkoutPlanner.sizeReps(s, moves: ["push-up", "kb-swing", "up-down"].map { lib[$0]! }, pace: .neutral, density: 1)
        XCTAssertEqual(reps, [4, 6, 4])
    }

    /// §7.4 rounding: per-side moves are even; above 20 round to 5; inside the range.
    func testRepRounding() {
        XCTAssertEqual(RulesWorkoutPlanner.roundReps(7.2, lib["lunge"]!), 8)
        XCTAssertEqual(RulesWorkoutPlanner.roundReps(23, lib["mountain-climber"]!), 30, "25 is odd for a per-side move")
        XCTAssertEqual(RulesWorkoutPlanner.roundReps(22.4, lib["jumping-jack"]!), 20)
        XCTAssertEqual(RulesWorkoutPlanner.roundReps(1.2, lib["burpee"]!), 3)
        XCTAssertEqual(RulesWorkoutPlanner.roundReps(99, lib["push-up"]!), 12)
    }

    /// §17.3 target round seconds for the coach's shapes.
    func testTargetRounds() {
        let target = { (id: String) in PaceModel.neutral.targetFreshRoundSec(self.section(id, ["push-up", "kb-swing", "up-down"]))! }
        XCTAssertEqual(target("rest-8x2"), 37, accuracy: 0.5)
        XCTAssertEqual(target("rest-4x4"), 49.6, accuracy: 0.5)
        XCTAssertEqual(target("amrap-12"), 66.3, accuracy: 0.5)
        XCTAssertEqual(target("amrap-20"), 83.9, accuracy: 0.5)
        let slow = PaceModel(windows: 1.25)
        XCTAssertLessThan(slow.targetFreshRoundSec(section("rest-5x3", ["push-up"]))!, target("rest-5x3"))
    }

    /// MC-60: the score function on generic fixtures.
    func testScoreFunction() {
        let coach = section("rest-5x3", ["push-up", "kb-swing", "up-down"], reps: [4, 7, 4])
        XCTAssertEqual(MetconQuality.score(coach).penalty, 0, accuracy: 1e-9)
        let long = section("amrap-20", ["up-down", "air-squat", "kb-deadlift", "db-push-press"], reps: [6, 8, 6, 8])
        XCTAssertLessThanOrEqual(MetconQuality.score(long).penalty, 0.5)
        let jumps = section("rest-5x3", ["burpee", "box-jump", "push-up"], reps: [3, 4, 5])
        XCTAssertGreaterThanOrEqual(MetconQuality.score(jumps).penalty, 2.0)
        let shoulders = section("stations-4x3", ["db-push-press", "wall-walk", "db-strict-press"])
        XCTAssertGreaterThan(MetconQuality.score(shoulders).penalty, 2.0)
        let lots = section("amrap-20", ["jumping-jack", "air-squat", "sit-up"], reps: [30, 20, 10])
        XCTAssertGreaterThan(MetconQuality.score(lots).penalty, 1.0)
        let repeated = MetconQuality.score(coach, weekMoveIDs: ["push-up", "kb-swing"])
        XCTAssertEqual(repeated.penalty, 1.0, accuracy: 1e-9)
        XCTAssertEqual(repeated.top?.name, "moves repeated from earlier this week")
    }

    /// MC-63: best of N is deterministic and never worse than the first candidate.
    func testBestOfNIsDeterministicAndBetter() throws {
        let planner = RulesWorkoutPlanner()
        var d = LocalDate(2026, 10, 19)
        var checked = 0
        var improved = 0
        while checked < 50 {
            defer { d = d.adding(days: 1) }
            guard PlannerSettings.default.rotation.isScheduled(d) else { continue }
            let req = PlanRequest(date: d, now: TestData.now)
            let a = try XCTUnwrap(planner.remixCandidate(req))
            let b = try XCTUnwrap(planner.remixCandidate(req))
            XCTAssertEqual(a.section, b.section)
            XCTAssertLessThanOrEqual(a.score.penalty, a.firstPenalty + 1e-9)
            if a.score.penalty < a.firstPenalty { improved += 1 }
            checked += 1
        }
        XCTAssertGreaterThan(improved, 0, "best of 12 does better than the first candidate sometimes")
    }

    // MARK: Feedback loop (§22)

    /// A done remixed piece with an expected score at the default pace and an actual score.
    func piece(_ day: Int, format: SectionFormat = .amrapWithRest, actual: Double, rating: Int? = 3) -> PlannedWorkout {
        var s = format == .amrapWithRest ? section("rest-5x3", ["push-up", "kb-swing", "up-down"], reps: [4, 6, 4])
                                         : section("amrap-15", ["push-up", "kb-swing", "up-down"], reps: [5, 8, 5])
        let expected = PaceModel.neutral.expectedRounds(s, library: lib)!
        s.expectedScore = expected
        let rounds = expected / actual
        let whole = Int(rounds)
        s.roundLogs = (1...(format == .amrap ? 1 : 5)).map {
            RoundLog(roundNumber: $0, rounds: whole, reps: Int(((rounds - Double(whole)) * Double(s.repsPerRound)).rounded()))
        }
        return PlannedWorkout(date: LocalDate(2027, 1, 4).adding(days: day), status: .done, sections: [s],
                              feedback: WorkoutFeedback(energy: .okay, metabolicDifficulty: rating))
    }

    /// MC-66: pace bounds, outliers and minimum count.
    func testPaceLearning() {
        let slow = (0..<5).map { piece($0 * 2, actual: 2.0) }
        XCTAssertEqual(MetconFeedback.learnedPace(from: slow).windows, 1.25, accuracy: 1e-9)
        XCTAssertEqual(MetconFeedback.learnedPace(from: slow).continuous, 1)
        let outliers = (0..<5).map { piece($0 * 2, actual: 0.4) }
        XCTAssertEqual(MetconFeedback.learnedPace(from: outliers).windows, 1)
        XCTAssertEqual(MetconFeedback.learnedPace(from: Array(slow.prefix(2))).windows, 1, "needs 3 pieces")
        let mild = (0..<4).map { piece($0 * 2, actual: 1.1) }
        XCTAssertEqual(MetconFeedback.learnedPace(from: mild).windows, 1.1, accuracy: 0.03)
        XCTAssertEqual(MetconFeedback.learnedPace(from: mild), MetconFeedback.learnedPace(from: mild))
        let fast = (0..<4).map { piece($0 * 2, format: .amrap, actual: 0.7) }
        XCTAssertEqual(MetconFeedback.learnedPace(from: fast).continuous, 0.8, accuracy: 1e-9)
    }

    /// MC-67: density from ratings.
    func testDensityReplay() {
        func d(_ ratings: [Int]) -> Double {
            MetconFeedback.density(from: ratings.enumerated().map { piece($0.offset, actual: 1, rating: $0.element) })
        }
        XCTAssertEqual(d([5, 5, 5, 5, 5, 5]), 0.8, accuracy: 1e-9)
        XCTAssertEqual(d([1, 1, 1, 1, 1, 1]), 1.2, accuracy: 1e-9)
        XCTAssertEqual(d([5, 3, 3, 3, 3, 3]), 1.0, accuracy: 1e-9)
        XCTAssertEqual(d([4, 4]), 0.9, accuracy: 1e-9)
        // Only the last 6 count.
        XCTAssertEqual(d([1, 1, 1, 3, 3, 3, 3, 3, 3]), 1.0, accuracy: 1e-9)
        // Reps stay inside the range at either end.
        let s = section("rest-5x3", ["push-up", "kb-swing", "up-down"])
        let moves = ["push-up", "kb-swing", "up-down"].map { lib[$0]! }
        for density in [0.8, 1.2] {
            let reps = RulesWorkoutPlanner.sizeReps(s, moves: moves, pace: .neutral, density: density)!
            for (r, m) in zip(reps, moves) { XCTAssertTrue(m.repRange.contains(r)) }
        }
    }

    /// MC-68: fading in 2 of the last 3 pieces lowers density by 0.10, once.
    func testFadeSignal() {
        func faded(_ day: Int, last: Int) -> PlannedWorkout {
            var w = piece(day, actual: 1)
            w.sections[0].roundLogs = (1...5).map { RoundLog(roundNumber: $0, rounds: $0 == 5 ? last : 5, reps: 0) }
            return w
        }
        let flat = [faded(0, last: 5), faded(2, last: 5), faded(4, last: 5)]
        XCTAssertFalse(MetconFeedback.fades(flat))
        XCTAssertEqual(MetconFeedback.density(from: flat), 1.0, accuracy: 1e-9)
        let fading = [faded(0, last: 5), faded(2, last: 4), faded(4, last: 3)]
        XCTAssertTrue(MetconFeedback.fades(fading))
        XCTAssertEqual(MetconFeedback.density(from: fading), 0.9, accuracy: 1e-9)
        // A later piece without fade ends it.
        XCTAssertFalse(MetconFeedback.fades(fading + [faded(6, last: 5), faded(8, last: 5)]))
    }
}
