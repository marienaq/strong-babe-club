import SwiftData
import XCTest
import WorkoutCore
@testable import StrongBabeClub

/// Store logic with an in-memory repository and a fixed clock
/// (Mon Oct 19 2026, 09:00 ET: block 1, week 1).
@MainActor
final class AppStoreTests: XCTestCase {
    let monday = Date(timeIntervalSince1970: 1_792_414_800)

    func makeStore(_ data: StoredData = StoredData()) -> AppStore {
        let store = AppStore(repository: InMemoryRepository(data), clock: { self.monday })
        store.load()
        return store
    }

    func testPreparePlansTodaysWorkout() async throws {
        let store = makeStore()
        XCTAssertEqual(store.today, LocalDate(2026, 10, 19))
        await store.prepare()
        let w = try XCTUnwrap(store.nextWorkout)
        XCTAssertEqual(w.date, store.today)
        XCTAssertEqual(w.sections.map(\.kind), [.warmup, .strength, .metabolic, .cooldown])
        XCTAssertEqual(store.liftPrograms.count, 6)
    }

    func testLogAndFinish() async throws {
        let store = makeStore()
        await store.prepare()
        let w = try XCTUnwrap(store.nextWorkout)
        let s = try XCTUnwrap(w.strengthSection)
        let item = try XCTUnwrap(s.items.first)
        for p in item.plannedSets {
            store.logSet(workout: w.id, section: s.id, item: item.id, setNumber: p.setNumber, reps: p.reps, weight: p.weight)
        }
        // Out-of-range values are ignored.
        store.logSet(workout: w.id, section: s.id, item: item.id, setNumber: 1, reps: 5, weight: 99_999)
        XCTAssertEqual(store.workout(id: w.id)?.strengthSection?.items.first?.setLogs.count, item.plannedSets.count)
        // The PR star can't be picked on a non-PR day (no history).
        let summary = store.finish(workout: w.id, feedback: WorkoutFeedback(energy: .high, strengthDifficulty: 3), sticker: .star, minutes: 48)
        let done = try XCTUnwrap(store.workout(id: w.id))
        XCTAssertEqual(done.status, .done)
        XCTAssertNil(done.sticker)
        XCTAssertEqual(done.durationMin, 48)
        XCTAssertEqual(summary?.streak, 1)
        XCTAssertTrue(store.todayIsDone)
    }

    func testCommonStickerIsKept() async throws {
        let store = makeStore()
        await store.prepare()
        let w = try XCTUnwrap(store.nextWorkout)
        store.finish(workout: w.id, feedback: WorkoutFeedback(), sticker: .bear, minutes: 40)
        XCTAssertEqual(store.workout(id: w.id)?.sticker, .bear)
    }

    func testShuffleKeepsIdentityAndOtherSections() async throws {
        let store = makeStore()
        await store.prepare()
        let w = try XCTUnwrap(store.nextWorkout)
        await store.shuffle(workout: w.id, section: .metabolic)
        let s = try XCTUnwrap(store.workout(id: w.id))
        XCTAssertEqual(s.strengthSection, w.strengthSection)
        XCTAssertEqual(s.salts.metabolic, 1)
    }

    func testMissedDaysAreBackfilled() async {
        let past = PlannedWorkout(date: LocalDate(2026, 10, 12), status: .done, source: "import")
        let store = makeStore(StoredData(workouts: [past]))
        await store.prepare()
        // Wed 14 and Fri 16 were scheduled but never logged.
        XCTAssertEqual(store.workouts.filter { $0.source == "missed" }.map(\.date), [LocalDate(2026, 10, 14), LocalDate(2026, 10, 16)])
        XCTAssertEqual(store.streak.current, 0)
        store.setStatus(.excused, on: LocalDate(2026, 10, 14))
        store.setStatus(.excused, on: LocalDate(2026, 10, 16))
        XCTAssertEqual(store.streak.current, 1)
    }

