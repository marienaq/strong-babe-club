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
        XCTAssertEqual(message, "Imported 1 of 1 workouts: 1 done.")
        // Regression: imported history must refresh history-based training maxes.
        XCTAssertEqual(store.liftPrograms[.deadlift]?.trainingMax, 195)
        // Re-importing replaces the earlier import (no duplicates).
        let again = try await store.importFile(Data(json.utf8))
        XCTAssertEqual(again, "Imported 1 of 1 workouts: 1 done. 1 earlier imported workouts were updated.")
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
        XCTAssertEqual(message, "Imported 0 of 1 workouts: 0 done, 1 not logged → missed (1 already in your journal).")
        XCTAssertEqual(store.workout(on: LocalDate(2026, 10, 19))?.sticker, .bear)
    }

    /// The synthetic fixture lands in the journal and the progress series.
    func testFixtureImportFeedsJournalAndProgress() async throws {
        let store = makeStore()
        let message = try await store.importFile(try Self.fixture)
        XCTAssertTrue(message.hasPrefix("Imported 7 of 10 workouts: 4 done, 1 sick day, 2 not logged → missed (skipped 3: "), message)
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
        for pack in SoundPack.allCases {
        for cue in TimerCue.allCases {
            let file = cue.soundFile(pack: pack)
            let name = (file as NSString).deletingPathExtension
            let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "wav"), file)
            let player = try AVAudioPlayer(contentsOf: url)
            XCTAssertGreaterThan(player.duration, 0.25, file)
            XCTAssertLessThan(player.duration, 30, "notification sounds must be under 30 s")
        }
        }
    }

    func testEachCueHasItsOwnHaptic() {
        let haptics = TimerCue.allCases.map { "\(TimerSound.haptic(for: $0))" }
        XCTAssertEqual(Set(haptics).count, TimerCue.allCases.count)
    }
}

/// Round 4: misses, sick days, breaks, today's options, stickers.
@MainActor
final class MissedAndStickerTests: XCTestCase {
    let monday = Date(timeIntervalSince1970: 1_792_414_800) // Mon Oct 19 2026

    func makeStore(_ data: StoredData = StoredData()) -> AppStore {
        let store = AppStore(repository: InMemoryRepository(data), clock: { self.monday })
        store.load()
        return store
    }

    /// Imported done days on every Mon/Wed/Fri in [from, to].
    func imported(_ from: LocalDate, _ to: LocalDate) -> [PlannedWorkout] {
        var out: [PlannedWorkout] = []
        var d = from
        while d <= to {
            if [.monday, .wednesday, .friday].contains(d.weekday) {
                out.append(PlannedWorkout(date: d, status: .done, source: "import"))
            }
            d = d.adding(days: 1)
        }
        return out
    }

    func testSummerGapCountsAsMissedUntilMarkedAsBreak() {
        let history = imported(LocalDate(2026, 6, 1), LocalDate(2026, 7, 3)) + imported(LocalDate(2026, 8, 3), LocalDate(2026, 10, 16))
        let store = makeStore(StoredData(workouts: history))
        XCTAssertEqual(store.streak.current, 33, "since Aug 3")
        XCTAssertEqual(store.streak.best, 33)
        let gap = try! XCTUnwrap(store.missedEntries.first)
        XCTAssertTrue(gap.isGroup)
        XCTAssertEqual(gap.label, "missed 4 weeks · Jul 6 – Jul 31")
        store.addBreak(label: "Spain", from: gap.from, to: gap.to)
        XCTAssertTrue(store.missedEntries.isEmpty)
        XCTAssertEqual(store.streak.current, 15 + 33)
        store.removeBreak(store.settings.breaks[0].id)
        XCTAssertEqual(store.streak.current, 33)
    }

    func testMissedDayToSickDayAndBack() {
        var history = imported(LocalDate(2026, 9, 7), LocalDate(2026, 10, 16))
        history.removeAll { $0.date == LocalDate(2026, 10, 7) }
        let store = makeStore(StoredData(workouts: history))
        XCTAssertEqual(store.missedEntries.map(\.label), ["missed · Wed Oct 7"])
        XCTAssertEqual(store.streak.current, 3)
        store.markSick(LocalDate(2026, 10, 7))
        XCTAssertTrue(store.missedEntries.isEmpty)
        XCTAssertEqual(store.streak.current, 17)
        store.markMissed(LocalDate(2026, 10, 7))
        XCTAssertEqual(store.missedEntries.map(\.label), ["missed · Wed Oct 7"])
        XCTAssertEqual(store.streak.current, 3)
    }

