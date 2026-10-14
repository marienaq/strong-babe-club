import Foundation

// The metcon section of a planned workout (spec metcon v2): benchmark
// check, the day's length and format, then a best-of-12 remix.

extension RulesWorkoutPlanner {
    /// What the length of today's metcon is based on (for "Why this?").
    struct MetconDay {
        var plan: DayMetconPlan
        var window: ClosedRange<Int>
        var budgetClipped: Bool
        var justShowUp: Bool
        var comeback: Bool
    }

    func buildMetabolic(_ ctx: inout Context, warmup: WorkoutSection, strength: WorkoutSection) throws -> WorkoutSection {
        var rng = ctx.rng(.metabolic)
        let scheduler = BenchmarkScheduler(calendar: ctx.calendar)
        if !ctx.position.isTestWeek, let due = scheduler.due(on: ctx.request.date, benchmarks: ctx.request.benchmarks, history: ctx.history) {
            if ctx.request.salts.metabolic == 0 {
                let (section, subs) = scheduler.instantiate(due, settings: ctx.settings, library: ctx.library, using: &rng)
                if let prev = PRDetector.previousBenchmarkResult(due.id, before: ctx.request.date, history: ctx.history, calendar: ctx.calendar) {
                    ctx.reason(.metabolic, "metabolic.benchmark",
                               "Your quarterly repeat. Last done in \(prev.date.longMonthName). Try to beat \(prev.score)!")
                } else {
                    ctx.reason(.metabolic, "metabolic.benchmark", "A quarterly benchmark: same moves, weights and timing every quarter. Set the score to beat!")
                }
                if !subs.isEmpty {
                    ctx.reason(.metabolic, "benchmark.modified",
                               "Swapped for your limits (\(subs.joined(separator: ", "))), so this score is marked \"modified\".")
                }
                return section
            }
            ctx.reason(.metabolic, "benchmark.deferred", "Shuffled: \(due.name) moves to your next metabolic day.")
        }
        return try buildRemixSection(&ctx, warmup: warmup, strength: strength, rng: &rng)
    }

    /// The day's plan when the date isn't a scheduled day (a moved workout):
    /// the week's middle length and a format by weight.
    func unscheduledPlan(_ ctx: Context, lift: Lift, rng: inout SeededRandom) -> DayMetconPlan {
        let phase = ctx.position.phase
        let allowed = MetconWeekPlan.allowedFormats(phase: phase)
        let window = phase == .test ? 780...960 : 1110...1200
        let format = allowed.filter { MetconCatalog.hasShape($0, in: window) }
            .weightedPick(using: &rng) { MetconCatalog.formatWeights[$0] ?? 1 } ?? .amrap
        return DayMetconPlan(date: ctx.request.date, lift: lift, phase: phase, window: window, format: format, allowedFormats: allowed,
                             isHeaviest: false, isPullDay: lift.slot == .overhead, lightDay: nil, otherFormats: [])
    }

