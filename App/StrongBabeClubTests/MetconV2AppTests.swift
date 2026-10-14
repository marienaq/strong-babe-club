import SwiftData
import XCTest
import WorkoutCore
@testable import StrongBabeClub

/// Metcon v2 in the app: persistence of the new fields, migrations of
/// stored data, and re-planning of plans made by the older rules.
/// Fixed clock: Mon Oct 19 2026, 09:00 ET (block 1, week 1).
@MainActor
final class MetconV2AppTests: XCTestCase {
    let monday = Date(timeIntervalSince1970: 1_792_414_800)

    func makeStore(_ data: StoredData = StoredData()) -> AppStore {
        var data = data
        data.settings.onboarded = true
        let store = AppStore(repository: InMemoryRepository(data), clock: { self.monday })
        store.load()
        return store
    }

    /// The old Tabata the v1 planner made (2 moves, 20/10, 8 min).
    func oldTabata() -> WorkoutSection {
        WorkoutSection(kind: .metabolic, format: .tabata, name: "tabata-8-8-fig", instructions: "Tabata: 8 rounds per move · 20 s work / 10 s rest",
                       rounds: 8, workSec: 20, restSec: 10, durationMin: 8,
                       items: [SectionItem(letter: "A", movementID: "jumping-jack", movementName: "Jumping Jacks"),
                               SectionItem(letter: "B", movementID: "air-squat", movementName: "Air Squats")])
    }

    func v1Plan(_ date: LocalDate, salt: UInt64 = 2) -> PlannedWorkout {
        var salts = SectionSalts()
        salts.metabolic = salt
        return PlannedWorkout(date: date, status: .planned, sections: [oldTabata()], salts: salts, source: "rules-v1",
                              sync: SyncStamp(createdAt: Date(timeIntervalSince1970: 1_792_000_000)))
    }

    /// Untouched "rules-v1" plans are re-planned under v2 on the first launch, keeping id and shuffles.
    func testUntouchedV1PlansAreReplanned() async throws {
        let today = v1Plan(LocalDate(2026, 10, 19))
        let wednesday = v1Plan(LocalDate(2026, 10, 21), salt: 0)
        let store = makeStore(StoredData(workouts: [today, wednesday]))
        await store.prepare()
        for old in [today, wednesday] {
            let w = try XCTUnwrap(store.workout(id: old.id))
            XCTAssertEqual(w.source, "rules-v2")
            XCTAssertEqual(w.salts, old.salts)
            XCTAssertEqual(w.sync.createdAt, old.sync.createdAt)
            let m = try XCTUnwrap(w.metabolicSection)
            XCTAssertTrue((3...5).contains(m.items.count))
            XCTAssertTrue((720...1440).contains(m.estimatedSeconds))
            XCTAssertNotNil(m.stimulus)
        }
    }

    /// Logged or done plans are never changed.
    func testTouchedPlansAreKept() async throws {
        var logged = v1Plan(LocalDate(2026, 10, 19))
        logged.sections[0].roundLogs = [RoundLog(roundNumber: 1, reps: 12)]
        let store = makeStore(StoredData(workouts: [logged]))
        await store.prepare()
        XCTAssertEqual(store.workout(id: logged.id), logged)
    }

    /// Stations stored as 60/60 intervals by older imports become stations (MC-11).
    func testLegacyStationsAreMigratedOnLoad() throws {
        let legacy = WorkoutSection(kind: .metabolic, format: .interval, instructions: "4 rounds of stations", rounds: 4, workSec: 60, restSec: 60,
                                    items: ["kb-swing", "push-up", "air-squat", "sit-up"].enumerated().map {
                                        SectionItem(letter: ["A", "B", "C", "D"][$0.offset], movementID: $0.element, movementName: $0.element)
                                    }, roundLogs: [RoundLog(roundNumber: 1, reps: 40)])
        let w = PlannedWorkout(date: LocalDate(2025, 3, 3), status: .done, sections: [legacy], source: "import")
        let repo = InMemoryRepository(StoredData(settings: { var s = PlannerSettings.default; s.onboarded = true; return s }(), workouts: [w]))
        let store = AppStore(repository: repo, clock: { self.monday })
        store.load()
        let s = try XCTUnwrap(store.workout(id: w.id)?.metabolicSection)
        XCTAssertEqual(s.format, .stations)
        XCTAssertEqual(s.roundRestSec, 60)
        XCTAssertEqual(s.estimatedSeconds, 1140)
        XCTAssertEqual(s.roundLogs, legacy.roundLogs, "logs untouched")
        XCTAssertEqual(try repo.load().workouts.first?.metabolicSection?.format, .stations, "saved")
    }

