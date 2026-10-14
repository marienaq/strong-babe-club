import Foundation

/// A move in the metcon pool: the resolved movement and, if it stands in
/// for another one (limits, equipment), the original.
struct MetconPick: Hashable {
    var move: Movement
    var from: Movement?
}

/// Everything a remixed metcon is built from (spec §7.1), after the week
/// plan and the day adjustments.
struct MetconSetup {
    var dayLift: Lift
    var window: ClosedRange<Int>
    var format: SectionFormat
    /// Formats the phase allows (fallbacks stay inside them).
    var formats: [SectionFormat]
    var isPullDay: Bool
    var maxMoves: Int
    var weightShift: Int
    /// Rep multiplier from recent ratings (§22.2).
    var density: Double
    var pace: PaceModel
    var deload: Bool
    /// Two earlier metcons this week already had a jumping move.
    var highImpactBlocked: Bool
    /// Moves in the week's earlier metcons.
    var weekMoveIDs: Set<String>
    /// Moves in any metcon in the last 7 days.
    var recentMoveIDs: Set<String>
    var warmupIDs: Set<String>
    var accessoryID: String?
    var usage: [Muscle: Int]

    var daySlot: LiftSlot { dayLift.slot }
}

/// Fallback steps (spec §7.7), applied in order.
enum MetconLevel: Int, Comparable {
    case normal
    /// F2: drop soft preferences.
    case noSoft
    /// F3: allow a second move of the same leg or arm kind.
    case sameKind
    /// F4: fewer moves (never below 3).
    case fewerMoves
    /// F6: a required slot with no move at all is filled from another slot.
    case relaxCoverage

    static func < (a: MetconLevel, b: MetconLevel) -> Bool { a.rawValue < b.rawValue }
}

struct MetconCandidate {
    var section: WorkoutSection
    var picks: [MetconPick]
    /// Which slots each move covers, in pick order. Extras are the 4th/5th moves.
    var coverage: [(slots: [MetconSlot], move: Movement, extra: Bool)]
    var relaxed: [MetconSlot]
    var score: MetconQuality.Score
    var snapNotes: [String]
    /// For time: the base scheme ("10-9-...-1") and expected finish seconds.
    var scheme: String?
    var finishSec: Double?
    /// Penalty of the first valid candidate in the winning group (best of N ≤ this).
    var firstPenalty: Double = 0
}

extension RulesWorkoutPlanner {
    static let timeFormats: Set<SectionFormat> = [.stations, .interval, .tabata]
    static let letters = ["A", "B", "C", "D", "E"]

    /// Step 4: allowed, resolved metcon moves for the day (no day's-lift
    /// clash, no accessory, no benchmark-only moves).
    func metconPool(_ ctx: Context, setup: MetconSetup) -> [MetconPick] {
        var seen: Set<String> = []
        var out: [MetconPick] = []
        for m in ctx.library.movements(with: .metabolic) where !m.has(.benchmarkOnly) {
            guard let r = ctx.library.resolve(m, equipment: ctx.equipment, limits: ctx.settings.limits) else { continue }
            let mv = r.movement
            guard !mv.fills.isEmpty, !mv.has(.benchmarkOnly), mv.id != setup.dayLift.movementID,
                  !mv.conflictsWith.contains(setup.daySlot), mv.id != setup.accessoryID,
                  seen.insert(mv.id).inserted else { continue }
            out.append(MetconPick(move: mv, from: r.substituted ? m : nil))
        }
        return out
    }

    static func formatPool(_ pool: [MetconPick], format: SectionFormat) -> [MetconPick] {
        pool.filter { p in
            if p.move.metconTimedOnly && !timeFormats.contains(format) { return false }
            if format == .forTime && (p.move.secondsPerRep >= 5 || p.move.metconTimedOnly) { return false }
            return true
        }
    }

