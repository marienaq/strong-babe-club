import XCTest
@testable import WorkoutCore

final class RecentHistoryTests: XCTestCase {
    let day = LocalDate(2026, 10, 19)

    func testLiftSessionsIncludeImportedAndAppLogged() throws {
        var imported = TestData.strengthDay(LocalDate(2026, 9, 21), .frontSquat, weights: [75, 95, 115])
        imported.source = "import"
        // A planner workout logged in the app (sets have completedAt).
        var app = try RulesWorkoutPlanner().makePlan(PlanRequest(date: LocalDate(2026, 10, 5), now: TestData.now))
        app.sections[1].items[0].setLogs = [SetLog(setNumber: 1, reps: 5, weight: 65, completedAt: TestData.now),
                                            SetLog(setNumber: 2, reps: 5, weight: 85, completedAt: TestData.now)]
        app.status = .done
        XCTAssertEqual(app.mainLift, .frontSquat)
        let older = TestData.strengthDay(LocalDate(2026, 9, 7), .frontSquat, weights: [95])
        let otherLift = TestData.strengthDay(LocalDate(2026, 10, 7), .deadlift, weights: [135])
        let future = TestData.strengthDay(LocalDate(2026, 10, 26), .frontSquat, weights: [200])
        let notDone = TestData.strengthDay(LocalDate(2026, 10, 12), .frontSquat, weights: [99], status: .planned)
        let all = [older, imported, app, otherLift, future, notDone]
        let recent = RecentHistory.liftSessions(.frontSquat, before: day, in: all)
        XCTAssertEqual(recent.map(\.date), [LocalDate(2026, 10, 5), LocalDate(2026, 9, 21), LocalDate(2026, 9, 7)])
        XCTAssertEqual(recent.first?.sets.map(\.weight), [65, 85])
        XCTAssertEqual(RecentHistory.liftSessions(.frontSquat, before: day, in: all, limit: 2).count, 2)
        XCTAssertTrue(RecentHistory.liftSessions(.pushJerk, before: day, in: all).isEmpty)
    }

    func testMetabolicPrefersSameWorkoutThenSameFormat() {
        let named = TestData.amrapSection(rounds: [(5, 1)])
        var other = TestData.amrapSection(rounds: [(4, 0)])
        other.name = "amrap-4-3-otter"
        let w1 = PlannedWorkout(date: LocalDate(2026, 7, 20), status: .done, sections: [named])
        let w2 = PlannedWorkout(date: LocalDate(2026, 9, 1), status: .done, sections: [other])
        var today = TestData.amrapSection(rounds: [])
        let same = RecentHistory.metabolic(for: today, before: day, in: [w1, w2])
        XCTAssertEqual(same.map(\.date), [LocalDate(2026, 7, 20)])
        XCTAssertEqual(same.first?.match, .sameWorkout)
        today.name = "amrap-5-4-brand-new"
        let fmt = RecentHistory.metabolic(for: today, before: day, in: [w1, w2])
        XCTAssertEqual(fmt.map(\.date), [LocalDate(2026, 9, 1), LocalDate(2026, 7, 20)])
        XCTAssertEqual(fmt.first?.match, .sameFormat)
        today.format = .tabata
        XCTAssertTrue(RecentHistory.metabolic(for: today, before: day, in: [w1, w2]).isEmpty)
        // Unscored sessions are skipped.
        let empty = PlannedWorkout(date: LocalDate(2026, 10, 1), status: .done, sections: [TestData.amrapSection(rounds: [])])
        XCTAssertEqual(RecentHistory.metabolic(for: TestData.amrapSection(rounds: []), before: day, in: [empty]).count, 0)
    }

    /// Progress chart: sets logged in the app count, not just imports.
    func testProgressSeriesUsesAppLoggedSets() throws {
        var app = try RulesWorkoutPlanner().makePlan(PlanRequest(date: LocalDate(2026, 10, 5), now: TestData.now))
        let sets = app.sections[1].items[0].plannedSets
        app.sections[1].items[0].setLogs = sets.map { SetLog(setNumber: $0.setNumber, reps: $0.reps, weight: $0.weight, completedAt: TestData.now) }
        app.status = .done
        let points = ProgressSeries.lift(.frontSquat, workouts: [app], since: LocalDate(2026, 1, 1))
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.topWeight, sets.last?.weight)
        // Typed-but-unlogged sets don't count (the app now auto-logs them).
        app.sections[1].items[0].setLogs = []
        XCTAssertTrue(ProgressSeries.lift(.frontSquat, workouts: [app]).isEmpty)
    }
}
