import Foundation

/// Display / planning unit. Stored weights are canonical pounds (Double),
/// so switching units never loses precision; everything converts on the way
/// in and out.
public enum WeightUnit: String, Codable, Sendable, CaseIterable {
    case lb, kg

    public static let poundsPerKilogram = 2.204_622_621_8

    public var symbol: String { rawValue }

    /// Canonical pounds -> this unit.
    public func fromPounds(_ lb: Double) -> Double { self == .lb ? lb : lb / WeightUnit.poundsPerKilogram }
    /// This unit -> canonical pounds.
    public func toPounds(_ v: Double) -> Double { self == .lb ? v : v * WeightUnit.poundsPerKilogram }

    /// Rounding step for training maxes and goals (5 lb / 2.5 kg).
    public var roundingStep: Double { self == .lb ? 5 : 2.5 }

    /// "135" / "61.2" (at most one decimal, trailing zeros dropped).
    public func format(pounds lb: Double) -> String { formatWeight(fromPounds(lb)) }

    /// "135 lb" / "61.2 kg"
    public func label(pounds lb: Double) -> String { "\(format(pounds: lb)) \(symbol)" }

    /// Re-rounds a canonical weight to this unit's step and returns pounds.
    public func rounded(pounds lb: Double, step: Double? = nil) -> Double {
        toPounds(fromPounds(lb).rounded(toNearest: step ?? roundingStep))
    }

    /// Unit used by core-generated text (reasons, labels). Set by the
    /// planner for the duration of a plan.
    @TaskLocal public static var current: WeightUnit = .lb
}

/// Weight with at most one decimal ("102.5", "61.2", "105").
public func formatWeight(_ value: Double) -> String {
    let r = (value * 10).rounded() / 10
    if r == r.rounded() { return String(Int(r)) }
    return String(format: "%.1f", r)
}

extension EquipmentInventory {
    /// The owner's home gym (lb).
    public static let poundsPreset = EquipmentInventory()

    /// A typical metric home gym: 20 kg bar, 1.25-20 kg plate pairs.
    public static let kilogramsPreset = EquipmentInventory(
        unit: .kg, barWeight: 20, platePairs: [1.25, 2.5, 5, 10, 15, 20],
        dumbbells: [4, 6, 8, 10], kettlebells: [8, 12, 16], medicineBall: 6)

    public static func preset(_ unit: WeightUnit) -> EquipmentInventory { unit == .lb ? poundsPreset : kilogramsPreset }

    /// Bar choices offered per unit.
    public static func barOptions(_ unit: WeightUnit) -> [Double] { unit == .lb ? [45, 35] : [20, 15] }
}

extension PlannedWorkout {
    /// Multiplies every weight (logs, plan, prescriptions, TM) by `factor`.
    /// Used to run the planner in kg and convert results back.
    public func scalingWeights(by factor: Double) -> PlannedWorkout {
        guard factor != 1 else { return self }
        var w = self
        w.sections = sections.map { $0.scalingWeights(by: factor) }
        return w
    }
}

extension WorkoutSection {
    public func scalingWeights(by factor: Double) -> WorkoutSection {
        guard factor != 1 else { return self }
        var s = self
        s.trainingMax = trainingMax.map { $0 * factor }
        s.items = items.map { i in
            var i = i
            i.prescribedWeight = i.prescribedWeight.map { $0 * factor }
            i.plannedSets = i.plannedSets.map { var p = $0; p.weight *= factor; return p }
            i.setLogs = i.setLogs.map { var l = $0; l.weight *= factor; return l }
            return i
        }
        return s
    }
}
