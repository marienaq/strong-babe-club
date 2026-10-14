import Foundation

/// Sync-ready bookkeeping shared by every persisted record.
public struct SyncStamp: Codable, Hashable, Sendable {
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(createdAt: Date, updatedAt: Date? = nil, deletedAt: Date? = nil) {
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
    }
}

public enum WorkoutStatus: String, Codable, Sendable, CaseIterable {
    case planned, done, skipped, excused
}

public enum SectionKind: String, Codable, Sendable, CaseIterable {
    case warmup, strength, metabolic, cooldown

    public var displayName: String {
        switch self {
        case .warmup: return "warm-up"
        case .strength: return "strength"
        case .metabolic: return "metabolic"
        case .cooldown: return "cool-down"
        }
    }
}

public enum SectionFormat: String, Codable, Sendable, CaseIterable {
    /// "3 rounds of A/B/C/D" (warm-ups).
    case rounds
    /// Every N min for M min, going up each set (strength, EMOM style).
    case everyNMin = "every_n_min"
    /// N sets going up, rest as needed.
    case setsGoingUp = "sets_going_up"
    /// e.g. 10-8-6-4-2
    case ladder
    /// Work / rest intervals: each round is a full circuit of the moves.
    case interval
    /// Timed stations back to back (60 s each), rest after each full round.
    case stations
    /// One AMRAP.
    case amrap
    /// Several AMRAPs with rest between ("amrap-5-4-...").
    case amrapWithRest = "amrap_with_rest"
    /// Descending ladder for time.
    case forTime = "for_time"
    case tabata
    case emom
    /// Fixed sets of reps (cool-down core work "15-15-15-15-15").
    case sets
    case other

    /// Name prefix used in `structure-rounds-time-word`.
    public var nameStructure: String {
        switch self {
        case .amrap, .amrapWithRest: return "amrap"
        case .forTime, .ladder: return "fortime"
        case .interval: return "interval"
        case .stations: return "stations"
        case .tabata: return "tabata"
        case .emom, .everyNMin: return "emom"
        default: return rawValue
        }
    }

    /// Friendly name for lists ("tabata", "for time").
    public var displayName: String {
        switch self {
        case .amrap, .amrapWithRest: return "amrap"
        case .forTime: return "for time"
        case .everyNMin, .emom: return "emom"
        case .setsGoingUp: return "sets"
        default: return rawValue
        }
    }

    /// Whether a lower score is better (for-time pieces).
    public var lowerIsBetter: Bool { self == .forTime }
}

/// One prescribed strength set ("set 4: 5 reps at 105 lb").
public struct PlannedSet: Codable, Hashable, Sendable {
    public var setNumber: Int
    public var reps: Int
    public var weight: Double
    public var percentOfTM: Double?

    public init(setNumber: Int, reps: Int, weight: Double, percentOfTM: Double? = nil) {
        self.setNumber = setNumber
        self.reps = reps
        self.weight = weight
        self.percentOfTM = percentOfTM
    }
}

/// A logged strength set.
public struct SetLog: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var setNumber: Int
    public var reps: Int
    public var weight: Double
    public var completedAt: Date?

    public init(id: UUID = UUID(), setNumber: Int, reps: Int, weight: Double, completedAt: Date? = nil) {
        self.id = id
        self.setNumber = setNumber
        self.reps = reps
        self.weight = weight
        self.completedAt = completedAt
    }
}

/// A logged metabolic round (rounds+reps, reps, or a time).
public struct RoundLog: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var roundNumber: Int
    public var rounds: Int?
    public var reps: Int?
    public var timeSec: Int?

    public init(id: UUID = UUID(), roundNumber: Int, rounds: Int? = nil, reps: Int? = nil, timeSec: Int? = nil) {
        self.id = id
        self.roundNumber = roundNumber
        self.rounds = rounds
        self.reps = reps
        self.timeSec = timeSec
    }

    public var isEmpty: Bool { rounds == nil && reps == nil && timeSec == nil }
}

public struct SectionItem: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var letter: String
    public var movementID: String
    public var movementName: String
    public var reps: Int?
    public var repsScheme: String?
    public var timeSec: Int?
    public var prescribedWeight: Double?
    /// Display label for the weight ("2 × 20 lb", "35 lb KB", "24\" box").
    public var weightLabel: String?
    public var plannedSets: [PlannedSet]
    public var setLogs: [SetLog]

    public init(id: UUID = UUID(), letter: String, movementID: String, movementName: String, reps: Int? = nil,
                repsScheme: String? = nil, timeSec: Int? = nil, prescribedWeight: Double? = nil,
                weightLabel: String? = nil, plannedSets: [PlannedSet] = [], setLogs: [SetLog] = []) {
        self.id = id
        self.letter = letter
        self.movementID = movementID
        self.movementName = movementName
        self.reps = reps
        self.repsScheme = repsScheme
        self.timeSec = timeSec
        self.prescribedWeight = prescribedWeight
        self.weightLabel = weightLabel
        self.plannedSets = plannedSets
        self.setLogs = setLogs
    }

    /// "3 DB hang squat cleans", "15-15-15-15-15 sit-ups", "30 s plank hold"
    public var displayLine: String {
        if let scheme = repsScheme { return "\(scheme) \(movementName)" }
        if let t = timeSec { return "\(t) s \(movementName)" }
        if let r = reps { return "\(r) \(movementName)" }
        return movementName
    }

    /// Heaviest logged weight (strength top set).
    public var topLoggedWeight: Double? { setLogs.map(\.weight).max() }
}

