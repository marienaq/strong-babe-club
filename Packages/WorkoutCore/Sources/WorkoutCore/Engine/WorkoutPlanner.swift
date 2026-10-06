import Foundation

/// Everything a planner needs to design one day's workout.
public struct PlanRequest: Sendable {
    public var date: LocalDate
    public var settings: PlannerSettings
    /// Past workouts (anything on/after `date` is ignored).
    public var history: [PlannedWorkout]
    /// Current training max per lift. Missing lifts fall back to history.
    public var trainingMaxes: [Lift: Double]
    public var benchmarks: [Benchmark]
    public var salts: SectionSalts
    /// Clock for sync stamps (injected for determinism).
    public var now: Date
    /// Keep an existing workout's id when re-planning / shuffling.
    public var workoutID: UUID?

    public init(date: LocalDate, settings: PlannerSettings = .default, history: [PlannedWorkout] = [],
                trainingMaxes: [Lift: Double] = [:], benchmarks: [Benchmark] = [], salts: SectionSalts = SectionSalts(),
                now: Date = Date(timeIntervalSince1970: 0), workoutID: UUID? = nil) {
        self.date = date
        self.settings = settings
        self.history = history
        self.trainingMaxes = trainingMaxes
        self.benchmarks = benchmarks
        self.salts = salts
        self.now = now
        self.workoutID = workoutID
    }
}

/// The seam between the screens and whatever designs the workouts.
///
/// v1 ships `RulesWorkoutPlanner` (offline, deterministic, explainable). A
/// future AI planner implements the same protocol: given history, feedback,
/// limits and schedule it returns a `PlannedWorkout` with its `reasons`. It
/// must call a server-side proxy (never ship API keys in the app) and should
/// fall back to the rules planner when offline.
public protocol WorkoutPlanner: Sendable {
    func plan(_ request: PlanRequest) async throws -> PlannedWorkout
    /// Re-picks one section (or everything when `section` is nil) within the same limits.
    func shuffle(_ workout: PlannedWorkout, section: SectionKind?, request: PlanRequest) async throws -> PlannedWorkout
}

public enum PlannerError: Error, Equatable {
    case noMovementsAvailable(SectionKind)
}

public struct RulesWorkoutPlanner: WorkoutPlanner {
    public let library: MovementLibrary

    public init(library: MovementLibrary = .standard) { self.library = library }

    public func plan(_ request: PlanRequest) async throws -> PlannedWorkout { try makePlan(request) }

    public func shuffle(_ workout: PlannedWorkout, section: SectionKind?, request: PlanRequest) async throws -> PlannedWorkout {
        try makeShuffle(workout, section: section, request: request)
    }

    public func makeShuffle(_ workout: PlannedWorkout, section: SectionKind?, request: PlanRequest) throws -> PlannedWorkout {
        var req = request
        var salts = workout.salts
        if let k = section { salts[k] &+= 1 } else { SectionKind.allCases.forEach { salts[$0] &+= 1 } }
        req.salts = salts
        req.date = workout.date
        req.workoutID = workout.id
        var out = try makePlan(req)
        out.sync = SyncStamp(createdAt: workout.sync.createdAt, updatedAt: request.now)
        return out
    }

    // MARK: - Planning

    public func makePlan(_ r: PlanRequest) throws -> PlannedWorkout {
        let settings = r.settings.sanitized()
        let history = r.history.filter { $0.date < r.date && !$0.isDeleted }.sorted { $0.date < $1.date }
        var ctx = Context(request: r, settings: settings, history: history, library: library)

        // Strength lift first: everything else is built around it.
        let strength = buildStrength(&ctx)
        let warmup = try buildWarmup(&ctx)
        let metabolic = try buildMetabolic(&ctx)
        let cooldown = try buildCooldown(&ctx)
        var sections = [warmup, strength, metabolic, cooldown]
        fitLength(&sections, &ctx)

        var idRNG = SeededRandom(date: r.date, salt: 0x1D)
        let id = r.workoutID ?? UUID.seeded(&idRNG)
        let workout = PlannedWorkout(id: id, date: r.date, status: .planned, sections: sections, reasons: ctx.reasons,
                                     coachNote: ctx.coachNote, salts: r.salts, position: ctx.position,
                                     durationMin: sections.map(WorkoutDuration.estimate).reduce(0, +),
                                     source: "rules-v1", sync: SyncStamp(createdAt: r.now))
        return workout
    }

