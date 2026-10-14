import Foundation

/// Quarterly benchmark repeats: each benchmark returns once per 13-week block,
/// spread about one every two weeks (slot n is due from block week 1 + 2n).
/// Week 13 catches up anything missed. Only one benchmark per week.
public struct BenchmarkScheduler: Sendable {
    public let calendar: ProgramCalendar

    public init(calendar: ProgramCalendar) { self.calendar = calendar }

    public static func dueWeek(forSlot slot: Int) -> Int {
        let s = ((slot % 6) + 6) % 6
        return 1 + 2 * s
    }

    public func isDone(_ b: Benchmark, inBlock block: Int, history: [PlannedWorkout]) -> Bool {
        let range = calendar.dateRange(ofBlock: block)
        return history.contains { w in
            w.status == .done && !w.isDeleted && range.contains(w.date) && w.sections.contains { $0.benchmarkID == b.id }
        }
    }

    /// Benchmarks due on `date` (active, valid, slot week reached, not done
    /// this block), in slot order. At most one per calendar week, except in
    /// the test weeks, which catch up anything missed.
    public func dueList(on date: LocalDate, benchmarks: [Benchmark], history: [PlannedWorkout],
                        library: MovementLibrary = .standard, lifts: [Lift] = Lift.allCases) -> [Benchmark] {
        let pos = calendar.position(on: date)
        guard pos.block >= 1 else { return [] }
        let past = history.filter { $0.date < date }
        if !pos.isTestWeek {
            let weekStart = date.startOfWeek
            let ranThisWeek = past.contains { w in
                w.date >= weekStart && w.status == .done && w.sections.contains { $0.benchmarkID != nil }
            }
            if ranThisWeek { return [] }
        }
        return benchmarks
            .filter { $0.active && BenchmarkValidator.isValid($0, library: library, lifts: lifts) }
            .filter { BenchmarkScheduler.dueWeek(forSlot: $0.quarterSlot) <= pos.week }
            .filter { !isDone($0, inBlock: pos.block, history: past) }
            .sorted { ($0.quarterSlot, $0.name) < ($1.quarterSlot, $1.name) }
    }

    /// The benchmark to run on `date`, if any. With a day's lift, only a
    /// benchmark with no move of that lift's pattern runs (the first
    /// compatible day runs it).
    public func due(on date: LocalDate, benchmarks: [Benchmark], history: [PlannedWorkout], dayLift: Lift? = nil,
                    settings: PlannerSettings = .default, library: MovementLibrary = .standard) -> Benchmark? {
        dueList(on: date, benchmarks: benchmarks, history: history, library: library, lifts: settings.lifts).first { b in
            guard let dayLift else { return true }
            return BenchmarkValidator.clash(b.template, dayLift: dayLift, settings: settings, library: library) == nil
        }
    }

    /// Copies a benchmark exactly. Moves that the limits/equipment rule out are
    /// substituted and the section is marked modified.
    public func instantiate<G: RandomNumberGenerator>(_ b: Benchmark, settings: PlannerSettings, library: MovementLibrary,
                                                      using rng: inout G) -> (section: WorkoutSection, substitutions: [String]) {
        var s = b.template
        s.id = UUID.seeded(&rng)
        s.benchmarkID = b.id
        s.name = b.name
        s.roundLogs = []
        s.athleteNote = ""
        var subs: [String] = []
        let equipment = settings.equipment.available
        s.items = s.items.map { item in
            var it = item
            it.id = UUID.seeded(&rng)
            it.setLogs = []
            if let m = library[item.movementID] ?? library.lookup(name: item.movementName) {
                if let r = library.resolve(m, equipment: equipment, limits: settings.limits), r.substituted {
                    subs.append("\(m.name) → \(r.movement.name)")
                    it.movementID = r.movement.id
                    it.movementName = r.movement.name
                } else if library.resolve(m, equipment: equipment, limits: settings.limits) == nil {
                    subs.append("\(m.name) → Air Squats")
                    it.movementID = "air-squat"
                    it.movementName = "Air Squats"
                    it.prescribedWeight = nil
                    it.weightLabel = nil
                }
            }
            return it
        }
        s.isModified = !subs.isEmpty
        s.stimulus = s.stimulus ?? MetconStimulus(format: s.format)
        // Expected rounds let a benchmark teach the pace model too.
        if s.expectedScore == nil, s.format == .amrap || s.format == .amrapWithRest,
           s.items.allSatisfy({ $0.reps != nil && library.movement(for: $0) != nil }) {
            s.expectedScore = PaceModel.neutral.expectedRounds(s, library: library)
        }
        return (s, subs)
    }
}