    func buildRemixSection(_ ctx: inout Context, warmup: WorkoutSection, strength: WorkoutSection,
                           rng: inout SeededRandom) throws -> WorkoutSection {
        let date = ctx.request.date
        let lift = ctx.lifts.first ?? ctx.rotation.lift(for: date)
        let plan = MetconWeekPlan.day(date, settings: ctx.settings) ?? unscheduledPlan(ctx, lift: lift, rng: &rng)
        let pos = ctx.position

        // §6.3 day adjustments: coach note, then the session budget.
        var window = plan.window
        let jsu = ctx.coachNote.makesPlanShorter
        let comeback = ctx.coachNote.kind == .comeback
        if jsu {
            window = 720...840
        } else if comeback {
            window = window.lowerBound...max(window.lowerBound, min(window.upperBound, MetconBand.middle.range.upperBound))
        }
        let nonMetcon = WorkoutDuration.estimate(warmup) + WorkoutDuration.estimate(strength) + 6
        let maxSec = min(max((ctx.settings.targetMinutes - nonMetcon) * 60, 720), 1440)
        var clipped = false
        if window.lowerBound > maxSec {
            window = max(720, maxSec - MetconWeekPlan.spread)...maxSec
            clipped = true
        } else if window.upperBound > maxSec {
            window = window.lowerBound...maxSec
            clipped = true
        }

        // Format: the week plan's, unless shuffled or it no longer fits.
        var allowed = plan.allowedFormats.filter { MetconCatalog.hasShape($0, in: window) }
        if pos.phase == .peak && plan.isHeaviest { allowed.removeAll { $0 == .forTime } }
        var format = plan.format
        if ctx.request.salts.metabolic > 0 || !allowed.contains(format) {
            // Prefer a different format from today's plan and the other days'.
            let fresh = allowed.filter { !plan.otherFormats.contains($0) }
            format = (fresh.isEmpty ? allowed : fresh).weightedPick(using: &rng) { f in
                (MetconCatalog.formatWeights[f] ?? 1) * (f == plan.format && ctx.request.salts.metabolic > 0 ? 0.2 : 1)
                    * (plan.otherFormats.contains(f) ? 0.4 : 1)
            } ?? .amrap
        }

        // Weight shift: each source is a reason; the total stays within -2...+1.
        var lighter: [String] = []
        var heavier: [String] = []
        if pos.phase == .deload { lighter.append("deload week") }
        if ctx.coachNote.makesPlanLighter {
            lighter.append("an easier day to get back in the groove")
        } else if ctx.history.last(where: { $0.status == .done })?.feedback?.energy == .sleepy {
            lighter.append("your energy was low last time")
        } else if plan.lightDay == .lighterWeights {
            lighter.append("the last day of the week is a lighter one")
        }
        let ratings = ctx.history.filter { $0.status == .done }.compactMap(\.feedback?.metabolicDifficulty).suffix(2)
        if ratings.count == 2 {
            let avg = Double(ratings.reduce(0, +)) / 2
            if avg >= 4.5 { lighter.append("your last two metcons were rated hard") } else if avg <= 2 { heavier.append("your last two metcons were rated easy") }
        }
        let shift = min(max(heavier.count - lighter.count, -2), 1)

        // History signals for the soft preferences and the week's limits.
        let weekStart = date.startOfWeek
        let thisWeek = ctx.history.filter { $0.date >= weekStart }
        let weekMetcons = thisWeek.compactMap(\.metabolicSection)
        let moveIDs = { (s: WorkoutSection) in s.items.compactMap { ctx.library.movement(for: $0)?.id } }
        let jumpy = weekMetcons.filter { s in s.items.contains { ctx.library.movement(for: $0)?.highImpact == true } }.count
        let recent = ctx.history.filter { $0.date >= date.adding(days: -7) && $0.status == .done }.compactMap(\.metabolicSection)

        let setup = MetconSetup(dayLift: lift, window: window, format: format, formats: allowed.isEmpty ? [.amrap] : allowed,
                                isPullDay: plan.isPullDay, maxMoves: jsu ? 4 : 5, weightShift: shift, density: 1,
                                pace: .neutral, deload: pos.phase == .deload, highImpactBlocked: jumpy >= 2,
                                weekMoveIDs: Set(weekMetcons.flatMap(moveIDs)), recentMoveIDs: Set(recent.flatMap(moveIDs)),
                                warmupIDs: Set(warmup.items.map(\.movementID)),
                                accessoryID: strength.secondaryItems.first?.movementID, usage: ctx.muscleUsage(days: 14))
        let c = try buildRemix(ctx, setup: setup, rng: &rng)
        var section = c.section
        section.id = UUID.seeded(&rng)

        // Name (step 10).
        var used = Set(ctx.history.compactMap { $0.metabolicSection?.name })
        ctx.request.benchmarks.forEach { used.insert($0.name) }
        let numbers = MetconCatalog.nameNumbers(section)
        section.name = WorkoutNamer.name(format: section.format, rounds: numbers.rounds, minutes: numbers.minutes, using: &rng, avoiding: used)

        let day = MetconDay(plan: plan, window: window, budgetClipped: clipped, justShowUp: jsu, comeback: comeback)
        addMetconReasons(&ctx, candidate: c, section: section, setup: setup, day: day, lighter: lighter, heavier: heavier)
        return section
    }

