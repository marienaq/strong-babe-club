import Foundation
@testable import WorkoutCore

/// Rule checks shared by the metcon property and regression tests. Each
/// returns plain-English violations (empty = fine), so a year-long run can
/// report every problem at once.
enum MetconChecks {
    static let lib = MovementLibrary.standard

    static func movement(_ item: SectionItem) -> Movement? { lib.movement(for: item) }

    /// Hard rules for any metcon, remixed or benchmark (MC-19, MC-20, MC-21, MC-33, MC-8).
    static func hardRules(_ w: PlannedWorkout) -> [String] {
        guard let s = w.metabolicSection else { return ["\(w.date): no metcon"] }
        var out: [String] = []
        let tag = "\(w.date) \(s.name ?? "?")"
        if !(3...5).contains(s.items.count) { out.append("\(tag): \(s.items.count) moves") }
        let secs = s.estimatedSeconds
        if !(720...1440).contains(secs) { out.append("\(tag): \(secs) s") }
        if let plan = IntervalPlan.forSection(s), plan.totalDuration != secs {
            out.append("\(tag): timer \(plan.totalDuration) s vs estimate \(secs) s")
        }
        if let lift = w.mainLift {
            for item in s.items {
                if item.movementID == lift.movementID { out.append("\(tag): has the day's lift") }
                if let m = movement(item), m.conflictsWith.contains(lift.slot) {
                    out.append("\(tag): \(m.name) clashes with \(lift.displayName) day")
                }
            }
        }
        return out
    }