    /// The hard constraints inside one metcon (spec §7.3).
    static func allows(_ m: Movement, after picks: [MetconPick], moves n: Int, level: MetconLevel, setup: MetconSetup) -> Bool {
        let ms = picks.map(\.move)
        if ms.contains(where: { $0.id == m.id }) { return false }
        let sameKind = level >= .sameKind
        if let k = m.legKind, ms.filter({ $0.legKind == k }).count >= (sameKind ? 2 : 1) { return false }
        for k in m.armKinds where ms.filter({ $0.armKinds.contains(k) }).count >= (sameKind ? 3 : 2) { return false }
        if m.overhead && ms.contains(where: \.overhead) { return false }
        if m.highImpact && (setup.highImpactBlocked || ms.contains(where: \.highImpact)) { return false }
        if m.gripHeavy && ms.filter(\.gripHeavy).count >= 2 { return false }
        if m.shoulderHeavy && ms.filter(\.shoulderHeavy).count >= (setup.daySlot == .overhead ? 1 : 2) { return false }
        if m.isBodyweightPattern(of: setup.daySlot) && ms.contains(where: { $0.isBodyweightPattern(of: setup.daySlot) }) { return false }
        if m.isCoreMove && ms.filter(\.isCoreMove).count >= (n == 5 ? 2 : 1) { return false }
        if m.isBarbellLift && ms.contains(where: \.isBarbellLift) { return false }
        return true
    }

    /// The coach's everyday moves (the names behind the alias table): picked
    /// more often, so remixes look like the coach's.
    static let staples: Set<String> = [
        "up-down", "push-up", "kb-swing", "burpee", "deadlift", "back-squat", "front-squat", "hang-power-clean", "push-press",
        "push-jerk", "power-clean", "sit-up", "db-push-press", "plate-ground-to-overhead", "goblet-squat", "db-snatch",
        "jumping-jack", "lunge", "bench-step-up", "air-squat", "v-up", "db-curl-press", "db-bench-press", "db-front-squat",
        "box-jump", "db-front-rack-lunge", "barbell-shoulder-press", "overhead-plate-lunge", "db-hang-squat-clean",
        "db-ground-to-overhead", "db-step-up", "australian-pull-up", "db-hang-clean-push-press", "db-deadlift", "db-thruster",
        "lemon-squeezer", "toe-tap", "leg-raise", "wall-walk", "mountain-climber",
    ]
    /// Moves that exist mainly so limits and small gyms still cover every
    /// slot: used, but less often when there's a choice.
    static let fallbacks: Set<String> = [
        "squat-thrust-hold", "marching-knees", "prone-swimmer", "skater-step", "lateral-shuffle-touch", "hand-release-push-up",
        "high-knees", "glute-bridge", "db-glute-bridge", "kb-farmer-carry", "lateral-bench-step-over", "skater",
    ]

    /// Soft preferences (spec §7.2, plus the familiarity weight above).
    static func pickWeight(_ p: MetconPick, slot: MetconSlot, uncovered: Set<MetconSlot>, level: MetconLevel,
                           setup: MetconSetup) -> Double {
        guard level < .noSoft else { return 1 }
        let m = p.move
        var w = 1.0
        if !m.requiredFills.subtracting([slot]).intersection(uncovered).isEmpty { w *= 1.3 }
        let maxUse = Double(setup.usage.values.max() ?? 1)
        let fresh = m.muscles.map { 1 - Double(setup.usage[$0] ?? 0) / max(maxUse, 1) }.max() ?? 0.5
        w *= 0.3 + fresh
        if setup.recentMoveIDs.contains(m.id) { w *= 0.4 }
        if setup.warmupIDs.contains(m.id) { w *= 0.5 }
        if m.isBodyweightPattern(of: setup.daySlot) { w *= 0.3 }
        if m.highImpact { w *= 0.7 }
        if slot == .arms && !setup.isPullDay { w *= m.armKind == .push ? 3 : 1 }
        if staples.contains(m.id) { w *= 2 } else if fallbacks.contains(m.id) { w *= 0.5 }
        return w
    }

    /// Rounds a raw rep count: half up, inside the unbroken range, even for
    /// per-side moves, and to the nearest 5 above 20.
    static func roundReps(_ raw: Double, _ m: Movement) -> Int {
        let range = m.repRange
        var r = min(max(Int((raw + 0.5).rounded(.down)), range.lowerBound), range.upperBound)
        if r > 20 { r = Int((Double(r) / 5).rounded()) * 5 }
        if m.countsEachSide && r % 2 == 1 { r += r > 20 ? 5 : 1 }
        while r > range.upperBound { r -= m.countsEachSide ? 2 : 1 }
        while r < range.lowerBound { r += m.countsEachSide ? 2 : 1 }
        return r
    }