public struct WorkoutSection: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var kind: SectionKind
    public var format: SectionFormat
    /// Metabolic name such as `amrap-5-4-fungi`.
    public var name: String?
    public var instructions: String
    public var rounds: Int?
    public var workSec: Int?
    public var restSec: Int?
    public var intervalSec: Int?
    public var durationMin: Int?
    public var benchmarkID: UUID?
    /// A benchmark whose moves were substituted for a limit (not like-for-like).
    public var isModified: Bool
    public var lift: Lift?
    /// Training max used to build the strength section.
    public var trainingMax: Double?
    public var athleteNote: String
    public var items: [SectionItem]
    public var roundLogs: [RoundLog]
    /// Stations: rest after each full round. Tabata: rest between moves
    /// (0 = the normal 20 s rest is the change-over). Nil in older data.
    public var roundRestSec: Int?
    /// The intended feel of a metcon. Nil in older data.
    public var stimulus: MetconStimulus?
    /// Expected rounds per window (AMRAPs) or finish seconds (for time).
    /// Used to learn the athlete's pace. Nil in older data and timed formats.
    public var expectedScore: Double?

    public init(id: UUID = UUID(), kind: SectionKind, format: SectionFormat, name: String? = nil, instructions: String,
                rounds: Int? = nil, workSec: Int? = nil, restSec: Int? = nil, intervalSec: Int? = nil,
                durationMin: Int? = nil, benchmarkID: UUID? = nil, isModified: Bool = false, lift: Lift? = nil,
                trainingMax: Double? = nil, athleteNote: String = "", items: [SectionItem] = [], roundLogs: [RoundLog] = [],
                roundRestSec: Int? = nil, stimulus: MetconStimulus? = nil, expectedScore: Double? = nil) {
        self.id = id
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
        self.items = items
        self.roundLogs = roundLogs
        self.roundRestSec = roundRestSec
        self.stimulus = stimulus
        self.expectedScore = expectedScore
    }

    /// Strength: the main lift(s); `secondaryItems` are the light accessories.
    public var mainItems: [SectionItem] {
        let mains = items.filter { !$0.plannedSets.isEmpty || Lift(movementName: $0.movementName) != nil }
        return mains.isEmpty ? items : mains
    }
    public var secondaryItems: [SectionItem] {
        let mainIDs = Set(mainItems.map(\.id))
        return items.filter { !mainIDs.contains($0.id) }
    }

    /// Reps in one full round (used to turn rounds+reps into total reps).
    public var repsPerRound: Int { items.compactMap(\.reps).reduce(0, +) }

    /// Rounds the athlete logs, matching the prescription and the timer:
    /// interval circuits / station rounds / AMRAP-with-rest blocks, Tabata
    /// rounds × moves, one row per EMOM interval, one row per ladder rung,
    /// one row for a single AMRAP.
    public var prescribedRounds: Int {
        switch format {
        case .tabata: return max(1, (rounds ?? 8) * max(1, items.count))
        case .interval, .stations, .amrapWithRest: return max(1, rounds ?? 1)
        case .emom:
            guard let d = durationMin else { return max(1, rounds ?? 1) }
            return max(1, d * 60 / max(1, intervalSec ?? 60))
        case .forTime, .ladder:
            let scheme = items.compactMap(\.repsScheme).first
            let rungs = scheme.map { $0.split(separator: "-").count } ?? 1
            return max(1, min(rungs, 20))
        case .amrap: return 1
        default: return max(1, rounds ?? 1)
        }
    }

    /// Short summary for the Today list ("3 rounds", "6 × 5", "amrap").
    public var shortSummary: String { todayDetail(compact: true) }

    /// Grey detail text on the Today list. `compact: false` names the lift
    /// ("6 × 3 Front Squat"); compact drops what can go ("Front Squat").
    public func todayDetail(compact: Bool) -> String {
        switch kind {
        case .warmup:
            let r = "\(rounds ?? 3) rounds"
            return compact ? r : r + (items.first.map { " · " + $0.movementName.lowercased() + " +\(max(0, items.count - 1))" } ?? "")
        case .strength:
            let mains = mainItems
            let names = mains.map(\.movementName).joined(separator: " + ")
            if mains.count > 1 { return names }
            if let sets = mains.first?.plannedSets, let first = sets.first {
                let allSame = sets.allSatisfy { $0.reps == first.reps }
                let scheme = allSame ? "\(sets.count) × \(first.reps)" : "\(sets.count) sets"
                return compact ? names : "\(scheme) \(names)"
            }
            return names
        case .metabolic:
            let label = format.displayName
            let minutes = WorkoutDuration.estimate(self)
            if compact { return label }
            return benchmarkID != nil ? "\(label) · benchmark" : "\(label) · \(minutes) min"
        case .cooldown:
            let core = items.first.map { $0.movementName.lowercased() } ?? "core"
            return compact || items.count < 2 ? core : core + " + stretch"
        }
    }
}