    struct Context {
        let request: PlanRequest
        let settings: PlannerSettings
        let history: [PlannedWorkout]
        let library: MovementLibrary
        let calendar: ProgramCalendar
        let rotation: LiftRotation
        let position: BlockPosition
        let plates: PlateCalculator
        let snapper: ImplementSnapper
        let equipment: Set<Equipment>
        let trainingMaxes: [Lift: Double]
        var lifts: [Lift] = []
        var coachNote: CoachNote
        var reasons: [PlanReason] = []

        init(request: PlanRequest, settings: PlannerSettings, history: [PlannedWorkout], library: MovementLibrary) {
            self.request = request
            self.settings = settings
            self.history = history
            self.library = library
            self.calendar = settings.calendar
            self.rotation = settings.rotation
            self.position = calendar.position(on: request.date)
            self.plates = PlateCalculator(inventory: settings.equipment)
            self.snapper = ImplementSnapper(inventory: settings.equipment)
            self.equipment = settings.equipment.available
            self.trainingMaxes = TrainingMax.resolve(programs: request.trainingMaxes, history: history,
                                                    barWeight: settings.equipment.barWeight)
            let lift = position.isTestWeek ? rotation.testLifts(for: request.date).0 : rotation.lift(for: request.date)
            self.coachNote = CoachNoteSelector.select(history: history, today: request.date, todaysLift: lift,
                                                      schedule: settings.sortedSchedule, breaks: settings.breaks)
        }

        mutating func reason(_ section: SectionKind?, _ rule: String, _ text: String) {
            reasons.append(PlanReason(section: section, rule: rule, text: text))
        }

        func rng(_ kind: SectionKind) -> SeededRandom {
            let k: UInt64
            switch kind {
            case .warmup: k = 0x57A1
            case .strength: k = 0x5719
            case .metabolic: k = 0x3E7A
            case .cooldown: k = 0xC001
            }
            return SeededRandom(date: request.date, salt: k &* 0x100_0000_01B3 ^ request.salts[kind])
        }

        var lighter: Bool {
            coachNote.makesPlanLighter || history.last(where: { $0.status == .done })?.feedback?.energy == .sleepy
        }

        /// How often each muscle was trained in the last `days` days.
        func muscleUsage(days: Int) -> [Muscle: Int] {
            let start = request.date.adding(days: -days)
            var usage: [Muscle: Int] = [:]
            for w in history where w.date >= start && w.status == .done {
                for s in w.sections where s.kind != .warmup {
                    for item in s.items {
                        let muscles: [Muscle]
                        if let lift = Lift(movementName: item.movementName) {
                            muscles = Array(lift.primaryMuscles)
                        } else {
                            muscles = (library[item.movementID] ?? library.lookup(name: item.movementName))?.muscles ?? []
                        }
                        muscles.forEach { usage[$0, default: 0] += 1 }
                    }
                }
            }
            return usage
        }

        func usageCount(of movementID: String, days: Int) -> Int {
            let start = request.date.adding(days: -days)
            return history.filter { $0.date >= start && $0.status == .done }
                .flatMap(\.sections).flatMap(\.items)
                .filter { $0.movementID == movementID || (library.lookup(name: $0.movementName)?.id == movementID) }
                .count
        }

        /// Allowed movements for a role, with substitutes applied (deduped).
        func candidates(_ role: MovementRole) -> [(movement: Movement, substitutedFrom: Movement?)] {
            var seen: Set<String> = []
            var out: [(Movement, Movement?)] = []
            for m in library.movements(with: role) {
                guard let res = library.resolve(m, equipment: equipment, limits: settings.limits) else { continue }
                guard !seen.contains(res.movement.id) else { continue }
                seen.insert(res.movement.id)
                out.append((res.movement, res.substituted ? m : nil))
            }
            return out
        }
    }

