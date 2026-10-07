import Foundation

/// A metabolic score summed over rounds.
public enum MetabolicScore: Hashable, Sendable, CustomStringConvertible {
    /// AMRAP-style rounds + extra reps.
    case roundsReps(rounds: Int, reps: Int)
    /// Total reps (intervals, Tabata).
    case reps(Int)
    /// For-time, in seconds (lower is better).
    case time(seconds: Int)

    /// Combines round logs into one score for the section's format.
    public static func from(_ logs: [RoundLog], format: SectionFormat) -> MetabolicScore? {
        let logs = logs.filter { !$0.isEmpty }
        guard !logs.isEmpty else { return nil }
        if format.lowerIsBetter || logs.allSatisfy({ $0.timeSec != nil && $0.rounds == nil && $0.reps == nil }) {
            let t = logs.compactMap(\.timeSec).reduce(0, +)
            return t > 0 ? .time(seconds: t) : nil
        }
        let rounds = logs.compactMap(\.rounds).reduce(0, +)
        let reps = logs.compactMap(\.reps).reduce(0, +)
        if logs.contains(where: { $0.rounds != nil }) { return .roundsReps(rounds: rounds, reps: reps) }
        return .reps(reps)
    }

    /// Total reps given the reps in one full round.
    public func totalReps(repsPerRound: Int) -> Int? {
        switch self {
        case .roundsReps(let r, let x): return r * max(0, repsPerRound) + x
        case .reps(let n): return n
        case .time: return nil
        }
    }

    public var description: String {
        switch self {
        case .roundsReps(let r, let x): return "\(r) + \(x)"
        case .reps(let n): return "\(n) reps"
        case .time(let s): return String(format: "%d:%02d", s / 60, s % 60)
        }
    }

    /// Positive when `self` beats `other` (reps for AMRAPs, seconds for time).
    public func improvement(over other: MetabolicScore, repsPerRound: Int) -> Int? {
        switch (self, other) {
        case (.time(let a), .time(let b)): return b - a
        case (.time, _), (_, .time): return nil
        default:
            guard let a = totalReps(repsPerRound: repsPerRound), let b = other.totalReps(repsPerRound: repsPerRound) else { return nil }
            return a - b
        }
    }
}

public struct BenchmarkResult: Hashable, Sendable {
    public var date: LocalDate
    public var block: Int
    public var score: MetabolicScore
    public var roundLogs: [RoundLog]
    public var modified: Bool
}

public enum PRDetector {
    /// Lifts whose top logged weight today beats every earlier session.
    public static func strengthPRs(in workout: PlannedWorkout, history: [PlannedWorkout]) -> [Lift: Double] {
        var out: [Lift: Double] = [:]
        guard let s = workout.strengthSection else { return out }
        let earlier = history.filter { $0.date < workout.date && $0.id != workout.id }
        for item in s.items {
            guard let lift = Lift(movementName: item.movementName), let top = item.setLogs.filter({ $0.reps > 0 }).map(\.weight).max() else { continue }
            let best = LiftHistory.sessions(of: lift, in: earlier).compactMap(\.topWeight).max() ?? 0
            if top > best && best > 0 { out[lift] = top }
        }
        return out
    }

    /// The most recent earlier result for a benchmark.
    public static func previousBenchmarkResult(_ benchmarkID: UUID, before date: LocalDate, history: [PlannedWorkout],
                                               calendar: ProgramCalendar) -> BenchmarkResult? {
        benchmarkResults(benchmarkID, history: history, calendar: calendar).last { $0.date < date }
    }

    public static func benchmarkResults(_ benchmarkID: UUID, history: [PlannedWorkout], calendar: ProgramCalendar) -> [BenchmarkResult] {
        history.filter { $0.status == .done && !$0.isDeleted }
            .sorted { $0.date < $1.date }
            .compactMap { w in
                guard let s = w.sections.first(where: { $0.benchmarkID == benchmarkID }),
                      let score = MetabolicScore.from(s.roundLogs, format: s.format) else { return nil }
                return BenchmarkResult(date: w.date, block: calendar.position(on: w.date).block, score: score,
                                       roundLogs: s.roundLogs, modified: s.isModified)
            }
    }

    /// A benchmark PR: beats the previous like-for-like result.
    public static func isBenchmarkPR(section: WorkoutSection, date: LocalDate, history: [PlannedWorkout], calendar: ProgramCalendar) -> Bool {
        guard let id = section.benchmarkID, !section.isModified,
              let today = MetabolicScore.from(section.roundLogs, format: section.format) else { return false }
        let previous = benchmarkResults(id, history: history.filter { $0.date < date }, calendar: calendar).filter { !$0.modified }
        guard let last = previous.last else { return false }
        return (today.improvement(over: last.score, repsPerRound: section.repsPerRound) ?? 0) > 0
    }

    public static func isPRDay(_ workout: PlannedWorkout, history: [PlannedWorkout], calendar: ProgramCalendar) -> Bool {
        if !strengthPRs(in: workout, history: history).isEmpty { return true }
        return workout.sections.contains { isBenchmarkPR(section: $0, date: workout.date, history: history, calendar: calendar) }
    }
}