/// Proposes ~6 benchmarks from history: the metabolic pieces done most often
/// with logged scores, mixing formats (max 2 per format). Pieces that break
/// the metcon rules (spec §11.1) are skipped.
public enum BenchmarkProposer {
    public static func propose(from history: [PlannedWorkout], count: Int = 6, library: MovementLibrary = .standard,
                               settings: PlannerSettings = .default) -> [Benchmark] {
        var perFormat: [SectionFormat: Int] = [:]
        var out: [Benchmark] = []
        for b in ranked(from: history, library: library, settings: settings) where out.count < count {
            let f = b.template.format
            guard perFormat[f, default: 0] < 2 else { continue }
            perFormat[f, default: 0] += 1
            var b = b
            b.quarterSlot = out.count
            out.append(b)
        }
        return out
    }

    /// Same pieces = same format and the same moves.
    static func key(_ s: WorkoutSection) -> String {
        s.format.rawValue + "|" + s.items.map(\.movementID).sorted().joined(separator: ",")
    }

    /// Every valid candidate from history, best first, each with a unique name.
    public static func ranked(from history: [PlannedWorkout], library: MovementLibrary = .standard,
                              settings: PlannerSettings = .default) -> [Benchmark] {
        struct Group { var section: WorkoutSection; var times: Int; var scored: Int; var last: LocalDate }
        var groups: [String: Group] = [:]
        for w in history where w.status == .done {
            guard let s = w.metabolicSection, !s.items.isEmpty, s.format != .other, s.benchmarkID == nil else { continue }
            let key = key(s)
            let scored = MetabolicScore.from(s.roundLogs, format: s.format) != nil ? 1 : 0
            if var g = groups[key] {
                g.times += 1
                g.scored += scored
                if w.date >= g.last { g.section = s; g.last = w.date }
                groups[key] = g
            } else {
                groups[key] = Group(section: s, times: 1, scored: scored, last: w.date)
            }
        }
        let ranked = groups.sorted {
            ($0.value.scored, $0.value.times, $0.value.last, $0.key) > ($1.value.scored, $1.value.times, $1.value.last, $1.key)
        }
        var out: [Benchmark] = []
        var rng = SeededRandom(seed: 0xBE7C)
        var used: Set<String> = []
        for (_, g) in ranked {
            guard BenchmarkValidator.intrinsicIssues(g.section, library: library, lifts: settings.lifts).isEmpty else { continue }
            var template = g.section
            template.roundLogs = []
            template.athleteNote = ""
            template.expectedScore = nil
            template.items = template.items.map { var i = $0; i.setLogs = []; return i }
            let minutes = template.format == .amrapWithRest ? max(1, (template.workSec ?? 240) / 60) : WorkoutDuration.estimate(template)
            let name = template.name.flatMap { WorkoutNamer.isValid($0) && !used.contains($0) ? $0 : nil }
                ?? WorkoutNamer.name(format: template.format, rounds: template.rounds ?? 1, minutes: minutes, using: &rng, avoiding: used)
            used.insert(name)
            template.name = name
            let id = UUID.seeded(&rng)
            template.benchmarkID = id
            out.append(Benchmark(id: id, name: name, template: template, active: true, quarterSlot: out.count))
        }
        return out
    }
}