    // MARK: Strength

    func buildStrength(_ ctx: inout Context) -> WorkoutSection {
        var rng = ctx.rng(.strength)
        let pos = ctx.position
        let date = ctx.request.date
        let week = ctx.rotation.week(for: date)

        if pos.isTestWeek {
            let (a, b) = ctx.rotation.testLifts(for: date)
            ctx.lifts = [a, b]
            ctx.reason(.strength, "test.week", "Test week: work up to heavy sets to set real training maxes. \"Heavy\" means 1-2 reps left in the tank.")
            var items: [SectionItem] = []
            var tmUsed: Double?
            for (i, lift) in [a, b].enumerated() {
                let tm = ctx.trainingMaxes[lift]!
                let lastTop = LiftHistory.sessions(of: lift, in: ctx.history).last?.topWeight
                let plan = StrengthPlanner.plan(lift: lift, position: pos, trainingMax: tm, calculator: ctx.plates,
                                                input: StrengthAdjustmentInput(), rampStart: (lastTop ?? tm) * 0.5)
                if let lastTop {
                    ctx.reason(.strength, "test.ramp_from_history",
                               "\(lift.displayName) warm-up sets start at 50% of your last top set (\(formatPounds(lastTop)) lb).")
                }
                if i == 0 { tmUsed = plan.trainingMax }
                items.append(SectionItem(id: UUID.seeded(&rng), letter: i == 0 ? "A" : "B", movementID: lift.movementID,
                                         movementName: lift.displayName, reps: plan.prescription.setReps.first,
                                         prescribedWeight: plan.sets.last?.weight, plannedSets: plan.sets))
            }
            let rxA = StrengthProgram.prescription(for: a, position: pos)
            return WorkoutSection(id: UUID.seeded(&rng), kind: .strength, format: .everyNMin,
                                  instructions: "Every 3 min: A then B, \(rxA.setReps.count) sets\nA: work up to a heavy 3 · B: heavy single, clean technique only",
                                  rounds: rxA.setReps.count, intervalSec: StrengthProgram.twoLiftInterval, lift: a, trainingMax: tmUsed, items: items)
        }

        var lift = ctx.rotation.lift(for: date)
        ctx.reason(.strength, "rotation.week", "It's your \(lift.slot.displayName) day in the two-week rotation, so it's \(lift.displayName).")

        // Never repeat the same main lift within 7 days.
        let recentLifts = Set(ctx.history.filter { $0.date >= date.adding(days: -6) && $0.status == .done }.compactMap(\.mainLift))
        if recentLifts.contains(lift) {
            let thisWeek = week == .a ? LiftRotation.weekA : LiftRotation.weekB
            let other = week == .a ? LiftRotation.weekB : LiftRotation.weekA
            if let alt = (thisWeek + other).first(where: { !recentLifts.contains($0) && $0.slot == lift.slot })
                ?? (thisWeek + other).first(where: { !recentLifts.contains($0) }) {
                ctx.reason(.strength, "rotation.no_repeat", "You did \(lift.displayName) in the last 7 days, so today is \(alt.displayName) instead.")
                lift = alt
            }
        }
        ctx.lifts = [lift]

        if pos.phase == .preProgram {
            ctx.reason(.strength, "block.pre_program",
                       "The program starts with test week on \(ctx.calendar.testWeekStart.shortDisplay). Until then: volume-style sets from your history.")
        } else {
            let label = pos.isDeloadOverride ? "a deload week (swapped in Settings)" : "the \(pos.phase.displayName) phase"
            ctx.reason(.strength, "block.phase", "Block \(pos.block), week \(pos.week): \(label).")
        }

        let joint = lift.jointStress.intersection(ctx.settings.limits.protectedJoints).sorted { $0.rawValue < $1.rawValue }.first
        let input = StrengthAdjustmentInput(lastSessions: Array(LiftHistory.sessions(of: lift, in: ctx.history).suffix(2)),
                                            capAtLowEnd: ctx.lighter,
                                            push: ctx.coachNote.kind == .push && ctx.coachNote.lift == lift,
                                            jointLimit: joint)
        let plan = StrengthPlanner.plan(lift: lift, position: pos, trainingMax: ctx.trainingMaxes[lift]!,
                                        calculator: ctx.plates, input: input)
        for n in plan.notes { if let text = n.text { ctx.reason(.strength, n.rule, text) } }

        // Shuffle only changes the format; lift and weights come from the block.
        let variant = ctx.request.salts.strength % 2
        var instructions = plan.prescription.instructions
        var format = SectionFormat.everyNMin
        if variant == 1 {
            format = .setsGoingUp
            let reps = Set(plan.prescription.setReps).count == 1 ? "\(plan.prescription.setReps[0])" : plan.prescription.setReps.map(String.init).joined(separator: "-")
            instructions = "\(plan.sets.count) sets × \(reps) going up\nRest about 2 min between sets"
            ctx.reason(.strength, "shuffle.format", "Shuffled: same lift and weights (set by your block), as straight sets instead of every 2 min.")
        }
        let item = SectionItem(id: UUID.seeded(&rng), letter: "A", movementID: lift.movementID, movementName: lift.displayName,
                               reps: plan.prescription.setReps.first, prescribedWeight: plan.sets.last?.weight, plannedSets: plan.sets)
        return WorkoutSection(id: UUID.seeded(&rng), kind: .strength, format: format, instructions: instructions,
                              rounds: plan.sets.count, intervalSec: plan.prescription.intervalSec, lift: lift,
                              trainingMax: plan.trainingMax, items: [item])
    }