    /// A stored benchmark that breaks the rules is retired (unchanged) and replaced from history (Q5).
    func testRuleBreakingBenchmarkIsRetiredOnLoad() throws {
        let two = Benchmark(name: "amrap-5-4-twosie", template: WorkoutSection(
            kind: .metabolic, format: .amrapWithRest, name: "amrap-5-4-twosie", instructions: "", rounds: 5, workSec: 240, restSec: 60,
            items: [SectionItem(letter: "A", movementID: "kb-swing", movementName: "KB Swings", reps: 10),
                    SectionItem(letter: "B", movementID: "push-up", movementName: "Push-Ups", reps: 5)]), quarterSlot: 2)
        let piece = WorkoutSection(kind: .metabolic, format: .amrap, instructions: "", durationMin: 15,
                                   items: [SectionItem(letter: "A", movementID: "kb-swing", movementName: "KB Swings", reps: 8),
                                           SectionItem(letter: "B", movementID: "push-up", movementName: "Push-Ups", reps: 4),
                                           SectionItem(letter: "C", movementID: "up-down", movementName: "Up/Downs", reps: 4)],
                                   roundLogs: [RoundLog(roundNumber: 1, rounds: 10, reps: 2)])
        let history = (0..<3).map { PlannedWorkout(date: LocalDate(2025, 5, 5).adding(days: 7 * $0), status: .done, sections: [piece], source: "import") }
        let store = makeStore(StoredData(workouts: history, benchmarks: [two]))
        let retired = try XCTUnwrap(store.benchmarks.first { $0.id == two.id })
        XCTAssertEqual(retired.retiredReason, "Only 2 moves; metcons need 3–5.")
        XCTAssertFalse(retired.active)
        XCTAssertEqual(retired.template, two.template)
        let new = try XCTUnwrap(store.benchmarks.first { $0.replacesID == two.id })
        XCTAssertEqual(new.quarterSlot, 2)
        XCTAssertEqual(new.template.items.count, 3)

        var off = PlannerSettings.default
        off.autoReplaceRetiredBenchmarks = false
        let noReplace = makeStore(StoredData(settings: off, workouts: history, benchmarks: [two]))
        XCTAssertEqual(noReplace.benchmarks.count, 1)
        XCTAssertTrue(noReplace.benchmarks[0].isRetired)
    }

    /// The new section and benchmark fields round-trip through SwiftData (MC-12).
    func testNewFieldsRoundTrip() throws {
        let repo = SwiftDataRepository(container: try SwiftDataRepository.makeContainer(inMemory: true))
        var stations = WorkoutSection(kind: .metabolic, format: .stations, name: "stations-4-19-otter", instructions: "4 rounds", rounds: 4,
                                      workSec: 60, restSec: 0, items: [SectionItem(letter: "A", movementID: "kb-swing", movementName: "KB Swings", timeSec: 60)])
        stations.roundRestSec = 60
        stations.stimulus = .repeat
        stations.expectedScore = 4.5
        let w = PlannedWorkout(date: LocalDate(2026, 10, 19), sections: [stations], source: "rules-v2")
        try repo.save(workouts: [w])
        XCTAssertEqual(try repo.load().workouts, [w])
        let b = Benchmark(name: "amrap-5-4-fig", template: stations, active: false, quarterSlot: 1,
                          retiredReason: "Only 2 moves; metcons need 3–5.", replacesID: UUID())
        try repo.save(benchmarks: [b])
        XCTAssertEqual(try repo.load().benchmarks, [b])
    }

