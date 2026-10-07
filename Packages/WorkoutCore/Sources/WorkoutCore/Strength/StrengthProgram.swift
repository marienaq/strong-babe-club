import Foundation

/// Sets/reps and top-set intensity for one lift in one phase.
public struct StrengthPrescription: Hashable, Sendable {
    public var lift: Lift
    public var phase: BlockPhase
    /// Reps per set, in order.
    public var setReps: [Int]
    /// Top set as a fraction of TM (low...high end of the phase range).
    public var topRange: ClosedRange<Double>
    /// Chosen top fraction for this week.
    public var topFraction: Double
    /// All sets at the same weight (deload).
    public var flat: Bool
    public var intervalSec: Int

    /// Coach-style instructions: "Every 2 min for 12 min\n5 reps · go up each set".
    public var instructions: String {
        let minutes = intervalSec * setReps.count / 60
        let every = intervalSec % 60 == 0 ? "\(intervalSec / 60) min" : String(format: "%d:%02d", intervalSec / 60, intervalSec % 60)
        let reps = Set(setReps).count == 1 ? "\(setReps[0]) reps" : setReps.map(String.init).joined(separator: "-") + " reps"
        switch phase {
        case .test:
            let tech = lift.isOlympic ? " Clean technique only." : ""
            return "Every \(every): work up to a heavy 3\n1-2 reps left in the tank, never a true max.\(tech)"
        case .deload:
            return "Every \(every) for \(minutes) min\n\(reps) at \(Int(topFraction * 100))% · fast and crisp"
        default:
            return "Every \(every) for \(minutes) min\n\(reps) · go up each set"
        }
    }
}

public enum StrengthProgram {
    /// Every 2 minutes (coach format); one main lift per session.
    public static let singleLiftInterval = 120

    /// The block table from IOS-PLAN.
    public static func prescription(for lift: Lift, position: BlockPosition) -> StrengthPrescription {
        let phase = position.phase
        let olympic = lift.isOlympic
        var setReps: [Int]
        var range: ClosedRange<Double>
        var flat = false
        switch phase {
        case .preProgram, .volume:
            setReps = Array(repeating: olympic ? 3 : 5, count: 6)
            range = olympic ? 0.70...0.75 : 0.75...0.80
        case .strength:
            setReps = Array(repeating: olympic ? 2 : 3, count: 6)
            range = olympic ? 0.80...0.85 : 0.85...0.90
        case .peak:
            setReps = olympic ? [2, 2, 2, 1, 1, 1] : [2, 2, 2, 2, 2, 1]
            range = olympic ? 0.85...0.90 : 0.90...0.95
        case .deload:
            setReps = Array(repeating: olympic ? 2 : 5, count: 5)
            range = 0.60...0.60
            flat = true
        case .test:
            // Work up to a heavy 3 with 1-2 reps in reserve (never a true max).
            setReps = [3, 3, 3, 3, 3, 3]
            range = 0.95...1.0
        }
        // Olympic lifts never go above 3 reps per set.
        if olympic { setReps = setReps.map { min($0, 3) } }

        // Progress through the phase range week by week.
        let weeks = phase.weeks
        let frac: Double
        if phase == .preProgram || weeks.count <= 1 || position.isDeloadOverride {
            frac = 0
        } else {
            frac = Double(min(max(position.week, weeks.lowerBound), weeks.upperBound) - weeks.lowerBound) / Double(weeks.count - 1)
        }
        let top = range.lowerBound + (range.upperBound - range.lowerBound) * frac
        let interval = singleLiftInterval
        return StrengthPrescription(lift: lift, phase: phase, setReps: setReps, topRange: range,
                                    topFraction: top, flat: flat, intervalSec: interval)
    }

    /// Ramping sets: climb evenly from ~50% of TM (or `start`) to the top set,
    /// each rounded to a loadable weight and never going down.
    public static func ramp(setReps: [Int], top: Double, start: Double, calculator: PlateCalculator,
                            flat: Bool = false, trainingMax: Double? = nil) -> [PlannedSet] {
        let n = setReps.count
        guard n > 0 else { return [] }
        let topW = calculator.round(top).weight
        if flat {
            return setReps.enumerated().map { i, r in
                PlannedSet(setNumber: i + 1, reps: r, weight: topW, percentOfTM: trainingMax.map { topW / $0 })
            }
        }
        let startW = min(calculator.round(max(start, calculator.barWeight)).weight, topW)
        // Climb evenly through the loadable weights between start and top,
        // strictly increasing. If there aren't enough distinct weights, the
        // lowest sets repeat the start weight (never the middle).
        let ladder = calculator.loadableTotals.filter { $0 >= startW - 0.001 && $0 <= topW + 0.001 }
        let steps = max(ladder.count - 1, 0)
        var weights: [Double]
        if n == 1 || ladder.isEmpty {
            weights = Array(repeating: topW, count: n)
        } else if steps >= n - 1 {
            weights = (0..<n).map { i in ladder[Int((Double(i * steps) / Double(n - 1)).rounded())] }
        } else {
            weights = Array(repeating: ladder[0], count: n - ladder.count) + ladder
        }
        weights[n - 1] = topW
        return (0..<n).map { i in
            PlannedSet(setNumber: i + 1, reps: setReps[i], weight: weights[i], percentOfTM: trainingMax.map { weights[i] / $0 })
        }
    }
}

