import Foundation

/// A training max worked out from recent history.
public struct TrainingMaxEstimate: Hashable, Sendable {
    public var trainingMax: Double
    /// Taken from a related lift (or old history): adjust after the first session.
    public var calibrating: Bool
    /// What it came from, e.g. "Deadlift 185 × 2 on Oct 2" or "Power Clean × 0.9".
    public var basis: String
}

/// Lift with no recent log -> a related movement × factor.
public struct RelatedLift: Hashable, Sendable {
    public var target: Lift
    public var source: String
    public var factor: Double

    public static let table: [RelatedLift] = [
        RelatedLift(target: .hangPowerClean, source: "Power Clean", factor: 0.9),
        RelatedLift(target: .pushJerk, source: "Split Jerk", factor: 0.9),
        RelatedLift(target: .pushJerk, source: "Push Press", factor: 1.05),
        RelatedLift(target: .frontSquat, source: "Back Squat", factor: 0.85),
        RelatedLift(target: .backSquat, source: "Front Squat", factor: 1 / 0.85),
    ]
}

extension TrainingMax {
    /// Days of history the estimate looks at.
    public static let estimateWindowDays = 28

    /// 90% of an e1RM, rounded to 5 lb.
    public static func fromE1RM(_ e1rm: Double) -> Double { (e1rm * tmFraction).rounded(toNearest: roundingStep) }

    /// Best Epley e1RM of a movement over done sessions in [from, to).
    /// Matches singular/plural names ("Split Jerks").
    public static func bestE1RM(movement name: String, in workouts: [PlannedWorkout], from: LocalDate, to: LocalDate)
        -> (e1rm: Double, weight: Double, reps: Int, date: LocalDate)? {
        func key(_ s: String) -> String {
            var k = MovementLibrary.slug(s)
            if k.hasSuffix("sses") { k.removeLast(2) }                       // presses -> press
            else if k.hasSuffix("s"), !k.hasSuffix("ss") { k.removeLast() }  // jerks -> jerk
            return k
        }
        let target = key(name)
        var best: (Double, Double, Int, LocalDate)?
        for w in workouts where w.status == .done && !w.isDeleted && w.date >= from && w.date < to {
            for s in w.sections where s.kind == .strength {
                for item in s.items where key(item.movementName) == target || key(item.movementID) == target {
                    for l in item.setLogs where l.weight > 0 && l.reps > 0 {
                        let e = epley(weight: l.weight, reps: l.reps)
                        if best == nil || e > best!.0 { best = (e, l.weight, l.reps, w.date) }
                    }
                }
            }
        }
        return best.map { (e1rm: $0.0, weight: $0.1, reps: $0.2, date: $0.3) }
    }

    /// TM = 90% of the best e1RM over the last 28 days before `asOf`.
    /// Without a direct log: related lift × factor (lowest if several),
    /// flagged calibrating; then the most recent session ever, also calibrating.
    public static func estimate(_ lift: Lift, history: [PlannedWorkout], asOf: LocalDate,
                                windowDays: Int = estimateWindowDays) -> TrainingMaxEstimate? {
        let from = asOf.adding(days: -windowDays)
        if let b = bestE1RM(movement: lift.displayName, in: history, from: from, to: asOf) {
            return TrainingMaxEstimate(trainingMax: fromE1RM(b.e1rm), calibrating: false,
                                       basis: "\(lift.displayName) \(formatPounds(b.weight)) × \(b.reps) on \(b.date.shortMonthName) \(b.date.day)")
        }
        let related = RelatedLift.table.filter { $0.target == lift }.compactMap { r -> (Double, String)? in
            bestE1RM(movement: r.source, in: history, from: from, to: asOf).map { ($0.e1rm * r.factor, "\(r.source) × \(r.factor == 1 / 0.85 ? "1/0.85" : formatPounds(r.factor))") }
        }
        if let lowest = related.min(by: { $0.0 < $1.0 }) {
            return TrainingMaxEstimate(trainingMax: fromE1RM(lowest.0), calibrating: true, basis: lowest.1)
        }
        if let last = LiftHistory.sessions(of: lift, in: history.filter { $0.date < asOf }).last,
           let e = last.sets.map({ epley(weight: $0.weight, reps: $0.reps) }).max() {
            return TrainingMaxEstimate(trainingMax: fromE1RM(e), calibrating: true,
                                       basis: "older history (\(last.date.shortMonthName) \(last.date.year))")
        }
        return nil
    }

    /// First rated session of a calibrating lift adjusts its TM more than
    /// usual: rated 1 → +10%, 2 → +5%, 4-5 → −5%.
    public static func calibrated(_ tm: Double, lift: Lift, history: [PlannedWorkout], from: LocalDate) -> (tm: Double, adjusted: Bool) {
        guard let first = LiftHistory.sessions(of: lift, in: history.filter { $0.date >= from })
            .first(where: { $0.strengthDifficulty != nil }), let r = first.strengthDifficulty else { return (tm, false) }
        let factor: Double
        switch r {
        case 1: factor = 1.10
        case 2: factor = 1.05
        case 4, 5: factor = 0.95
        default: factor = 1
        }
        return ((tm * factor).rounded(toNearest: roundingStep), true)
    }
}
