import Foundation

/// What a movement can be used for when building a workout.
public enum MovementRole: String, Codable, Sendable, CaseIterable {
    /// Warm-up move A: raises the heart rate.
    case warmupCardio = "warmup_cardio"
    /// Warm-up moves B-D: prime the day's lift.
    case warmupPrimer = "warmup_primer"
    case metabolic
    case core
    case stretch
    /// One of the six fixed barbell lifts.
    case mainLift = "main_lift"
    /// Tagged so benchmarks can be checked, but never picked for a remixed metcon.
    case benchmarkOnly = "benchmark_only"
}

public struct Movement: Codable, Hashable, Sendable, Identifiable {
    /// Stable slug ("kb-swing"). Imported movements are slugified names.
    public var id: String
    public var name: String
    public var pattern: MovementPattern
    public var muscles: [Muscle]
    /// Everything required (all of it must be available).
    public var equipment: [Equipment]
    public var implement: Implement
    public var highImpact: Bool
    public var jointFlags: [Joint]
    /// Default prescribed weight in lb (DB weights are per hand).
    public var defaultWeight: Double?
    /// DB move that may become a KB move when the DB is too light.
    public var kettlebellAlternative: Bool
    /// Uses a pair of dumbbells ("2 × 20 lb").
    public var dumbbellPair: Bool
    public var roles: [MovementRole]
    /// Warm-up primers: the lift slots they prepare.
    public var primes: [LiftSlot]
    /// Typical reps in a metcon round (mid intensity) or seconds if `timed`.
    public var baseReps: Int
    public var timed: Bool
    /// Low-impact replacement when "avoid jumping" is on.
    public var noJumpSubstitute: String?
    /// Replacement when a joint limit rules this out.
    public var jointSubstitute: String?
    /// How the move works inside a metcon (slots, pace, flags, conflicts).
    public var metcon: MetconTags

    public init(id: String, name: String, pattern: MovementPattern, muscles: [Muscle], equipment: [Equipment] = [.bodyweight],
                implement: Implement = .bodyweight, highImpact: Bool = false, jointFlags: [Joint] = [], defaultWeight: Double? = nil,
                kettlebellAlternative: Bool = false, dumbbellPair: Bool = false, roles: [MovementRole], primes: [LiftSlot] = [],
                baseReps: Int = 10, timed: Bool = false, noJumpSubstitute: String? = nil, jointSubstitute: String? = nil,
                metcon: MetconTags = .none) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.muscles = muscles
        self.equipment = equipment
        self.implement = implement
        self.highImpact = highImpact
        self.jointFlags = jointFlags
        self.defaultWeight = defaultWeight
        self.kettlebellAlternative = kettlebellAlternative
        self.dumbbellPair = dumbbellPair
        self.roles = roles
        self.primes = primes
        self.baseReps = baseReps
        self.timed = timed
        self.noJumpSubstitute = noJumpSubstitute
        self.jointSubstitute = jointSubstitute
        self.metcon = metcon
    }

    public func has(_ role: MovementRole) -> Bool { roles.contains(role) }

    /// Allowed with this equipment and these limits (no substitution).
    public func isAllowed(equipment available: Set<Equipment>, limits: TrainingLimits) -> Bool {
        guard equipment.allSatisfy(available.contains) else { return false }
        if limits.avoidJumping && highImpact { return false }
        if !limits.protectedJoints.isDisjoint(with: jointFlags) { return false }
        return true
    }

    /// Plural-ish display name for a line like "5 KB swings".
    public var lineName: String { name }
}

/// The curated movement library. Seeded with generic, commonly programmed
/// movements matching the home gym (see IOS-PLAN "Home gym").
public struct MovementLibrary: Sendable {
    public let movements: [Movement]
    private let byID: [String: Movement]
    private let bySlug: [String: Movement]
    /// Coach-style names (as slugs) that map to a library id ("russian-kb-swing").
    public let aliases: [String: String]
    private let lookups = LookupCache()

    public init(_ movements: [Movement] = MovementLibrary.seed, aliases: [String: String] = MovementLibrary.standardAliases) {
        self.movements = movements
        var d: [String: Movement] = [:]
        var n: [String: Movement] = [:]
        for m in movements {
            d[m.id] = m
            n[MovementLibrary.slug(m.name)] = n[MovementLibrary.slug(m.name)] ?? m
        }
        self.byID = d
        self.bySlug = n
        self.aliases = aliases
    }

    public static let standard = MovementLibrary()

    public subscript(id: String) -> Movement? { byID[id] }

    public func movements(with role: MovementRole) -> [Movement] { movements.filter { $0.has(role) } }

    /// Applies equipment + limits. Returns the movement itself, a substitute
    /// (flagged), or nil if nothing fits.
    public func resolve(_ m: Movement, equipment: Set<Equipment>, limits: TrainingLimits) -> (movement: Movement, substituted: Bool)? {
        if m.isAllowed(equipment: equipment, limits: limits) { return (m, false) }
        var candidates: [String] = []
        if let s = m.noJumpSubstitute { candidates.append(s) }
        if let s = m.jointSubstitute { candidates.append(s) }
        for id in candidates {
            if let sub = self[id], sub.isAllowed(equipment: equipment, limits: limits) { return (sub, true) }
            // One more hop (e.g. box jump -> step-up -> glute bridge for knees).
            if let sub = self[id] {
                for id2 in [sub.noJumpSubstitute, sub.jointSubstitute].compactMap({ $0 }) {
                    if let sub2 = self[id2], sub2.isAllowed(equipment: equipment, limits: limits) { return (sub2, true) }
                }
            }
        }
        return nil
    }