    /// Step 7: technical (and barbell) moves first, loaded before bodyweight;
    /// then no grip or shoulder moves back to back (wrapping for round
    /// formats), alternating upper and lower body where possible.
    static func order(_ picks: [MetconPick], wraps: Bool, soft: Bool) -> [MetconPick] {
        let isTech = { (p: MetconPick) in p.move.technical || p.move.isBarbellLift }
        let tech = picks.filter(isTech).enumerated().sorted { a, b in
            let la = a.element.move.implement != .bodyweight, lb = b.element.move.implement != .bodyweight
            return la != lb ? la : a.offset < b.offset
        }.map(\.element)
        let rest = picks.filter { !isTech($0) }
        guard soft else { return tech + rest }
        func adjacent(_ seq: [MetconPick], _ flag: (Movement) -> Bool) -> Bool {
            guard seq.count > 1 else { return false }
            for i in 0..<seq.count {
                let j = i + 1
                if j == seq.count && (!wraps || seq.count < 3) { break }
                if flag(seq[i].move) && flag(seq[j % seq.count].move) { return true }
            }
            return false
        }
        func alternation(_ seq: [MetconPick]) -> Int {
            var score = 0
            for i in 0..<seq.count {
                let j = i + 1
                if j == seq.count && !wraps { break }
                let a = seq[i].move, b = seq[j % seq.count].move
                if (a.isUpper && b.isLower) || (a.isLower && b.isUpper) { score += 1 }
            }
            return score
        }
        // Technical orders that keep loaded moves before bodyweight ones.
        let techOrders = permutations(tech).filter { t in
            !zip(t, t.dropFirst()).contains { $0.move.implement == .bodyweight && $1.move.implement != .bodyweight }
        }
        var best: [MetconPick]?
        var bestScore = -1
        for t in techOrders {
            for perm in permutations(rest) {
                let seq = t + perm
                guard !adjacent(seq, \.gripHeavy), !adjacent(seq, \.shoulderHeavy) else { continue }
                let s = alternation(seq)
                if s > bestScore { best = seq; bestScore = s }
            }
        }
        return best ?? tech + rest
    }

    /// All orders of up to 5 items, in a fixed (lexicographic) order.
    static func permutations<T>(_ xs: [T]) -> [[T]] {
        guard xs.count > 1 else { return [xs] }
        var out: [[T]] = []
        for i in xs.indices {
            var rest = xs
            let x = rest.remove(at: i)
            for p in permutations(rest) { out.append([x] + p) }
        }
        return out
    }

    /// Reps per move (spec §7.4): AMRAPs share the target round time
    /// evenly (one move switch each), EMOMs get about 35 s of work. Then the
    /// density from ratings, re-rounded inside the unbroken range.
    static func sizeReps(_ section: WorkoutSection, moves: [Movement], pace: PaceModel, density: Double) -> [Int]? {
        let n = Double(moves.count)
        let perMove: Double
        switch section.format {
        case .amrap, .amrapWithRest:
            guard let target = pace.targetFreshRoundSec(section) else { return nil }
            perMove = (target - PaceModel.switchSec * n) / n
        case .emom:
            perMove = 35
        default:
            return nil
        }
        return moves.map { m in
            let r = roundReps(perMove / max(m.secondsPerRep, 0.1), m)
            return roundReps(Double(r) * density, m)
        }
    }

    static let countWeights: [Int: Double] = [3: 45, 4: 50, 5: 5]

    /// Picks the move count for a shape: 3 (45), 4 (50), 5 (5).
    static func pickCount(_ counts: [Int], level: MetconLevel, rng: inout SeededRandom) -> Int? {
        guard !counts.isEmpty else { return nil }
        if level >= .fewerMoves { return counts.min() }
        return counts.weightedPick(using: &rng) { countWeights[$0] ?? 1 }
    }

    // MARK: One candidate (steps 3-11)

    /// Step 3: shapes (with move counts) whose length fits the window, in a
    /// weighted random order: 3 moves (45), 4 (50), 5 (5).
    static func shapeOptions(format: SectionFormat, window: ClosedRange<Int>, setup: MetconSetup, level: MetconLevel,
                             rng: inout SeededRandom) -> [(shape: MetconShape?, moves: Int)] {
        var options: [(shape: MetconShape?, moves: Int)] = []
        if format == .forTime {
            options = [3, 4, 5].filter { $0 <= setup.maxMoves }.map { (nil, $0) }
        } else {
            for s in MetconCatalog.shapes(format) {
                for c in s.moveCounts where c <= setup.maxMoves && window.contains(s.seconds(moves: c) ?? 0) { options.append((s, c)) }
            }
        }
        if level >= .fewerMoves, let fewest = options.map(\.moves).min() { options = options.filter { $0.moves == fewest } }
        var ordered: [(shape: MetconShape?, moves: Int)] = []
        while !options.isEmpty {
            guard let pick = Array(options.indices).weightedPick(using: &rng, weight: { countWeights[options[$0].moves] ?? 1 }) else { break }
            ordered.append(options.remove(at: pick))
        }
        return ordered
    }

