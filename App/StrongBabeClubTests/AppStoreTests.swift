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
        await store.prepare() // TMs start as defaults (no history yet)
        XCTAssertEqual(store.liftPrograms[.deadlift]?.trainingMax, 65)
        let message = try await store.importFile(Data(json.utf8))
        XCTAssertEqual(message, "Imported 1 of 1 workouts.")
        // Regression: imported history must refresh history-based training maxes.
        XCTAssertEqual(store.liftPrograms[.deadlift]?.trainingMax, 195)
        // Re-importing replaces the earlier import (no duplicates).
        let again = try await store.importFile(Data(json.utf8))
        XCTAssertEqual(again, "Imported 1 of 1 workouts. 1 earlier imported workouts were updated.")
        XCTAssertEqual(store.visibleWorkouts.filter { $0.source == "import" }.count, 1)
        let backup = try store.exportBackup()
        let other = makeStore()
        _ = try await other.importFile(backup)
        XCTAssertEqual(other.workouts.count, store.workouts.count)
        do {
            _ = try await store.importFile(Data("hello".utf8))
            XCTFail("expected an error")
        } catch {}
        XCTAssertTrue(store.exportCSV().contains("Deadlift"))
    }

    static var fixture: Data {
        get throws {
            try Data(contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Packages/WorkoutCore/Tests/Fixtures/sample_history.json"))
        }
    }

    /// A day logged in the app is never overwritten by an import.
    func testImportKeepsAppLoggedDays() async throws {
        let store = makeStore()
        await store.prepare()
        let w = try XCTUnwrap(store.nextWorkout) // Mon Oct 19
        store.finish(workout: w.id, feedback: WorkoutFeedback(), sticker: .bear, minutes: 40)
        let json = "[{\"date\": \"2026-10-19\", \"sections\": [{\"kind\": \"warmup\", \"items\": []}]}]"
        let message = try await store.importFile(Data(json.utf8))
        XCTAssertEqual(message, "Imported 0 of 1 workouts (1 already in your journal).")
        XCTAssertEqual(store.workout(on: LocalDate(2026, 10, 19))?.sticker, .bear)
    }

    /// The synthetic fixture lands in the journal and the progress series.
    func testFixtureImportFeedsJournalAndProgress() async throws {
        let store = makeStore()
        let message = try await store.importFile(try Self.fixture)
        XCTAssertTrue(message.hasPrefix("Imported 5 of 8 workouts (skipped 3: "), message)
        XCTAssertEqual(store.doneWorkouts.count, 4)
        XCTAssertEqual(ProgressSeries.lift(.deadlift, workouts: store.visibleWorkouts).map(\.topWeight), [140])
        XCTAssertEqual(ProgressSeries.lift(.backSquat, workouts: store.visibleWorkouts).count, 1)
        XCTAssertNil(store.importProgress)
    }

    /// A save failure part-way through leaves nothing behind and is reported.
    func testImportIsAllOrNothing() async throws {
        var many: [String] = []
        var d = LocalDate(2025, 1, 6)
        for _ in 0..<(AppStore.importBatchSize + 20) {
            many.append("{\"date\": \"\(d.iso)\", \"sections\": [{\"kind\": \"strength\", \"items\": [{\"letter\": \"A\", \"reps\": 5, \"movement\": \"Deadlift\"}], \"logged_weights_lb\": [100]}]}")
            d = d.adding(days: 2)
        }
        let repo = InMemoryRepository()
        repo.failOnBatch = 2
        let store = AppStore(repository: repo, clock: { self.monday })
        store.load()
        do {
            _ = try await store.importFile(Data(("[" + many.joined(separator: ",") + "]").utf8))
            XCTFail("expected the import to fail")
        } catch let e as StoreError {
            XCTAssertEqual(e, .importNotSaved)
        }
        XCTAssertTrue(try repo.load().workouts.isEmpty, "first batch rolled back")
        XCTAssertTrue(store.workouts.isEmpty)
        XCTAssertNil(store.importProgress)
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

import AVFoundation

/// The synthesized timer cues ship in the app bundle and are usable both for
/// in-app playback and as notification sounds (< 30 s, LPCM WAV).
@MainActor
final class TimerSoundTests: XCTestCase {
    func testEveryCueHasAPlayableBundledSound() throws {
        let bundle = Bundle(for: AppStore.self)
        for cue in TimerCue.allCases {
            let name = (cue.soundFile as NSString).deletingPathExtension
            let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "wav"), cue.soundFile)
            let player = try AVAudioPlayer(contentsOf: url)
            XCTAssertGreaterThan(player.duration, 0.3, cue.soundFile)
            XCTAssertLessThan(player.duration, 30, "notification sounds must be under 30 s")
        }
    }

    func testEachCueHasItsOwnHaptic() {
        let haptics = TimerCue.allCases.map { "\(TimerSound.haptic(for: $0))" }
        XCTAssertEqual(Set(haptics).count, TimerCue.allCases.count)
    }
}