/// Inputs that tune the top set away from the plain block percentage.
public struct StrengthAdjustmentInput: Sendable {
    public var lastSessions: [LiftSession]
    /// Low energy / comeback / "just show up": cap at the low end of the range.
    public var capAtLowEnd: Bool
    /// "Push" coach note for this lift: one extra plate step.
    public var push: Bool
    /// A knee/wrist limit touches this lift: cap at the low end.
    public var jointLimit: Joint?

    public init(lastSessions: [LiftSession] = [], capAtLowEnd: Bool = false, push: Bool = false, jointLimit: Joint? = nil) {
        self.lastSessions = lastSessions
        self.capAtLowEnd = capAtLowEnd
        self.push = push
        self.jointLimit = jointLimit
    }
}

public struct StrengthNote: Hashable, Sendable {
    public var rule: String
    public var text: String?
}

public struct StrengthPlan: Sendable {
    public var prescription: StrengthPrescription
    public var trainingMax: Double
    public var sets: [PlannedSet]
    /// Rules that fired, in order, with the explanation (if any).
    public var notes: [StrengthNote]
    public var cappedAtPlateMax: Bool

    public var ruleIDs: [String] { notes.map(\.rule) }
    public var reasons: [String] { notes.compactMap(\.text) }
}

public enum StrengthPlanner {
    /// Applies the "adjusting to how sessions feel" rules from IOS-PLAN.
    /// Top set for a calibration session (pre-block, or a lift whose TM is
    /// still calibrating): heavy enough that the rating tells us something.
    public static let calibrationTop = 0.80

    public static func plan(lift: Lift, position: BlockPosition, trainingMax tmIn: Double,
                            calculator: PlateCalculator, input: StrengthAdjustmentInput,
                            rampStart: Double? = nil, calibration: Bool = false) -> StrengthPlan {
        var rx = StrengthProgram.prescription(for: lift, position: position)
        if calibration {
            rx.topFraction = calibrationTop
            rx.topRange = calibrationTop...calibrationTop
        }
        var notes: [StrengthNote] = []
        func note(_ rule: String, _ text: String?) { notes.append(StrengthNote(rule: rule, text: text)) }
        var tm = tmIn
        let recent = input.lastSessions.suffix(2)
        let last = input.lastSessions.last

        // Two misses in a row -> TM drops 10%.
        if recent.count == 2, recent.allSatisfy(\.missedRep), rx.phase != .test {
            tm = TrainingMax.afterTwoMisses(tm)
            note("tm.two_misses", "Missed reps the last two \(lift.displayName.lowercased()) days, so the training max drops 10% to \(formatPounds(tm)).")
        }

        var top = calculator.round(tm * rx.topFraction).weight
        let lowEnd = calculator.round(tm * rx.topRange.lowerBound).weight

        if rx.phase != .test, rx.phase != .deload, let last, let lastTop = last.topWeight, !notes.contains(where: { $0.rule == "tm.two_misses" }) {
            let rating = last.strengthDifficulty
            if last.missedRep || rating == 5 {
                top = calculator.round(lastTop).weight
                let why = last.missedRep ? "a rep was missed" : "you rated it 5/5"
                note("adjust.repeat", "Last time topped at \(formatPounds(lastTop)) and \(why), so today repeats that weight.")
            } else if let r = rating, r <= 2, !last.missedRep {
                top = max(top, calculator.step(up: lastTop))
                note("adjust.step_up", "Last time you hit \(formatPounds(lastTop)) and rated it \(r)/5, so today goes one plate step heavier.")
            } else {
                let rated = rating.map { " and rated it \($0)/5" } ?? ""
                note("block.percent", "You hit \(formatPounds(lastTop)) last time\(rated). Today tops out at \(formatPounds(top)): \(Int((rx.topFraction * 100).rounded()))% of your \(formatPounds(tm)) \(WeightUnit.current.symbol) training max.")
            }
        } else if rx.phase != .test {
            note("block.percent", "Heaviest set: \(Int((rx.topFraction * 100).rounded()))% of your \(formatPounds(tm)) \(WeightUnit.current.symbol) training max = \(formatPounds(top)) \(WeightUnit.current.symbol).")
        }

        if input.push, rx.phase != .test, rx.phase != .deload {
            top = calculator.step(up: top)
            note("coach.push", "You've earned a heavier day: +\(formatPounds(calculator.smallestStep)) \(WeightUnit.current.symbol) on the heaviest set.")
        }
        if input.capAtLowEnd, top > lowEnd {
            top = lowEnd
            note("cap.low_end", "Taking it easier today: the heaviest set stays at the low end of the \(rx.phase.displayName) range (\(formatPounds(lowEnd)) \(WeightUnit.current.symbol)).")
        }
        if let joint = input.jointLimit {
            top = min(top, lowEnd)
            note("limit.\(joint.rawValue)", "Going easy on your \(joint.rawValue): the heaviest set stays at the low end of the range (\(formatPounds(top)) \(WeightUnit.current.symbol)).")
        }

        let capped = top > calculator.maxLoadable - 0.001 && tm * rx.topFraction > calculator.maxLoadable
        if capped {
            note("plates.ceiling", "Capped at \(formatPounds(calculator.maxLoadable)) \(WeightUnit.current.symbol): that's all your plates make. Time for more plates!")
        }
        top = min(top, calculator.maxLoadable)

        let start = rampStart ?? tm * 0.5
        let sets = StrengthProgram.ramp(setReps: rx.setReps, top: top, start: start, calculator: calculator,
                                        flat: rx.flat, trainingMax: tm)
        return StrengthPlan(prescription: rx, trainingMax: tm, sets: sets, notes: notes, cappedAtPlateMax: capped)
    }
}
