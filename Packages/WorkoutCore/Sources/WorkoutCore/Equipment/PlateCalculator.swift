import Foundation

/// Plates for one side of the bar.
public struct PlateLoadout: Hashable, Sendable {
    public let total: Double
    public let barWeight: Double
    /// Heaviest first.
    public let perSide: [Double]

    /// "bar + 25 + 5 each side", or "bar only".
    public var description: String {
        guard !perSide.isEmpty else { return "bar only" }
        return "bar + " + perSide.map(formatPounds).joined(separator: " + ") + " each side"
    }

    /// "105 lb = bar + 25 + 5 each side"
    public var sentence: String { "\(formatPounds(total)) lb = \(description)" }
}

public struct RoundedLoad: Hashable, Sendable {
    public let requested: Double
    public let weight: Double
    public let loadout: PlateLoadout
    /// The request was above the heaviest loadable weight.
    public let cappedAtMax: Bool
    /// The request was below the empty bar.
    public let belowBar: Bool
}

/// Works out loadable barbell weights for the owner's plate pairs.
///
/// Each *pair* contributes one plate per side, so with pairs
/// 2.5, 5, 10, 10, 15, 25, 25 and a 45 lb bar the heaviest load is
/// 45 + 2 × 92.5 = 230 lb and the smallest jump is 5 lb.
public struct PlateCalculator: Hashable, Sendable {
    public enum Rounding: Sendable { case nearest, down, up }

    public let barWeight: Double
    public let platesPerSide: [Double]
    /// Reachable per-side sums (quarter-pound units) -> fewest-plate combination.
    private let combos: [Int: [Double]]
    public let loadableTotals: [Double]

    public init(barWeight: Double = 45, platePairs: [Double] = EquipmentInventory.homeGym.platePairs) {
        self.barWeight = barWeight
        let plates = platePairs.filter { $0 > 0 && $0.isFinite }.sorted(by: >)
        self.platesPerSide = plates
        // Subset-sum DP keeping the combination with the fewest plates
        // (ties broken toward heavier plates, which come first).
        var best: [Int: [Double]] = [0: []]
        for p in plates {
            let unit = Int((p * 4).rounded())
            for (sum, combo) in best.sorted(by: { $0.key > $1.key }) {
                let ns = sum + unit
                let candidate = combo + [p]
                if let existing = best[ns], existing.count <= candidate.count { continue }
                best[ns] = candidate
            }
        }
        self.combos = best
        self.loadableTotals = best.keys.sorted().map { barWeight + 2 * Double($0) / 4 }
    }

    public init(inventory: EquipmentInventory) {
        self.init(barWeight: inventory.barWeight, platePairs: inventory.platePairs)
    }

    public var maxLoadable: Double { loadableTotals.last ?? barWeight }

    /// Smallest increase available from the plates (5 lb for the home gym).
    public var smallestStep: Double {
        guard let m = platesPerSide.min() else { return 0 }
        return 2 * m
    }

    /// Exact loadout, or nil if `total` cannot be made.
    public func loadout(for total: Double) -> PlateLoadout? {
        let perSide = (total - barWeight) / 2
        guard perSide >= -0.001 else { return nil }
        let unit = Int((perSide * 4).rounded())
        guard abs(Double(unit) / 4 - perSide) < 0.01, let combo = combos[unit] else { return nil }
        return PlateLoadout(total: total, barWeight: barWeight, perSide: combo.sorted(by: >))
    }

    public func round(_ target: Double, _ mode: Rounding = .nearest) -> RoundedLoad {
        let t = target.isFinite ? target : barWeight
        let totals = loadableTotals.isEmpty ? [barWeight] : loadableTotals
        let chosen: Double
        switch mode {
        case .nearest:
            // Ties go to the lighter weight (never round a lift up by accident).
            chosen = totals.min { a, b in
                let da = abs(a - t), db = abs(b - t)
                return da == db ? a < b : da < db
            }!
        case .down:
            chosen = totals.last { $0 <= t + 0.001 } ?? totals[0]
        case .up:
            chosen = totals.first { $0 >= t - 0.001 } ?? totals[totals.count - 1]
        }
        return RoundedLoad(requested: target, weight: chosen, loadout: loadout(for: chosen)!,
                           cappedAtMax: t > maxLoadable + 0.001, belowBar: t < barWeight - 0.001)
    }

    /// Next loadable weight above `weight` ("one plate step").
    public func step(up weight: Double, by steps: Int = 1) -> Double {
        var w = round(weight).weight
        for _ in 0..<max(0, steps) {
            guard let next = loadableTotals.first(where: { $0 > w + 0.001 }) else { break }
            w = next
        }
        return w
    }
}

/// Warns ahead of time when a lift is heading past the plate ceiling.
public struct PlateCeilingWarning: Hashable, Sendable {
    public let lift: Lift
    /// Blocks from now (0 = the current block already needs more plates).
    public let blocksAway: Int
    public let projectedOneRepMax: Double
    public let maxLoadable: Double

    public var message: String {
        let when = blocksAway == 0 ? "already" : "in about \(blocksAway) block\(blocksAway == 1 ? "" : "s")"
        return "\(lift.displayName) may pass your \(formatPounds(maxLoadable)) lb plate limit \(when). Time to get more plates."
    }

    /// Projects each lift's estimated 1RM (TM / 0.9) forward with the per-block
    /// increment and reports lifts that cross `maxLoadable` within `horizon` blocks.
    public static func forecast(trainingMaxes: [Lift: Double], calculator: PlateCalculator, horizonBlocks: Int = 2) -> [PlateCeilingWarning] {
        var out: [PlateCeilingWarning] = []
        for lift in Lift.allCases {
            guard let tm = trainingMaxes[lift], tm > 0 else { continue }
            for n in 0...max(0, horizonBlocks) {
                let projected = (tm + Double(n) * lift.newBlockIncrement) / TrainingMax.tmFraction
                if projected > calculator.maxLoadable {
                    out.append(PlateCeilingWarning(lift: lift, blocksAway: n, projectedOneRepMax: projected.rounded(),
                                                   maxLoadable: calculator.maxLoadable))
                    break
                }
            }
        }
        return out
    }
}
