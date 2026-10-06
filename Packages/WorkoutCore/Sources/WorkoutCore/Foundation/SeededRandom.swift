import Foundation

/// SplitMix64: a tiny, fast, well-distributed seeded generator.
/// The planner only ever uses this (never `SystemRandomNumberGenerator`), so the
/// same inputs + seed always produce the same workout.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    /// Stable seed for a date plus an optional "shuffle" counter.
    public init(date: LocalDate, salt: UInt64 = 0) {
        self.init(seed: UInt64(bitPattern: Int64(date.daysSinceEpoch)) &* 0x9E37_79B9_7F4A_7C15 ^ (salt &+ 0xD1B5_4A32_D192_ED03))
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension Array {
    /// Deterministic weighted pick. Elements with weight <= 0 are never chosen.
    func weightedPick<G: RandomNumberGenerator>(using rng: inout G, weight: (Element) -> Double) -> Element? {
        let weights = map { Swift.max(0, weight($0)) }
        let total = weights.reduce(0, +)
        guard total > 0 else { return nil }
        var target = Double(rng.next() % 1_000_000) / 1_000_000 * total
        for (i, w) in weights.enumerated() where w > 0 {
            if target < w { return self[i] }
            target -= w
        }
        return indices.last { weights[$0] > 0 }.map { self[$0] }
    }

    /// Deterministic Fisher-Yates using the provided generator.
    func seededShuffled<G: RandomNumberGenerator>(using rng: inout G) -> [Element] {
        var a = self
        guard a.count > 1 else { return a }
        for i in stride(from: a.count - 1, to: 0, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1))
            a.swapAt(i, j)
        }
        return a
    }
}

extension Double {
    /// Rounds to the nearest multiple of `step`; exact halves round up.
    func rounded(toNearest step: Double) -> Double {
        guard step > 0 else { return self }
        return (self / step + 0.5 + 1e-9).rounded(.down) * step
    }
}

/// Formats pounds without a trailing ".0" ("102.5", "105").
/// Exact amounts such as plate sizes keep up to two decimals ("1.25").
public func formatPounds(_ value: Double) -> String {
    if value == value.rounded() { return String(Int(value)) }
    var s = String(format: "%.2f", value)
    while s.hasSuffix("0") { s.removeLast() }
    return s
}

extension UUID {
    /// Deterministic UUID (v4 layout) from a seeded generator.
    static func seeded<G: RandomNumberGenerator>(_ rng: inout G) -> UUID {
        let a = rng.next(), b = rng.next()
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 { bytes[i] = UInt8(truncatingIfNeeded: a >> (8 * UInt64(i))) }
        for i in 0..<8 { bytes[8 + i] = UInt8(truncatingIfNeeded: b >> (8 * UInt64(i))) }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
