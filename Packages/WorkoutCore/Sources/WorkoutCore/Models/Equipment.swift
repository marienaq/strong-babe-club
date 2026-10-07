import Foundation

public enum MovementPattern: String, Codable, Sendable, CaseIterable {
    case squat, hinge, press, pull, lunge, carry, core, cardio, mobility
}

public enum Muscle: String, Codable, Sendable, CaseIterable, Comparable {
    case quads, glutes, hamstrings, calves, lowerBack = "lower_back", core, chest, shoulders, triceps, upperBack = "upper_back", lats, biceps

    public static func < (a: Muscle, b: Muscle) -> Bool { a.rawValue < b.rawValue }

    public var displayName: String {
        switch self {
        case .lowerBack: return "lower back"
        case .upperBack: return "upper back"
        default: return rawValue
        }
    }
}

public enum Joint: String, Codable, Sendable, CaseIterable {
    case knee, wrist
}

public enum Equipment: String, Codable, Sendable, CaseIterable {
    case barbell, dumbbell, kettlebell, medicineBall = "medicine_ball", box, bench, lowBar = "low_bar", bike, bodyweight

    public var displayName: String {
        switch self {
        case .barbell: return "Barbell + plates"
        case .dumbbell: return "Dumbbells"
        case .kettlebell: return "Kettlebells"
        case .medicineBall: return "Medicine ball"
        case .box: return "Boxes"
        case .bench: return "Bench"
        case .lowBar: return "Bar for Australian pull-ups"
        case .bike: return "Bike"
        case .bodyweight: return "Bodyweight"
        }
    }
}

/// The owner's home gym. Everything is editable in Settings.
public struct EquipmentInventory: Codable, Hashable, Sendable {
    /// Unit of every weight in this inventory.
    public var unit: WeightUnit
    public var hasBarbell: Bool
    public var barWeight: Double
    /// One entry per *pair* of plates (each pair loads one plate per side).
    public var platePairs: [Double]
    public var dumbbells: [Double]
    public var kettlebells: [Double]
    public var medicineBall: Double?
    public var boxHeights: [Int]
    public var hasBench: Bool
    public var hasLowBar: Bool
    public var hasBike: Bool

    public init(unit: WeightUnit = .lb, hasBarbell: Bool = true, barWeight: Double = 45, platePairs: [Double] = [2.5, 5, 10, 10, 15, 25, 25],
                dumbbells: [Double] = [10, 15, 20], kettlebells: [Double] = [22, 26, 35], medicineBall: Double? = 12,
                boxHeights: [Int] = [24, 32], hasBench: Bool = true, hasLowBar: Bool = true, hasBike: Bool = false) {
        self.unit = unit
        self.hasBarbell = hasBarbell
        self.barWeight = barWeight
        self.platePairs = platePairs
        self.dumbbells = dumbbells
        self.kettlebells = kettlebells
        self.medicineBall = medicineBall
        self.boxHeights = boxHeights
        self.hasBench = hasBench
        self.hasLowBar = hasLowBar
        self.hasBike = hasBike
    }

    public static let homeGym = EquipmentInventory()

    enum CodingKeys: String, CodingKey {
        case unit, hasBarbell, barWeight, platePairs, dumbbells, kettlebells, medicineBall, boxHeights, hasBench, hasLowBar, hasBike
    }