    func testTodaySickSkipMoveAndUndo() async throws {
        let store = makeStore()
        await store.prepare()
        let w = try XCTUnwrap(store.workout(on: store.today))
        XCTAssertNil(store.todayChange)

        store.sickToday()
        XCTAssertEqual(store.todayChange, .sick)
        XCTAssertEqual(store.workout(id: w.id)?.status, .excused)
        store.undoTodayChange()
        XCTAssertNil(store.todayChange)
        XCTAssertEqual(store.workout(id: w.id)?.status, .planned)

        store.skipToday()
        XCTAssertEqual(store.todayChange, .skipped)
        store.undoTodayChange()
        XCTAssertEqual(store.workout(id: w.id)?.status, .planned)

        // Mon -> Tue (the next non-training day this week).
        XCTAssertEqual(store.moveTarget, LocalDate(2026, 10, 20))
        store.moveToday()
        XCTAssertEqual(store.todayChange, .moved(LocalDate(2026, 10, 20)))
        XCTAssertEqual(store.workout(id: w.id)?.date, LocalDate(2026, 10, 20))
        XCTAssertNil(store.moveTarget, "nothing left to move today")
        store.undoTodayChange()
        XCTAssertNil(store.todayChange)
        XCTAssertEqual(store.workout(id: w.id)?.date, store.today)
        XCTAssertEqual(store.visibleWorkouts.filter { $0.date == store.today }.count, 1, "marker removed")
    }

    func testMoveOnlyWithinTheWeekToAFreeDay() async throws {
        let sundayClock = Date(timeIntervalSince1970: 1_792_414_800 + 6 * 86_400) // Sun Oct 25
        var s = PlannerSettings.default
        s.schedule = [.sunday]
        let store = AppStore(repository: InMemoryRepository(StoredData(settings: s)), clock: { sundayClock })
        store.load()
        await store.prepare()
        XCTAssertNotNil(store.workout(on: store.today))
        XCTAssertNil(store.moveTarget, "Sunday is the last day of the week")
    }

    func testImportedStickersAreClearedOnLoad() {
        var w = PlannedWorkout(date: LocalDate(2026, 9, 7), status: .done, sticker: .barbell, source: "import")
        w.sync = SyncStamp(createdAt: monday)
        let mine = PlannedWorkout(date: LocalDate(2026, 9, 9), status: .done, sticker: .bear, source: "rules-v1")
        let repo = InMemoryRepository(StoredData(workouts: [w, mine]))
        let store = AppStore(repository: repo, clock: { self.monday })
        store.load()
        XCTAssertNil(store.workout(id: w.id)?.sticker)
        XCTAssertNil(try repo.load().workouts.first { $0.id == w.id }?.sticker, "persisted")
        XCTAssertEqual(store.workout(id: mine.id)?.sticker, .bear)
        XCTAssertEqual(store.stickerSlots.first, .sticker(.bear, date: LocalDate(2026, 9, 9)))
    }

    func testImportedHistoryLeavesStickerPageEmpty() async throws {
        let store = makeStore(StoredData(workouts: imported(LocalDate(2026, 8, 3), LocalDate(2026, 10, 16))))
        await store.prepare()
        let slots = store.stickerSlots
        XCTAssertEqual(slots.count, 12)
        XCTAssertEqual(slots.first, .today)
        XCTAssertEqual(slots.dropFirst().filter { $0 == .empty }.count, 11)
    }
}

/// Round 4b: unlogged imported days are missed; re-import refreshes statuses
/// but keeps the owner's own decisions.
@MainActor
final class UnloggedImportTests: XCTestCase {
    let monday = Date(timeIntervalSince1970: 1_792_414_800) // Mon Oct 19 2026

