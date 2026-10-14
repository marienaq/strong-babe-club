import Foundation

/// Metcon length bands (spec §3), by estimated seconds.
public enum MetconBand: String, Codable, Sendable, CaseIterable, Comparable {
    /// 12:00-16:59
    case short
    /// 17:00-20:59
    case middle
    /// 21:00-24:00
    case long

    public var range: ClosedRange<Int> {
        switch self {
        case .short: return 720...1019
        case .middle: return 1020...1259
        case .long: return 1260...1440
        }
    }

    public static func of(seconds: Int) -> MetconBand {
        if seconds < 1020 { return .short }
        if seconds < 1260 { return .middle }
        return .long
    }

    public static func < (a: MetconBand, b: MetconBand) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

/// One concrete catalog entry: format + rounds + work/rest + move count
/// (spec §5.3). The planner never invents shapes outside the catalog.
public struct MetconShape: Hashable, Sendable, Identifiable {
    public var id: String
    public var format: SectionFormat
    /// Blocks (AMRAP with rest), rounds (stations), circuits (interval),
    /// rounds per move (Tabata), cycles (EMOM). 1 for AMRAP and for time.
    public var rounds: Int
    /// Fixed move count (EMOM, stations, interval, Tabata). Nil = 3-5 by choice.
    public var moves: Int?
    public var workSec: Int?
    public var restSec: Int?
    public var roundRestSec: Int?
    /// AMRAP length, or EMOM minutes.
    public var minutes: Int?
    /// For time: the base rep scheme ("10-9-...-1").
    public var scheme: [Int]?
    /// Pick weight among shapes of the same format (for-time scheme preference).
    public var weight: Double

    public init(id: String, format: SectionFormat, rounds: Int = 1, moves: Int? = nil, workSec: Int? = nil, restSec: Int? = nil,
                roundRestSec: Int? = nil, minutes: Int? = nil, scheme: [Int]? = nil, weight: Double = 1) {
        self.id = id
        self.format = format
        self.rounds = rounds
        self.moves = moves
        self.workSec = workSec
        self.restSec = restSec
        self.roundRestSec = roundRestSec
        self.minutes = minutes
        self.scheme = scheme
        self.weight = weight
    }

    public var stimulus: MetconStimulus { MetconStimulus(format: format)! }

    /// Move counts this shape allows.
    public var moveCounts: [Int] {
        if let moves { return [moves] }
        switch format {
        case .amrap: return (minutes ?? 12) >= 15 ? [3, 4, 5] : [3, 4]
        case .amrapWithRest: return (workSec ?? 0) >= 240 ? [3, 4, 5] : [3, 4]
        default: return [3, 4, 5]
        }
    }

    /// A metcon section skeleton for this shape (no items yet).
    public func section(capMinutes: Int? = nil) -> WorkoutSection {
        WorkoutSection(kind: .metabolic, format: format, instructions: "", rounds: rounds, workSec: workSec, restSec: restSec,
                       intervalSec: format == .emom ? 60 : nil, durationMin: format == .forTime ? capMinutes : minutes,
                       roundRestSec: roundRestSec, stimulus: stimulus)
    }

    /// Estimated seconds with `n` moves (for time: nil, it depends on the cap).
    public func seconds(moves n: Int) -> Int? {
        guard format != .forTime else { return nil }
        if let cached = MetconCatalog.secondsTable[id]?[n] { return cached }
        return computeSeconds(moves: n)
    }

    func computeSeconds(moves n: Int) -> Int {
        var s = section()
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        s.items = (0..<n).map { SectionItem(id: zero, letter: "ABCDE".map(String.init)[min($0, 4)], movementID: "m\($0)", movementName: "M\($0)") }
        return WorkoutDuration.estimateSeconds(s)
    }

    /// Seconds for each allowed move count (empty for for-time).
    public var allSeconds: [Int] { moveCounts.compactMap { seconds(moves: $0) } }