    /// An on-disk store written by the previous version (no metcon v2
    /// columns) opens with the current schema: history survives, the new
    /// fields read as nil.
    func testStoreFromBeforeV2OpensWithHistoryIntact() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("prev2-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let workoutID = UUID(), sectionID = UUID(), benchmarkID = UUID()
        let oldTemplate = Data(#"{"id":"2C3B0A3A-1B0D-4E4C-9B0B-0E7E1B5C0A11","kind":"metabolic","format":"tabata","instructions":"old","rounds":8,"workSec":20,"restSec":10,"isModified":false,"athleteNote":"","items":[],"roundLogs":[]}"#.utf8)
        do {
            let schema = Schema(PreV2Schema.models)
            let old = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let ctx = old.mainContext
            let w = PreV2Schema.WorkoutRecord(id: workoutID, date: "2026-10-12", status: "done", source: "rules-v1",
                                              reasonsJSON: Data("[]".utf8), saltsJSON: Data("{}".utf8), feedbackNotes: "felt good",
                                              createdAt: monday, updatedAt: monday)
            ctx.insert(w)
            let s = PreV2Schema.SectionRecord(id: sectionID, position: 0, kind: "metabolic", format: "tabata", name: "tabata-8-8-fig",
                                              instructions: "old", rounds: 8, workSec: 20, restSec: 10)
            ctx.insert(s)
            s.workout = w
            let log = PreV2Schema.RoundLogRecord(id: UUID(), roundNumber: 1, reps: 14)
            ctx.insert(log)
            log.section = s
            ctx.insert(PreV2Schema.BenchmarkRecord(id: benchmarkID, name: "tabata-8-8-fig", templateJSON: oldTemplate, active: true, quarterSlot: 0))
            try ctx.save()
        }
        let schema = Schema(PersistenceSchema.models)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        let d = try SwiftDataRepository(container: container).load()
        let w = try XCTUnwrap(d.workouts.first)
        XCTAssertEqual(w.id, workoutID)
        XCTAssertEqual(w.status, .done)
        let s = try XCTUnwrap(w.metabolicSection)
        XCTAssertEqual(s.id, sectionID)
        XCTAssertEqual(s.roundLogs.map(\.reps), [14])
        XCTAssertNil(s.roundRestSec)
        XCTAssertNil(s.stimulus)
        XCTAssertNil(s.expectedScore)
        let b = try XCTUnwrap(d.benchmarks.first)
        XCTAssertEqual(b.id, benchmarkID)
        XCTAssertNil(b.retiredReason)
        XCTAssertNil(b.replacesID)
        XCTAssertNil(b.template.roundRestSec)
    }

    /// A pool too small for a metcon explains how to fix it.
    func testTooFewMovesMessage() {
        XCTAssertEqual(PlannerError.metconPoolTooSmall(available: 2).userMessage,
                       "Your equipment and limits leave fewer than 3 metcon moves. Add equipment or relax a limit in Settings.")
    }
}

/// A copy of the SwiftData schema as shipped before metcon v2 (no
/// roundRestSec / stimulus / expectedScore on sections, no retiredReason /
/// replacesID on benchmarks). Used only to write an old store in tests.
enum PreV2Schema {
    static let models: [any PersistentModel.Type] = [
        WorkoutRecord.self, SectionRecord.self, ItemRecord.self, SetLogRecord.self, RoundLogRecord.self,
        LiftProgramRecord.self, BenchmarkRecord.self, GoalRecord.self, SettingsRecord.self,
    ]

    @Model final class WorkoutRecord {
        @Attribute(.unique) var id: UUID
        var date: String
        var status: String
        var source: String
        var reasonsJSON: Data
        var coachNoteJSON: Data?
        var saltsJSON: Data
        var positionJSON: Data?
        var sticker: String?
        var hasFeedback: Bool = false
        var energy: String?
        var strengthDifficulty: Int?
        var metabolicDifficulty: Int?
        var feedbackNotes: String
        var durationMin: Int?
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        @Relationship(deleteRule: .cascade, inverse: \SectionRecord.workout) var sections: [SectionRecord] = []