    // MARK: Warm-up

    func buildWarmup(_ ctx: inout Context) throws -> WorkoutSection {
        var rng = ctx.rng(.warmup)
        let lift = ctx.lifts.first ?? .backSquat
        let cardio = ctx.candidates(.warmupCardio)
        guard let a = cardio.weightedPick(using: &rng, weight: { c in c.movement.highImpact ? 0.7 : 1 }) else {
            throw PlannerError.noMovementsAvailable(.warmup)
        }
        var slots = [lift.slot, lift.slot, lift.slot]
        if ctx.lifts.count > 1 { slots[2] = ctx.lifts[1].slot }
        let primers = ctx.candidates(.warmupPrimer)
        var chosen: [(Movement, Movement?)] = []
        for slot in slots {
            let pool = primers.filter { $0.movement.primes.contains(slot) && !chosen.map(\.0.id).contains($0.movement.id) }
            let fallback = primers.filter { !chosen.map(\.0.id).contains($0.movement.id) }
            guard let pick = (pool.isEmpty ? fallback : pool).weightedPick(using: &rng, weight: { c in
                // Prefer patterns not already picked.
                chosen.contains { $0.0.pattern == c.movement.pattern } ? 0.4 : 1
            }) else { throw PlannerError.noMovementsAvailable(.warmup) }
            chosen.append((pick.movement, pick.substitutedFrom))
        }
        let rounds = ctx.coachNote.makesPlanShorter ? 2 : FormatLibrary.warmupRounds
        var items: [SectionItem] = []
        for (i, (m, _)) in ([(a.movement, a.substitutedFrom)] + chosen).enumerated() {
            items.append(makeItem(m, letter: String("ABCD"[String.Index(utf16Offset: i, in: "ABCD")]), reps: m.baseReps,
                                  ctx: ctx, rng: &rng))
        }
        let slotNames = Set(slots).map(\.displayName).sorted().joined(separator: " and ")
        var why = "Warms up the \(slotNames) pattern for \(ctx.lifts.map(\.displayName).joined(separator: " + "))."
        if ctx.settings.limits.avoidJumping { why += " No jumping, per your limits." }
        else if a.movement.highImpact { why += " Light jumping to get the heart rate up." }
        ctx.reason(.warmup, "warmup.primes", why)
        let subs = ([(a.movement, a.substitutedFrom)] + chosen).compactMap { m, from in from.map { "\($0.name) → \(m.name)" } }
        if !subs.isEmpty { ctx.reason(.warmup, "limits.substitute", "Swapped for your limits: " + subs.joined(separator: ", ") + ".") }
        return WorkoutSection(id: UUID.seeded(&rng), kind: .warmup, format: .rounds,
                              instructions: "\(rounds) rounds, not for time. Ease in and use light weights.",
                              rounds: rounds, items: items)
    }