    public var schemeText: String? { scheme?.map(String.init).joined(separator: "-") }
}

/// Shapes, weights, copy and names for planner-built metcons.
public enum MetconCatalog {
    /// Hard rule: every metcon is 12-24 minutes.
    public static let lengthRange = 720...1440
    /// For-time caps run 15-24 minutes (E is 12-20 min, cap = 1.2 × E).
    public static let forTimeCaps = 15...24

    public static let shapes: [MetconShape] = {
        var out: [MetconShape] = []
        for d in [12, 14, 15, 16, 18, 20] {
            out.append(MetconShape(id: "amrap-\(d)", format: .amrap, minutes: d))
        }
        for (n, c) in [(3, 4), (4, 3), (3, 5), (5, 3), (4, 4), (3, 6), (4, 5), (5, 4)] {
            out.append(MetconShape(id: "emom-\(n)x\(c)", format: .emom, rounds: n * c, moves: n, minutes: n * c))
        }
        for (r, w, x) in [(3, 4, 60), (4, 3, 60), (3, 5, 60), (5, 3, 60), (4, 4, 60), (8, 2, 30), (3, 6, 60), (6, 3, 60), (4, 5, 60), (5, 4, 60)] {
            out.append(MetconShape(id: "rest-\(r)x\(w)", format: .amrapWithRest, rounds: r, workSec: w * 60, restSec: x))
        }
        for (r, n) in [(3, 4), (4, 3), (3, 5), (5, 3), (4, 4), (6, 3), (4, 5), (5, 4)] {
            out.append(MetconShape(id: "stations-\(r)x\(n)", format: .stations, rounds: r, moves: n, workSec: 60, restSec: 0, roundRestSec: 60))
        }
        // 45/15 is left out: its work density (0.76) is above the interval limit of 0.75 (§18.2).
        for (n, c) in [(3, 5), (5, 3), (4, 4), (3, 6), (4, 5), (5, 4), (3, 7), (4, 6), (3, 8)] {
            for (w, x) in [(30, 30), (40, 20)] {
                out.append(MetconShape(id: "interval-\(n)x\(c)-\(w)-\(x)", format: .interval, rounds: c, moves: n, workSec: w, restSec: x))
            }
        }
        // Tabata (owner decision Q2): 40/20, one move at a time, the 20 s
        // rest is the change-over. 3 × 4 (700 s) is under 12 min, so it's out.
        for (n, r) in [(3, 5), (4, 4), (3, 6), (4, 5), (5, 4), (3, 7), (4, 6)] {
            out.append(MetconShape(id: "tabata-\(n)x\(r)", format: .tabata, rounds: r, moves: n, workSec: 40, restSec: 20, roundRestSec: 0))
        }
        let schemes: [(String, [Int], Double)] = [
            ("ft-21-15-9", [21, 15, 9], 1), ("ft-15-3", [15, 12, 9, 6, 3], 1), ("ft-10-2", [10, 8, 6, 4, 2], 1),
            ("ft-10-1", Array((1...10).reversed()), 3), ("ft-1-10", Array(1...10), 3), ("ft-21-3", [21, 18, 15, 12, 9, 6, 3], 1),
        ]
        for (id, scheme, weight) in schemes {
            out.append(MetconShape(id: id, format: .forTime, scheme: scheme, weight: weight))
        }
        return out
    }()

    static let byFormat: [SectionFormat: [MetconShape]] = Dictionary(grouping: shapes, by: \.format)

    public static func shapes(_ format: SectionFormat) -> [MetconShape] { byFormat[format] ?? [] }

    /// Shape id -> move count -> seconds (worked out once).
    static let secondsTable: [String: [Int: Int]] = {
        var t: [String: [Int: Int]] = [:]
        for s in shapes where s.format != .forTime {
            t[s.id] = Dictionary(uniqueKeysWithValues: s.moveCounts.map { ($0, s.computeSeconds(moves: $0)) })
        }
        return t
    }()

