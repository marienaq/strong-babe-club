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

    public init(id: String, name: String, pattern: MovementPattern, muscles: [Muscle], equipment: [Equipment] = [.bodyweight],
                implement: Implement = .bodyweight, highImpact: Bool = false, jointFlags: [Joint] = [], defaultWeight: Double? = nil,
                kettlebellAlternative: Bool = false, dumbbellPair: Bool = false, roles: [MovementRole], primes: [LiftSlot] = [],
                baseReps: Int = 10, timed: Bool = false, noJumpSubstitute: String? = nil, jointSubstitute: String? = nil) {
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

    public init(_ movements: [Movement] = MovementLibrary.seed) {
        self.movements = movements
        var d: [String: Movement] = [:]
        for m in movements { d[m.id] = m }
        self.byID = d
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

    /// Finds a library movement by display name (case-insensitive) or slug.
    public func lookup(name: String) -> Movement? {
        let s = MovementLibrary.slug(name)
        if let m = byID[s] { return m }
        return movements.first { MovementLibrary.slug($0.name) == s }
    }
}

extension MovementLibrary {
    // swiftlint:disable function_body_length
    public static let seed: [Movement] = {
        var m: [Movement] = []
        func add(_ x: Movement) { m.append(x) }

        // The six fixed lifts.
        for lift in Lift.allCases {
            add(Movement(id: lift.movementID, name: lift.displayName, pattern: lift.pattern, muscles: Array(lift.primaryMuscles).sorted(),
                         equipment: [.barbell], implement: .barbell, jointFlags: Array(lift.jointStress).sorted { $0.rawValue < $1.rawValue },
                         roles: [.mainLift], baseReps: 5))
        }

        // Heart-rate raisers (warm-up A) and conditioning.
        add(Movement(id: "jumping-jack", name: "Jumping Jacks", pattern: .cardio, muscles: [.calves, .shoulders], highImpact: true,
                     roles: [.warmupCardio, .metabolic], baseReps: 25, noJumpSubstitute: "toe-tap"))
        add(Movement(id: "toe-tap", name: "Toe Taps", pattern: .cardio, muscles: [.calves, .quads], roles: [.warmupCardio, .metabolic], baseReps: 20))
        add(Movement(id: "burpee", name: "Burpees", pattern: .cardio, muscles: [.chest, .quads, .shoulders], highImpact: true, jointFlags: [.wrist],
                     roles: [.warmupCardio, .metabolic], baseReps: 6, noJumpSubstitute: "up-down", jointSubstitute: "squat-thrust-hold"))
        add(Movement(id: "up-down", name: "Up/Downs", pattern: .cardio, muscles: [.chest, .quads], jointFlags: [.wrist],
                     roles: [.warmupCardio, .metabolic], baseReps: 6, jointSubstitute: "squat-thrust-hold"))
        add(Movement(id: "squat-thrust-hold", name: "Squat to Stand", pattern: .squat, muscles: [.quads, .hamstrings],
                     roles: [.warmupCardio, .metabolic], baseReps: 8))
        add(Movement(id: "high-knees", name: "High Knees", pattern: .cardio, muscles: [.quads, .calves, .core], highImpact: true,
                     roles: [.warmupCardio], baseReps: 30, noJumpSubstitute: "marching-knees"))
        add(Movement(id: "marching-knees", name: "Marching Knee Drives", pattern: .cardio, muscles: [.quads, .core],
                     roles: [.warmupCardio], baseReps: 30))
        add(Movement(id: "mountain-climber", name: "Mountain Climbers", pattern: .cardio, muscles: [.core, .shoulders], jointFlags: [.wrist],
                     roles: [.warmupCardio, .metabolic], baseReps: 20, jointSubstitute: "marching-knees"))
        add(Movement(id: "bike-cal", name: "Bike Calories", pattern: .cardio, muscles: [.quads], equipment: [.bike], implement: .bike,
                     roles: [.metabolic], baseReps: 10))

        // Squat primers / leg work.
        add(Movement(id: "air-squat", name: "Air Squats", pattern: .squat, muscles: [.quads, .glutes], roles: [.warmupPrimer, .metabolic],
                     primes: [.squat], baseReps: 10))
        add(Movement(id: "goblet-squat", name: "KB Goblet Squats", pattern: .squat, muscles: [.quads, .glutes, .core], equipment: [.kettlebell],
                     implement: .kettlebell, jointFlags: [.knee], defaultWeight: 26, roles: [.warmupPrimer, .metabolic], primes: [.squat],
                     baseReps: 10, jointSubstitute: "glute-bridge"))
        add(Movement(id: "lunge", name: "Alternating Lunges", pattern: .lunge, muscles: [.quads, .glutes], jointFlags: [.knee],
                     roles: [.warmupPrimer, .metabolic], primes: [.squat], baseReps: 10, jointSubstitute: "glute-bridge"))
        add(Movement(id: "db-reverse-lunge", name: "DB Reverse Lunges", pattern: .lunge, muscles: [.quads, .glutes], equipment: [.dumbbell],
                     implement: .dumbbell, jointFlags: [.knee], defaultWeight: 15, dumbbellPair: true, roles: [.metabolic], baseReps: 10,
                     jointSubstitute: "db-glute-bridge"))
        add(Movement(id: "bench-step-up", name: "Bench Step-Ups", pattern: .lunge, muscles: [.quads, .glutes], equipment: [.bench],
                     implement: .bench, jointFlags: [.knee], roles: [.warmupPrimer, .metabolic], primes: [.squat], baseReps: 10,
                     jointSubstitute: "glute-bridge"))
        add(Movement(id: "box-step-up", name: "Box Step-Ups", pattern: .lunge, muscles: [.quads, .glutes], equipment: [.box],
                     implement: .box, jointFlags: [.knee], roles: [.metabolic], baseReps: 10, jointSubstitute: "glute-bridge"))
        add(Movement(id: "box-jump", name: "Box Jumps", pattern: .squat, muscles: [.quads, .glutes, .calves], equipment: [.box],
                     implement: .box, highImpact: true, jointFlags: [.knee], roles: [.metabolic], baseReps: 6,
                     noJumpSubstitute: "box-step-up", jointSubstitute: "box-step-up"))
        add(Movement(id: "glute-bridge", name: "Glute Bridges", pattern: .hinge, muscles: [.glutes, .hamstrings],
                     roles: [.warmupPrimer, .metabolic], primes: [.squat, .hipPull], baseReps: 12))
        add(Movement(id: "db-glute-bridge", name: "DB Glute Bridges", pattern: .hinge, muscles: [.glutes, .hamstrings], equipment: [.dumbbell],
                     implement: .dumbbell, defaultWeight: 20, roles: [.metabolic], baseReps: 12))
        add(Movement(id: "cossack-squat", name: "Cossack Squats", pattern: .squat, muscles: [.quads, .glutes], jointFlags: [.knee],
                     roles: [.warmupPrimer], primes: [.squat], baseReps: 6, jointSubstitute: "glute-bridge"))

        // Hinge / pull primers.
        add(Movement(id: "good-morning", name: "Good Mornings", pattern: .hinge, muscles: [.hamstrings, .lowerBack], roles: [.warmupPrimer],
                     primes: [.hipPull], baseReps: 10))
        add(Movement(id: "db-rdl", name: "DB Romanian Deadlifts", pattern: .hinge, muscles: [.hamstrings, .glutes, .lowerBack],
                     equipment: [.dumbbell], implement: .dumbbell, defaultWeight: 20, dumbbellPair: true, roles: [.warmupPrimer, .metabolic],
                     primes: [.hipPull], baseReps: 8))
        add(Movement(id: "kb-deadlift", name: "KB Deadlifts", pattern: .hinge, muscles: [.hamstrings, .glutes], equipment: [.kettlebell],
                     implement: .kettlebell, defaultWeight: 35, roles: [.warmupPrimer, .metabolic], primes: [.hipPull], baseReps: 10))
        add(Movement(id: "inchworm", name: "Inchworms", pattern: .mobility, muscles: [.hamstrings, .shoulders, .core], jointFlags: [.wrist],
                     roles: [.warmupPrimer], primes: [.hipPull, .overhead], baseReps: 5, jointSubstitute: "good-morning"))
        add(Movement(id: "kb-swing", name: "KB Swings", pattern: .hinge, muscles: [.hamstrings, .glutes, .shoulders], equipment: [.kettlebell],
                     implement: .kettlebell, defaultWeight: 26, roles: [.warmupPrimer, .metabolic], primes: [.hipPull], baseReps: 12))
        add(Movement(id: "db-hang-squat-clean", name: "DB Hang Squat Cleans", pattern: .squat, muscles: [.quads, .glutes, .upperBack],
                     equipment: [.dumbbell], implement: .dumbbell, jointFlags: [.wrist], defaultWeight: 20, dumbbellPair: true,
                     roles: [.metabolic], baseReps: 6, jointSubstitute: "kb-deadlift"))
        add(Movement(id: "db-snatch", name: "Alternating DB Snatches", pattern: .hinge, muscles: [.hamstrings, .glutes, .shoulders],
                     equipment: [.dumbbell], implement: .dumbbell, defaultWeight: 20, kettlebellAlternative: true, roles: [.metabolic], baseReps: 10))
        add(Movement(id: "kb-high-pull", name: "KB Sumo Deadlift High Pulls", pattern: .pull, muscles: [.upperBack, .glutes, .shoulders],
                     equipment: [.kettlebell], implement: .kettlebell, defaultWeight: 26, roles: [.metabolic], baseReps: 10))
        add(Movement(id: "db-row", name: "Bench DB Rows", pattern: .pull, muscles: [.lats, .upperBack, .biceps], equipment: [.dumbbell, .bench],
                     implement: .dumbbell, defaultWeight: 20, roles: [.warmupPrimer, .metabolic], primes: [.hipPull], baseReps: 10))
        add(Movement(id: "australian-pull-up", name: "Australian Pull-Ups", pattern: .pull, muscles: [.lats, .upperBack, .biceps],
                     equipment: [.lowBar], roles: [.warmupPrimer, .metabolic], primes: [.hipPull, .overhead], baseReps: 6))

        // Press primers / upper body.
        add(Movement(id: "push-up", name: "Push-Ups", pattern: .press, muscles: [.chest, .triceps, .shoulders], jointFlags: [.wrist],
                     roles: [.warmupPrimer, .metabolic], primes: [.overhead], baseReps: 6, jointSubstitute: "db-floor-press"))
        add(Movement(id: "db-floor-press", name: "DB Floor Press", pattern: .press, muscles: [.chest, .triceps], equipment: [.dumbbell],
                     implement: .dumbbell, defaultWeight: 20, dumbbellPair: true, roles: [.metabolic], baseReps: 10))
        add(Movement(id: "inchworm-shoulder-tap", name: "Inchworm Shoulder Taps", pattern: .press, muscles: [.shoulders, .core],
                     jointFlags: [.wrist], roles: [.warmupPrimer], primes: [.overhead], baseReps: 4, jointSubstitute: "arm-circle"))
        add(Movement(id: "arm-circle", name: "Arm Circles", pattern: .mobility, muscles: [.shoulders], roles: [.warmupPrimer],
                     primes: [.overhead], baseReps: 10))
        add(Movement(id: "plate-ground-to-overhead", name: "Plate Ground to Overhead", pattern: .press, muscles: [.shoulders, .glutes, .core],
                     equipment: [.barbell], implement: .barbell, defaultWeight: 10, roles: [.warmupPrimer, .metabolic],
                     primes: [.overhead, .hipPull], baseReps: 8))
        add(Movement(id: "db-strict-press", name: "DB Strict Press", pattern: .press, muscles: [.shoulders, .triceps], equipment: [.dumbbell],
                     implement: .dumbbell, defaultWeight: 10, dumbbellPair: true, roles: [.warmupPrimer], primes: [.overhead], baseReps: 8))
        add(Movement(id: "db-push-press", name: "DB Push Press", pattern: .press, muscles: [.shoulders, .triceps, .quads], equipment: [.dumbbell],
                     implement: .dumbbell, defaultWeight: 20, dumbbellPair: true, roles: [.metabolic], baseReps: 8))
        add(Movement(id: "db-thruster", name: "DB Thrusters", pattern: .squat, muscles: [.quads, .glutes, .shoulders], equipment: [.dumbbell],
                     implement: .dumbbell, defaultWeight: 15, dumbbellPair: true, roles: [.metabolic], baseReps: 8))
        add(Movement(id: "db-bench-press", name: "DB Bench Press", pattern: .press, muscles: [.chest, .triceps], equipment: [.dumbbell, .bench],
                     implement: .dumbbell, defaultWeight: 20, dumbbellPair: true, roles: [.metabolic], baseReps: 10))
        add(Movement(id: "tricep-dip", name: "Bench Tricep Dips", pattern: .press, muscles: [.triceps], equipment: [.bench], implement: .bench,
                     jointFlags: [.wrist], roles: [.metabolic], baseReps: 10, jointSubstitute: "db-floor-press"))
        add(Movement(id: "wall-walk", name: "Wall Walks", pattern: .press, muscles: [.shoulders, .core], jointFlags: [.wrist],
                     roles: [.metabolic], baseReps: 3, jointSubstitute: "db-strict-press"))
        add(Movement(id: "med-ball-slam", name: "Med Ball Slams", pattern: .hinge, muscles: [.core, .shoulders, .lats], equipment: [.medicineBall],
                     implement: .medicineBall, defaultWeight: 12, roles: [.metabolic], baseReps: 10))
        add(Movement(id: "bear-crawl", name: "Bear Crawl Steps", pattern: .carry, muscles: [.core, .shoulders], jointFlags: [.wrist],
                     roles: [.metabolic], baseReps: 10, jointSubstitute: "marching-knees"))
        add(Movement(id: "kb-farmer-carry", name: "KB Suitcase March", pattern: .carry, muscles: [.core, .upperBack], equipment: [.kettlebell],
                     implement: .kettlebell, defaultWeight: 35, roles: [.metabolic], baseReps: 20))

        // Core (cool-down / accessory).
        add(Movement(id: "sit-up", name: "Sit-Ups", pattern: .core, muscles: [.core], roles: [.core, .metabolic], baseReps: 12))
        add(Movement(id: "v-up", name: "V-Ups", pattern: .core, muscles: [.core], roles: [.core, .metabolic], baseReps: 10))
        add(Movement(id: "leg-raise", name: "Leg Raises", pattern: .core, muscles: [.core], roles: [.core], baseReps: 12))
        add(Movement(id: "lemon-squeezer", name: "Lemon Squeezers", pattern: .core, muscles: [.core], roles: [.core], baseReps: 12))
        add(Movement(id: "plank-hold", name: "Plank Hold", pattern: .core, muscles: [.core, .shoulders], jointFlags: [.wrist], roles: [.core],
                     baseReps: 30, timed: true, jointSubstitute: "dead-bug"))
        add(Movement(id: "side-plank", name: "Side Plank (each side)", pattern: .core, muscles: [.core], roles: [.core], baseReps: 20, timed: true))
        add(Movement(id: "dead-bug", name: "Dead Bugs", pattern: .core, muscles: [.core], roles: [.core], baseReps: 12))
        add(Movement(id: "hollow-hold", name: "Hollow Hold", pattern: .core, muscles: [.core], roles: [.core], baseReps: 20, timed: true))
        add(Movement(id: "flutter-kick", name: "Flutter Kicks", pattern: .core, muscles: [.core], roles: [.core], baseReps: 20))
        add(Movement(id: "russian-twist", name: "Russian Twists", pattern: .core, muscles: [.core], roles: [.core], baseReps: 16))

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