    // MARK: Metabolic

    func buildMetabolic(_ ctx: inout Context) throws -> WorkoutSection {
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

        let lighter = ctx.lighter
        let budget = max(8, ctx.settings.targetMinutes - 30)
        var templates = ctx.position.isTestWeek ? FormatLibrary.short : FormatLibrary.metabolic
        if ctx.coachNote.makesPlanShorter { templates = templates.filter { $0.minutes <= 15 } }
        let fitting = templates.filter { $0.minutes <= budget }
        // Variety: formats used in the last 2 weeks are less likely.
        let recentFormats = ctx.history.filter { $0.date >= ctx.request.date.adding(days: -14) && $0.status == .done }
            .compactMap { $0.metabolicSection?.format }
        guard let template = (fitting.isEmpty ? templates : fitting).weightedPick(using: &rng, weight: { t in
            1 / (1 + Double(recentFormats.filter { $0 == t.format }.count))
        }) else {
            throw PlannerError.noMovementsAvailable(.metabolic)
        }

        // Moves: avoid loading the muscles the strength work just hammered and
        // favour muscles trained least over the last 2 weeks.
        let liftMuscles = ctx.lifts.reduce(into: Set<Muscle>()) { $0.formUnion($1.primaryMuscles) }
        let usage = ctx.muscleUsage(days: 14)
        let maxUse = Double(usage.values.max() ?? 1)
        var pool = ctx.candidates(.metabolic).filter { c in
            let overlap = liftMuscles.intersection(c.movement.muscles).count
            return !(overlap >= 2 && c.movement.implement != .bodyweight)
        }
        if template.format == .tabata || template.format == .interval {
            pool = pool.filter { !$0.movement.timed }
        }
        var picked: [(Movement, Movement?)] = []
        for _ in 0..<template.moveCount {
            let options = pool.filter { c in !picked.contains { $0.0.id == c.movement.id || $0.0.pattern == c.movement.pattern } }
            guard let p = options.weightedPick(using: &rng, weight: { c in
                let fresh = c.movement.muscles.map { 1 - Double(usage[$0] ?? 0) / max(maxUse, 1) }.max() ?? 0.5
                return 0.3 + fresh
            }) ?? pool.first(where: { c in !picked.contains { $0.0.id == c.movement.id } }) else { break }
            picked.append((p.movement, p.substitutedFrom))
        }
        guard !picked.isEmpty else { throw PlannerError.noMovementsAvailable(.metabolic) }

        // Weights follow recent metabolic ratings.
        let ratings = ctx.history.filter { $0.status == .done }.compactMap(\.feedback?.metabolicDifficulty).suffix(2)
        var weightShift = 0
        if lighter { weightShift = -1 }
        else if ratings.count == 2 {
            let avg = Double(ratings.reduce(0, +)) / 2
            if avg >= 4.5 { weightShift = -1 } else if avg <= 2 { weightShift = 1 }
        }

        let repsFactor: Double
        switch template.intensity {
        case .low: repsFactor = 0.5
        case .mid: repsFactor = 1
        case .high: repsFactor = 1
        }
        var items: [SectionItem] = []
        var snapNotes: [String] = []
        for (i, (m, _)) in picked.enumerated() {
            let letter = String("ABCD"[String.Index(utf16Offset: i, in: "ABCD")])
            var reps: Int? = max(2, Int((Double(m.baseReps) * repsFactor).rounded()))
            var scheme: String?
            var time: Int?
            switch template.format {
            case .forTime: scheme = template.repsScheme; reps = nil
            case .tabata, .interval: reps = nil; time = template.workSec
            default: break
            }
            if m.timed { time = m.baseReps; reps = nil }
            var item = makeItem(m, letter: letter, reps: reps, ctx: ctx, rng: &rng, weightShift: weightShift, notes: &snapNotes)
            item.repsScheme = scheme
            if time != nil { item.timeSec = time; item.reps = nil }
            items.append(item)
        }

        var used = Set(ctx.history.compactMap { $0.metabolicSection?.name })
        ctx.request.benchmarks.forEach { used.insert($0.name) }
        let name = WorkoutNamer.name(format: template.format, rounds: template.rounds, minutes: template.nameMinutes,
                                     using: &rng, avoiding: used)

        let least = Muscle.allCases.filter { m in picked.contains { $0.0.muscles.contains(m) } }
            .min { (usage[$0] ?? 0, $0.rawValue) < (usage[$1] ?? 0, $1.rawValue) }
        var why = "A fresh \(template.format.nameStructure) that stays off the muscles today's \(ctx.lifts.first?.displayName.lowercased() ?? "lift") works."
        if let least, !usage.isEmpty { why += " Extra \(least.displayName), which you've trained least in the last 2 weeks." }
        ctx.reason(.metabolic, "metabolic.remix", why)
        if weightShift < 0 {
            let cause = lighter ? (ctx.coachNote.makesPlanLighter ? "an easier day to get back in the groove" : "your energy was low last time")
                                : "your last two metcons were rated hard"
            ctx.reason(.metabolic, "metabolic.lighter", "Weights one size lighter: \(cause).")
        }
        if weightShift > 0 { ctx.reason(.metabolic, "metabolic.heavier", "Weights one size heavier: your last two metcons were rated easy.") }
        let subs = picked.compactMap { m, from in from.map { "\($0.name) → \(m.name)" } }
        if !subs.isEmpty { ctx.reason(.metabolic, "limits.substitute", "Swapped for your limits: " + subs.joined(separator: ", ") + ".") }
        snapNotes.forEach { ctx.reason(.metabolic, "equipment.snap", $0) }

        return WorkoutSection(id: UUID.seeded(&rng), kind: .metabolic, format: template.format, name: name,
                              instructions: template.instructions, rounds: template.rounds, workSec: template.workSec,
                              restSec: template.restSec, intervalSec: template.format == .emom ? 60 : nil,
                              durationMin: template.durationMin, items: items)
    }

