import Foundation

public enum Implement: String, Codable, Sendable {
    case barbell, dumbbell, kettlebell, medicineBall = "medicine_ball", bodyweight, box, bench, bike
}

/// Result of fitting a prescribed weight to the owner's dumbbells/kettlebells.
public struct SnappedLoad: Hashable, Sendable {
    public var implement: Implement
    public var weight: Double
    public var reps: Int?
    /// Reason the prescription changed (heavier than available, swapped to KB...).
    public var note: String?

    /// "2 × 20 lb" for dumbbell pairs, "35 lb KB", "12 lb ball".
    public func label(pair: Bool) -> String {
        switch implement {
        case .dumbbell: return pair ? "2 × \(formatPounds(weight)) lb" : "\(formatPounds(weight)) lb DB"
        case .kettlebell: return "\(formatPounds(weight)) lb KB"
        case .medicineBall: return "\(formatPounds(weight)) lb ball"
        default: return "\(formatPounds(weight)) lb"
        }
    }
}

/// Snaps DB/KB prescriptions to what is in the home gym (DB 10/15/20, KB 22/26/35).
public struct ImplementSnapper: Hashable, Sendable {
    public let dumbbells: [Double]
    public let kettlebells: [Double]

    public init(dumbbells: [Double] = EquipmentInventory.homeGym.dumbbells,
                kettlebells: [Double] = EquipmentInventory.homeGym.kettlebells) {
        self.dumbbells = dumbbells.filter { $0 > 0 }.sorted()
        self.kettlebells = kettlebells.filter { $0 > 0 }.sorted()
    }

    public init(inventory: EquipmentInventory) {
        self.init(dumbbells: inventory.dumbbells, kettlebells: inventory.kettlebells)
    }

    /// Nearest weight; exact ties go to the lighter one.
    static func nearest(_ target: Double, in options: [Double]) -> Double? {
        options.min { a, b in
            let da = abs(a - target), db = abs(b - target)
            return da == db ? a < b : da < db
        }
    }

    public func snapKettlebell(_ target: Double, reps: Int? = nil) -> SnappedLoad? {
        guard let maxKB = kettlebells.last, let w = ImplementSnapper.nearest(target, in: kettlebells) else { return nil }
        if target > maxKB * 1.1, let r = reps {
            let scaled = Int((Double(r) * target / maxKB).rounded(.up))
            return SnappedLoad(implement: .kettlebell, weight: maxKB, reps: scaled,
                               note: "Heavier than your kettlebells: \(formatPounds(maxKB)) lb for \(scaled) reps instead.")
        }
        return SnappedLoad(implement: .kettlebell, weight: w, reps: reps, note: nil)
    }

    /// A DB prescription heavier than the heaviest dumbbell becomes a kettlebell
    /// (if the move allows one and a close KB exists) or more reps.
    public func snapDumbbell(_ target: Double, reps: Int? = nil, kettlebellAlternative: Bool = false) -> SnappedLoad? {
        guard let maxDB = dumbbells.last else {
            return kettlebellAlternative ? snapKettlebell(target, reps: reps) : nil
        }
        if target <= maxDB + 2.5 {
            let w = ImplementSnapper.nearest(target, in: dumbbells) ?? maxDB
            return SnappedLoad(implement: .dumbbell, weight: w, reps: reps, note: nil)
        }
        if kettlebellAlternative, let kb = ImplementSnapper.nearest(target, in: kettlebells), abs(kb - target) <= 5 {
            return SnappedLoad(implement: .kettlebell, weight: kb, reps: reps,
                               note: "Heavier than your dumbbells, so it's a \(formatPounds(kb)) lb kettlebell.")
        }
        guard let r = reps else {
            return SnappedLoad(implement: .dumbbell, weight: maxDB, reps: nil,
                               note: "Heavier than your dumbbells: use \(formatPounds(maxDB)) lb and slow the tempo.")
        }
        let scaled = Int((Double(r) * target / maxDB).rounded(.up))
        return SnappedLoad(implement: .dumbbell, weight: maxDB, reps: scaled,
                           note: "Heavier than your dumbbells: \(formatPounds(maxDB)) lb for \(scaled) reps instead.")
    }

    /// One size lighter / heavier (used when metabolic ratings say too hard / too easy).
    public func shift(_ load: SnappedLoad, by steps: Int) -> SnappedLoad {
        let options = load.implement == .kettlebell ? kettlebells : load.implement == .dumbbell ? dumbbells : []
        guard let idx = options.firstIndex(of: load.weight) else { return load }
        let n = min(max(idx + steps, 0), options.count - 1)
        var out = load
        out.weight = options[n]
        return out
    }
}
