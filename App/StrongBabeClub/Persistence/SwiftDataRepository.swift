import Foundation
import SwiftData
import WorkoutCore

/// SwiftData-backed repository. Workouts are replaced wholesale on save
/// (delete + insert, cascading to children), which keeps the mapping simple
/// and avoids partially-updated graphs.
@MainActor
final class SwiftDataRepository: Repository {
    let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return e
    }()
    private let decoder = JSONDecoder()

    init(container: ModelContainer) {
        self.container = container
    }

    /// On-disk store in Application Support, protected with
    /// NSFileProtectionComplete (unreadable while the device is locked).
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(PersistenceSchema.models)
        if inMemory {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        }
        let dir = try FileProtection.protectedStoreDirectory()
        let config = ModelConfiguration("Journal", schema: schema, url: dir.appendingPathComponent("journal.store"),
                                        allowsSave: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: config)
        FileProtection.protectContents(of: dir)
        return container
    }

    // MARK: Load

    func load() throws -> StoredData {
        var d = StoredData()
        if let s = try context.fetch(FetchDescriptor<SettingsRecord>()).first {
            d.settings = (try? decoder.decode(PlannerSettings.self, from: s.json)) ?? .default
        }
        let records = try context.fetch(FetchDescriptor<WorkoutRecord>(sortBy: [SortDescriptor(\.date)]))
        d.workouts = records.compactMap(toDomain)
        d.liftPrograms = try context.fetch(FetchDescriptor<LiftProgramRecord>()).compactMap { r in
            guard let lift = Lift(rawValue: r.lift) else { return nil }
            return LiftProgram(lift: lift, trainingMax: r.trainingMax, blockStartDate: r.blockStartDate.flatMap(LocalDate.init(iso:)),
                               blockWeek: r.blockWeek, phase: r.phase.flatMap(BlockPhase.init(rawValue:)),
                               source: LiftProgram.Source(rawValue: r.source) ?? .manual)
        }
        d.benchmarks = try context.fetch(FetchDescriptor<BenchmarkRecord>(sortBy: [SortDescriptor(\.quarterSlot)])).compactMap { r in
            guard let t = try? decoder.decode(WorkoutSection.self, from: r.templateJSON) else { return nil }
            return Benchmark(id: r.id, name: r.name, template: t, active: r.active, quarterSlot: r.quarterSlot)
        }
        d.goals = try context.fetch(FetchDescriptor<GoalRecord>()).compactMap { r in
            guard let lift = Lift(rawValue: r.lift) else { return nil }
            return Goal(id: r.id, lift: lift, targetWeight: r.targetWeight, byDate: r.byDate.flatMap(LocalDate.init(iso:)))
        }
        return d
    }

    // MARK: Save

    func save(workouts: [PlannedWorkout]) throws {
        // Delete first and save, so cascades run and unique ids are free
        // before the replacement graph is inserted.
        for w in workouts { try deleteWorkout(id: w.id) }
        try context.save()
        for w in workouts { try insert(w) }
        try context.save()
    }

    func save(settings: PlannerSettings) throws {
        try replace(SettingsRecord.self, with: [SettingsRecord(json: try encoder.encode(settings), updatedAt: Date())])
    }

    func save(liftPrograms: [LiftProgram]) throws {
        try replace(LiftProgramRecord.self, with: liftPrograms.map { p in
            LiftProgramRecord(lift: p.lift.rawValue, trainingMax: p.trainingMax, blockStartDate: p.blockStartDate?.iso,
                              blockWeek: p.blockWeek, phase: p.phase?.rawValue, source: p.source.rawValue, updatedAt: Date())
        })
    }

    func save(benchmarks: [Benchmark]) throws {
        try replace(BenchmarkRecord.self, with: try benchmarks.map { b in
            BenchmarkRecord(id: b.id, name: b.name, templateJSON: try encoder.encode(b.template), active: b.active, quarterSlot: b.quarterSlot)
        })
    }

    func save(goals: [Goal]) throws {
        try replace(GoalRecord.self, with: goals.map { g in
            GoalRecord(id: g.id, lift: g.lift.rawValue, targetWeight: g.targetWeight, byDate: g.byDate?.iso)
        })
    }

    func insert(batch: [PlannedWorkout]) throws {
        do {
            for w in batch { try insert(w) }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func delete(workoutIDs: [UUID]) throws {
        for id in workoutIDs { try deleteWorkout(id: id) }
        try context.save()
    }

    /// Replaces every row of a small table.
    private func replace<T: PersistentModel>(_ type: T.Type, with rows: [T]) throws {
        for old in try context.fetch(FetchDescriptor<T>()) { context.delete(old) }
        try context.save()
        rows.forEach { context.insert($0) }
        try context.save()
    }

    func replaceAll(_ d: StoredData) throws {
        try deleteAll()
        try save(settings: d.settings)
        try save(workouts: d.workouts)
        try save(liftPrograms: d.liftPrograms)
        try save(benchmarks: d.benchmarks)
        try save(goals: d.goals)
    }

    func deleteAll() throws {
        try replace(WorkoutRecord.self, with: [])
        try replace(LiftProgramRecord.self, with: [])
        try replace(BenchmarkRecord.self, with: [])
        try replace(GoalRecord.self, with: [])
        try replace(SettingsRecord.self, with: [])
    }

    // MARK: Mapping

    private func deleteWorkout(id: UUID) throws {
        let target = id
        let existing = try context.fetch(FetchDescriptor<WorkoutRecord>(predicate: #Predicate<WorkoutRecord> { $0.id == target }))
        existing.forEach { context.delete($0) }
    }

    private func insert(_ w: PlannedWorkout) throws {
        let r = WorkoutRecord(id: w.id, date: w.date.iso, status: w.status.rawValue, source: w.source,
                              reasonsJSON: try encoder.encode(w.reasons),
                              coachNoteJSON: try w.coachNote.map { try encoder.encode($0) },
                              saltsJSON: try encoder.encode(w.salts),
                              positionJSON: try w.position.map { try encoder.encode($0) },
                              sticker: w.sticker?.rawValue, hasFeedback: w.feedback != nil, energy: w.feedback?.energy?.rawValue,
                              strengthDifficulty: w.feedback?.strengthDifficulty, metabolicDifficulty: w.feedback?.metabolicDifficulty,
                              feedbackNotes: w.feedback?.notes ?? "", durationMin: w.durationMin,
                              createdAt: w.sync.createdAt, updatedAt: w.sync.updatedAt, deletedAt: w.sync.deletedAt)
        context.insert(r)
        for (si, s) in w.sections.enumerated() {
            let sr = SectionRecord(id: s.id, position: si, kind: s.kind.rawValue, format: s.format.rawValue, name: s.name,
                                   instructions: s.instructions, rounds: s.rounds, workSec: s.workSec, restSec: s.restSec,
                                   intervalSec: s.intervalSec, durationMin: s.durationMin, benchmarkID: s.benchmarkID,
                                   isModified: s.isModified, lift: s.lift?.rawValue, trainingMax: s.trainingMax, athleteNote: s.athleteNote)
            context.insert(sr)
            sr.workout = r
            for (ii, item) in s.items.enumerated() {
                let ir = ItemRecord(id: item.id, position: ii, letter: item.letter, movementID: item.movementID,
                                    movementName: item.movementName, reps: item.reps, repsScheme: item.repsScheme,
                                    timeSec: item.timeSec, prescribedWeight: item.prescribedWeight, weightLabel: item.weightLabel,
                                    plannedSetsJSON: try encoder.encode(item.plannedSets))
                context.insert(ir)
                ir.section = sr
                for log in item.setLogs {
                    let lr = SetLogRecord(id: log.id, setNumber: log.setNumber, reps: log.reps, weight: log.weight, completedAt: log.completedAt)
                    context.insert(lr)
                    lr.item = ir
                }
            }
            for log in s.roundLogs {
                let rr = RoundLogRecord(id: log.id, roundNumber: log.roundNumber, rounds: log.rounds, reps: log.reps, timeSec: log.timeSec)
                context.insert(rr)
                rr.section = sr
            }
        }
    }

    private func toDomain(_ r: WorkoutRecord) -> PlannedWorkout? {
        guard let date = LocalDate(iso: r.date) else { return nil }
        let sections: [WorkoutSection] = r.sections.sorted { $0.position < $1.position }.compactMap { s in
            guard let kind = SectionKind(rawValue: s.kind) else { return nil }
            let items: [SectionItem] = s.items.sorted { $0.position < $1.position }.map { i in
                SectionItem(id: i.id, letter: i.letter, movementID: i.movementID, movementName: i.movementName, reps: i.reps,
                            repsScheme: i.repsScheme, timeSec: i.timeSec, prescribedWeight: i.prescribedWeight,
                            weightLabel: i.weightLabel,
                            plannedSets: (try? decoder.decode([PlannedSet].self, from: i.plannedSetsJSON)) ?? [],
                            setLogs: i.setLogs.sorted { $0.setNumber < $1.setNumber }.map {
                                SetLog(id: $0.id, setNumber: $0.setNumber, reps: $0.reps, weight: $0.weight, completedAt: $0.completedAt)
                            })
            }
            return WorkoutSection(id: s.id, kind: kind, format: SectionFormat(rawValue: s.format) ?? .other, name: s.name,
                                  instructions: s.instructions, rounds: s.rounds, workSec: s.workSec, restSec: s.restSec,
                                  intervalSec: s.intervalSec, durationMin: s.durationMin, benchmarkID: s.benchmarkID,
                                  isModified: s.isModified, lift: s.lift.flatMap(Lift.init(rawValue:)), trainingMax: s.trainingMax,
                                  athleteNote: s.athleteNote, items: items,
                                  roundLogs: s.roundLogs.sorted { $0.roundNumber < $1.roundNumber }.map {
                                      RoundLog(id: $0.id, roundNumber: $0.roundNumber, rounds: $0.rounds, reps: $0.reps, timeSec: $0.timeSec)
                                  })
        }
        let feedback = r.hasFeedback
            ? WorkoutFeedback(energy: r.energy.flatMap(Energy.init(rawValue:)), strengthDifficulty: r.strengthDifficulty,
                              metabolicDifficulty: r.metabolicDifficulty, notes: r.feedbackNotes)
            : nil
        return PlannedWorkout(id: r.id, date: date, status: WorkoutStatus(rawValue: r.status) ?? .planned, sections: sections,
                              reasons: (try? decoder.decode([PlanReason].self, from: r.reasonsJSON)) ?? [],
                              coachNote: r.coachNoteJSON.flatMap { try? decoder.decode(CoachNote.self, from: $0) },
                              sticker: r.sticker.flatMap(StickerID.init(rawValue:)), feedback: feedback,
                              salts: (try? decoder.decode(SectionSalts.self, from: r.saltsJSON)) ?? SectionSalts(),
                              position: r.positionJSON.flatMap { try? decoder.decode(BlockPosition.self, from: $0) },
                              durationMin: r.durationMin, source: r.source,
                              sync: SyncStamp(createdAt: r.createdAt, updatedAt: r.updatedAt, deletedAt: r.deletedAt))
    }
}