    func metconCandidate(format: SectionFormat, shape: MetconShape?, moves n: Int, window: ClosedRange<Int>, setup: MetconSetup,
                         pool: [MetconPick], level: MetconLevel, ctx: Context, rng: inout SeededRandom) -> MetconCandidate? {
        let fpool = Self.formatPool(pool, format: format)
        guard fpool.count >= 3 else { return nil }

        // Step 5: required slots, fewest candidates first.
        let armsNeedPull = setup.isPullDay && fpool.contains { $0.move.armKinds.contains(.pull) }
        func covers(_ m: Movement, _ slot: MetconSlot) -> Bool {
            m.fills.contains(slot) && (slot != .arms || !armsNeedPull || m.armKinds.contains(.pull))
        }
        var required = MetconSlot.required
        var relaxed: [MetconSlot] = []
        if level >= .relaxCoverage {
            relaxed = required.filter { s in !fpool.contains { covers($0.move, s) } }
            required.removeAll { relaxed.contains($0) }
        }
        let counts = required.map { slot in fpool.filter { covers($0.move, slot) }.count }
        let order = required.indices.sorted { (counts[$0], $0) < (counts[$1], $1) }.map { required[$0] }

        var picks: [MetconPick] = []
        var covered: Set<MetconSlot> = []
        var coverage: [(slots: [MetconSlot], move: Movement, extra: Bool)] = []
        for slot in order where !covered.contains(slot) {
            let uncovered = Set(order).subtracting(covered)
            let options = fpool.filter { covers($0.move, slot) && Self.allows($0.move, after: picks, moves: n, level: level, setup: setup) }
            guard let p = options.weightedPick(using: &rng, weight: { Self.pickWeight($0, slot: slot, uncovered: uncovered, level: level, setup: setup) })
            else { return nil }
            picks.append(p)
            var gained = [slot]
            // A full-body move counts for up to two slots.
            if let extra = order.first(where: { $0 != slot && !covered.contains($0) && covers(p.move, $0) }) { gained.append(extra) }
            covered.formUnion(gained)
            coverage.append((gained, p.move, false))
            if picks.count > n { return nil }
        }

        // Step 6: extras until the move count is reached.
        while picks.count < n {
            let ms = picks.map(\.move)
            let legKinds = Set(ms.compactMap(\.legKind))
            let onlyPush = ms.contains { $0.armKinds.contains(.push) } && !ms.contains { $0.armKinds.contains(.pull) }
            let ok = { (p: MetconPick) in Self.allows(p.move, after: picks, moves: n, level: level, setup: setup) }
            var arms = fpool.filter { $0.move.fills.contains(.arms) && $0.move.armKinds.contains(onlyPush ? .pull : .push) && ok($0) }
            if arms.isEmpty { arms = fpool.filter { $0.move.fills.contains(.arms) && ok($0) } }
            let slots: [(MetconSlot, Double, [MetconPick])] = [
                (.core, 35, fpool.filter { $0.move.fills.contains(.core) && ok($0) }),
                (.legs, 25, fpool.filter { $0.move.fills.contains(.legs) && !legKinds.contains($0.move.legKind ?? .squat) && ok($0) }),
                (.arms, 25, arms),
                (.agility, 15, fpool.filter { $0.move.fills.contains(.agility) && ok($0) }),
            ].filter { !$0.2.isEmpty }
            guard let (slot, _, options) = slots.weightedPick(using: &rng, weight: { level >= .noSoft ? 1 : $0.1 }),
                  let p = options.weightedPick(using: &rng, weight: {
                      Self.pickWeight($0, slot: slot, uncovered: [], level: level, setup: setup)
                  }) else { return nil }
            picks.append(p)
            coverage.append(([slot], p.move, true))
        }
        guard (3...5).contains(picks.count), picks.count <= setup.maxMoves else { return nil }

        // Step 7: order.
        // (The order never fails, so it applies at every fallback level.)
        let ordered = Self.order(picks, wraps: format != .forTime, soft: true)

        // Step 8: reps or time, then weights.
        var section = shape?.section() ?? MetconShape(id: "ft", format: .forTime).section(capMinutes: 15)
        var notes: [String] = []
        var items: [SectionItem] = []
        for (i, p) in ordered.enumerated() {
            items.append(makeMetconItem(p.move, letter: Self.letters[i], ctx: ctx, rng: &rng, weightShift: setup.weightShift, notes: &notes))
        }
        var scheme: String?
        var finish: Double?
        switch format {
        case .amrap, .amrapWithRest, .emom:
            guard let reps = Self.sizeReps(section, moves: ordered.map(\.move), pace: setup.pace, density: setup.density) else { return nil }
            for i in items.indices { items[i].reps = reps[i] }
        case .stations, .interval, .tabata:
            for i in items.indices {
                items[i].reps = nil
                items[i].timeSec = section.workSec
            }
        case .forTime:
            // Step 9: a scheme whose expected finish is 12-20 min and whose cap fits the day.
            let shapes = MetconCatalog.shapes(.forTime)
            var remaining = shapes
            var found: (MetconShape, Double, Int)?
            while !remaining.isEmpty, found == nil {
                guard let s = remaining.weightedPick(using: &rng, weight: \.weight) else { break }
                remaining.removeAll { $0.id == s.id }
                let base = s.scheme ?? []
                let moves = ordered.map(\.move)
                let tooBig = moves.contains { m in
                    (base.max() ?? 0) * PaceModel.forTimeMultiplier(secondsPerRep: m.secondsPerRep) > 2 * m.repRange.upperBound
                }
                guard !tooBig else { continue }
                let e = setup.pace.forTimeSeconds(scheme: base, moves: moves)
                guard (720...1200).contains(Int(e.rounded())) else { continue }
                let cap = min(24, Int((1.2 * e / 60).rounded(.up)))
                guard window.contains(cap * 60), MetconCatalog.forTimeCaps.contains(cap) else { continue }
                found = (s, e, cap)
            }
            guard let (s, e, cap) = found, let base = s.scheme else { return nil }
            section.durationMin = cap
            scheme = s.schemeText
            finish = e
            for (i, p) in ordered.enumerated() {
                let mult = PaceModel.forTimeMultiplier(secondsPerRep: p.move.secondsPerRep)
                items[i].reps = nil
                items[i].repsScheme = base.map { String($0 * mult) }.joined(separator: "-")
            }
        default:
            return nil
        }
        section.items = items
        section.stimulus = MetconStimulus(format: format)
        switch format {
        case .amrap, .amrapWithRest: section.expectedScore = setup.pace.expectedRounds(section, library: ctx.library)
        case .forTime: section.expectedScore = finish.map { $0.rounded() }
        default: section.expectedScore = nil
        }
        section.instructions = MetconCatalog.instructions(section, scheme: scheme, deload: setup.deload)

        // Step 11: hard rules (with the expected rounds of MC-52).
        if format == .amrapWithRest, !(3.2...6.5).contains(section.expectedScore ?? 0) { return nil }
        if format == .amrap, !(7.5...13.5).contains(section.expectedScore ?? 0) { return nil }
        let secs = section.estimatedSeconds
        guard window.contains(secs), MetconCatalog.lengthRange.contains(secs) else { return nil }
        guard Set(required).isSubset(of: covered) else { return nil }
        for (item, p) in zip(section.items, ordered) {
            if let r = item.reps, !p.move.repRange.contains(r) || (p.move.countsEachSide && r % 2 == 1) { return nil }
        }
        let score = MetconQuality.score(section, library: ctx.library, pace: setup.pace, weekMoveIDs: setup.weekMoveIDs)
        return MetconCandidate(section: section, picks: ordered, coverage: coverage, relaxed: relaxed, score: score,
                               snapNotes: notes, scheme: scheme, finishSec: finish)
    }