    /// Normalizes a free-text movement name to a slug id.
    public static func slug(_ name: String) -> String {
        let lowered = name.lowercased()
        var out = ""
        var lastDash = false
        for ch in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(ch) && ch.isASCII {
                out.unicodeScalars.append(ch)
                lastDash = false
            } else if !lastDash && !out.isEmpty {
                out.append("-")
                lastDash = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return String(out.prefix(80))
    }

    /// Finds a library movement by display name (case-insensitive), slug,
    /// coach-style alias, or a plural/singular form of any of those.
    public func lookup(name: String) -> Movement? {
        if let hit = lookups.get(name) { return hit.movement }
        let found = findByName(name)
        lookups.set(name, found)
        return found
    }

    private func findByName(_ name: String) -> Movement? {
        let s = MovementLibrary.slug(name)
        var forms = [s]
        if s.hasSuffix("s") { forms.append(String(s.dropLast())) } else { forms.append(s + "s") }
        if s.hasSuffix("es") { forms.append(String(s.dropLast(2))) }
        for f in forms {
            if let m = byID[f] ?? bySlug[f] { return m }
            if let id = aliases[f], let m = byID[id] { return m }
        }
        return nil
    }

    /// Library movement for a section item (by id, then by name).
    public func movement(for item: SectionItem) -> Movement? {
        self[item.movementID] ?? lookup(name: item.movementName)
    }

    /// Coach-style names used in at least 5 of the coach's metcons (generic names only).
    public static let standardAliases: [String: String] = [
        "up-down": "up-down", "push-up": "push-up",
        "kb-swing": "kb-swing", "russian-kb-swing": "kb-swing",
        "burpee": "burpee",
        "sit-up": "sit-up", "strict-sit-up": "sit-up",
        "goblet-squat": "goblet-squat", "kb-goblet-squat": "goblet-squat", "db-goblet-squat": "goblet-squat",
        "single-arm-db-power-snatch": "db-snatch", "db-power-snatch": "db-snatch",
        "jumping-jack": "jumping-jack",
        "forward-lunge": "lunge", "reverse-lunge": "lunge",
        "step-up": "bench-step-up",
        "db-curl-db-press": "db-curl-press",
        "bench-jump": "box-jump",
        "overhead-kb-swing": "kb-overhead-swing",
        "db-lunge": "db-front-rack-lunge",
        "shoulder-press": "barbell-shoulder-press",
        "db-bench-step-up": "db-step-up",
        "db-hang-power-clean-push-press": "db-hang-clean-push-press",
        "toe-tap": "toe-tap", "leg-raise": "leg-raise", "wall-walk": "wall-walk",
    ]
}

/// Remembers name lookups (history items are looked up over and over).
private final class LookupCache: @unchecked Sendable {
    struct Hit { var movement: Movement? }
    private var hits: [String: Hit] = [:]
    private let lock = NSLock()

    func get(_ name: String) -> Hit? {
        lock.lock()
        defer { lock.unlock() }
        return hits[name]
    }

    func set(_ name: String, _ m: Movement?) {
        lock.lock()
        defer { lock.unlock() }
        if hits.count > 5000 { hits.removeAll() }
        hits[name] = Hit(movement: m)
    }
}

extension MovementLibrary {
    /// Shorthand for the metcon tag tables in spec §4.4, §4.5 and §17.2.
    static func tags(_ fills: [MetconSlot], leg: LegKind? = nil, arm: [ArmKind] = [], oh: Bool = false, spr: Double,
                     reps: ClosedRange<Int>, side: Bool = false, grip: Bool = false, shoulder: Bool = false, tech: Bool = false,
                     conflicts: [LiftSlot] = [], timedOnly: Bool? = nil, load: Double? = nil, barbell: BarbellLoad? = nil) -> MetconTags {
        MetconTags(fills: Set(fills), legKind: leg, armKinds: arm, overhead: oh, secondsPerRep: spr, repRange: reps,
                   countsEachSide: side, gripHeavy: grip, shoulderHeavy: shoulder, technical: tech,
                   conflictsWith: Set(conflicts), timedOnly: timedOnly, load: load, barbell: barbell)
    }

    /// Metcon tags of the six main lifts. Light barbell lifts may appear in
    /// metcons (never the day's lift): squats and deadlift at 50% of the
    /// training max, cleans and presses at 55%.
    static func liftTags(_ lift: Lift) -> MetconTags {
        switch lift {
        case .backSquat:
            return tags([.legs], leg: .squat, spr: 2.5, reps: 5...12, tech: true, conflicts: [.squat], barbell: BarbellLoad(.backSquat, 0.5))
        case .frontSquat:
            return tags([.legs], leg: .squat, spr: 2.5, reps: 5...10, tech: true, conflicts: [.squat], barbell: BarbellLoad(.frontSquat, 0.5))
        case .deadlift:
            return tags([.legs], leg: .hinge, spr: 2.0, reps: 5...12, grip: true, tech: true, conflicts: [.hipPull],
                        barbell: BarbellLoad(.deadlift, 0.5))
        case .hangPowerClean:
            return tags([.legs, .arms], leg: .hinge, arm: [.pull], spr: 2.5, reps: 3...10, grip: true, tech: true,
                        conflicts: [.hipPull], barbell: BarbellLoad(.hangPowerClean, 0.55))
        case .pushPress:
            return tags([.arms], arm: [.push], oh: true, spr: 2.0, reps: 5...12, shoulder: true, tech: true, conflicts: [.overhead],
                        barbell: BarbellLoad(.pushPress, 0.55))
        case .pushJerk:
            return tags([.arms], arm: [.push], oh: true, spr: 2.2, reps: 3...10, shoulder: true, tech: true, conflicts: [.overhead],
                        barbell: BarbellLoad(.pushJerk, 0.55))
        }
    }

