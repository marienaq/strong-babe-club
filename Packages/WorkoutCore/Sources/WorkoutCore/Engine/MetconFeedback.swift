import Foundation

/// Learns from scores and ratings (spec §22). Everything here is a pure
/// function of history, so plans stay deterministic.
public enum MetconFeedback {
    public static let paceRange = 0.80...1.25
    public static let densityRange = 0.80...1.20

    /// Pace family of a metcon (nil for time-based formats).
    enum Family { case windows, continuous, forTime }

    static func family(_ f: SectionFormat) -> Family? {
        switch f {
        case .amrapWithRest: return .windows
        case .amrap: return .continuous
        case .forTime: return .forTime
        default: return nil
        }
    }

    /// Rounds (with partial reps) the athlete scored per window (AMRAP with
    /// rest) or in total (AMRAP).
    static func actualRounds(_ s: WorkoutSection) -> Double? {
        let logs = s.roundLogs.filter { $0.rounds != nil }
        guard !logs.isEmpty else { return nil }
        let rpr = Double(max(1, s.repsPerRound))
        let total = logs.reduce(0.0) { $0 + Double($1.rounds ?? 0) + Double($1.reps ?? 0) / rpr }
        return s.format == .amrapWithRest ? total / Double(logs.count) : total
    }

    /// Expected score at the default pace, worked out again from the moves
    /// (so the learned multiplier never feeds back into itself).
    static func neutralExpected(_ s: WorkoutSection, library: MovementLibrary) -> Double? {
        switch s.format {
        case .amrap, .amrapWithRest:
            return PaceModel.neutral.expectedRounds(s, library: library)
        case .forTime:
            var work = 0.0
            var rungs = 0
            for item in s.items {
                guard let m = library.movement(for: item), let scheme = item.repsScheme else { return nil }
                let reps = scheme.split(separator: "-").compactMap { Int($0) }
                rungs = max(rungs, reps.count)
                work += Double(reps.reduce(0, +)) * m.secondsPerRep
            }
            guard work > 0 else { return nil }
            return PaceModel.forTimeDefault * work + PaceModel.switchSec * Double(s.items.count * rungs)
        default:
            return nil
        }
    }

    /// One multiplier per family: the median of (expected ÷ actual rounds)
    /// or (actual ÷ expected seconds) over the family's last 8 scored
    /// pieces. Needs 3; outliers (outside 0.5-2.0) are ignored.
    public static func learnedPace(from history: [PlannedWorkout], library: MovementLibrary = .standard) -> PaceModel {
        var ratios: [Family: [Double]] = [:]
        for w in history.sorted(by: { $0.date < $1.date }) where w.status == .done && !w.isDeleted {
            guard let s = w.metabolicSection, s.expectedScore != nil, let fam = family(s.format),
                  let expected = neutralExpected(s, library: library), expected > 0 else { continue }
            let r: Double
            if fam == .forTime {
                let t = s.roundLogs.compactMap(\.timeSec).reduce(0, +)
                guard t > 0 else { continue }
                r = Double(t) / expected
            } else {
                guard let actual = actualRounds(s), actual > 0 else { continue }
                r = expected / actual
            }
            guard (0.5...2.0).contains(r) else { continue }
            ratios[fam, default: []].append(r)
        }
        func multiplier(_ f: Family) -> Double {
            let last = Array((ratios[f] ?? []).suffix(8)).sorted()
            guard last.count >= 3 else { return 1 }
            let mid = last.count / 2
            let median = last.count % 2 == 1 ? last[mid] : (last[mid - 1] + last[mid]) / 2
            return min(max(median, paceRange.lowerBound), paceRange.upperBound)
        }
        return PaceModel(windows: multiplier(.windows), continuous: multiplier(.continuous), forTime: multiplier(.forTime))
    }

    /// Rep density from the last 6 metcon ratings (oldest first): 5 -0.10,
    /// 4 -0.05, 3 back toward 1.0 by 0.05, 2 +0.05, 1 +0.10; then -0.10 more
    /// if recent pieces faded. Clamped to 0.80-1.20.
    public static func density(from history: [PlannedWorkout], library: MovementLibrary = .standard) -> Double {
        let rated = history.sorted { $0.date < $1.date }
            .filter { $0.status == .done && !$0.isDeleted && $0.metabolicSection != nil && $0.feedback?.metabolicDifficulty != nil }
            .suffix(6)
        var d = 1.0
        for w in rated {
            switch w.feedback?.metabolicDifficulty ?? 3 {
            case 5: d -= 0.10
            case 4: d -= 0.05
            case 3: d += d > 1 ? -min(0.05, d - 1) : min(0.05, 1 - d)
            case 2: d += 0.05
            default: d += 0.10
            }
            d = min(max(d, densityRange.lowerBound), densityRange.upperBound)
        }
        if fades(history) { d -= 0.10 }
        return (min(max(d, densityRange.lowerBound), densityRange.upperBound) * 100).rounded() / 100
    }

    /// Score of one round for comparing first and last rounds.
    static func roundScore(_ log: RoundLog, repsPerRound: Int) -> Double? {
        if let r = log.rounds { return Double(r) + Double(log.reps ?? 0) / Double(max(1, repsPerRound)) }
        return log.reps.map(Double.init)
    }

    /// In 2 of the last 3 scored multi-round pieces, the last round scored
    /// under 85% of the first (the athlete usually holds or speeds up).
    public static func fades(_ history: [PlannedWorkout]) -> Bool {
        let multi: Set<SectionFormat> = [.amrapWithRest, .stations, .interval, .tabata]
        let pieces = history.sorted { $0.date < $1.date }.compactMap { w -> (Double, Double)? in
            guard w.status == .done, let s = w.metabolicSection, multi.contains(s.format) else { return nil }
            let logs = s.roundLogs.filter { !$0.isEmpty }.sorted { $0.roundNumber < $1.roundNumber }
            guard logs.count >= 2, let first = logs.first.flatMap({ roundScore($0, repsPerRound: s.repsPerRound) }),
                  let last = logs.last.flatMap({ roundScore($0, repsPerRound: s.repsPerRound) }), first > 0 else { return nil }
            return (first, last)
        }.suffix(3)
        return pieces.filter { $0.1 / $0.0 < 0.85 }.count >= 2
    }

    /// Back after a break of 28+ days: true for the first 14 days back (MC-65).
    public static func isComeback(history: [PlannedWorkout], on date: LocalDate) -> Bool {
        let done = history.filter { $0.status == .done && !$0.isDeleted && $0.date < date }.map(\.date).sorted()
        guard let last = done.last else { return false }
        if last.days(until: date) >= 28 { return true }
        var start: LocalDate?
        for (a, b) in zip(done, done.dropFirst()) where a.days(until: b) >= 28 { start = b }
        guard let start else { return false }
        return start.days(until: date) < 14
    }
}