    /// Rules for planner-built (remixed) metcons: MC-18, MC-22-24, MC-26,
    /// MC-48-50, MC-52, MC-53, MC-55, MC-56.
    static func remixRules(_ w: PlannedWorkout, settings: PlannerSettings, strict: Bool) -> [String] {
        guard let s = w.metabolicSection, s.benchmarkID == nil else { return [] }
        var out: [String] = []
        let tag = "\(w.date) \(s.name ?? "?")"
        let moves = s.items.map(movement)
        guard moves.allSatisfy({ $0 != nil }) else { return ["\(tag): unknown move"] }
        let ms = moves.compactMap { $0 }
        let reasons = w.reasons(for: .metabolic)
        let rules = reasons.map(\.rule)
        let relaxed = rules.contains("metabolic.coverage_relaxed")

        // MC-18 stimulus
        if let st = s.stimulus { if !st.formats.contains(s.format) { out.append("\(tag): stimulus \(st) vs \(s.format)") } } else { out.append("\(tag): no stimulus") }
        // MC-22 coverage
        for slot in MetconSlot.required where !relaxed && !ms.contains(where: { $0.fills.contains(slot) }) {
            out.append("\(tag): no \(slot) move")
        }
        if relaxed { out.append("\(tag): coverage relaxed") }
        // MC-23 constraints
        let lift = w.mainLift
        let kindMax = strict ? 1 : 2
        for k in LegKind.allCases where ms.filter({ $0.legKind == k }).count > kindMax { out.append("\(tag): \(k) x\(ms.filter { $0.legKind == k }.count)") }
        for k in ArmKind.allCases where ms.filter({ $0.armKinds.contains(k) }).count > (strict ? 2 : 3) { out.append("\(tag): too many \(k)") }
        if ms.filter(\.overhead).count > 1 { out.append("\(tag): 2 overhead") }
        if ms.filter(\.highImpact).count > 1 { out.append("\(tag): 2 high impact") }
        if ms.filter(\.gripHeavy).count > 2 { out.append("\(tag): grip x3") }
        if ms.filter(\.shoulderHeavy).count > (lift?.slot == .overhead ? 1 : 2) { out.append("\(tag): shoulder heavy") }
        if let lift, ms.filter({ $0.isBodyweightPattern(of: lift.slot) }).count > 1 { out.append("\(tag): 2 bodyweight \(lift.slot)") }
        if ms.filter(\.isCoreMove).count > (ms.count == 5 ? 2 : 1) { out.append("\(tag): too much core") }
        if ms.filter(\.isBarbellLift).count > 1 { out.append("\(tag): 2 barbell lifts") }
        if ms.filter({ $0.fills.contains(.agility) }).count > 1 { out.append("\(tag): 2 agility moves") }
        for (item, m) in zip(s.items, ms) {
            if let r = item.reps, !m.repRange.contains(r) || (m.countsEachSide && r % 2 == 1) { out.append("\(tag): \(r) \(m.name)") }
            if let scheme = item.repsScheme {
                let rungs = scheme.split(separator: "-").compactMap { Int($0) }
                if (rungs.max() ?? 0) > 2 * m.repRange.upperBound { out.append("\(tag): rung \(rungs.max() ?? 0) \(m.name)") }
                if rungs.reduce(0, +) > 6 * m.repRange.upperBound { out.append("\(tag): \(rungs.reduce(0, +)) \(m.name)") }
            }
            // MC-24 allowed moves; MC-3 never benchmark-only.
            if !m.isAllowed(equipment: settings.equipment.available, limits: settings.limits) { out.append("\(tag): \(m.name) not allowed") }
            if m.has(.benchmarkOnly) { out.append("\(tag): benchmark-only \(m.name)") }
            if m.metconTimedOnly && ![.stations, .interval, .tabata].contains(s.format) { out.append("\(tag): timed \(m.name) in \(s.format)") }
            // MC-55: one rep count, the same every round.
            if [.amrap, .amrapWithRest, .emom].contains(s.format) && (item.reps == nil || item.repsScheme != nil) {
                out.append("\(tag): \(m.name) has no fixed reps")
            }
        }
        if s.format == .forTime && ms.filter({ PaceModel.forTimeMultiplier(secondsPerRep: $0.secondsPerRep) > 1 }).count > 1 {
            out.append("\(tag): two counting moves in a for time")
        }
        // MC-26 ordering
        let tech = ms.map { $0.technical || $0.isBarbellLift }
        if let firstNonTech = tech.firstIndex(of: false), tech[firstNonTech...].contains(true) { out.append("\(tag): technical move not first") }
        let wraps = s.format != .forTime
        if orderExists(ms, wraps: wraps) && hasAdjacent(ms, wraps: wraps) { out.append("\(tag): grip/shoulder back to back") }
        // MC-48 name
        if let name = s.name {
            let n = MetconCatalog.nameNumbers(s)
            if !WorkoutNamer.isValid(name) || !name.hasPrefix("\(s.format.nameStructure)-\(n.rounds)-\(n.minutes)-") {
                out.append("\(tag): name vs \(s.format.nameStructure)-\(n.rounds)-\(n.minutes)")
            }
        } else { out.append("\(w.date): no name") }
        // MC-49 reasons
        for rule in ["metabolic.stimulus", "metabolic.length", "metabolic.slots", "metabolic.avoids_lift"] where rules.filter({ $0 == rule }).count != 1 {
            out.append("\(tag): \(rule) x\(rules.filter { $0 == rule }.count)")
        }
        if [.amrap, .amrapWithRest, .emom, .forTime].contains(s.format) && !rules.contains("metabolic.reps") { out.append("\(tag): no reps reason") }
        if [.amrap, .amrapWithRest].contains(s.format),
           !(reasons.first { $0.rule == "metabolic.reps" }?.text.contains("rounds") ?? false) { out.append("\(tag): reps reason has no rounds") }
        for r in reasons where r.text.lowercased().contains("remix") || r.text.contains("stays off the muscles") { out.append("\(tag): old copy") }
        // MC-50 reasons are true
        if let length = reasons.first(where: { $0.rule == "metabolic.length" }), !length.text.hasPrefix("\(WorkoutDuration.estimate(s)) min today") {
            out.append("\(tag): length says \(length.text.prefix(8))")
        }
        if let slots = reasons.first(where: { $0.rule == "metabolic.slots" }) {
            for (label, name) in slotMentions(slots.text) {
                guard let i = s.items.firstIndex(where: { $0.movementName == name }), let m = movement(s.items[i]) else {
                    out.append("\(tag): slots names \(name)")
                    continue
                }
                for slot in label where !m.fills.contains(slot) { out.append("\(tag): \(name) listed under \(slot)") }
            }
        }
        // MC-52, MC-53 expected scores
        switch s.format {
        case .amrapWithRest:
            if !(3.2...6.5).contains(s.expectedScore ?? 0) { out.append("\(tag): \(s.expectedScore ?? 0) rounds per window") }
        case .amrap:
            if !(7.5...13.5).contains(s.expectedScore ?? 0) { out.append("\(tag): \(s.expectedScore ?? 0) rounds") }
        case .forTime:
            let e = s.expectedScore ?? 0
            if !(720...1200).contains(e) || (s.durationMin ?? 99) > 24 { out.append("\(tag): E \(e)") }
        default:
            if s.expectedScore != nil { out.append("\(tag): timed piece has an expected score") }
        }
        // MC-56 density
        let d = MetconCatalog.density(s)
        switch s.format {
        case .amrapWithRest, .stations: if !(0.67...0.90).contains(d) { out.append("\(tag): density \(d)") }
        case .interval, .tabata: if !(0.50...0.75).contains(d) { out.append("\(tag): density \(d)") }
        case .amrap: if s.estimatedSeconds > 1200 { out.append("\(tag): continuous over 20 min") }
        default: break
        }
        // MC-7 Tabata 40/20
        if s.format == .tabata && (s.workSec != 40 || s.restSec != 20 || s.roundRestSec != 0) { out.append("\(tag): Tabata not 40/20") }
        return out
    }