    // MARK: Best of N with fallbacks

    /// Builds N = 12 candidates and keeps the best (spec §20.3). Falls back
    /// step by step (§7.7) and never returns a metcon that breaks a hard rule.
    func buildRemix(_ ctx: Context, setup: MetconSetup, rng: inout SeededRandom) throws -> MetconCandidate {
        let pool = metconPool(ctx, setup: setup)
        guard pool.count >= 3 else { throw PlannerError.metconPoolTooSmall(available: pool.count) }
        let seed = rng.next()
        var attempt: UInt64 = 0
        // The shape and move count are picked once; the 12 candidates vary
        // the moves (so the best-of-12 doesn't drift toward fewer moves).
        func best(_ format: SectionFormat, _ level: MetconLevel, _ window: ClosedRange<Int>) -> MetconCandidate? {
            var shapeRNG = SeededRandom(seed: seed ^ (UInt64(MetconCatalog.formats.firstIndex(of: format) ?? 0) &+ 1) &* 0xA24B_AED4_963E_E407)
            for option in Self.shapeOptions(format: format, window: window, setup: setup, level: level, rng: &shapeRNG) {
                var winner: MetconCandidate?
                for _ in 0..<12 {
                    var r = SeededRandom(seed: seed &+ attempt &* 0x9E37_79B9_7F4A_7C15)
                    attempt &+= 1
                    guard var c = metconCandidate(format: format, shape: option.shape, moves: option.moves, window: window, setup: setup,
                                                  pool: pool, level: level, ctx: ctx, rng: &r) else { continue }
                    c.firstPenalty = winner?.firstPenalty ?? c.score.penalty
                    if winner == nil || c.score.penalty < winner!.score.penalty { winner = c }
                }
                if let winner { return winner }
            }
            return nil
        }
        // F5 order: the planned format, then the same stimulus, then any
        // format with a shape in the window (time-based first when the pool
        // is mostly timed holds).
        func formats(_ window: ClosedRange<Int>) -> [SectionFormat] {
            let stim = MetconStimulus(format: setup.format)
            var rest = setup.formats.filter { $0 != setup.format && MetconCatalog.hasShape($0, in: window) }
            let timed = pool.filter(\.move.metconTimedOnly).count
            rest.sort { a, b in
                let sa = MetconStimulus(format: a) == stim, sb = MetconStimulus(format: b) == stim
                if sa != sb { return sa }
                if timed * 2 >= pool.count {
                    let ta = Self.timeFormats.contains(a), tb = Self.timeFormats.contains(b)
                    if ta != tb { return ta }
                }
                return MetconCatalog.formats.firstIndex(of: a)! < MetconCatalog.formats.firstIndex(of: b)!
            }
            return [setup.format] + rest
        }
        for window in [setup.window, MetconCatalog.lengthRange] {
            let fs = formats(window)
            for f in fs {
                for level in [MetconLevel.normal, .noSoft, .sameKind, .fewerMoves] {
                    if let c = best(f, level, window) { return c }
                }
            }
            for f in fs {
                if let c = best(f, .relaxCoverage, window) { return c }
            }
        }
        throw PlannerError.metconPoolTooSmall(available: pool.count)
    }