    /// Tolerant: inventories saved before units existed are pounds.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = EquipmentInventory()
        unit = try c.decodeIfPresent(WeightUnit.self, forKey: .unit) ?? .lb
        hasBarbell = try c.decodeIfPresent(Bool.self, forKey: .hasBarbell) ?? d.hasBarbell
        barWeight = try c.decodeIfPresent(Double.self, forKey: .barWeight) ?? d.barWeight
        platePairs = try c.decodeIfPresent([Double].self, forKey: .platePairs) ?? d.platePairs
        dumbbells = try c.decodeIfPresent([Double].self, forKey: .dumbbells) ?? d.dumbbells
        kettlebells = try c.decodeIfPresent([Double].self, forKey: .kettlebells) ?? d.kettlebells
        medicineBall = try c.decodeIfPresent(Double.self, forKey: .medicineBall)
        boxHeights = try c.decodeIfPresent([Int].self, forKey: .boxHeights) ?? d.boxHeights
        hasBench = try c.decodeIfPresent(Bool.self, forKey: .hasBench) ?? d.hasBench
        hasLowBar = try c.decodeIfPresent(Bool.self, forKey: .hasLowBar) ?? d.hasLowBar
        hasBike = try c.decodeIfPresent(Bool.self, forKey: .hasBike) ?? d.hasBike
    }

    public var available: Set<Equipment> {
        var s: Set<Equipment> = [.bodyweight]
        if hasBarbell { s.insert(.barbell) }
        if !dumbbells.isEmpty { s.insert(.dumbbell) }
        if !kettlebells.isEmpty { s.insert(.kettlebell) }
        if medicineBall != nil { s.insert(.medicineBall) }
        if !boxHeights.isEmpty { s.insert(.box) }
        if hasBench { s.insert(.bench) }
        if hasLowBar { s.insert(.lowBar) }
        if hasBike { s.insert(.bike) }
        return s
    }

    /// Lowest box height (the default for jumps and step-ups).
    public var defaultBoxHeight: Int? { boxHeights.min() }

    /// Values are clamped into sane ranges (used after imports / edits).
    public func sanitized() -> EquipmentInventory {
        func clean(_ xs: [Double], _ range: ClosedRange<Double>, max count: Int) -> [Double] {
            Array(xs.filter { $0.isFinite && range.contains($0) }.prefix(count)).sorted()
        }
        var c = self
        c.barWeight = barWeight.isFinite ? min(max(barWeight, 0), 100) : 45
        c.platePairs = clean(platePairs, 0.5...100, max: 30).sorted()
        c.dumbbells = Array(Set(clean(dumbbells, 1...200, max: 30))).sorted()
        c.kettlebells = Array(Set(clean(kettlebells, 1...200, max: 30))).sorted()
        if let m = medicineBall, !(m.isFinite && (1...100).contains(m)) { c.medicineBall = nil }
        c.boxHeights = Array(Set(boxHeights.filter { (6...48).contains($0) })).sorted()
        return c
    }
}

/// Limits the owner can set in Settings.
public struct TrainingLimits: Codable, Hashable, Sendable {
    public var avoidJumping: Bool
    public var easyOnKnee: Bool
    public var easyOnWrist: Bool

    public init(avoidJumping: Bool = false, easyOnKnee: Bool = false, easyOnWrist: Bool = false) {
        self.avoidJumping = avoidJumping
        self.easyOnKnee = easyOnKnee
        self.easyOnWrist = easyOnWrist
    }

    public var protectedJoints: Set<Joint> {
        var s: Set<Joint> = []
        if easyOnKnee { s.insert(.knee) }
        if easyOnWrist { s.insert(.wrist) }
        return s
    }
}

/// Everything the owner configures that the planner reads.
public struct PlannerSettings: Codable, Hashable, Sendable {
    /// Display name for the greeting. Empty means "friend".
    public var displayName: String
    public var schedule: [Weekday]
    public var equipment: EquipmentInventory
    public var limits: TrainingLimits
    public var targetMinutes: Int
    /// Monday of a known "Week A" (Back Squat / Deadlift / Push Press).
    public var rotationAnchor: LocalDate
    /// Start of the program: an initial test period if `initialTestWeeks` > 0,
    /// otherwise block 1 itself (the owner's block 1: Mon Oct 12 2026).
    public var testWeekStart: LocalDate
    /// 0 = straight into block 1; 2 = two test weeks first (new users who
    /// choose "test").
    public var initialTestWeeks: Int
    /// Mondays of weeks that are swapped to a deload (e.g. holidays).
    public var deloadWeeks: [LocalDate]
    /// Planned breaks (vacations): scheduled days inside are excused.
    public var breaks: [TrainingBreak]
    /// Main lifts in rotation order.
    public var lifts: [Lift]
    /// Finished (or skipped) onboarding. Older saved settings count as onboarded.
    public var onboarded: Bool

