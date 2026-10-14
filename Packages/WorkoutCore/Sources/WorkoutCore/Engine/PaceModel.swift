import Foundation

/// How fast the athlete moves through a metcon (spec §17). Fresh pace is
/// the calibrated seconds per rep; longer pieces run slower than fresh.
/// The three multipliers are learned from scores (§22.1) and start at 1.
public struct PaceModel: Hashable, Sendable {
    /// AMRAP-with-rest windows.
    public var windows: Double
    /// One continuous AMRAP.
    public var continuous: Double
    /// For-time pieces.
    public var forTime: Double

    public init(windows: Double = 1, continuous: Double = 1, forTime: Double = 1) {
        self.windows = windows
        self.continuous = continuous
        self.forTime = forTime
    }

    public static let neutral = PaceModel()

    /// Seconds to switch from one move to the next.
    public static let switchSec = 5.0
    /// Default for-time pace (fresh × 1.35).
    public static let forTimeDefault = 1.35

    // MARK: Default factors and coach targets (§17.3)

    /// Window pace relative to fresh: 2-min windows run a bit faster, 4-6-min a bit slower.
    public static func windowFactor(workSec: Int) -> Double {
        switch workSec {
        case ..<150: return 0.9
        case ..<210: return 1.0
        default: return 1.1
        }
    }

    /// The coach's median rounds per window.
    public static func targetRounds(workSec: Int) -> Double {
        switch (workSec + 30) / 60 {
        case ...2: return 3.6
        case 3: return 3.7
        case 4: return 4.4
        case 5: return 5.2
        default: return 6.0
        }
    }

    /// Continuous AMRAPs slow down the longer they run (12 min 1.18, 20 min 1.30).
    public static func continuousFactor(minutes: Int) -> Double { 1 + 0.015 * Double(minutes) }

    /// The coach's median rounds for a continuous AMRAP of this length.
    public static func continuousTargetRounds(minutes: Int) -> Double {
        switch minutes {
        case ...14: return 9.2
        case 15...16: return 10.5
        case 17...18: return 10.6
        default: return 11.0
        }
    }

    public var forTimeFactor: Double { PaceModel.forTimeDefault * forTime }

    /// Pace factor for an AMRAP section (default × learned), or nil.
    public func factor(_ s: WorkoutSection) -> Double? {
        switch s.format {
        case .amrapWithRest: return PaceModel.windowFactor(workSec: s.workSec ?? 240) * windows
        case .amrap: return PaceModel.continuousFactor(minutes: s.durationMin ?? 12) * continuous
        case .emom: return 1
        case .forTime: return forTimeFactor
        default: return nil
        }
    }

    /// Seconds one window (or the whole AMRAP) lasts.
    static func windowSec(_ s: WorkoutSection) -> Double? {
        switch s.format {
        case .amrapWithRest: return Double(s.workSec ?? 240)
        case .amrap: return Double((s.durationMin ?? 12) * 60)
        default: return nil
        }
    }

    /// Fresh round seconds to aim for, so the athlete gets the coach's
    /// usual number of rounds (clamped to the coach's p5-p95).
    public func targetFreshRoundSec(_ s: WorkoutSection) -> Double? {
        guard let window = PaceModel.windowSec(s), let f = factor(s) else { return nil }
        if s.format == .amrapWithRest {
            let t = window / (PaceModel.targetRounds(workSec: s.workSec ?? 240) * f)
            return min(max(t, 35), 60)
        }
        let t = window / (PaceModel.continuousTargetRounds(minutes: s.durationMin ?? 12) * f)
        return min(max(t, 55), 105)
    }

    /// Fresh seconds for one round of these items (reps × s/rep + switches).
    public static func freshRoundSec(_ items: [SectionItem], library: MovementLibrary) -> Double {
        var t = 0.0
        for item in items {
            let spr = library.movement(for: item)?.secondsPerRep ?? 2
            t += Double(item.reps ?? 0) * spr + switchSec
        }
        return t
    }

    /// Expected rounds per window (AMRAP with rest) or in total (AMRAP).
    public func expectedRounds(_ s: WorkoutSection, library: MovementLibrary) -> Double? {
        guard let window = PaceModel.windowSec(s), let f = factor(s) else { return nil }
        let fresh = PaceModel.freshRoundSec(s.items, library: library)
        guard fresh > 0 else { return nil }
        return window / (fresh * f)
    }

    /// For time: rep multiplier per move (fast moves get 2-3× the scheme).
    public static func forTimeMultiplier(secondsPerRep spr: Double) -> Int {
        spr <= 0.6 ? 3 : spr <= 1.0 ? 2 : 1
    }

    /// For time: expected finish seconds E.
    public func forTimeSeconds(scheme: [Int], moves: [Movement]) -> Double {
        let total = Double(scheme.reduce(0, +))
        let work = moves.reduce(0.0) { $0 + total * Double(PaceModel.forTimeMultiplier(secondsPerRep: $1.secondsPerRep)) * $1.secondsPerRep }
        return forTimeFactor * work + PaceModel.switchSec * Double(moves.count * scheme.count)
    }
}