        init(id: UUID, date: String, status: String, source: String, reasonsJSON: Data, saltsJSON: Data, feedbackNotes: String,
             createdAt: Date, updatedAt: Date) {
            self.id = id
            self.date = date
            self.status = status
            self.source = source
            self.reasonsJSON = reasonsJSON
            self.saltsJSON = saltsJSON
            self.feedbackNotes = feedbackNotes
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    @Model final class SectionRecord {
        @Attribute(.unique) var id: UUID
        var position: Int
        var kind: String
        var format: String
        var name: String?
        var instructions: String
        var rounds: Int?
        var workSec: Int?
        var restSec: Int?
        var intervalSec: Int?
        var durationMin: Int?
        var benchmarkID: UUID?
        var isModified: Bool = false
        var lift: String?
        var trainingMax: Double?
        var athleteNote: String = ""
        var workout: WorkoutRecord?
        @Relationship(deleteRule: .cascade, inverse: \ItemRecord.section) var items: [ItemRecord] = []
        @Relationship(deleteRule: .cascade, inverse: \RoundLogRecord.section) var roundLogs: [RoundLogRecord] = []

        init(id: UUID, position: Int, kind: String, format: String, name: String?, instructions: String, rounds: Int?, workSec: Int?, restSec: Int?) {
            self.id = id
            self.position = position
            self.kind = kind
            self.format = format
            self.name = name
            self.instructions = instructions
            self.rounds = rounds
            self.workSec = workSec
            self.restSec = restSec
        }
    }

    @Model final class ItemRecord {
        @Attribute(.unique) var id: UUID
        var position: Int
        var letter: String
        var movementID: String
        var movementName: String
        var reps: Int?
        var repsScheme: String?
        var timeSec: Int?
        var prescribedWeight: Double?
        var weightLabel: String?
        var plannedSetsJSON: Data
        var section: SectionRecord?
        @Relationship(deleteRule: .cascade, inverse: \SetLogRecord.item) var setLogs: [SetLogRecord] = []

        init(id: UUID, position: Int, letter: String, movementID: String, movementName: String, plannedSetsJSON: Data) {
            self.id = id
            self.position = position
            self.letter = letter
            self.movementID = movementID
            self.movementName = movementName
            self.plannedSetsJSON = plannedSetsJSON
        }
    }

    @Model final class SetLogRecord {
        @Attribute(.unique) var id: UUID
        var setNumber: Int
        var reps: Int
        var weight: Double
        var completedAt: Date?
        var item: ItemRecord?

        init(id: UUID, setNumber: Int, reps: Int, weight: Double) {
            self.id = id
            self.setNumber = setNumber
            self.reps = reps
            self.weight = weight
        }
    }

    @Model final class RoundLogRecord {
        @Attribute(.unique) var id: UUID
        var roundNumber: Int
        var rounds: Int?
        var reps: Int?
        var timeSec: Int?
        var section: SectionRecord?

        init(id: UUID, roundNumber: Int, reps: Int?) {
            self.id = id
            self.roundNumber = roundNumber
            self.reps = reps
        }
    }

    @Model final class LiftProgramRecord {
        @Attribute(.unique) var lift: String
        var trainingMax: Double
        var blockStartDate: String?
        var blockWeek: Int?
        var phase: String?
        var source: String
        var updatedAt: Date

        init(lift: String, trainingMax: Double, source: String, updatedAt: Date) {
            self.lift = lift
            self.trainingMax = trainingMax
            self.source = source
            self.updatedAt = updatedAt
        }
    }

    @Model final class BenchmarkRecord {
        @Attribute(.unique) var id: UUID
        var name: String
        var templateJSON: Data
        var active: Bool
        var quarterSlot: Int

        init(id: UUID, name: String, templateJSON: Data, active: Bool, quarterSlot: Int) {
            self.id = id
            self.name = name
            self.templateJSON = templateJSON
            self.active = active
            self.quarterSlot = quarterSlot
        }
    }

    @Model final class GoalRecord {
        @Attribute(.unique) var id: UUID
        var lift: String
        var targetWeight: Double
        var byDate: String?

        init(id: UUID, lift: String, targetWeight: Double) {
            self.id = id
            self.lift = lift
            self.targetWeight = targetWeight
        }
    }

    @Model final class SettingsRecord {
        @Attribute(.unique) var key: String
        var json: Data
        var updatedAt: Date

        init(key: String = "settings", json: Data, updatedAt: Date) {
            self.key = key
            self.json = json
            self.updatedAt = updatedAt
        }
    }
}