    // MARK: Cool-down

    func buildCooldown(_ ctx: inout Context) throws -> WorkoutSection {
        var rng = ctx.rng(.cooldown)
        let cores = ctx.candidates(.core)
        guard !cores.isEmpty else { throw PlannerError.noMovementsAvailable(.cooldown) }
        let counts = cores.map { ($0, ctx.usageCount(of: $0.movement.id, days: 28)) }
        let minCount = counts.map(\.1).min() ?? 0
        let leastUsed = counts.filter { $0.1 == minCount }.map(\.0)
        let core = leastUsed.weightedPick(using: &rng, weight: { _ in 1 })!.movement

        let liftMuscles = ctx.lifts.reduce(into: Set<Muscle>()) { $0.formUnion($1.primaryMuscles) }
        let stretches = ctx.candidates(.stretch)
        let bestOverlap = stretches.map { liftMuscles.intersection($0.movement.muscles).count }.max() ?? 0
        let stretch = stretches.filter { liftMuscles.intersection($0.movement.muscles).count == bestOverlap }
            .weightedPick(using: &rng, weight: { _ in 1 })?.movement

        var coreItem = makeItem(core, letter: "A", reps: nil, ctx: ctx, rng: &rng)
        if core.timed {
            coreItem.timeSec = core.baseReps
            coreItem.repsScheme = nil
        } else {
            coreItem.repsScheme = FormatLibrary.coreScheme
            coreItem.reps = 15
        }
        var items = [coreItem]
        if let stretch {
            var s = makeItem(stretch, letter: "B", reps: nil, ctx: ctx, rng: &rng)
            s.timeSec = stretch.baseReps
            items.append(s)
        }
        let coreLine = core.timed ? "\(FormatLibrary.coreTimedSets) × \(core.baseReps) s \(core.name)" : "\(FormatLibrary.coreScheme) \(core.name)"
        var why = minCount == 0 ? "\(core.name): a core move you haven't done in the last 4 weeks." : "\(core.name) is the core move you've done least this month."
        if let stretch { why += " The \(stretch.name.lowercased()) is for after \(ctx.lifts.first?.displayName.lowercased() ?? "lifting")." }
        ctx.reason(.cooldown, "cooldown.core_least", why)
        return WorkoutSection(id: UUID.seeded(&rng), kind: .cooldown, format: .sets,
                              instructions: "\(coreLine), then \(stretch.map { "\($0.baseReps) s \($0.name.lowercased()) each side" } ?? "stretch")",
                              rounds: core.timed ? FormatLibrary.coreTimedSets : 5, items: items)
    }

