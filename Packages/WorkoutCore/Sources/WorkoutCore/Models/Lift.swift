import Foundation

/// The six fixed barbell lifts of v1.
public enum Lift: String, CaseIterable, Codable, Sendable, Comparable {
    case backSquat = "back_squat"
    case deadlift
    case pushPress = "push_press"
    case frontSquat = "front_squat"
    case hangPowerClean = "hang_power_clean"
    case pushJerk = "push_jerk"

    public var displayName: String {
        switch self {
        case .backSquat: return "Back Squat"
        case .deadlift: return "Deadlift"
        case .pushPress: return "Push Press"
        case .frontSquat: return "Front Squat"
        case .hangPowerClean: return "Hang Power Clean"
        case .pushJerk: return "Push Jerk"
        }
    }

    /// Program group from the block table: squats/deadlift/push press vs Olympic lifts.
    public var isOlympic: Bool { self == .hangPowerClean || self == .pushJerk }

    /// Lower-body lifts add +10 lb per block; presses and Olympic lifts +5 lb.
    public var isLowerBody: Bool { self == .backSquat || self == .frontSquat || self == .deadlift }
    public var newBlockIncrement: Double { isLowerBody ? 10 : 5 }

    /// The weekly slot the lift fills (Mon squat, Wed hip/pull, Fri overhead).
    public var slot: LiftSlot {
        switch self {
        case .backSquat, .frontSquat: return .squat
        case .deadlift, .hangPowerClean: return .hipPull
        case .pushPress, .pushJerk: return .overhead
        }
    }

    public var pattern: MovementPattern {
        switch slot {
        case .squat: return .squat
        case .hipPull: return .hinge
        case .overhead: return .press
        }
    }

    public var primaryMuscles: Set<Muscle> {
        switch self {
        case .backSquat, .frontSquat: return [.quads, .glutes, .core]
        case .deadlift: return [.hamstrings, .glutes, .lowerBack]
        case .hangPowerClean: return [.hamstrings, .glutes, .upperBack, .shoulders]
        case .pushPress, .pushJerk: return [.shoulders, .triceps, .quads]
        }
    }

    /// Joints the rack position / pattern stresses (used by the knee/wrist limits).
    public var jointStress: Set<Joint> {
        switch self {
        case .backSquat: return [.knee]
        case .frontSquat: return [.knee, .wrist]
        case .deadlift: return []
        case .hangPowerClean, .pushJerk: return [.wrist]
        case .pushPress: return []
        }
    }

    /// Movement library id of the lift.
    public var movementID: String { rawValue.replacingOccurrences(of: "_", with: "-") }

    /// Matches canonical movement names from the coach's sheet ("Hang Power Clean").
    public init?(movementName: String) {
        var key = movementName.trimmingCharacters(in: .whitespaces).lowercased()
        // Plural forms from the sheet ("Front Squats", "Hang Power Cleans").
        if key.hasSuffix("es"), Lift.allCases.contains(where: { $0.displayName.lowercased() == String(key.dropLast(2)) }) {
            key = String(key.dropLast(2))
        } else if key.hasSuffix("s"), !Lift.allCases.contains(where: { $0.displayName.lowercased() == key }) {
            key = String(key.dropLast())
        }
        guard let lift = Lift.allCases.first(where: { $0.displayName.lowercased() == key || $0.movementID == key }) else {
            return nil
        }
        self = lift
    }

    public static func < (a: Lift, b: Lift) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

public enum LiftSlot: String, Codable, Sendable, CaseIterable {
    case squat, hipPull = "hip_pull", overhead

    public var displayName: String {
        switch self {
        case .squat: return "squat"
        case .hipPull: return "hip / pull"
        case .overhead: return "overhead"
        }
    }
}
