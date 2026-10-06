import Foundation

/// Training-max math: Epley e1RM, 90% TM, block-to-block progression.
public enum TrainingMax {
    public static let tmFraction = 0.9
    public static let roundingStep = 5.0

    /// Epley estimated 1RM: w × (1 + reps / 30). A single is its own 1RM.
    public static func epley(weight: Double, reps: Int) -> Double {
        guard weight > 0, reps > 0 else { return 0 }
        if reps == 1 { return weight }
        return weight * (1 + Double(reps) / 30)
    }

    /// e1RM rounded to 5 lb, then TM = 90% rounded to 5 lb.
    /// (185 × 5 -> e1RM ~215 -> TM 195, matching IOS-PLAN's table.)
    public static func fromSet(weight: Double, reps: Int) -> Double {
        let e1rm = epley(weight: weight, reps: reps).rounded(toNearest: roundingStep)
        return (e1rm * tmFraction).rounded(toNearest: roundingStep)
    }

    /// Best TM implied by any logged set (used for test-week results).
    public static func fromSets(_ sets: [SetLog]) -> Double? {
        sets.filter { $0.reps > 0 && $0.weight > 0 }.map { fromSet(weight: $0.weight, reps: $0.reps) }.max()
    }

    /// New block: TM + increment, or the week-13 test result, whichever is lower.
    public static func nextBlock(current: Double, lift: Lift, testResult: Double?) -> Double {
        let progressed = current + lift.newBlockIncrement
        guard let t = testResult, t > 0 else { return progressed }
        return min(progressed, t)
    }

    /// Two misses in a row: drop 10%.
    public static func afterTwoMisses(_ tm: Double) -> Double {
        (tm * 0.9).rounded(toNearest: roundingStep)
    }

    /// Fallback TM for a lift from imported/logged history: the most recent
    /// session's top set.
    public static func fromHistory(_ lift: Lift, workouts: [PlannedWorkout]) -> Double? {
        guard let last = LiftHistory.sessions(of: lift, in: workouts).last, let top = last.topSet else { return nil }
        return fromSet(weight: top.weight, reps: top.reps)
    }

    /// Resolves the TM for each lift: explicit program first, then history,
    /// then a conservative empty-bar default.
    public static func resolve(programs: [Lift: Double], history: [PlannedWorkout], barWeight: Double) -> [Lift: Double] {
        var out: [Lift: Double] = [:]
        for lift in Lift.allCases {
            if let tm = programs[lift], tm > 0 {
                out[lift] = tm
            } else if let tm = fromHistory(lift, workouts: history) {
                out[lift] = tm
            } else {
                out[lift] = max(barWeight, 45) + 20
            }
        }
        return out
    }
}

/// A past session of one of the six lifts, derived from a workout's logs.
public struct LiftSession: Hashable, Sendable {
    public var date: LocalDate
    public var lift: Lift
    public var sets: [SetLog]
    public var plannedSets: [PlannedSet]
    public var strengthDifficulty: Int?
    public var energy: Energy?

    public var topSet: SetLog? {
        sets.max { ($0.weight, $0.reps) < ($1.weight, $1.reps) }
    }

    public var topWeight: Double? { topSet?.weight }

    /// A planned set was logged with fewer reps, or not logged at all.
    public var missedRep: Bool {
        guard !plannedSets.isEmpty else { return false }
        for p in plannedSets {
            guard let log = sets.first(where: { $0.setNumber == p.setNumber }) else { return true }
            if log.reps < p.reps { return true }
        }
        return false
    }

    public var volume: Double { sets.reduce(0) { $0 + $1.weight * Double($1.reps) } }
}

public enum LiftHistory {
    /// Completed sessions of `lift`, oldest first.
    public static func sessions(of lift: Lift, in workouts: [PlannedWorkout]) -> [LiftSession] {
        var out: [LiftSession] = []
        for w in workouts where w.status == .done && !w.isDeleted {
            guard let s = w.strengthSection else { continue }
            for item in s.items where Lift(movementName: item.movementName) == lift || item.movementID == lift.movementID {
                let logs = item.setLogs.filter { $0.weight > 0 && $0.reps > 0 }
                guard !logs.isEmpty else { continue }
                out.append(LiftSession(date: w.date, lift: lift, sets: logs, plannedSets: item.plannedSets,
                                       strengthDifficulty: w.feedback?.strengthDifficulty, energy: w.feedback?.energy))
            }
        }
        return out.sorted { $0.date < $1.date }
    }
}