public enum Energy: String, Codable, Sendable, CaseIterable {
    case high, okay, sleepy
}

public struct WorkoutFeedback: Codable, Hashable, Sendable {
    public var energy: Energy?
    /// 1 easy ... 5 brutal
    public var strengthDifficulty: Int?
    public var metabolicDifficulty: Int?
    public var notes: String

    public init(energy: Energy? = nil, strengthDifficulty: Int? = nil, metabolicDifficulty: Int? = nil, notes: String = "") {
        self.energy = energy
        self.strengthDifficulty = strengthDifficulty.map { min(max($0, 1), 5) }
        self.metabolicDifficulty = metabolicDifficulty.map { min(max($0, 1), 5) }
        self.notes = String(notes.prefix(4000))
    }

    /// Low energy or a 4-5 difficulty rating.
    public var wasRough: Bool {
        energy == .sleepy || (strengthDifficulty ?? 0) >= 4 || (metabolicDifficulty ?? 0) >= 4
    }
}

/// Per-section shuffle counters. Same date + same salts = same workout.
public struct SectionSalts: Codable, Hashable, Sendable {
    public var warmup: UInt64 = 0
    public var strength: UInt64 = 0
    public var metabolic: UInt64 = 0
    public var cooldown: UInt64 = 0

    public init() {}

    public subscript(kind: SectionKind) -> UInt64 {
        get {
            switch kind {
            case .warmup: return warmup
            case .strength: return strength
            case .metabolic: return metabolic
            case .cooldown: return cooldown
            }
        }
        set {
            switch kind {
            case .warmup: warmup = newValue
            case .strength: strength = newValue
            case .metabolic: metabolic = newValue
            case .cooldown: cooldown = newValue
            }
        }
    }
}

/// One explanation produced by a rule that fired while planning.
public struct PlanReason: Codable, Hashable, Sendable {
    public var section: SectionKind?
    public var rule: String
    public var text: String

    public init(section: SectionKind?, rule: String, text: String) {
        self.section = section
        self.rule = rule
        self.text = text
    }
}

public struct PlannedWorkout: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var date: LocalDate
    public var status: WorkoutStatus
    public var sections: [WorkoutSection]
    public var reasons: [PlanReason]
    public var coachNote: CoachNote?
    public var sticker: StickerID?
    public var feedback: WorkoutFeedback?
    public var salts: SectionSalts
    public var position: BlockPosition?
    public var durationMin: Int?
    /// Where the workout came from ("planner", "import", ...).
    public var source: String
    public var sync: SyncStamp

    public init(id: UUID = UUID(), date: LocalDate, status: WorkoutStatus = .planned, sections: [WorkoutSection] = [],
                reasons: [PlanReason] = [], coachNote: CoachNote? = nil, sticker: StickerID? = nil,
                feedback: WorkoutFeedback? = nil, salts: SectionSalts = SectionSalts(), position: BlockPosition? = nil,
                durationMin: Int? = nil, source: String = "planner", sync: SyncStamp = SyncStamp(createdAt: Date(timeIntervalSince1970: 0))) {
        self.id = id
        self.date = date
        self.status = status
        self.sections = sections
        self.reasons = reasons
        self.coachNote = coachNote
        self.sticker = sticker
        self.feedback = feedback
        self.salts = salts
        self.position = position
        self.durationMin = durationMin
        self.source = source
        self.sync = sync
    }

    public func section(_ kind: SectionKind) -> WorkoutSection? { sections.first { $0.kind == kind } }
    public var strengthSection: WorkoutSection? { section(.strength) }
    public var metabolicSection: WorkoutSection? { section(.metabolic) }

    /// Main lift of the day (the first strength lift).
    public var mainLift: Lift? { strengthSection?.lift ?? strengthSection?.items.compactMap { Lift(movementName: $0.movementName) }.first }

    public func reasons(for kind: SectionKind) -> [PlanReason] { reasons.filter { $0.section == kind } }

    public var isDeleted: Bool { sync.deletedAt != nil }

    /// Estimated length in minutes.
    public var estimatedMinutes: Int { sections.map(WorkoutDuration.estimate).reduce(0, +) }
}

