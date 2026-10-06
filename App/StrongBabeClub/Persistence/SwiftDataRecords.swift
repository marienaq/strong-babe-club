import Foundation
import SwiftData
import WorkoutCore

// SwiftData records mirroring IOS-PLAN's data model. Every table carries
// id / createdAt / updatedAt / deletedAt (sync-ready). Ordered children keep
// an explicit `position` because SwiftData to-many relationships are unordered.
// Small nested value types (reasons, coach note, planned sets, settings) are
// stored as JSON blobs.

@Model
final class WorkoutRecord {
    @Attribute(.unique) var id: UUID
    /// ISO date "YYYY-MM-DD" (sorts correctly as a string).
    var date: String
    var status: String
    var source: String
    var reasonsJSON: Data
    var coachNoteJSON: Data?
    var saltsJSON: Data
    var positionJSON: Data?
    var sticker: String?
    var hasFeedback: Bool
    var energy: String?
    var strengthDifficulty: Int?
    var metabolicDifficulty: Int?
    var feedbackNotes: String
    var durationMin: Int?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    @Relationship(deleteRule: .cascade, inverse: \SectionRecord.workout) var sections: [SectionRecord] = []

    init(id: UUID, date: String, status: String, source: String, reasonsJSON: Data, coachNoteJSON: Data?, saltsJSON: Data,
         positionJSON: Data?, sticker: String?, hasFeedback: Bool, energy: String?, strengthDifficulty: Int?,
         metabolicDifficulty: Int?, feedbackNotes: String, durationMin: Int?, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id
        self.date = date
        self.status = status
        self.source = source
        self.reasonsJSON = reasonsJSON
        self.coachNoteJSON = coachNoteJSON
        self.saltsJSON = saltsJSON
        self.positionJSON = positionJSON
        self.sticker = sticker
        self.hasFeedback = hasFeedback
        self.energy = energy
        self.strengthDifficulty = strengthDifficulty
        self.metabolicDifficulty = metabolicDifficulty
        self.feedbackNotes = feedbackNotes
        self.durationMin = durationMin
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

@Model
final class SectionRecord {
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
    var isModified: Bool
    var lift: String?
    var trainingMax: Double?
    var athleteNote: String
    var workout: WorkoutRecord?
    @Relationship(deleteRule: .cascade, inverse: \ItemRecord.section) var items: [ItemRecord] = []
    @Relationship(deleteRule: .cascade, inverse: \RoundLogRecord.section) var roundLogs: [RoundLogRecord] = []

    init(id: UUID, position: Int, kind: String, format: String, name: String?, instructions: String, rounds: Int?,
         workSec: Int?, restSec: Int?, intervalSec: Int?, durationMin: Int?, benchmarkID: UUID?, isModified: Bool,
         lift: String?, trainingMax: Double?, athleteNote: String) {
        self.id = id
        self.position = position
        self.kind = kind
        self.format = format
        self.name = name
        self.instructions = instructions
        self.rounds = rounds
        self.workSec = workSec
        self.restSec = restSec
        self.intervalSec = intervalSec
        self.durationMin = durationMin
        self.benchmarkID = benchmarkID
        self.isModified = isModified
        self.lift = lift
        self.trainingMax = trainingMax
        self.athleteNote = athleteNote
    }
}

@Model
final class ItemRecord {
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

    init(id: UUID, position: Int, letter: String, movementID: String, movementName: String, reps: Int?, repsScheme: String?,
         timeSec: Int?, prescribedWeight: Double?, weightLabel: String?, plannedSetsJSON: Data) {
        self.id = id
        self.position = position
        self.letter = letter
        self.movementID = movementID
        self.movementName = movementName
        self.reps = reps
        self.repsScheme = repsScheme
        self.timeSec = timeSec
        self.prescribedWeight = prescribedWeight
        self.weightLabel = weightLabel
        self.plannedSetsJSON = plannedSetsJSON
    }
}

@Model
final class SetLogRecord {
    @Attribute(.unique) var id: UUID
    var setNumber: Int
    var reps: Int
    var weight: Double
    var completedAt: Date?
    var item: ItemRecord?

    init(id: UUID, setNumber: Int, reps: Int, weight: Double, completedAt: Date?) {
        self.id = id
        self.setNumber = setNumber
        self.reps = reps
        self.weight = weight
        self.completedAt = completedAt
    }
}

@Model
final class RoundLogRecord {
    @Attribute(.unique) var id: UUID
    var roundNumber: Int
    var rounds: Int?
    var reps: Int?
    var timeSec: Int?
    var section: SectionRecord?

    init(id: UUID, roundNumber: Int, rounds: Int?, reps: Int?, timeSec: Int?) {
        self.id = id
        self.roundNumber = roundNumber
        self.rounds = rounds
        self.reps = reps
        self.timeSec = timeSec
    }
}

@Model
final class LiftProgramRecord {
    @Attribute(.unique) var lift: String
    var trainingMax: Double
    var blockStartDate: String?
    var blockWeek: Int?
    var phase: String?
    var source: String
    var updatedAt: Date

    init(lift: String, trainingMax: Double, blockStartDate: String?, blockWeek: Int?, phase: String?, source: String, updatedAt: Date) {
        self.lift = lift
        self.trainingMax = trainingMax
        self.blockStartDate = blockStartDate
        self.blockWeek = blockWeek
        self.phase = phase
        self.source = source
        self.updatedAt = updatedAt
    }
}

@Model
final class BenchmarkRecord {
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

@Model
final class GoalRecord {
    @Attribute(.unique) var id: UUID
    var lift: String
    var targetWeight: Double
    var byDate: String?

    init(id: UUID, lift: String, targetWeight: Double, byDate: String?) {
        self.id = id
        self.lift = lift
        self.targetWeight = targetWeight
        self.byDate = byDate
    }
}

@Model
final class SettingsRecord {
    @Attribute(.unique) var key: String
    var json: Data
    var updatedAt: Date

    init(key: String = "settings", json: Data, updatedAt: Date) {
        self.key = key
        self.json = json
        self.updatedAt = updatedAt
    }
}

enum PersistenceSchema {
    static let models: [any PersistentModel.Type] = [
        WorkoutRecord.self, SectionRecord.self, ItemRecord.self, SetLogRecord.self, RoundLogRecord.self,
        LiftProgramRecord.self, BenchmarkRecord.self, GoalRecord.self, SettingsRecord.self,
    ]
}