    func json(_ days: [(String, Bool)]) -> Data {
        let rows = days.map { d, logged in
            "{\"date\": \"\(d)\", \"sections\": [{\"kind\": \"strength\", \"athlete_note\": \(logged ? "\"85, 105\"" : "null"), \"items\": [{\"letter\": \"A\", \"reps\": 5, \"movement\": \"Deadlift\"}], \"logged_weights_lb\": \(logged ? "[85, 105]" : "null")}]}"
        }
        return Data(("[" + rows.joined(separator: ",") + "]").utf8)
    }

    func testUnloggedDayIsMissedAndCanBeConfirmed() async throws {
        let store = AppStore(repository: InMemoryRepository(), clock: { self.monday })
        store.load()
        let msg = try await store.importFile(json([("2026-10-12", true), ("2026-10-14", false), ("2026-10-16", true)]))
        XCTAssertTrue(msg.hasPrefix("Imported 3 of 3 workouts: 2 done, 1 not logged → missed"), msg)
        XCTAssertEqual(store.missedEntries.map(\.label), ["missed · Wed Oct 14"])
        XCTAssertEqual(store.streak.current, 0, "2 of 3 that week resets")

        store.markDoneUnlogged(LocalDate(2026, 10, 14))
        XCTAssertTrue(store.missedEntries.isEmpty)
        XCTAssertEqual(store.streak.current, 3)
        XCTAssertNil(store.workout(on: LocalDate(2026, 10, 14))?.sticker)

        // Re-import keeps the owner's "I did it", one record per day.
        _ = try await store.importFile(json([("2026-10-12", true), ("2026-10-14", false), ("2026-10-16", true)]))
        XCTAssertEqual(store.workout(on: LocalDate(2026, 10, 14))?.status, .done)
        XCTAssertEqual(store.visibleWorkouts.filter { $0.date == LocalDate(2026, 10, 14) }.count, 1)
    }

    func testReimportRefreshesStatuses() async throws {
        let store = AppStore(repository: InMemoryRepository(), clock: { self.monday })
        store.load()
        _ = try await store.importFile(json([("2026-10-12", true), ("2026-10-14", true)]))
        XCTAssertEqual(store.workout(on: LocalDate(2026, 10, 14))?.status, .done)
        _ = try await store.importFile(json([("2026-10-12", true), ("2026-10-14", false)]))
        XCTAssertEqual(store.workout(on: LocalDate(2026, 10, 14))?.status, .skipped)
        XCTAssertEqual(store.visibleWorkouts.filter { $0.source.hasPrefix("import") }.count, 2)
    }
}

@MainActor
final class UnitSwitchTests: XCTestCase {
    func testSwitchingUnitsKeepsHistoryAndRoundsTMsAndGoals() async throws {
        let history = [PlannedWorkout(date: LocalDate(2026, 10, 12), status: .done,
                                      sections: [WorkoutSection(kind: .strength, format: .everyNMin, instructions: "", lift: .deadlift,
                                                                items: [SectionItem(letter: "A", movementID: "deadlift", movementName: "Deadlift",
                                                                                    setLogs: [SetLog(setNumber: 1, reps: 5, weight: 185)])])],
                                      source: "import")]
        let store = AppStore(repository: InMemoryRepository(StoredData(workouts: history, goals: [Goal(lift: .deadlift, targetWeight: 200)])),
                             clock: { Date(timeIntervalSince1970: 1_792_414_800) })
        store.load()
        await store.prepare()
        store.switchUnits(to: .kg)
        XCTAssertEqual(store.unit, .kg)
        XCTAssertEqual(store.settings.equipment.barWeight, 20)
        // History is untouched (canonical pounds), shown in kg.
        XCTAssertEqual(store.workouts.first { $0.source == "import" }?.strengthSection?.items[0].setLogs[0].weight, 185)
        XCTAssertEqual(store.label(185), "83.9 kg")
        // TM and goal re-rounded to 2.5 kg.
        let tm = try XCTUnwrap(store.liftPrograms[.deadlift]?.trainingMax)
        XCTAssertEqual(WeightUnit.kg.fromPounds(tm).truncatingRemainder(dividingBy: 2.5), 0, accuracy: 1e-6)
        XCTAssertEqual(WeightUnit.kg.fromPounds(store.goals[0].targetWeight), 90, accuracy: 1e-6)
        // Entering a TM in kg stores pounds.
        store.setTrainingMax(.pushPress, WeightUnit.kg.toPounds(51))
        XCTAssertEqual(WeightUnit.kg.fromPounds(store.liftPrograms[.pushPress]!.trainingMax), 50, accuracy: 1e-6)
        // Next plan is in kg with loadable plates.
        await store.ensurePlan(for: store.nextPlanDate(after: store.today))
        let calc = PlateCalculator(inventory: store.settings.equipment)
        for s in try XCTUnwrap(store.nextWorkout?.strengthSection?.items.first?.plannedSets) {
            XCTAssertNotNil(calc.loadout(for: WeightUnit.kg.fromPounds(s.weight)))
        }
    }
}
