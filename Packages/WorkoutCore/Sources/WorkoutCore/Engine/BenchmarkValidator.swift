import Foundation

/// Checks benchmarks against the metcon rules (spec §11.1). Benchmarks are
/// the coach's design, so they are never changed: a benchmark that breaks
/// the rules is retired, and one that clashes with today's lift waits for
/// a compatible day.
public enum BenchmarkValidator {
    /// Problems with the benchmark itself, as plain sentences (empty = valid).
    public static func intrinsicIssues(_ s: WorkoutSection, library: MovementLibrary = .standard,
                                       lifts: [Lift] = Lift.allCases) -> [String] {
        var out: [String] = []
        let n = s.items.count
        if n < 3 { out.append("Only \(n) move\(n == 1 ? "" : "s"); metcons need 3–5") }
        if n > 5 { out.append("\(n) moves; metcons need 3–5") }
        if s.format == .other { out.append("Its format can't be timed") }
        let secs = WorkoutDuration.estimateSeconds(s)
        if !MetconCatalog.lengthRange.contains(secs) {
            out.append("About \(WorkoutDuration.estimate(s)) min; metcons are 12–24 min")
        }
        let moves = s.items.map { library.movement(for: $0) }
        for (item, m) in zip(s.items, moves) where m == nil {
            out.append("\"\(item.movementName)\" isn't a move the app knows")
        }
        let known = moves.compactMap { $0 }
        if !known.contains(where: { $0.fills.contains(.legs) }) { out.append("No leg move") }
        if !known.contains(where: { $0.fills.contains(.arms) }) { out.append("No arm move") }
        let slots = Set(LiftRotation.cleaned(lifts).map(\.slot))
        if !slots.isEmpty, slots.allSatisfy({ slot in known.contains { clashes($0, slot: slot) } }) {
            out.append("It clashes with every lift day in your rotation")
        }
        return out
    }

    /// "Only 2 moves; metcons need 3–5." (nil when valid).
    public static func retiredReason(_ s: WorkoutSection, library: MovementLibrary = .standard, lifts: [Lift] = Lift.allCases) -> String? {
        intrinsicIssues(s, library: library, lifts: lifts).first.map { $0 + "." }
    }

    public static func isValid(_ b: Benchmark, library: MovementLibrary = .standard, lifts: [Lift] = Lift.allCases) -> Bool {
        !b.isRetired && intrinsicIssues(b.template, library: library, lifts: lifts).isEmpty
    }

    static func clashes(_ m: Movement, slot: LiftSlot) -> Bool {
        m.conflictsWith.contains(slot)
    }

    /// The moves as they will run with these limits and equipment (substitutes applied).
    static func resolvedMoves(_ s: WorkoutSection, settings: PlannerSettings, library: MovementLibrary) -> [Movement?] {
        s.items.map { item in
            guard let m = library.movement(for: item) else { return nil }
            return library.resolve(m, equipment: settings.equipment.available, limits: settings.limits)?.movement ?? m
        }
    }

    /// The move that clashes with today's lift (nil = fine today).
    public static func clash(_ s: WorkoutSection, dayLift: Lift, settings: PlannerSettings = .default,
                             library: MovementLibrary = .standard) -> Movement? {
        resolvedMoves(s, settings: settings, library: library).compactMap { $0 }
            .first { $0.id == dayLift.movementID || clashes($0, slot: dayLift.slot) }
    }
}

/// Keeps the stored benchmarks within the rules: retires the ones that
/// break them (content untouched) and, unless turned off, adds a
/// replacement from history into the retired one's quarter slot.
public enum BenchmarkMaintenance {
    public static func refresh(_ benchmarks: [Benchmark], history: [PlannedWorkout], settings: PlannerSettings = .default,
                               library: MovementLibrary = .standard) -> [Benchmark] {
        var out = benchmarks
        for i in out.indices where !out[i].isRetired {
            if let reason = BenchmarkValidator.retiredReason(out[i].template, library: library, lifts: settings.lifts) {
                out[i].retiredReason = reason
                out[i].active = false
            }
        }
        guard settings.autoReplaceRetiredBenchmarks else { return out }
        let retired = out.filter { b in b.isRetired && !out.contains { $0.replacesID == b.id } }
        guard !retired.isEmpty else { return out }
        var keys = Set(out.map { BenchmarkProposer.key($0.template) })
        var names = Set(out.map(\.name))
        var candidates = BenchmarkProposer.ranked(from: history, library: library, settings: settings)
        for old in retired.sorted(by: { $0.quarterSlot < $1.quarterSlot }) {
            guard let i = candidates.firstIndex(where: { !keys.contains(BenchmarkProposer.key($0.template)) }) else { break }
            var b = candidates.remove(at: i)
            keys.insert(BenchmarkProposer.key(b.template))
            if names.contains(b.name) {
                var rng = SeededRandom(seed: UInt64(old.quarterSlot) &+ 0xBE7D)
                let numbers = MetconCatalog.nameNumbers(b.template)
                b.name = WorkoutNamer.name(format: b.template.format, rounds: numbers.rounds, minutes: numbers.minutes, using: &rng, avoiding: names)
                b.template.name = b.name
            }
            names.insert(b.name)
            b.quarterSlot = old.quarterSlot
            b.replacesID = old.id
            out.append(b)
        }
        return out
    }

    /// "{name} was retired: {reason} Its old scores are kept."
    public static func retiredText(_ b: Benchmark) -> String? {
        b.retiredReason.map { "\(b.name) was retired: \($0) Its old scores are kept." }
    }
}