    /// "(label) (Name)" pairs from the metabolic.slots sentence.
    static func slotMentions(_ text: String) -> [([MetconSlot], String)] {
        var out: [([MetconSlot], String)] = []
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "("), let close = rest[open...].firstIndex(of: ")") {
            let name = String(rest[rest.index(after: open)..<close])
            let before = rest[..<open]
            let label = before.split(whereSeparator: { $0 == "," || $0 == ";" }).last.map(String.init) ?? ""
            let clause = label.components(separatedBy: " and ").count > 1 && !label.contains("together")
                ? label.components(separatedBy: " and ").last ?? label : label
            var slots: [MetconSlot] = []
            if clause.contains("heart rate") { slots.append(.heart) }
            if clause.contains("legs") { slots.append(.legs) }
            if clause.contains("arms") { slots.append(.arms) }
            if clause.contains("core") { slots.append(.core) }
            if clause.contains("agility") { slots.append(.agility) }
            out.append((slots, name))
            rest = rest[rest.index(after: close)...]
        }
        return out
    }

    static func hasAdjacent(_ ms: [Movement], wraps: Bool) -> Bool {
        guard ms.count > 1 else { return false }
        for i in 0..<ms.count {
            let j = i + 1
            if j == ms.count && (!wraps || ms.count < 3) { break }
            let a = ms[i], b = ms[j % ms.count]
            if (a.gripHeavy && b.gripHeavy) || (a.shoulderHeavy && b.shoulderHeavy) { return true }
        }
        return false
    }

    /// A technical-first order with no grip or shoulder moves back to back exists.
    static func orderExists(_ ms: [Movement], wraps: Bool) -> Bool {
        let tech = ms.filter { $0.technical || $0.isBarbellLift }
        let rest = ms.filter { !($0.technical || $0.isBarbellLift) }
        let techOrders = RulesWorkoutPlanner.permutations(tech).filter { t in
            !zip(t, t.dropFirst()).contains { $0.implement == .bodyweight && $1.implement != .bodyweight }
        }
        return techOrders.contains { t in
            RulesWorkoutPlanner.permutations(rest).contains { !hasAdjacent(t + $0, wraps: wraps) }
        }
    }
}