    // MARK: "Why this?"

    func addMetconReasons(_ ctx: inout Context, candidate c: MetconCandidate, section: WorkoutSection, setup: MetconSetup,
                          day: MetconDay, lighter: [String], heavier: [String]) {
        let stimulus = section.stimulus ?? .grind
        ctx.reason(.metabolic, "metabolic.stimulus", "\(stimulus.title): \(stimulus.line).")
        let minutes = WorkoutDuration.estimate(section)
        var length = lengthReason(ctx, section: section, setup: setup, day: day)
        if day.budgetClipped { length += " (sized to fit your \(ctx.settings.targetMinutes)-min session)" }
        ctx.reason(.metabolic, "metabolic.length", "\(minutes) min today: \(length).")
        ctx.reason(.metabolic, "metabolic.slots", slotsText(c))
        ctx.reason(.metabolic, "metabolic.avoids_lift", "No \(Self.patternText(setup.daySlot)) in here: today is \(setup.dayLift.displayName) day.")
        if let reps = repsText(section, candidate: c, setup: setup, library: ctx.library) { ctx.reason(.metabolic, "metabolic.reps", reps) }
        if setup.weightShift < 0 {
            let size = setup.weightShift == -2 ? "two sizes" : "one size"
            ctx.reason(.metabolic, "metabolic.lighter", "Weights \(size) lighter: \(Self.list(lighter)).")
        } else if setup.weightShift > 0 {
            ctx.reason(.metabolic, "metabolic.heavier", "Weights one size heavier: \(Self.list(heavier)).")
        }
        let subs = c.picks.compactMap { p in p.from.map { "\($0.name) → \(p.move.name)" } }
        if !subs.isEmpty { ctx.reason(.metabolic, "limits.substitute", "Swapped for your limits: " + subs.joined(separator: ", ") + ".") }
        c.snapNotes.forEach { ctx.reason(.metabolic, "equipment.snap", $0) }
        for slot in c.relaxed {
            let filler = c.picks.first { !$0.move.requiredFills.isEmpty }?.move.name ?? c.picks.first?.move.name ?? "another move"
            ctx.reason(.metabolic, "metabolic.coverage_relaxed", "Your equipment and limits leave no \(slot.displayName) move, so \(filler) fills in.")
        }
        if c.score.penalty > MetconQuality.threshold {
            ctx.reason(.metabolic, "metabolic.quality_relaxed", "Your limits make this one a bit unusual: \(c.score.top?.name ?? "fewer choices than usual").")
        }
    }

    static func patternText(_ slot: LiftSlot) -> String {
        switch slot {
        case .squat: return "loaded squats"
        case .hipPull: return "heavy hinges or cleans"
        case .overhead: return "loaded overhead presses"
        }
    }

    /// "a, b and c"
    static func list(_ xs: [String]) -> String {
        guard xs.count > 1 else { return xs.first ?? "" }
        return xs.dropLast().joined(separator: ", ") + " and " + xs.last!
    }

    func lengthReason(_ ctx: Context, section: WorkoutSection, setup: MetconSetup, day: MetconDay) -> String {
        let pos = ctx.position
        let lift = setup.dayLift.displayName
        if day.justShowUp { return "showing up is the win, so it's the shortest version" }
        if day.comeback { return "you're getting back into it, so it stays middle-length" }
        if pos.isTestWeek { return "test week: a short piece after your heavy lift" }
        if day.plan.lightDay == .short { return "the last day of the week is a lighter one" }
        if pos.phase == .peak && day.plan.isHeaviest { return "\(lift) is your heaviest lift this week, and peak weeks keep metcons short" }
        if day.plan.isHeaviest { return "\(lift) is your heaviest lift this week, so this is the week's shortest piece" }
        if pos.phase == .deload { return "deload week: a longer, easier piece" }
        if pos.phase == .peak { return "peak week: a little shorter so your lifts stay fresh" }
        if MetconBand.of(seconds: section.estimatedSeconds) == .long { return "the long piece of your week, with time to settle into it" }
        return "about the same length as your other metcons this week"
    }