public struct LiftProgram: Codable, Hashable, Sendable {
    public enum Source: String, Codable, Sendable { case history, test, manual, progression, calibrating }

    public var lift: Lift
    public var trainingMax: Double
    public var blockStartDate: LocalDate?
    public var blockWeek: Int?
    public var phase: BlockPhase?
    public var source: Source

    public init(lift: Lift, trainingMax: Double, blockStartDate: LocalDate? = nil, blockWeek: Int? = nil,
                phase: BlockPhase? = nil, source: Source = .history) {
        self.lift = lift
        self.trainingMax = trainingMax
        self.blockStartDate = blockStartDate
        self.blockWeek = blockWeek
        self.phase = phase
        self.source = source
    }
}

public struct Benchmark: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    /// The exact metabolic section to repeat (moves, weights, timing).
    public var template: WorkoutSection
    public var active: Bool
    /// 0-based slot inside the 13-week block (slot n is due from week 1 + 2n).
    public var quarterSlot: Int
    /// Set when the benchmark breaks the metcon rules ("Only 2 moves; ...").
    /// Retired benchmarks are never scheduled; their template is never changed.
    public var retiredReason: String?
    /// Added automatically to replace this retired benchmark (shown as "new").
    public var replacesID: UUID?

    public init(id: UUID = UUID(), name: String, template: WorkoutSection, active: Bool = true, quarterSlot: Int,
                retiredReason: String? = nil, replacesID: UUID? = nil) {
        self.id = id
        self.name = name
        self.template = template
        self.active = active
        self.quarterSlot = quarterSlot
        self.retiredReason = retiredReason
        self.replacesID = replacesID
    }

    public var isRetired: Bool { retiredReason != nil }
}

public struct Goal: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var lift: Lift
    public var targetWeight: Double
    public var byDate: LocalDate?

    public init(id: UUID = UUID(), lift: Lift, targetWeight: Double, byDate: LocalDate? = nil) {
        self.id = id
        self.lift = lift
        self.targetWeight = targetWeight
        self.byDate = byDate
    }
}

/// Section length estimates. Metcons are estimated in seconds from their
/// structure (spec §5.2); everything else in whole minutes.
public enum WorkoutDuration {
    /// Estimated minutes, rounded half up.
    public static func estimate(_ s: WorkoutSection) -> Int {
        switch s.kind {
        case .warmup: return max(4, (s.rounds ?? 3) * 3)
        case .cooldown: return 6
        case .strength:
            if let i = s.intervalSec {
                // Two lifts share each interval ("every 3 min: A then B").
                let sets = s.items.map(\.plannedSets.count).max() ?? 6
                return max(8, Int((Double(i * sets) / 60).rounded()))
            }
            return 14
        case .metabolic:
            return (estimateSeconds(s) + 30) / 60
        }
    }

    /// Estimated seconds. No trailing rest is counted after the last work
    /// period (the same as the timer).
    public static func estimateSeconds(_ s: WorkoutSection) -> Int {
        guard s.kind == .metabolic else { return estimate(s) * 60 }
        let n = max(1, s.items.count)
        let r = max(1, s.rounds ?? 1)
        let x = max(0, s.restSec ?? 0)
        switch s.format {
        case .amrap, .forTime, .ladder:
            return (s.durationMin ?? 12) * 60
        case .emom, .everyNMin:
            if let d = s.durationMin { return d * 60 }
            return r * (s.intervalSec ?? 60)
        case .amrapWithRest:
            let w = s.workSec ?? (s.durationMin ?? 4) * 60
            return r * w + (r - 1) * x
        case .stations:
            let w = s.workSec ?? 60
            return r * (n * w + (n - 1) * x) + (r - 1) * (s.roundRestSec ?? 60)
        case .interval:
            let w = s.workSec ?? 40
            return r * n * (w + x) - x
        case .tabata:
            // One move at a time: R rounds of work/rest, then the next move.
            let w = s.workSec ?? 40
            let between = (s.roundRestSec ?? 0) > 0 ? s.roundRestSec! : x
            return n * r * w + n * (r - 1) * x + (n - 1) * between
        default:
            if let d = s.durationMin { return d * 60 }
            let w = s.workSec ?? 0
            return w > 0 ? r * (w + x) : 720
        }
    }
}

extension WorkoutSection {
    /// Estimated length in seconds (metcons) or minutes × 60.
    public var estimatedSeconds: Int { WorkoutDuration.estimateSeconds(self) }
}