public struct LiftPoint: Hashable, Sendable {
    public var date: LocalDate
    public var topWeight: Double
    public var volume: Double

    public init(date: LocalDate, topWeight: Double, volume: Double) {
        self.date = date
        self.topWeight = topWeight
        self.volume = volume
    }
}

public struct BenchmarkRow: Hashable, Sendable {
    public var benchmark: Benchmark
    /// Best result per block (quarter).
    public var byBlock: [Int: BenchmarkResult]
}

public struct GoalProgress: Hashable, Sendable {
    public var goal: Goal
    public var best: Double
    public var fraction: Double
    public var reached: Bool
}

public enum ProgressSeries {
    public static func lift(_ lift: Lift, workouts: [PlannedWorkout], since: LocalDate? = nil) -> [LiftPoint] {
        LiftHistory.sessions(of: lift, in: workouts)
            .filter { since == nil || $0.date >= since! }
            .compactMap { s in s.topWeight.map { LiftPoint(date: s.date, topWeight: $0, volume: s.volume) } }
    }

    public static func benchmarks(_ benchmarks: [Benchmark], workouts: [PlannedWorkout], calendar: ProgramCalendar) -> [BenchmarkRow] {
        benchmarks.map { b in
            var byBlock: [Int: BenchmarkResult] = [:]
            for r in PRDetector.benchmarkResults(b.id, history: workouts, calendar: calendar) {
                if let existing = byBlock[r.block],
                   (r.score.improvement(over: existing.score, repsPerRound: b.template.repsPerRound) ?? 0) <= 0 { continue }
                byBlock[r.block] = r
            }
            return BenchmarkRow(benchmark: b, byBlock: byBlock)
        }
    }

    public static func goal(_ goal: Goal, workouts: [PlannedWorkout]) -> GoalProgress {
        let best = LiftHistory.sessions(of: goal.lift, in: workouts).compactMap(\.topWeight).max() ?? 0
        let f = goal.targetWeight > 0 ? min(1, best / goal.targetWeight) : 0
        return GoalProgress(goal: goal, best: best, fraction: f, reached: best >= goal.targetWeight && goal.targetWeight > 0)
    }

    /// Phase of each of the 13 weeks of a block, for the block strip.
    public static func blockStrip() -> [BlockPhase] { (1...ProgramCalendar.blockLengthWeeks).map(BlockPhase.forBlockWeek) }

    /// Strength summary for the Finish screen.
    public static func strengthSummary(_ section: WorkoutSection?) -> (top: Double, total: Double)? {
        guard let s = section else { return nil }
        let logs = s.items.flatMap(\.setLogs)
        guard let top = logs.map(\.weight).max() else { return nil }
        return (top, logs.reduce(0) { $0 + $1.weight * Double($1.reps) })
    }
}

/// Recent sessions for the "view history" panels.
public enum RecentHistory {
    /// The last `limit` completed sessions of a lift before `date`, newest
    /// first. Includes imported history and sets logged in the app.
    public static func liftSessions(_ lift: Lift, before date: LocalDate, in workouts: [PlannedWorkout], limit: Int = 3) -> [LiftSession] {
        Array(LiftHistory.sessions(of: lift, in: workouts.filter { $0.date < date }).suffix(max(0, limit)).reversed())
    }

    public struct MetabolicEntry: Hashable, Sendable {
        public enum Match: Sendable { case sameWorkout, sameFormat }
        public var date: LocalDate
        public var name: String
        public var format: SectionFormat
        public var roundLogs: [RoundLog]
        public var score: MetabolicScore
        public var match: Match
    }

    /// Past scores for the same workout (benchmark id or name) or, failing
    /// that, the same format. Newest first; only sessions with a score.
    public static func metabolic(for section: WorkoutSection, before date: LocalDate, in workouts: [PlannedWorkout],
                                 limit: Int = 3) -> [MetabolicEntry] {
        let past = workouts.filter { $0.date < date && $0.status == .done && !$0.isDeleted }.sorted { $0.date > $1.date }
        func entries(_ match: MetabolicEntry.Match, _ pick: (WorkoutSection) -> Bool) -> [MetabolicEntry] {
            past.compactMap { w -> MetabolicEntry? in
                guard let s = w.sections.first(where: { $0.kind == .metabolic && pick($0) }),
                      let score = MetabolicScore.from(s.roundLogs, format: s.format) else { return nil }
                return MetabolicEntry(date: w.date, name: s.name ?? s.format.displayName, format: s.format,
                                      roundLogs: s.roundLogs, score: score, match: match)
            }
        }
        let same = entries(.sameWorkout) { s in
            if let id = section.benchmarkID, s.benchmarkID == id { return true }
            if let n = section.name, s.name == n { return true }
            return false
        }
        if !same.isEmpty { return Array(same.prefix(limit)) }
        return Array(entries(.sameFormat) { $0.format == section.format }.prefix(limit))
    }
}