    /// "Covers heart rate (Up/Downs), legs (KB Swings) and arms (Push-Ups), plus core (Sit-Ups)."
    func slotsText(_ c: MetconCandidate) -> String {
        let req = c.coverage.filter { !$0.extra }
            .sorted { ($0.slots.map(Self.slotRank).min() ?? 9) < ($1.slots.map(Self.slotRank).min() ?? 9) }
        var parts: [String] = []
        for entry in req {
            let slots = entry.slots.sorted { Self.slotRank($0) < Self.slotRank($1) }
            parts.append(slots.count == 1 ? "\(slots[0].displayName) (\(entry.move.name))"
                         : "\(slots.map(\.displayName).joined(separator: " and ")) together (\(entry.move.name))")
        }
        var text = parts.isEmpty ? "A mix of moves" : "Covers " + Self.list(parts)
        for entry in c.coverage where entry.extra {
            let slot = entry.slots[0]
            let label = slot == .core || slot == .agility ? slot.displayName : "more \(slot.displayName)"
            text += ", plus \(label) (\(entry.move.name))"
        }
        return text + "."
    }

    static func slotRank(_ s: MetconSlot) -> Int { [MetconSlot.heart, .legs, .arms, .core, .agility].firstIndex(of: s)! }

    /// "about 4" / "about 3.5"
    static func about(_ x: Double) -> String {
        let half = (x * 2).rounded() / 2
        return half == half.rounded() ? "\(Int(half))" : String(format: "%.1f", half)
    }

    func repsText(_ s: WorkoutSection, candidate c: MetconCandidate, setup: MetconSetup, library: MovementLibrary) -> String? {
        switch s.format {
        case .amrapWithRest, .amrap:
            let fresh = PaceModel.freshRoundSec(s.items, library: library)
            let roundSec = Int((fresh * (setup.pace.factor(s) ?? 1) / 5).rounded()) * 5
            let k = Self.about(s.expectedScore ?? 0)
            let tail = s.format == .amrap ? "about \(k) rounds in \(s.durationMin ?? 12) min" : "about \(k) rounds per block"
            return "Reps are sized so a round takes about \(roundSec) s and every set can go unbroken: \(tail)."
        case .emom:
            return "Reps are sized to about 35 s of work each minute, so every set can go unbroken with a short breather."
        case .forTime:
            let e = Int(((c.finishSec ?? 0) / 60).rounded())
            return "Reps are sized so you should finish in about \(e) min, well under the \(s.durationMin ?? 15)-min cap."
        default:
            return nil
        }
    }

    // MARK: Length

    /// Fits the session to the target (spec §9). The metcon was already
    /// sized to the budget, so only the warm-up is trimmed (3 → 2 rounds);
    /// the metcon never goes under 12 minutes and benchmarks keep their length.
    func fitLength(_ sections: inout [WorkoutSection], _ ctx: inout Context) {
        var target = ctx.settings.targetMinutes
        if ctx.coachNote.makesPlanShorter { target = min(target, 40) }
        var total = sections.map(WorkoutDuration.estimate).reduce(0, +)
        guard total > target else { return }
        if let wi = sections.firstIndex(where: { $0.kind == .warmup }), (sections[wi].rounds ?? 3) > 2 {
            sections[wi].rounds = 2
            sections[wi].instructions = "2 rounds, not for time. Ease in and use light weights."
            total = sections.map(WorkoutDuration.estimate).reduce(0, +)
            ctx.reason(.warmup, "length.warmup_trimmed", "Warm-up cut to 2 rounds so the session fits about \(target) min.")
        }
        guard total > target else { return }
        let benchmark = sections.contains { $0.kind == .metabolic && $0.benchmarkID != nil }
        ctx.reason(.metabolic, "length.over_target", benchmark
                   ? "About \(total) min today, a little over your \(target)-min target: benchmarks keep their full length."
                   : "About \(total) min today, a little over your \(target)-min target, so the metcon still gets its 12 minutes.")
    }
}
