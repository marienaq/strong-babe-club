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

    /// The benchmark to run on `date`, if any.
    public func due(on date: LocalDate, benchmarks: [Benchmark], history: [PlannedWorkout]) -> Benchmark? {
        let pos = calendar.position(on: date)
        guard pos.block >= 1 else { return nil }
        let past = history.filter { $0.date < date }
        // At most one benchmark per calendar week (week 13 excepted).
        if pos.week != 13 {
            let weekStart = date.startOfWeek
            let ranThisWeek = past.contains { w in
                w.date >= weekStart && w.status == .done && w.sections.contains { $0.benchmarkID != nil }
            }
            if ranThisWeek { return nil }
        }
        return benchmarks
            .filter { $0.active }
            .filter { BenchmarkScheduler.dueWeek(forSlot: $0.quarterSlot) <= pos.week }
            .filter { !isDone($0, inBlock: pos.block, history: past) }
            .sorted { ($0.quarterSlot, $0.name) < ($1.quarterSlot, $1.name) }
            .first
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
        return (s, subs)
    }
}

/// Proposes ~6 benchmarks from history: the metabolic pieces done most often
/// with logged scores, mixing formats (max 2 per format).
public enum BenchmarkProposer {
    public static func propose(from history: [PlannedWorkout], count: Int = 6) -> [Benchmark] {
        struct Group { var section: WorkoutSection; var times: Int; var scored: Int; var last: LocalDate }
        var groups: [String: Group] = [:]
        for w in history where w.status == .done {
            guard let s = w.metabolicSection, !s.items.isEmpty, s.format != .other else { continue }
            let key = s.format.rawValue + "|" + s.items.map(\.movementID).sorted().joined(separator: ",")
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
        var perFormat: [SectionFormat: Int] = [:]
        var out: [Benchmark] = []
        var rng = SeededRandom(seed: 0xBE7C)
        var used: Set<String> = []
        for (_, g) in ranked where out.count < count {
            let f = g.section.format
            guard perFormat[f, default: 0] < 2 else { continue }
            perFormat[f, default: 0] += 1
            var template = g.section
            template.roundLogs = []
            template.athleteNote = ""
            template.items = template.items.map { var i = $0; i.setLogs = []; return i }
            let minutes = template.format == .amrapWithRest ? max(1, (template.workSec ?? 240) / 60) : WorkoutDuration.estimate(template)
            let name = template.name.flatMap { WorkoutNamer.isValid($0) ? $0 : nil }
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