    // MARK: Items

    /// A metcon item with its default load (§19.2). Barbell lifts are loaded
    /// from the training max and rounded to the plates (Q1).
    func makeMetconItem(_ m: Movement, letter: String, ctx: Context, rng: inout SeededRandom, weightShift: Int,
                        notes: inout [String]) -> SectionItem {
        if let bb = m.metcon.barbell {
            var item = SectionItem(id: UUID.seeded(&rng), letter: letter, movementID: m.id, movementName: m.name)
            let tm = ctx.trainingMaxes[bb.lift] ?? ctx.settings.equipment.barWeight
            var w = ctx.plates.round(tm * bb.fraction).weight
            let totals = ctx.plates.loadableTotals
            if weightShift < 0 {
                for _ in 0..<(-weightShift) { w = totals.last { $0 < w - 0.001 } ?? w }
            } else if weightShift > 0 {
                for _ in 0..<weightShift { w = totals.first { $0 > w + 0.001 } ?? w }
            }
            item.prescribedWeight = w
            item.weightLabel = "\(formatPounds(w)) \(WeightUnit.current.symbol)"
            return item
        }
        var loaded = m
        loaded.defaultWeight = m.metcon.load ?? m.defaultWeight
        var item = makeItem(loaded, letter: letter, reps: nil, ctx: ctx, rng: &rng, weightShift: weightShift, notes: &notes)
        // Plates: one size lighter / heavier from the plates on hand.
        if m.implement == .barbell, weightShift != 0, let w = item.prescribedWeight {
            let plates = Array(Set(ctx.settings.equipment.platePairs)).sorted()
            if let i = plates.firstIndex(where: { abs($0 - w) < 0.01 }) ?? plates.lastIndex(where: { $0 < w }) {
                let shifted = plates[min(max(i + weightShift, 0), plates.count - 1)]
                item.prescribedWeight = shifted
                item.weightLabel = "\(formatPounds(shifted)) \(WeightUnit.current.symbol) plate"
            }
        }
        return item
    }
}