    /// Planner metcon formats.
    public static let formats: [SectionFormat] = [.amrap, .emom, .amrapWithRest, .stations, .interval, .tabata, .forTime]

    /// Pick weights (sum 100), close to the coach's mix with Tabata added (§6.1).
    public static let formatWeights: [SectionFormat: Double] = [
        .amrap: 17, .emom: 3, .amrapWithRest: 30, .stations: 15, .interval: 10, .tabata: 8, .forTime: 17,
    ]

    public static let stimulusWeights: [MetconStimulus: Double] = [.grind: 20, .repeat: 45, .race: 17, .intervals: 18]

    /// True if the format has at least one shape whose length is in `window`.
    public static func hasShape(_ format: SectionFormat, in window: ClosedRange<Int>) -> Bool {
        if format == .forTime { return forTimeCaps.contains { window.contains($0 * 60) } }
        return shapes(format).contains { $0.allSeconds.contains(where: window.contains) }
    }

    /// Seconds of work (not rest) in a section, for the density rules (§18.2).
    public static func workSeconds(_ s: WorkoutSection) -> Int {
        let n = max(1, s.items.count), r = max(1, s.rounds ?? 1)
        switch s.format {
        case .amrapWithRest: return r * (s.workSec ?? 240)
        case .stations: return r * n * (s.workSec ?? 60)
        case .interval, .tabata: return r * n * (s.workSec ?? 40)
        default: return WorkoutDuration.estimateSeconds(s)
        }
    }

    public static func density(_ s: WorkoutSection) -> Double {
        let total = WorkoutDuration.estimateSeconds(s)
        return total > 0 ? Double(workSeconds(s)) / Double(total) : 1
    }

    /// "1 min" / "30 s".
    static func restText(_ sec: Int) -> String { sec % 60 == 0 ? "\(sec / 60) min" : "\(sec) s" }

    /// The line shown under the metcon name (spec §7.6).
    public static func instructions(_ s: WorkoutSection, scheme: String? = nil, deload: Bool = false) -> String {
        let r = s.rounds ?? 1
        var text: String
        switch s.format {
        case .amrap:
            text = "As many rounds as you can in \(s.durationMin ?? 12) min"
        case .emom:
            text = "Every minute for \(s.durationMin ?? r) min · one move per minute, in order"
        case .amrapWithRest:
            text = "\(r) rounds · as many as you can in \((s.workSec ?? 240) / 60) min · rest \(restText(s.restSec ?? 60))"
        case .stations:
            text = "\(r) rounds · \(s.workSec ?? 60) s at each station, no rest between stations · rest \(restText(s.roundRestSec ?? 60)) after each round"
        case .interval:
            text = "\(r) rounds · \(s.workSec ?? 40) s work / \(s.restSec ?? 20) s rest on each move, in order"
        case .tabata:
            text = "Tabata 40/20 · one move at a time: \(r) rounds of 40 s work / 20 s rest, then straight on to the next move"
        case .forTime:
            text = "\(scheme ?? "21-15-9") for time · cap \(s.durationMin ?? 15) min"
        default:
            text = "\(r) rounds"
        }
        if deload { text += "\nEasy, steady pace." }
        return text
    }

    /// Rounds and minutes for the `structure-rounds-minutes-word` name (§11.6).
    public static func nameNumbers(_ s: WorkoutSection) -> (rounds: Int, minutes: Int) {
        let total = WorkoutDuration.estimate(s)
        switch s.format {
        case .amrap: return (1, s.durationMin ?? total)
        case .amrapWithRest: return (s.rounds ?? 1, max(1, (s.workSec ?? 240) / 60))
        case .stations, .interval, .tabata: return (s.rounds ?? 1, total)
        case .emom: return (s.durationMin ?? total, s.durationMin ?? total)
        case .forTime: return (1, s.durationMin ?? total)
        default: return (s.rounds ?? 1, total)
        }
    }
}