    // MARK: Helpers

    func makeItem(_ m: Movement, letter: String, reps: Int?, ctx: Context, rng: inout SeededRandom, weightShift: Int = 0) -> SectionItem {
        var ignored: [String] = []
        return makeItem(m, letter: letter, reps: reps, ctx: ctx, rng: &rng, weightShift: weightShift, notes: &ignored)
    }

    func makeItem(_ m: Movement, letter: String, reps: Int?, ctx: Context, rng: inout SeededRandom, weightShift: Int,
                  notes: inout [String]) -> SectionItem {
        var item = SectionItem(id: UUID.seeded(&rng), letter: letter, movementID: m.id, movementName: m.name, reps: reps)
        guard let w = m.defaultWeight else {
            if m.implement == .box, let h = ctx.settings.equipment.defaultBoxHeight { item.weightLabel = "\(h)\" box" }
            return item
        }
        switch m.implement {
        case .dumbbell:
            if var s = ctx.snapper.snapDumbbell(w, reps: reps, kettlebellAlternative: m.kettlebellAlternative) {
                s = ctx.snapper.shift(s, by: weightShift)
                item.prescribedWeight = s.weight
                item.reps = s.reps ?? reps
                item.weightLabel = s.label(pair: m.dumbbellPair && s.implement == .dumbbell)
                if let n = s.note { notes.append("\(m.name): \(n)") }
            }
        case .kettlebell:
            if var s = ctx.snapper.snapKettlebell(w, reps: reps) {
                s = ctx.snapper.shift(s, by: weightShift)
                item.prescribedWeight = s.weight
                item.reps = s.reps ?? reps
                item.weightLabel = s.label(pair: false)
                if let n = s.note { notes.append("\(m.name): \(n)") }
            }
        case .medicineBall:
            if let ball = ctx.settings.equipment.medicineBall {
                item.prescribedWeight = ball
                item.weightLabel = "\(formatPounds(ball)) lb ball"
            }
        case .barbell:
            item.prescribedWeight = w
            item.weightLabel = "\(formatPounds(w)) lb plate"
        default:
            break
        }
        return item
    }

    /// Trims the metabolic piece until the workout fits the target length.
    func fitLength(_ sections: inout [WorkoutSection], _ ctx: inout Context) {
        var target = ctx.settings.targetMinutes
        if ctx.coachNote.makesPlanShorter { target = min(target, 40) }
        guard let mi = sections.firstIndex(where: { $0.kind == .metabolic }), sections[mi].benchmarkID == nil else { return }
        var trimmed = false
        var guardCount = 0
        while sections.map(WorkoutDuration.estimate).reduce(0, +) > target, guardCount < 20 {
            guardCount += 1
            var s = sections[mi]
            switch s.format {
            case .amrapWithRest, .interval:
                guard let r = s.rounds, r > 2 else { break }
                s.rounds = r - 1
            case .amrap, .emom, .forTime:
                guard let d = s.durationMin, d > 6 else { break }
                s.durationMin = d - 2
                if s.format == .emom { s.rounds = d - 2 }
            default:
                break
            }
            if s == sections[mi] { break }
            sections[mi] = s
            trimmed = true
        }
        if trimmed {
            var s = sections[mi]
            s.instructions = MetabolicTemplate(format: s.format, rounds: s.rounds ?? 1, workSec: s.workSec, restSec: s.restSec,
                                               durationMin: s.durationMin, repsScheme: s.items.first?.repsScheme,
                                               moveCount: s.items.count, intensity: .mid).instructions
            sections[mi] = s
            ctx.reason(.metabolic, "length.trimmed", "Trimmed so the whole workout fits about \(target) min.")
        }
    }
}
