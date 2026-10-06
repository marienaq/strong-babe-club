import Foundation

public struct TimerPhase: Hashable, Sendable {
    public enum Kind: String, Sendable { case work, rest }
    public var kind: Kind
    public var duration: Int
    /// 1-based round / set number.
    public var round: Int
}

public struct TimerSnapshot: Hashable, Sendable {
    public var phaseIndex: Int
    public var phase: TimerPhase?
    public var remainingInPhase: Int
    public var elapsedInPhase: Int
    public var totalRemaining: Int
    public var isFinished: Bool
    /// 0...1 progress through the current phase.
    public var phaseProgress: Double
}

/// A sequence of work/rest phases. Pure value logic, driven by elapsed seconds.
public struct IntervalPlan: Hashable, Sendable {
    public let phases: [TimerPhase]

    public init(phases: [TimerPhase]) { self.phases = phases.filter { $0.duration > 0 } }

    /// Strength "every N min" (EMOM style): each set starts on the interval.
    public static func everyInterval(seconds: Int, sets: Int) -> IntervalPlan {
        IntervalPlan(phases: (0..<max(0, sets)).map { TimerPhase(kind: .work, duration: max(1, seconds), round: $0 + 1) })
    }

    /// Metabolic work/rest; no trailing rest after the last round.
    public static func workRest(rounds: Int, work: Int, rest: Int) -> IntervalPlan {
        var p: [TimerPhase] = []
        for r in 1...max(1, rounds) {
            p.append(TimerPhase(kind: .work, duration: max(1, work), round: r))
            if r < rounds && rest > 0 { p.append(TimerPhase(kind: .rest, duration: rest, round: r)) }
        }
        return IntervalPlan(phases: p)
    }

    /// Builds the right timer for a section.
    public static func forSection(_ s: WorkoutSection) -> IntervalPlan? {
        switch s.format {
        case .everyNMin, .emom:
            let sets = s.format == .emom ? s.prescribedRounds : (s.items.map(\.plannedSets.count).max() ?? s.rounds ?? 6)
            return .everyInterval(seconds: s.intervalSec ?? 120, sets: sets)
        case .tabata:
            return .workRest(rounds: s.prescribedRounds, work: s.workSec ?? 20, rest: s.restSec ?? 10)
        case .amrapWithRest, .interval:
            return .workRest(rounds: s.prescribedRounds, work: s.workSec ?? 60, rest: s.restSec ?? 0)
        case .amrap, .forTime:
            return .workRest(rounds: 1, work: (s.durationMin ?? 12) * 60, rest: 0)
        default:
            return nil
        }
    }

    public var totalDuration: Int { phases.reduce(0) { $0 + $1.duration } }

    /// Seconds from start at which each phase begins.
    public var phaseStarts: [Int] {
        var t = 0
        return phases.map { p in defer { t += p.duration }; return t }
    }

    public func snapshot(at elapsed: Int) -> TimerSnapshot {
        let e = max(0, elapsed)
        var t = 0
        for (i, p) in phases.enumerated() {
            if e < t + p.duration {
                let inPhase = e - t
                return TimerSnapshot(phaseIndex: i, phase: p, remainingInPhase: p.duration - inPhase, elapsedInPhase: inPhase,
                                     totalRemaining: totalDuration - e, isFinished: false,
                                     phaseProgress: Double(inPhase) / Double(p.duration))
            }
            t += p.duration
        }
        return TimerSnapshot(phaseIndex: phases.count, phase: nil, remainingInPhase: 0, elapsedInPhase: 0,
                             totalRemaining: 0, isFinished: true, phaseProgress: 1)
    }

    /// Phase indexes that started in (from, to] seconds: used for haptics.
    public func transitions(from: Int, to: Int) -> [Int] {
        guard to > from else { return [] }
        var out = phaseStarts.enumerated().filter { $0.element > from && $0.element <= to }.map(\.offset)
        if from < totalDuration && to >= totalDuration { out.append(phases.count) }
        return out
    }
}

/// What the timer should sound like at a transition.
public enum TimerCue: String, Sendable, CaseIterable {
    /// First work phase starts (or work after rest): "go".
    case workStart = "work"
    /// Bell (round over), then the rest tone.
    case roundEndRest = "bell_rest"
    /// Bell (round over), then straight into the next work round (EMOM).
    case roundEndWork = "bell_work"
    /// Final bell: all rounds done.
    case finished = "finish"

    /// Bundled sound file for a pack (see scripts/make-sounds.py).
    public func soundFile(pack: SoundPack = .boxing) -> String { "\(pack.rawValue)_\(rawValue).wav" }
}

/// Five synthesized timer sound packs.
public enum SoundPack: String, Codable, Sendable, CaseIterable {
    case boxing, arcade, chimes, cowbell, marimba

    public var displayName: String {
        switch self {
        case .boxing: return "Boxing gym"
        case .arcade: return "Arcade"
        case .chimes: return "Wind chimes"
        case .cowbell: return "Cowbell"
        case .marimba: return "Soft marimba"
        }
    }
}

extension IntervalPlan {
    /// Cue for entering phase `index` (`phases.count` = finished).
    public func cue(enteringPhase index: Int) -> TimerCue? {
        guard index >= 0 else { return nil }
        if index >= phases.count { return phases.isEmpty ? nil : .finished }
        let p = phases[index]
        guard index > 0 else { return p.kind == .work ? .workStart : nil }
        let prev = phases[index - 1]
        switch (prev.kind, p.kind) {
        case (.work, .rest): return .roundEndRest
        case (.work, .work): return .roundEndWork
        case (.rest, .work): return .workStart
        case (.rest, .rest): return nil
        }
    }
}

/// Start / pause / reset bookkeeping, independent of any UI timer.
public struct TimerClock: Hashable, Sendable {
    public private(set) var startedAt: Date?
    public private(set) var accumulated: TimeInterval = 0

    public init() {}

    public var isRunning: Bool { startedAt != nil }

    public mutating func start(at now: Date) {
        guard startedAt == nil else { return }
        startedAt = now
    }

    public mutating func pause(at now: Date) {
        guard let s = startedAt else { return }
        accumulated += max(0, now.timeIntervalSince(s))
        startedAt = nil
    }

    public mutating func reset() {
        startedAt = nil
        accumulated = 0
    }

    public func elapsed(at now: Date) -> TimeInterval {
        accumulated + (startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    /// Wall-clock dates of upcoming phase changes (for local notifications).
    public func upcomingTransitions(_ plan: IntervalPlan, now: Date) -> [(phaseIndex: Int, date: Date)] {
        guard isRunning else { return [] }
        let e = elapsed(at: now)
        var out: [(Int, Date)] = []
        for (i, start) in plan.phaseStarts.enumerated() where Double(start) > e {
            out.append((i, now.addingTimeInterval(Double(start) - e)))
        }
        if Double(plan.totalDuration) > e { out.append((plan.phases.count, now.addingTimeInterval(Double(plan.totalDuration) - e))) }
        return out
    }
}

/// "2:41"
public func formatClock(_ seconds: Int) -> String {
    let s = max(0, seconds)
    return String(format: "%d:%02d", s / 60, s % 60)
}