    public init(displayName: String = "", schedule: [Weekday] = [.monday, .wednesday, .friday],
                equipment: EquipmentInventory = .homeGym, limits: TrainingLimits = TrainingLimits(),
                targetMinutes: Int = 50, rotationAnchor: LocalDate = LocalDate(2026, 9, 28),
                testWeekStart: LocalDate = LocalDate(2026, 10, 12), deloadWeeks: [LocalDate] = [],
                breaks: [TrainingBreak] = [], lifts: [Lift] = Lift.allCases, onboarded: Bool = false, initialTestWeeks: Int = 0) {
        self.displayName = displayName
        self.schedule = schedule
        self.equipment = equipment
        self.limits = limits
        self.targetMinutes = targetMinutes
        self.rotationAnchor = rotationAnchor
        self.testWeekStart = testWeekStart
        self.deloadWeeks = deloadWeeks
        self.breaks = breaks
        self.lifts = lifts
        self.onboarded = onboarded
        self.initialTestWeeks = initialTestWeeks
    }

    enum CodingKeys: String, CodingKey {
        case displayName, schedule, equipment, limits, targetMinutes, rotationAnchor, testWeekStart, deloadWeeks, breaks, lifts, onboarded, initialTestWeeks
    }

    /// Tolerant: settings saved by older versions (no `breaks`, ...) still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PlannerSettings()
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? d.displayName
        schedule = try c.decodeIfPresent([Weekday].self, forKey: .schedule) ?? d.schedule
        equipment = try c.decodeIfPresent(EquipmentInventory.self, forKey: .equipment) ?? d.equipment
        limits = try c.decodeIfPresent(TrainingLimits.self, forKey: .limits) ?? d.limits
        targetMinutes = try c.decodeIfPresent(Int.self, forKey: .targetMinutes) ?? d.targetMinutes
        rotationAnchor = try c.decodeIfPresent(LocalDate.self, forKey: .rotationAnchor) ?? d.rotationAnchor
        testWeekStart = try c.decodeIfPresent(LocalDate.self, forKey: .testWeekStart) ?? d.testWeekStart
        deloadWeeks = try c.decodeIfPresent([LocalDate].self, forKey: .deloadWeeks) ?? d.deloadWeeks
        breaks = try c.decodeIfPresent([TrainingBreak].self, forKey: .breaks) ?? []
        lifts = try c.decodeIfPresent([Lift].self, forKey: .lifts) ?? Lift.allCases
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? true
        // Older settings had a one-week test before block 1; that test week is
        // dropped: their block 1 starts on the saved date.
        initialTestWeeks = try c.decodeIfPresent(Int.self, forKey: .initialTestWeeks) ?? 0
    }

    public static let `default` = PlannerSettings()

    public var units: WeightUnit { equipment.unit }

    /// Switches units: loads that unit's preset gym (kept as-is if already in it).
    public func switchingUnits(to unit: WeightUnit) -> PlannerSettings {
        guard unit != equipment.unit else { return self }
        var s = self
        s.equipment = EquipmentInventory.preset(unit)
        return s
    }

    public var greetingName: String {
        let n = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "friend" : String(n.prefix(40))
    }

    public var sortedSchedule: [Weekday] {
        let s = Array(Set(schedule)).sorted()
        return s.isEmpty ? [.monday, .wednesday, .friday] : s
    }

    public var calendar: ProgramCalendar {
        ProgramCalendar(testWeekStart: testWeekStart, initialTestWeeks: initialTestWeeks, deloadWeeks: Set(deloadWeeks.map(\.startOfWeek)))
    }

    public var rotation: LiftRotation { LiftRotation(anchor: rotationAnchor, schedule: sortedSchedule, lifts: lifts) }

    public func sanitized() -> PlannerSettings {
        var c = self
        c.displayName = String(displayName.prefix(40))
        c.schedule = sortedSchedule
        c.equipment = equipment.sanitized()
        c.targetMinutes = min(max(targetMinutes, 20), 120)
        c.rotationAnchor = rotationAnchor.startOfWeek
        c.testWeekStart = testWeekStart.startOfWeek
        c.deloadWeeks = Array(Set(deloadWeeks.map(\.startOfWeek))).sorted().suffix(52)
        c.breaks = Array(breaks.map { $0.sanitized() }.sorted { $0.from < $1.from }.prefix(50))
        c.lifts = LiftRotation.cleaned(lifts)
        c.initialTestWeeks = initialTestWeeks > 0 ? ProgramCalendar.testWeeks : 0
        return c
    }
}