    func testImportCoachHistoryAndBackupRoundTrip() async throws {
        let json = """
        [{"date": "2026-10-02", "sections": [{"kind": "strength", "items": [{"letter": "A", "reps": 5, "movement": "Deadlift"}],
          "logged_weights_lb": [85, 110, 135, 160, 185]}]}]
        """
        let store = makeStore()
        let message = try store.importFile(Data(json.utf8))
        XCTAssertTrue(message.contains("Imported 1"))
        await store.prepare()
        XCTAssertEqual(store.liftPrograms[.deadlift]?.trainingMax, 195)
        let backup = try store.exportBackup()
        let other = makeStore()
        _ = try other.importFile(backup)
        XCTAssertEqual(other.workouts.count, store.workouts.count)
        XCTAssertThrowsError(try store.importFile(Data("hello".utf8)))
        XCTAssertTrue(store.exportCSV().contains("Deadlift"))
    }

    func testSettingsAreSanitized() {
        let store = makeStore()
        var s = store.settings
        s.targetMinutes = 5000
        s.displayName = String(repeating: "x", count: 500)
        store.updateSettings(s)
        XCTAssertEqual(store.settings.targetMinutes, 120)
        XCTAssertEqual(store.settings.displayName.count, 40)
    }
}

/// Domain -> SwiftData records -> domain must be lossless.
@MainActor
final class SwiftDataRepositoryTests: XCTestCase {
    func testWorkoutRoundTrip() throws {
        let repo = SwiftDataRepository(container: try SwiftDataRepository.makeContainer(inMemory: true))
        var w = try RulesWorkoutPlanner().makePlan(PlanRequest(date: LocalDate(2026, 10, 19), now: Date(timeIntervalSince1970: 1_792_414_800)))
        let s = try XCTUnwrap(w.strengthSection)
        w.sections[1].items[0].setLogs = [SetLog(setNumber: 1, reps: 5, weight: 65, completedAt: Date(timeIntervalSince1970: 1_792_415_000))]
        w.sections[2].roundLogs = [RoundLog(roundNumber: 1, rounds: 5, reps: 2)]
        w.feedback = WorkoutFeedback(energy: .okay, strengthDifficulty: 3, metabolicDifficulty: 4, notes: "felt good")
        w.sticker = .kettle
        w.status = .done
        XCTAssertEqual(s.kind, .strength)

        try repo.save(workouts: [w])
        XCTAssertEqual(try repo.load().workouts, [w])

        // Saving again replaces (no duplicates, children not orphaned).
        w.sections[3].athleteNote = "stretch more"
        try repo.save(workouts: [w])
        let loaded = try repo.load().workouts
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first, w)
        XCTAssertEqual(try repo.container.mainContext.fetchCount(FetchDescriptor<SectionRecord>()), 4)
    }

    func testOtherTablesRoundTrip() throws {
        let repo = SwiftDataRepository(container: try SwiftDataRepository.makeContainer(inMemory: true))
        var settings = PlannerSettings.default
        settings.displayName = "Sam"
        settings.limits.avoidJumping = true
        try repo.save(settings: settings)
        try repo.save(liftPrograms: [LiftProgram(lift: .deadlift, trainingMax: 195, blockStartDate: LocalDate(2026, 10, 19), blockWeek: 1, phase: .volume, source: .test)])
        let template = WorkoutSection(kind: .metabolic, format: .amrapWithRest, name: "amrap-5-4-fungi", instructions: "5 rounds", rounds: 5, workSec: 240, restSec: 60)
        try repo.save(benchmarks: [Benchmark(name: "amrap-5-4-fungi", template: template, quarterSlot: 0)])
        try repo.save(goals: [Goal(lift: .deadlift, targetWeight: 200, byDate: LocalDate(2027, 1, 15))])
        let d = try repo.load()
        XCTAssertEqual(d.settings, settings)
        XCTAssertEqual(d.liftPrograms.first?.trainingMax, 195)
        XCTAssertEqual(d.liftPrograms.first?.blockStartDate, LocalDate(2026, 10, 19))
        XCTAssertEqual(d.benchmarks.first?.template, template)
        XCTAssertEqual(d.goals.first?.byDate, LocalDate(2027, 1, 15))
        try repo.deleteAll()
        XCTAssertTrue(try repo.load().workouts.isEmpty)
        XCTAssertTrue(try repo.load().goals.isEmpty)
    }
}