    // swiftlint:disable function_body_length
    public static let seed: [Movement] = {
        var m: [Movement] = []
        func add(_ x: Movement) { m.append(x) }

        // The six fixed lifts. Also usable light inside a metcon (never on their own day).
        for lift in Lift.allCases {
            add(Movement(id: lift.movementID, name: lift.displayName, pattern: lift.pattern, muscles: Array(lift.primaryMuscles).sorted(),
                         equipment: [.barbell], implement: .barbell, jointFlags: Array(lift.jointStress).sorted { $0.rawValue < $1.rawValue },
                         roles: [.mainLift, .metabolic], baseReps: 5, metcon: liftTags(lift)))
        }

        // Heart-rate raisers (warm-up A) and conditioning.
        add(Movement(id: "jumping-jack", name: "Jumping Jacks", pattern: .cardio, muscles: [.calves, .shoulders], highImpact: true,
                     roles: [.warmupCardio, .metabolic], baseReps: 25, noJumpSubstitute: "toe-tap",
                     metcon: tags([.heart], spr: 1.1, reps: 10...30)))
        add(Movement(id: "toe-tap", name: "Toe Taps", pattern: .cardio, muscles: [.calves, .quads], roles: [.warmupCardio, .metabolic], baseReps: 20,
                     metcon: tags([.heart], spr: 0.6, reps: 10...40, side: true)))
        add(Movement(id: "burpee", name: "Burpees", pattern: .cardio, muscles: [.chest, .quads, .shoulders], highImpact: true, jointFlags: [.wrist],
                     roles: [.warmupCardio, .metabolic], baseReps: 6, noJumpSubstitute: "up-down", jointSubstitute: "squat-thrust-hold",
                     metcon: tags([.heart], spr: 4.6, reps: 3...10)))
        add(Movement(id: "up-down", name: "Up/Downs", pattern: .cardio, muscles: [.chest, .quads], jointFlags: [.wrist],
                     roles: [.warmupCardio, .metabolic], baseReps: 6, jointSubstitute: "squat-thrust-hold",
                     metcon: tags([.heart], spr: 2.5, reps: 3...10)))
        add(Movement(id: "squat-thrust-hold", name: "Squat to Stand", pattern: .squat, muscles: [.quads, .hamstrings],
                     roles: [.warmupCardio, .metabolic], baseReps: 8,
                     metcon: tags([.heart, .legs], leg: .squat, spr: 2.6, reps: 4...12)))
        add(Movement(id: "high-knees", name: "High Knees", pattern: .cardio, muscles: [.quads, .calves, .core], highImpact: true,
                     roles: [.warmupCardio, .metabolic], baseReps: 30, noJumpSubstitute: "marching-knees",
                     metcon: tags([.heart], spr: 0.5, reps: 20...50, side: true)))
        add(Movement(id: "marching-knees", name: "Marching Knee Drives", pattern: .cardio, muscles: [.quads, .core],
                     roles: [.warmupCardio, .metabolic], baseReps: 30,
                     metcon: tags([.heart], spr: 0.5, reps: 20...50, side: true)))
        add(Movement(id: "mountain-climber", name: "Mountain Climbers", pattern: .cardio, muscles: [.core, .shoulders], jointFlags: [.wrist],
                     roles: [.warmupCardio, .metabolic], baseReps: 20, jointSubstitute: "marching-knees",
                     metcon: tags([.heart, .core], spr: 0.6, reps: 10...40, side: true)))
        add(Movement(id: "bike-cal", name: "Bike Calories", pattern: .cardio, muscles: [.quads], equipment: [.bike], implement: .bike,
                     roles: [.metabolic], baseReps: 10,
                     metcon: tags([.heart], spr: 4.2, reps: 5...20)))

        // Squat primers / leg work.
        add(Movement(id: "air-squat", name: "Air Squats", pattern: .squat, muscles: [.quads, .glutes], roles: [.warmupPrimer, .metabolic],
                     primes: [.squat], baseReps: 10,
                     metcon: tags([.legs], leg: .squat, spr: 1.6, reps: 6...20)))
        add(Movement(id: "goblet-squat", name: "KB Goblet Squats", pattern: .squat, muscles: [.quads, .glutes, .core], equipment: [.kettlebell],
                     implement: .kettlebell, jointFlags: [.knee], defaultWeight: 26, roles: [.warmupPrimer, .metabolic], primes: [.squat],
                     baseReps: 10, jointSubstitute: "glute-bridge",
                     metcon: tags([.legs], leg: .squat, spr: 2.5, reps: 5...15, grip: true, conflicts: [.squat], load: 35)))
        add(Movement(id: "lunge", name: "Alternating Lunges", pattern: .lunge, muscles: [.quads, .glutes], jointFlags: [.knee],
                     roles: [.warmupPrimer, .metabolic], primes: [.squat], baseReps: 10, jointSubstitute: "glute-bridge",
                     metcon: tags([.legs], leg: .lunge, spr: 1.7, reps: 6...20, side: true)))
        add(Movement(id: "db-reverse-lunge", name: "DB Reverse Lunges", pattern: .lunge, muscles: [.quads, .glutes], equipment: [.dumbbell],
                     implement: .dumbbell, jointFlags: [.knee], defaultWeight: 15, dumbbellPair: true, roles: [.metabolic], baseReps: 10,
                     jointSubstitute: "db-glute-bridge",
                     metcon: tags([.legs], leg: .lunge, spr: 2.3, reps: 6...16, side: true, grip: true, load: 15)))
        add(Movement(id: "bench-step-up", name: "Bench Step-Ups", pattern: .lunge, muscles: [.quads, .glutes], equipment: [.bench],
                     implement: .bench, jointFlags: [.knee], roles: [.warmupPrimer, .metabolic], primes: [.squat], baseReps: 10,
                     jointSubstitute: "glute-bridge",
                     metcon: tags([.legs], leg: .lunge, spr: 1.9, reps: 6...20, side: true)))
        add(Movement(id: "box-step-up", name: "Box Step-Ups", pattern: .lunge, muscles: [.quads, .glutes], equipment: [.box],
                     implement: .box, jointFlags: [.knee], roles: [.metabolic], baseReps: 10, jointSubstitute: "glute-bridge",
                     metcon: tags([.legs], leg: .lunge, spr: 1.9, reps: 6...20, side: true)))
        add(Movement(id: "box-jump", name: "Box Jumps", pattern: .squat, muscles: [.quads, .glutes, .calves], equipment: [.box],
                     implement: .box, highImpact: true, jointFlags: [.knee], roles: [.metabolic], baseReps: 6,
                     noJumpSubstitute: "box-step-up", jointSubstitute: "box-step-up",
                     metcon: tags([.heart, .legs], leg: .squat, spr: 2.8, reps: 3...10, tech: true)))
        add(Movement(id: "db-split-squat", name: "DB Split Squats", pattern: .lunge, muscles: [.quads, .glutes], equipment: [.dumbbell],
                     implement: .dumbbell, jointFlags: [.knee], defaultWeight: 15, dumbbellPair: true, roles: [.metabolic], baseReps: 8,
                     jointSubstitute: "db-glute-bridge",
                     metcon: tags([.legs], leg: .lunge, spr: 2.6, reps: 6...12, side: true, grip: true, load: 15)))
        add(Movement(id: "glute-bridge", name: "Glute Bridges", pattern: .hinge, muscles: [.glutes, .hamstrings],
                     roles: [.warmupPrimer, .metabolic], primes: [.squat, .hipPull], baseReps: 12,
                     metcon: tags([.legs], leg: .hinge, spr: 1.6, reps: 8...20)))
        add(Movement(id: "db-glute-bridge", name: "DB Glute Bridges", pattern: .hinge, muscles: [.glutes, .hamstrings], equipment: [.dumbbell],
                     implement: .dumbbell, defaultWeight: 20, roles: [.metabolic], baseReps: 12,
                     metcon: tags([.legs], leg: .hinge, spr: 1.9, reps: 8...20, conflicts: [.hipPull], load: 20)))
        add(Movement(id: "cossack-squat", name: "Cossack Squats", pattern: .squat, muscles: [.quads, .glutes], jointFlags: [.knee],
                     roles: [.warmupPrimer], primes: [.squat], baseReps: 6, jointSubstitute: "glute-bridge"))
        add(Movement(id: "db-front-squat", name: "DB Front Squats", pattern: .squat, muscles: [.quads, .glutes, .core], equipment: [.dumbbell],
                     implement: .dumbbell, jointFlags: [.knee], defaultWeight: 20, dumbbellPair: true, roles: [.metabolic], baseReps: 8,
                     jointSubstitute: "db-glute-bridge",
                     metcon: tags([.legs], leg: .squat, spr: 2.5, reps: 5...15, grip: true, conflicts: [.squat], load: 20)))
        add(Movement(id: "db-step-up", name: "DB Step-Ups", pattern: .lunge, muscles: [.quads, .glutes], equipment: [.dumbbell, .box],
                     implement: .dumbbell, jointFlags: [.knee], defaultWeight: 10, dumbbellPair: true, roles: [.metabolic], baseReps: 10,
                     jointSubstitute: "db-glute-bridge",
                     metcon: tags([.legs], leg: .lunge, spr: 2.1, reps: 6...16, side: true, grip: true, load: 10)))
        add(Movement(id: "db-front-rack-lunge", name: "DB Front Rack Lunges", pattern: .lunge, muscles: [.quads, .glutes, .core],
                     equipment: [.dumbbell], implement: .dumbbell, jointFlags: [.knee], defaultWeight: 20, dumbbellPair: true,
                     roles: [.metabolic], baseReps: 10, jointSubstitute: "db-glute-bridge",
                     metcon: tags([.legs], leg: .lunge, spr: 2.3, reps: 6...16, side: true, grip: true, load: 20)))
        add(Movement(id: "overhead-plate-lunge", name: "Overhead Plate Lunges", pattern: .lunge, muscles: [.quads, .glutes, .shoulders, .core],
                     equipment: [.barbell], implement: .barbell, jointFlags: [.knee], defaultWeight: 15, roles: [.metabolic], baseReps: 10,
                     jointSubstitute: "plate-ground-to-overhead",
                     metcon: tags([.legs, .arms], leg: .lunge, arm: [.push], oh: true, spr: 2.3, reps: 6...12, side: true, shoulder: true,
                                  conflicts: [.overhead], load: 15)))

        // Hinge / pull primers.
        add(Movement(id: "good-morning", name: "Good Mornings", pattern: .hinge, muscles: [.hamstrings, .lowerBack], roles: [.warmupPrimer],
                     primes: [.hipPull], baseReps: 10))
        add(Movement(id: "db-rdl", name: "DB Romanian Deadlifts", pattern: .hinge, muscles: [.hamstrings, .glutes, .lowerBack],
                     equipment: [.dumbbell], implement: .dumbbell, defaultWeight: 20, dumbbellPair: true, roles: [.warmupPrimer, .metabolic],
                     primes: [.hipPull], baseReps: 8,
                     metcon: tags([.legs], leg: .hinge, spr: 2.3, reps: 6...12, grip: true, conflicts: [.hipPull], load: 20)))
        add(Movement(id: "kb-deadlift", name: "KB Deadlifts", pattern: .hinge, muscles: [.hamstrings, .glutes], equipment: [.kettlebell],
                     implement: .kettlebell, defaultWeight: 35, roles: [.warmupPrimer, .metabolic], primes: [.hipPull], baseReps: 10,
                     metcon: tags([.legs], leg: .hinge, spr: 1.9, reps: 6...15, grip: true, conflicts: [.hipPull], load: 35)))
        add(Movement(id: "db-deadlift", name: "DB Deadlifts", pattern: .hinge, muscles: [.hamstrings, .glutes, .lowerBack],
                     equipment: [.dumbbell], implement: .dumbbell, defaultWeight: 20, dumbbellPair: true, roles: [.metabolic], baseReps: 10,
                     metcon: tags([.legs], leg: .hinge, spr: 1.9, reps: 6...15, grip: true, conflicts: [.hipPull], load: 20)))
        add(Movement(id: "inchworm", name: "Inchworms", pattern: .mobility, muscles: [.hamstrings, .shoulders, .core], jointFlags: [.wrist],
                     roles: [.warmupPrimer], primes: [.hipPull, .overhead], baseReps: 5, jointSubstitute: "good-morning"))
        add(Movement(id: "kb-swing", name: "KB Swings", pattern: .hinge, muscles: [.hamstrings, .glutes, .shoulders], equipment: [.kettlebell],
                     implement: .kettlebell, defaultWeight: 26, roles: [.warmupPrimer, .metabolic], primes: [.hipPull], baseReps: 12,
                     metcon: tags([.legs, .heart], leg: .hinge, spr: 1.8, reps: 6...20, grip: true, load: 35)))
        add(Movement(id: "db-hang-squat-clean", name: "DB Hang Squat Cleans", pattern: .squat, muscles: [.quads, .glutes, .upperBack],
                     equipment: [.dumbbell], implement: .dumbbell, jointFlags: [.wrist], defaultWeight: 20, dumbbellPair: true,
                     roles: [.metabolic], baseReps: 6, jointSubstitute: "kb-deadlift",
                     metcon: tags([.legs, .arms], leg: .squat, arm: [.pull], spr: 2.5, reps: 4...10, grip: true, tech: true,
                                  conflicts: [.squat, .hipPull], load: 20)))
        add(Movement(id: "db-snatch", name: "Alternating DB Snatches", pattern: .hinge, muscles: [.hamstrings, .glutes, .shoulders],
                     equipment: [.dumbbell], implement: .dumbbell, defaultWeight: 20, kettlebellAlternative: true, roles: [.metabolic], baseReps: 10,
                     metcon: tags([.legs, .arms, .heart], leg: .hinge, arm: [.pull], oh: true, spr: 1.6, reps: 6...16, side: true, grip: true,
                                  shoulder: true, tech: true, load: 20)))
        add(Movement(id: "kb-high-pull", name: "KB Sumo Deadlift High Pulls", pattern: .pull, muscles: [.upperBack, .glutes, .shoulders],
                     equipment: [.kettlebell], implement: .kettlebell, defaultWeight: 26, roles: [.metabolic], baseReps: 10,
                     metcon: tags([.legs, .arms], leg: .hinge, arm: [.pull], spr: 2.1, reps: 6...15, grip: true, conflicts: [.hipPull], load: 26)))
        add(Movement(id: "db-row", name: "Bench DB Rows", pattern: .pull, muscles: [.lats, .upperBack, .biceps], equipment: [.dumbbell, .bench],
                     implement: .dumbbell, defaultWeight: 20, roles: [.warmupPrimer, .metabolic], primes: [.hipPull], baseReps: 10,
                     metcon: tags([.arms], arm: [.pull], spr: 2.1, reps: 6...16, side: true, grip: true, load: 20)))
        add(Movement(id: "db-bent-over-row", name: "DB Bent-Over Rows", pattern: .pull, muscles: [.lats, .upperBack, .biceps],
                     equipment: [.dumbbell], implement: .dumbbell, defaultWeight: 20, dumbbellPair: true, roles: [.metabolic], baseReps: 10,
                     metcon: tags([.arms], arm: [.pull], spr: 2.1, reps: 6...15, grip: true, load: 20)))
        add(Movement(id: "australian-pull-up", name: "Australian Pull-Ups", pattern: .pull, muscles: [.lats, .upperBack, .biceps],
                     equipment: [.lowBar], roles: [.warmupPrimer, .metabolic], primes: [.hipPull, .overhead], baseReps: 6,
                     metcon: tags([.arms], arm: [.pull], spr: 3.2, reps: 3...12, grip: true)))
        add(Movement(id: "prone-swimmer", name: "Prone Swimmers", pattern: .pull, muscles: [.upperBack, .lats, .lowerBack],
                     roles: [.metabolic], baseReps: 10,
                     metcon: tags([.arms], arm: [.pull], spr: 1.6, reps: 6...16)))
        add(Movement(id: "power-clean", name: "Power Cleans", pattern: .hinge, muscles: [.hamstrings, .glutes, .upperBack, .shoulders],
                     equipment: [.barbell], implement: .barbell, jointFlags: [.wrist], roles: [.metabolic], baseReps: 5,
                     metcon: tags([.legs, .arms], leg: .hinge, arm: [.pull], spr: 2.6, reps: 3...10, grip: true, tech: true,
                                  conflicts: [.hipPull], barbell: BarbellLoad(.hangPowerClean, 0.55))))

        // Press primers / upper body.
        add(Movement(id: "push-up", name: "Push-Ups", pattern: .press, muscles: [.chest, .triceps, .shoulders], jointFlags: [.wrist],
                     roles: [.warmupPrimer, .metabolic], primes: [.overhead], baseReps: 6, jointSubstitute: "db-floor-press",
                     metcon: tags([.arms], arm: [.push], spr: 2.5, reps: 3...12)))
        add(Movement(id: "hand-release-push-up", name: "Hand-Release Push-Ups", pattern: .press, muscles: [.chest, .triceps, .shoulders],
                     jointFlags: [.wrist], roles: [.metabolic], baseReps: 5, jointSubstitute: "db-floor-press",
                     metcon: tags([.arms], arm: [.push], spr: 3.7, reps: 3...10)))
        add(Movement(id: "db-floor-press", name: "DB Floor Press", pattern: .press, muscles: [.chest, .triceps], equipment: [.dumbbell],
                     implement: .dumbbell, defaultWeight: 20, dumbbellPair: true, roles: [.metabolic], baseReps: 10,
                     metcon: tags([.arms], arm: [.push], spr: 2.1, reps: 6...15, load: 20)))
        add(Movement(id: "inchworm-shoulder-tap", name: "Inchworm Shoulder Taps", pattern: .press, muscles: [.shoulders, .core],
                     jointFlags: [.wrist], roles: [.warmupPrimer], primes: [.overhead], baseReps: 4, jointSubstitute: "arm-circle"))
        add(Movement(id: "arm-circle", name: "Arm Circles", pattern: .mobility, muscles: [.shoulders], roles: [.warmupPrimer],
                     primes: [.overhead], baseReps: 10))
        add(Movement(id: "plate-ground-to-overhead", name: "Plate Ground to Overhead", pattern: .press, muscles: [.shoulders, .glutes, .core],
                     equipment: [.barbell], implement: .barbell, defaultWeight: 10, roles: [.warmupPrimer, .metabolic],
                     primes: [.overhead, .hipPull], baseReps: 8,
                     metcon: tags([.legs, .arms], leg: .hinge, arm: [.push], oh: true, spr: 2.1, reps: 5...12, shoulder: true, load: 25)))
        add(Movement(id: "db-ground-to-overhead", name: "DB Ground to Overhead", pattern: .press, muscles: [.shoulders, .glutes, .core],
                     equipment: [.dumbbell], implement: .dumbbell, defaultWeight: 15, roles: [.metabolic], baseReps: 8,
                     metcon: tags([.legs, .arms], leg: .hinge, arm: [.push], oh: true, spr: 2.3, reps: 5...12, shoulder: true, load: 15)))
        add(Movement(id: "db-strict-press", name: "DB Strict Press", pattern: .press, muscles: [.shoulders, .triceps], equipment: [.dumbbell],
                     implement: .dumbbell, defaultWeight: 10, dumbbellPair: true, roles: [.warmupPrimer, .metabolic], primes: [.overhead], baseReps: 8,
                     metcon: tags([.arms], arm: [.push], oh: true, spr: 2.1, reps: 5...12, shoulder: true, conflicts: [.overhead], load: 10)))
        add(Movement(id: "db-push-press", name: "DB Push Press", pattern: .press, muscles: [.shoulders, .triceps, .quads], equipment: [.dumbbell],
                     implement: .dumbbell, defaultWeight: 20, dumbbellPair: true, roles: [.metabolic], baseReps: 8,
                     metcon: tags([.arms], arm: [.push], oh: true, spr: 1.7, reps: 5...12, shoulder: true, conflicts: [.overhead], load: 20)))
        add(Movement(id: "db-curl-press", name: "DB Curl + Press", pattern: .press, muscles: [.biceps, .shoulders, .triceps],
                     equipment: [.dumbbell], implement: .dumbbell, defaultWeight: 15, dumbbellPair: true, roles: [.metabolic], baseReps: 8,
                     metcon: tags([.arms], arm: [.pull, .push], oh: true, spr: 2.5, reps: 5...12, shoulder: true, conflicts: [.overhead], load: 15)))
        add(Movement(id: "db-hang-clean-push-press", name: "DB Hang Clean + Push Press", pattern: .press,
                     muscles: [.glutes, .upperBack, .shoulders, .triceps], equipment: [.dumbbell], implement: .dumbbell, defaultWeight: 20,
                     dumbbellPair: true, roles: [.metabolic], baseReps: 6,
                     metcon: tags([.legs, .arms], leg: .hinge, arm: [.push], oh: true, spr: 2.7, reps: 4...10, grip: true, shoulder: true,
                                  tech: true, conflicts: [.hipPull, .overhead], load: 20)))
        add(Movement(id: "db-thruster", name: "DB Thrusters", pattern: .squat, muscles: [.quads, .glutes, .shoulders], equipment: [.dumbbell],
                     implement: .dumbbell, defaultWeight: 15, dumbbellPair: true, roles: [.metabolic], baseReps: 8,
                     metcon: tags([.legs, .arms, .heart], leg: .squat, arm: [.push], oh: true, spr: 2.5, reps: 5...12, shoulder: true,
                                  conflicts: [.squat, .overhead], load: 20)))
        add(Movement(id: "barbell-thruster", name: "Thrusters", pattern: .squat, muscles: [.quads, .glutes, .shoulders], equipment: [.barbell],
                     implement: .barbell, jointFlags: [.knee], roles: [.metabolic], baseReps: 5,
                     metcon: tags([.legs, .arms, .heart], leg: .squat, arm: [.push], oh: true, spr: 2.6, reps: 5...10, shoulder: true, tech: true,
                                  conflicts: [.squat, .overhead], barbell: BarbellLoad(.pushPress, 0.55))))
        add(Movement(id: "barbell-shoulder-press", name: "Shoulder Press", pattern: .press, muscles: [.shoulders, .triceps], equipment: [.barbell],
                     implement: .barbell, roles: [.metabolic], baseReps: 5,
                     metcon: tags([.arms], arm: [.push], oh: true, spr: 2.2, reps: 5...10, shoulder: true, tech: true,
                                  conflicts: [.overhead], barbell: BarbellLoad(.pushPress, 0.55))))
        add(Movement(id: "db-bench-press", name: "DB Bench Press", pattern: .press, muscles: [.chest, .triceps], equipment: [.dumbbell, .bench],
                     implement: .dumbbell, defaultWeight: 20, dumbbellPair: true, roles: [.metabolic], baseReps: 10,
                     metcon: tags([.arms], arm: [.push], spr: 2.1, reps: 6...15, load: 20)))
        add(Movement(id: "tricep-dip", name: "Bench Tricep Dips", pattern: .press, muscles: [.triceps], equipment: [.bench], implement: .bench,
                     jointFlags: [.wrist], roles: [.metabolic], baseReps: 10, jointSubstitute: "db-floor-press",
                     metcon: tags([.arms], arm: [.push], spr: 1.9, reps: 6...15)))
        add(Movement(id: "wall-walk", name: "Wall Walks", pattern: .press, muscles: [.shoulders, .core], jointFlags: [.wrist],
                     roles: [.metabolic], baseReps: 3, jointSubstitute: "db-strict-press",
                     metcon: tags([.arms, .core], arm: [.push], oh: true, spr: 12.6, reps: 1...5, shoulder: true, tech: true, conflicts: [.overhead])))
        add(Movement(id: "med-ball-slam", name: "Med Ball Slams", pattern: .hinge, muscles: [.core, .shoulders, .lats], equipment: [.medicineBall],
                     implement: .medicineBall, defaultWeight: 12, roles: [.metabolic], baseReps: 10,
                     metcon: tags([.heart, .core], spr: 2.1, reps: 6...15, load: 12)))
        add(Movement(id: "bear-crawl", name: "Bear Crawl Steps", pattern: .carry, muscles: [.core, .shoulders], jointFlags: [.wrist],
                     roles: [.metabolic], baseReps: 10, jointSubstitute: "skater-step",
                     metcon: tags([.agility, .core], spr: 0.8, reps: 10...30, shoulder: true)))
        add(Movement(id: "kb-farmer-carry", name: "KB Suitcase March", pattern: .carry, muscles: [.core, .upperBack], equipment: [.kettlebell],
                     implement: .kettlebell, defaultWeight: 35, roles: [.metabolic], baseReps: 20,
                     metcon: tags([.core], spr: 0.8, reps: 10...40, side: true, grip: true, load: 35)))

        // Agility (footwork).
        add(Movement(id: "lateral-bench-step-over", name: "Lateral Bench Step-Overs", pattern: .cardio, muscles: [.quads, .glutes, .calves],
                     equipment: [.bench], implement: .bench, jointFlags: [.knee], roles: [.metabolic], baseReps: 10,
                     jointSubstitute: "lateral-shuffle-touch",
                     metcon: tags([.agility, .heart], spr: 1.6, reps: 6...20)))
        add(Movement(id: "skater", name: "Skaters", pattern: .cardio, muscles: [.glutes, .quads, .calves], highImpact: true,
                     roles: [.metabolic], baseReps: 16, noJumpSubstitute: "skater-step",
                     metcon: tags([.agility, .heart], spr: 0.8, reps: 10...30, side: true)))
        add(Movement(id: "skater-step", name: "Skater Steps", pattern: .cardio, muscles: [.glutes, .quads], roles: [.metabolic], baseReps: 16,
                     metcon: tags([.agility], spr: 1.1, reps: 10...30, side: true)))
        add(Movement(id: "lateral-shuffle-touch", name: "Lateral Shuffle Touches", pattern: .cardio, muscles: [.quads, .glutes],
                     roles: [.metabolic], baseReps: 12,
                     metcon: tags([.agility, .heart], spr: 1.6, reps: 6...20, side: true)))

        // Tagged so benchmarks can be checked; never picked for remixes.
        add(Movement(id: "kb-overhead-swing", name: "Overhead KB Swings", pattern: .hinge, muscles: [.hamstrings, .glutes, .shoulders],
                     equipment: [.kettlebell], implement: .kettlebell, defaultWeight: 26, roles: [.benchmarkOnly], baseReps: 10,
                     metcon: tags([.legs, .heart, .arms], leg: .hinge, arm: [.push], oh: true, spr: 2.0, reps: 6...15, grip: true,
                                  shoulder: true, conflicts: [.overhead], load: 26)))
        add(Movement(id: "db-curl", name: "DB Curls", pattern: .pull, muscles: [.biceps], equipment: [.dumbbell], implement: .dumbbell,
                     defaultWeight: 15, dumbbellPair: true, roles: [.benchmarkOnly], baseReps: 10,
                     metcon: tags([.arms], arm: [.pull], spr: 2.0, reps: 6...15, grip: true, load: 15)))

        // Core (cool-down / accessory, and the core slot of a metcon).
        add(Movement(id: "sit-up", name: "Sit-Ups", pattern: .core, muscles: [.core], roles: [.core, .metabolic], baseReps: 12,
                     metcon: tags([.core], spr: 1.6, reps: 6...20)))
        add(Movement(id: "v-up", name: "V-Ups", pattern: .core, muscles: [.core], roles: [.core, .metabolic], baseReps: 10,
                     metcon: tags([.core], spr: 2.1, reps: 5...15)))
        add(Movement(id: "leg-raise", name: "Leg Raises", pattern: .core, muscles: [.core], roles: [.core, .metabolic], baseReps: 12,
                     metcon: tags([.core], spr: 2.1, reps: 6...15)))
        add(Movement(id: "lemon-squeezer", name: "Lemon Squeezers", pattern: .core, muscles: [.core], roles: [.core, .metabolic], baseReps: 12,
                     metcon: tags([.core], spr: 1.9, reps: 6...15)))
        add(Movement(id: "plank-hold", name: "Plank Hold", pattern: .core, muscles: [.core, .shoulders], jointFlags: [.wrist], roles: [.core, .metabolic],
                     baseReps: 30, timed: true, jointSubstitute: "dead-bug",
                     metcon: tags([.core], spr: 0, reps: 20...60, timedOnly: true)))
        add(Movement(id: "side-plank", name: "Side Plank (each side)", pattern: .core, muscles: [.core], roles: [.core], baseReps: 20, timed: true))
        // Cool-down only, but tagged so the wrist swap for planks keeps the core slot.
        add(Movement(id: "dead-bug", name: "Dead Bugs", pattern: .core, muscles: [.core], roles: [.core], baseReps: 12,
                     metcon: tags([.core], spr: 2.0, reps: 6...15, side: true)))
        add(Movement(id: "hollow-hold", name: "Hollow Hold", pattern: .core, muscles: [.core], roles: [.core, .metabolic], baseReps: 20, timed: true,
                     metcon: tags([.core], spr: 0, reps: 20...60, timedOnly: true)))
        add(Movement(id: "flutter-kick", name: "Flutter Kicks", pattern: .core, muscles: [.core], roles: [.core, .metabolic], baseReps: 20,
                     metcon: tags([.core], spr: 0.5, reps: 10...40, side: true)))
        add(Movement(id: "russian-twist", name: "Russian Twists", pattern: .core, muscles: [.core], roles: [.core, .metabolic], baseReps: 16,
                     metcon: tags([.core], spr: 0.8, reps: 10...30, side: true)))

        // Stretches.
        add(Movement(id: "hip-flexor-stretch", name: "Hip Flexor Stretch", pattern: .mobility, muscles: [.quads, .glutes], roles: [.stretch], baseReps: 45, timed: true))
        add(Movement(id: "couch-stretch", name: "Couch Stretch", pattern: .mobility, muscles: [.quads], roles: [.stretch], baseReps: 45, timed: true))
        add(Movement(id: "pigeon-stretch", name: "Pigeon Stretch", pattern: .mobility, muscles: [.glutes], jointFlags: [.knee], roles: [.stretch],
                     baseReps: 45, timed: true, jointSubstitute: "figure-four-stretch"))
        add(Movement(id: "figure-four-stretch", name: "Figure-Four Stretch", pattern: .mobility, muscles: [.glutes], roles: [.stretch], baseReps: 45, timed: true))
        add(Movement(id: "hamstring-stretch", name: "Hamstring Stretch", pattern: .mobility, muscles: [.hamstrings, .lowerBack], roles: [.stretch], baseReps: 45, timed: true))
        add(Movement(id: "childs-pose", name: "Child's Pose", pattern: .mobility, muscles: [.lowerBack, .lats], roles: [.stretch], baseReps: 45, timed: true))
        add(Movement(id: "thoracic-opener", name: "Thread the Needle", pattern: .mobility, muscles: [.upperBack, .shoulders], roles: [.stretch], baseReps: 30, timed: true))
        add(Movement(id: "doorway-pec-stretch", name: "Doorway Chest Stretch", pattern: .mobility, muscles: [.chest, .shoulders], roles: [.stretch], baseReps: 30, timed: true))
        add(Movement(id: "triceps-stretch", name: "Overhead Triceps Stretch", pattern: .mobility, muscles: [.triceps, .lats], roles: [.stretch], baseReps: 30, timed: true))
        add(Movement(id: "calf-stretch", name: "Calf Stretch", pattern: .mobility, muscles: [.calves], roles: [.stretch], baseReps: 30, timed: true))
        return m
    }()
}
