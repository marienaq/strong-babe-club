import Foundation

/// A role a move fills in a metcon (spec §3): one for heart rate, one for
/// legs, one for arms, and sometimes core or agility.
public enum MetconSlot: String, Codable, Sendable, CaseIterable, Comparable {
    case heart, legs, arms, core, agility

    /// Heart, legs and arms must be covered by every remixed metcon.
    public static let required: [MetconSlot] = [.legs, .arms, .heart]

    public var displayName: String {
        switch self {
        case .heart: return "heart rate"
        default: return rawValue
        }
    }

    public static func < (a: MetconSlot, b: MetconSlot) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

/// Kind of leg work: knee-dominant, single-leg, or hip-dominant.
public enum LegKind: String, Codable, Sendable, CaseIterable {
    case squat, lunge, hinge
}

/// Kind of arm work.
public enum ArmKind: String, Codable, Sendable, CaseIterable {
    case push, pull
}

/// The intended feel of a metcon (spec §6.1).
public enum MetconStimulus: String, Codable, Sendable, CaseIterable {
    /// Steady, continuous, sustainable pace (AMRAP, EMOM).
    case grind
    /// Hard efforts with rest, repeatable (AMRAP with rest, stations).
    case `repeat`
    /// Finish the work fast (for time).
    case race
    /// Work and rest on the clock (intervals, Tabata).
    case intervals

    public var title: String {
        switch self {
        case .grind: return "Steady grind"
        case .repeat: return "Repeat efforts"
        case .race: return "Race"
        case .intervals: return "Intervals"
        }
    }

    /// One plain sentence for "Why this?".
    public var line: String {
        switch self {
        case .grind: return "pick a pace you can hold the whole time and keep moving"
        case .repeat: return "push each round hard; the rest lets you do it again"
        case .race: return "get the work done as fast as you can, under the cap"
        case .intervals: return "the clock runs the work and rest; go hard in every work period"
        }
    }

    public var formats: [SectionFormat] {
        switch self {
        case .grind: return [.amrap, .emom]
        case .repeat: return [.amrapWithRest, .stations]
        case .race: return [.forTime]
        case .intervals: return [.interval, .tabata]
        }
    }

    /// The stimulus a metabolic format belongs to (nil for non-metcon formats).
    public init?(format: SectionFormat) {
        guard let s = MetconStimulus.allCases.first(where: { $0.formats.contains(format) }) else { return nil }
        self = s
    }
}

/// A barbell lift used light inside a metcon (owner decision Q1): its load
/// is a share of a training max, rounded to the plates.
public struct BarbellLoad: Codable, Hashable, Sendable {
    public var lift: Lift
    public var fraction: Double

    public init(_ lift: Lift, _ fraction: Double) {
        self.lift = lift
        self.fraction = fraction
    }
}

/// Metcon tags of a movement (spec §4.1). Code-defined on the seed library,
/// never persisted.
public struct MetconTags: Codable, Hashable, Sendable {
    public var fills: Set<MetconSlot>
    public var legKind: LegKind?
    /// In the order listed by the spec; the first one is the main kind.
    public var armKinds: [ArmKind]
    public var overhead: Bool
    /// Typical seconds per counted rep at metcon pace (athlete-calibrated, §17.2).
    public var secondsPerRep: Double
    /// Reps per set the athlete can do unbroken at metcon pace.
    public var repRange: ClosedRange<Int>
    /// Reps are counted per side, so prescribed reps are even.
    public var countsEachSide: Bool
    public var gripHeavy: Bool
    public var shoulderHeavy: Bool
    /// Needs care, so it goes first.
    public var technical: Bool
    /// Day slots on which this move is never used (it loads the day's pattern).
    public var conflictsWith: Set<LiftSlot>
    /// Only usable in time-based formats (holds). Nil means "same as `timed`".
    public var timedOnly: Bool?
    /// Metcon default weight in lb (§19.2). Nil falls back to the warm-up default.
    public var load: Double?
    /// Barbell lifts: load from a training max (Q1).
    public var barbell: BarbellLoad?

    public init(fills: Set<MetconSlot> = [], legKind: LegKind? = nil, armKinds: [ArmKind] = [], overhead: Bool = false,
                secondsPerRep: Double = 0, repRange: ClosedRange<Int> = 1...1, countsEachSide: Bool = false,
                gripHeavy: Bool = false, shoulderHeavy: Bool = false, technical: Bool = false,
                conflictsWith: Set<LiftSlot> = [], timedOnly: Bool? = nil, load: Double? = nil, barbell: BarbellLoad? = nil) {
        self.fills = fills
        self.legKind = legKind
        self.armKinds = armKinds
        self.overhead = overhead
        self.secondsPerRep = secondsPerRep
        self.repRange = repRange
        self.countsEachSide = countsEachSide
        self.gripHeavy = gripHeavy
        self.shoulderHeavy = shoulderHeavy
        self.technical = technical
        self.conflictsWith = conflictsWith
        self.timedOnly = timedOnly
        self.load = load
        self.barbell = barbell
    }

    /// Not tagged for metcons.
    public static let none = MetconTags()
}

extension Movement {
    public var fills: Set<MetconSlot> { metcon.fills }
    public var legKind: LegKind? { metcon.legKind }
    /// Main kind of arm work (a curl + press is pull first, then push).
    public var armKind: ArmKind? { metcon.armKinds.first }
    public var armKinds: [ArmKind] { metcon.armKinds }
    public var overhead: Bool { metcon.overhead }
    public var secondsPerRep: Double { metcon.secondsPerRep }
    public var repRange: ClosedRange<Int> { metcon.repRange }
    public var countsEachSide: Bool { metcon.countsEachSide }
    public var gripHeavy: Bool { metcon.gripHeavy }
    public var shoulderHeavy: Bool { metcon.shoulderHeavy }
    public var technical: Bool { metcon.technical }
    public var conflictsWith: Set<LiftSlot> { metcon.conflictsWith }
    public var metconTimedOnly: Bool { metcon.timedOnly ?? timed }
    /// A barbell lift loaded from a training max (not a plate move).
    public var isBarbellLift: Bool { metcon.barbell != nil }

    /// Fills a slot that matters for coverage (legs, arms, heart).
    public var requiredFills: Set<MetconSlot> { fills.intersection(MetconSlot.required) }

    /// A move that is mainly core work (sit-ups, holds, crawls).
    public var isCoreMove: Bool {
        fills.contains(.core) && fills.isDisjoint(with: [.legs, .arms, .heart])
    }

    /// Mostly upper body (for alternating upper and lower in the order).
    public var isUpper: Bool { fills.contains(.arms) && !fills.contains(.legs) }
    public var isLower: Bool { fills.contains(.legs) && !fills.contains(.arms) }

    /// Loads the day's pattern without weight (air squats on squat day): allowed, at most one.
    public func isBodyweightPattern(of slot: LiftSlot) -> Bool {
        guard implement == .bodyweight || implement == .box || implement == .bench else { return false }
        switch slot {
        case .squat: return legKind == .squat
        case .hipPull: return legKind == .hinge
        case .overhead: return overhead
        }
    }
}
