import Foundation

/// "Does this look like the coach's?" A penalty score for one metcon (spec
/// §20). The coach's own metcons score 0 at the median and ≤ 2.0 in 94% of
/// cases, so 2.0 is the "looks like the coach" threshold.
public enum MetconQuality {
    public static let threshold = 2.0

    public struct Feature: Hashable, Sendable {
        public var name: String
        public var penalty: Double
    }

    public struct Score: Hashable, Sendable {
        public var penalty: Double
        public var features: [Feature]
        /// The feature that costs the most (for "Why this?").
        public var top: Feature? { features.filter { $0.penalty > 0 }.max { $0.penalty < $1.penalty } }
    }

    /// weight × min(2, distance outside the OK range ÷ distance from the OK
    /// edge to where the penalty reaches the weight).
    static func penalty(_ value: Double, ok: ClosedRange<Double>, low: Double? = nil, high: Double? = nil, weight: Double) -> Double {
        if value < ok.lowerBound, let low, ok.lowerBound > low {
            return weight * min(2, (ok.lowerBound - value) / (ok.lowerBound - low))
        }
        if value > ok.upperBound, let high, high > ok.upperBound {
            return weight * min(2, (value - ok.upperBound) / (high - ok.upperBound))
        }
        return 0
    }

    /// Scores a metcon section. `weekMoveIDs` are moves in the week's other metcons.
    public static func score(_ s: WorkoutSection, library: MovementLibrary = .standard, pace: PaceModel = .neutral,
                             weekMoveIDs: Set<String> = []) -> Score {
        let moves = s.items.map { library.movement(for: $0) }
        let known = moves.compactMap { $0 }
        var f: [Feature] = []
        func add(_ name: String, _ p: Double) { f.append(Feature(name: name, penalty: p)) }

        let n = s.items.count
        let wraps = s.format != .forTime
        func adjacentPairs(_ flag: (Movement) -> Bool) -> Int {
            guard n > 1 else { return 0 }
            var pairs = 0
            for i in 0..<n {
                let j = i + 1
                if j == n && (!wraps || n < 3) { break }
                if let a = moves[i], let b = moves[j % n], flag(a), flag(b) { pairs += 1 }
            }
            return pairs
        }

        add("two jumping moves", penalty(Double(known.filter(\.highImpact).count), ok: 0...1, high: 2, weight: 2))
        add("several technical moves", penalty(Double(known.filter { $0.technical || $0.isBarbellLift }.count), ok: 0...1, high: 3, weight: 1))
        add("a lot of grip work", penalty(Double(known.filter(\.gripHeavy).count), ok: 0...2, high: 3, weight: 1))
        add("grip moves back to back", penalty(Double(adjacentPairs(\.gripHeavy)), ok: 0...0, high: 2, weight: 1))
        add("a lot of shoulder work", penalty(Double(known.filter(\.shoulderHeavy).count), ok: 0...1, high: 2, weight: 1.5))
        add("shoulder moves back to back", penalty(Double(adjacentPairs(\.shoulderHeavy)), ok: 0...0, high: 1, weight: 2))
        add("long rests", penalty(MetconCatalog.density(s), ok: 0.67...1, low: 0.5, weight: 1))

        let repFormats: Set<SectionFormat> = [.amrap, .amrapWithRest, .emom]
        if repFormats.contains(s.format), s.items.allSatisfy({ $0.reps != nil }) {
            let reps = Double(s.items.compactMap(\.reps).reduce(0, +))
            add(reps < 12 ? "very few reps per round" : "a lot of reps per round", penalty(reps, ok: 12...40, low: 8, high: 50, weight: 1))
        }
        if s.format == .amrap || s.format == .amrapWithRest, s.items.allSatisfy({ $0.reps != nil }) {
            let fresh = PaceModel.freshRoundSec(s.items, library: library)
            let largest = zip(s.items, moves).map { Double($0.reps ?? 0) * ($1?.secondsPerRep ?? 2) }.max() ?? 0
            if fresh > 0 { add("one move takes most of the round", penalty(largest / fresh, ok: 0...0.45, high: 0.55, weight: 1)) }
            let rounds = pace.expectedRounds(s, library: library) ?? 0
            if s.format == .amrapWithRest {
                add(fresh < 39 ? "very short rounds" : "long rounds", penalty(fresh, ok: 39...60, low: 30, high: 75, weight: 1.5))
                add(rounds < 3 ? "few rounds per block" : "many rounds per block", penalty(rounds, ok: 3...6.5, low: 2, high: 8, weight: 1.5))
            } else {
                add(fresh < 56 ? "very short rounds" : "long rounds", penalty(fresh, ok: 56...102, low: 45, high: 120, weight: 1.5))
                add(rounds < 7.5 ? "few rounds" : "many rounds", penalty(rounds, ok: 7.5...13.5, low: 5, high: 16, weight: 1.5))
            }
        }
        let repeats = Set(known.map(\.id)).intersection(weekMoveIDs).count
        add("moves repeated from earlier this week", 0.5 * Double(repeats))
        return Score(penalty: f.reduce(0) { $0 + $1.penalty }, features: f)
    }
}
