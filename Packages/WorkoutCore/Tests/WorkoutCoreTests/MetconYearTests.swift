import Foundation
import XCTest
@testable import WorkoutCore

/// Plans every scheduled day for a year (spec §14.1) and checks every
/// metcon against the rules. Synthetic data only.
///
/// `swift test` runs a reduced matrix (classic schedule; full gym and
/// bodyweight only with all 8 limit combinations; other targets). Set
/// METCON_FULL_MATRIX=1 for every limit × equipment × schedule combination.
enum MetconYearHarness {
    static let start = LocalDate(2026, 10, 12)
    static let end = LocalDate(2027, 10, 11)

    struct Config: CustomStringConvertible {
        var name: String
        var settings: PlannerSettings
        /// Full home gym, no limits: the strict §7.3 limits always hold.
        var strict: Bool

        var description: String { name }
    }

    enum Feedback { case neutral, allHard, allEasy, alternating }

    struct Result {
        var config: Config
        var plans: [PlannedWorkout]
        var violations: [String]
        /// The plans as done (with ratings and scores), plus the fixture history.
        var history: [PlannedWorkout]

        func pace(before d: LocalDate) -> PaceModel { MetconFeedback.learnedPace(from: history.filter { $0.date < d }) }
    }

    static let schedules: [(String, [Weekday])] = [
        ("MWF", [.monday, .wednesday, .friday]), ("TuTh", [.tuesday, .thursday]),
        ("MTuThF", [.monday, .tuesday, .thursday, .friday]), ("M-F", [.monday, .tuesday, .wednesday, .thursday, .friday]),
    ]

    static var equipments: [(String, EquipmentInventory)] {
        var bw = EquipmentInventory.homeGym
        bw.hasBarbell = false; bw.dumbbells = []; bw.kettlebells = []; bw.medicineBall = nil
        bw.boxHeights = []; bw.hasBench = false; bw.hasLowBar = false; bw.hasBike = false
        var db = bw
        db.dumbbells = EquipmentInventory.homeGym.dumbbells
        var kb = bw
        kb.kettlebells = EquipmentInventory.homeGym.kettlebells
        var noBench = EquipmentInventory.homeGym
        noBench.hasBench = false; noBench.boxHeights = []; noBench.hasLowBar = false
        return [("full", .homeGym), ("bodyweight", bw), ("bw+db", db), ("bw+kb", kb), ("no bench/box/bar", noBench),
                ("kg gym", EquipmentInventory.preset(.kg))]
    }

    static var limitCombos: [TrainingLimits] {
        (0..<8).map { TrainingLimits(avoidJumping: $0 & 1 != 0, easyOnKnee: $0 & 2 != 0, easyOnWrist: $0 & 4 != 0) }
    }

    static func config(_ eq: (String, EquipmentInventory), _ limits: TrainingLimits, _ sched: (String, [Weekday]), target: Int = 50) -> Config {
        var s = PlannerSettings.default
        s.equipment = eq.1
        s.limits = limits
        s.schedule = sched.1
        s.targetMinutes = target
        let l = "\(limits.avoidJumping ? "J" : "-")\(limits.easyOnKnee ? "K" : "-")\(limits.easyOnWrist ? "W" : "-")"
        return Config(name: "\(eq.0) \(l) \(sched.0) \(target)min", settings: s,
                      strict: eq.0 == "full" && limits == TrainingLimits())
    }

    static var fullMatrix: Bool { ProcessInfo.processInfo.environment["METCON_FULL_MATRIX"] == "1" }

    static func configs() -> [Config] {
        var out: [Config] = []
        let eqs = equipments
        let classic = schedules[0]
        if fullMatrix {
            for eq in eqs { for l in limitCombos { for sch in schedules { out.append(config(eq, l, sch)) } } }
        } else {
            for l in limitCombos {
                out.append(config(eqs[0], l, classic))
                out.append(config(eqs[1], l, classic))
            }
            for eq in eqs.dropFirst(2) { out.append(config(eq, TrainingLimits(), classic)) }
            for sch in schedules.dropFirst() { out.append(config(eqs[0], TrainingLimits(), sch)) }
        }
        for t in [20, 30, 40, 60] { out.append(config(eqs[0], TrainingLimits(), classic, target: t)) }
        return out
    }

    /// The 6 fixture benchmarks: valid with Back Squats, valid with Front
    /// Squats, a 2-move one, a 6-minute one, valid stations, valid for time.
    static func benchmarks() -> [Benchmark] {
        func item(_ l: String, _ id: String, reps: Int? = nil, scheme: String? = nil, weight: Double? = nil) -> SectionItem {
            SectionItem(letter: l, movementID: id, movementName: MovementLibrary.standard[id]!.name, reps: reps, repsScheme: scheme,
                        prescribedWeight: weight)
        }
        func b(_ slot: Int, _ name: String, _ s: WorkoutSection) -> Benchmark {
            var t = s
            t.name = name
            let id = UUID.seeded(&rng)
            t.benchmarkID = id
            return Benchmark(id: id, name: name, template: t, quarterSlot: slot)
        }
        var rng = SeededRandom(seed: 0xBE11)
        return [
            b(0, "amrap-5-3-squatty", WorkoutSection(kind: .metabolic, format: .amrapWithRest, instructions: "5 rounds", rounds: 5, workSec: 180,
                                                      restSec: 60, items: [item("A", "back-squat", reps: 6, weight: 65), item("B", "up-down", reps: 3),
                                                                           item("C", "plate-ground-to-overhead", reps: 6, weight: 25)])),
            b(1, "amrap-1-18-fronty", WorkoutSection(kind: .metabolic, format: .amrap, instructions: "18 min", rounds: 1, durationMin: 18,
                                                      items: [item("A", "front-squat", reps: 5, weight: 65), item("B", "push-up", reps: 5),
                                                              item("C", "kb-swing", reps: 8, weight: 35)])),
            b(2, "amrap-5-4-twosie", TestData.amrapSection(rounds: [])),
            b(3, "amrap-1-6-tiny", WorkoutSection(kind: .metabolic, format: .amrap, instructions: "6 min", rounds: 1, durationMin: 6,
                                                   items: [item("A", "air-squat", reps: 10), item("B", "push-up", reps: 5), item("C", "burpee", reps: 3)])),
            b(4, "stations-4-19-statey", WorkoutSection(kind: .metabolic, format: .stations, instructions: "4 rounds", rounds: 4, workSec: 60, restSec: 0,
                                                         items: [item("A", "kb-swing"), item("B", "push-up"), item("C", "jumping-jack"), item("D", "sit-up")],
                                                         roundRestSec: 60)),
            b(5, "fortime-1-16-racey", WorkoutSection(kind: .metabolic, format: .forTime, instructions: "for time", rounds: 1, durationMin: 16,
                                                       items: [item("A", "lunge", scheme: "10-9-8-7-6-5-4-3-2-1"), item("B", "push-up", scheme: "10-9-8-7-6-5-4-3-2-1"),
                                                               item("C", "up-down", scheme: "10-9-8-7-6-5-4-3-2-1"), item("D", "sit-up", scheme: "10-9-8-7-6-5-4-3-2-1")])),
        ]
    }

    static func feedback(_ f: Feedback, day n: Int) -> WorkoutFeedback {
        switch f {
        case .neutral: return WorkoutFeedback(energy: .okay, strengthDifficulty: 3, metabolicDifficulty: 3)
        case .allHard: return WorkoutFeedback(energy: .okay, strengthDifficulty: 3, metabolicDifficulty: 5)
        case .allEasy: return WorkoutFeedback(energy: .okay, strengthDifficulty: 3, metabolicDifficulty: 1)
        case .alternating: return WorkoutFeedback(energy: .okay, strengthDifficulty: 3, metabolicDifficulty: n % 2 == 0 ? 5 : 1)
        }
    }

    /// Marks a plan done with feedback and one round log.
    static func done(_ w: PlannedWorkout, feedback f: Feedback, day n: Int) -> PlannedWorkout {
        var w = w
        w.status = .done
        w.feedback = feedback(f, day: n)
        if let i = w.sections.firstIndex(where: { $0.kind == .metabolic }) {
            let s = w.sections[i]
            let k = s.expectedScore ?? 4
            switch s.format {
            case .forTime: w.sections[i].roundLogs = [RoundLog(roundNumber: 1, timeSec: Int(k))]
            case .amrap, .amrapWithRest:
                w.sections[i].roundLogs = [RoundLog(roundNumber: 1, rounds: Int(k), reps: Int((k - k.rounded(.down)) * Double(s.repsPerRound)))]
            default: w.sections[i].roundLogs = [RoundLog(roundNumber: 1, reps: 20)]
            }
        }
        return w
    }

    static func run(_ config: Config, feedback: Feedback = .neutral, checkDeterminism: Bool = false) -> Result {
        let planner = RulesWorkoutPlanner()
        var history = TestData.consistentHistory(from: LocalDate(2026, 8, 31), to: LocalDate(2026, 10, 9), settings: config.settings)
        let bench = benchmarks()
        var plans: [PlannedWorkout] = []
        var violations: [String] = []
        var d = start
        var n = 0
        while d <= end {
            defer { d = d.adding(days: 1) }
            guard config.settings.rotation.isScheduled(d) else { continue }
            n += 1
            let req = PlanRequest(date: d, settings: config.settings, history: history, benchmarks: bench, now: TestData.now)
            do {
                let w = try planner.makePlan(req)
                violations += MetconChecks.hardRules(w).map { "\(config): \($0)" }
                violations += MetconChecks.remixRules(w, settings: config.settings, strict: config.strict).map { "\(config): \($0)" }
                if checkDeterminism && n % 10 == 0, (try? planner.makePlan(req)) != w { violations.append("\(config): \(d) not deterministic") }
                plans.append(w)
                history.append(done(w, feedback: feedback, day: n))
            } catch {
                violations.append("\(config): \(d) threw \(error)")
            }
        }
        return Result(config: config, plans: plans, violations: violations, history: history)
    }

    /// Runs configurations in parallel (each one is independent).
    static func runAll(_ configs: [Config], feedback: Feedback = .neutral) -> [Result] {
        var results = [Result?](repeating: nil, count: configs.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: configs.count) { i in
            let r = run(configs[i], feedback: feedback, checkDeterminism: i == 0)
            lock.lock()
            results[i] = r
            lock.unlock()
        }
        return results.compactMap { $0 }
    }

    /// The default setup's year, planned once and shared by the tests.
    static let defaultYear: Result = run(config(equipments[0], TrainingLimits(), schedules[0]), checkDeterminism: true)
}

final class MetconYearTests: XCTestCase {
    func report(_ v: [String], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(v.isEmpty, "\(v.count) violations:\n" + v.prefix(25).joined(separator: "\n"), file: file, line: line)
    }

    /// MC-3, MC-7, MC-8, MC-19-24, MC-26, MC-28, MC-29, MC-33, MC-48-50,
    /// MC-52, MC-53, MC-55, MC-56 in every configuration; R10.
    func testEveryConfigurationKeepsTheRules() {
        let results = MetconYearHarness.runAll(MetconYearHarness.configs())
        report(results.flatMap(\.violations))
        for r in results { XCTAssertGreaterThan(r.plans.count, 90, r.config.name) }
    }

    /// MC-61: full home gym (any limits) always looks like the coach's;
    /// bodyweight only may not, but then says so.
    func testQualityThreshold() {
        let configs = MetconYearHarness.configs().filter { $0.name.hasPrefix("full") || $0.name.hasPrefix("bodyweight") }
        var v: [String] = []
        for r in MetconYearHarness.runAll(configs) {
            for w in r.plans {
                guard let s = w.metabolicSection, s.benchmarkID == nil else { continue }
                let score = MetconQuality.score(s, pace: r.pace(before: w.date))
                let relaxed = w.reasons.contains { $0.rule == "metabolic.quality_relaxed" }
                if score.penalty > MetconQuality.threshold + 1e-9 && (r.config.name.hasPrefix("full") || !relaxed) {
                    v.append("\(r.config): \(w.date) \(s.name ?? "") \(score.penalty) \(score.top?.name ?? "")")
                }
            }
        }
        report(v)
    }

    /// MC-62: median penalty ≤ 0.5 and p90 ≤ 1.5 for the default setup.
    func testTypicalQualityIsCoachLike() {
        let year = MetconYearHarness.defaultYear
        let penalties = year.plans.compactMap { w -> Double? in
            guard let s = w.metabolicSection, s.benchmarkID == nil else { return nil }
            return MetconQuality.score(s, pace: year.pace(before: w.date)).penalty
        }.sorted()
        XCTAssertGreaterThan(penalties.count, 100)
        XCTAssertLessThanOrEqual(penalties[penalties.count / 2], 0.5)
        XCTAssertLessThanOrEqual(penalties[Int(Double(penalties.count) * 0.9)], 1.5)
    }

    /// Weeks of the default setup (benchmark days and adjusted days excluded where the rule says so).
    func weeks(_ plans: [PlannedWorkout]) -> [[PlannedWorkout]] {
        Dictionary(grouping: plans, by: { $0.date.startOfWeek }).sorted { $0.key < $1.key }.map { $0.value.sorted { $0.date < $1.date } }
    }

    static func adjusted(_ w: PlannedWorkout) -> Bool {
        w.coachNote?.kind == .justShowUp || w.coachNote?.kind == .comeback || w.reasons.contains {
            $0.rule == "metabolic.comeback" || $0.text.contains("sized to fit") || $0.text.contains("lighter one")
        }
    }

    /// Q7 (replaces MC-14) and MC-15: the week's lengths sit within 3 minutes
    /// and the heaviest lift's day is never longer than another day.
    func testWeekLengthsAreAboutEqualAndHeaviestIsShortest() {
        let settings = PlannerSettings.default
        for week in weeks(MetconYearHarness.defaultYear.plans) {
            let remixes = week.filter { $0.metabolicSection?.benchmarkID == nil && !Self.adjusted($0) }
            let secs = remixes.compactMap { $0.metabolicSection?.estimatedSeconds }
            if let lo = secs.min(), let hi = secs.max() {
                XCTAssertLessThanOrEqual(hi - lo, MetconWeekPlan.spread, "\(week[0].date): \(secs)")
            }
            guard let heavy = remixes.first(where: { MetconWeekPlan.day($0.date, settings: settings)?.isHeaviest == true }),
                  let hs = heavy.metabolicSection?.estimatedSeconds else { continue }
            for w in remixes where w.id != heavy.id {
                XCTAssertLessThanOrEqual(hs, w.metabolicSection!.estimatedSeconds, "\(w.date)")
            }
        }
    }

    /// MC-16: no repeated format in a week (no shuffles); 3 of 4 stimuli in
    /// every 4-week window. MC-27: pull days and weekly pull. At most 2
    /// metcons with a jumping move a week.
    func testWeeklyVarietyPullAndImpact() {
        let settings = PlannerSettings.default
        let lib = MovementLibrary.standard
        let ws = weeks(MetconYearHarness.defaultYear.plans)
        for week in ws where week.count == settings.sortedSchedule.count {
            let remixes = week.compactMap(\.metabolicSection).filter { $0.benchmarkID == nil }
            if week.count >= 3 { XCTAssertEqual(Set(remixes.map(\.format)).count, remixes.count, "\(week[0].date): \(remixes.map(\.format))") }
            let jumpy = week.compactMap(\.metabolicSection).filter { $0.items.contains { lib.movement(for: $0)?.highImpact == true } }
            XCTAssertLessThanOrEqual(jumpy.count, 2, "\(week[0].date)")
            let pulls = week.compactMap(\.metabolicSection).filter { $0.items.contains { lib.movement(for: $0)?.armKinds.contains(.pull) == true } }
            XCTAssertGreaterThanOrEqual(pulls.count, 1, "\(week[0].date)")
            for w in week where MetconWeekPlan.day(w.date, settings: settings)?.isPullDay == true && w.metabolicSection?.benchmarkID == nil {
                XCTAssertTrue(w.metabolicSection!.items.contains { lib.movement(for: $0)?.armKinds.contains(.pull) == true }, "\(w.date)")
            }
        }
        for i in 0...(ws.count - 4) {
            let stimuli = Set(ws[i..<(i + 4)].joined().compactMap { $0.metabolicSection?.stimulus })
            XCTAssertGreaterThanOrEqual(stimuli.count, 3, "\(ws[i][0].date)")
        }
    }

    /// MC-17 and move-count shares over a year of the default setup.
    func testFormatMixAndMoveCounts() {
        let remixes = MetconYearHarness.defaultYear.plans.compactMap(\.metabolicSection).filter { $0.benchmarkID == nil }
        let n = Double(remixes.count)
        for (stimulus, weight) in MetconCatalog.stimulusWeights {
            let share = Double(remixes.filter { $0.stimulus == stimulus }.count) / n * 100
            XCTAssertEqual(share, weight, accuracy: 10, "\(stimulus)")
        }
        let share = { (k: Int) in Double(remixes.filter { $0.items.count == k }.count) / n }
        XCTAssertTrue((0.35...0.55).contains(share(3)), "3 moves: \(share(3))")
        XCTAssertTrue((0.40...0.60).contains(share(4)), "4 moves: \(share(4))")
        XCTAssertTrue((0.02...0.12).contains(share(5)), "5 moves: \(share(5))")
    }

    /// MC-30, MC-31, MC-47: lengths and stimuli by phase.
    func testPhaseRules() {
        let settings = PlannerSettings.default
        for w in MetconYearHarness.defaultYear.plans {
            guard let s = w.metabolicSection, s.benchmarkID == nil, let pos = w.position else { continue }
            let secs = s.estimatedSeconds
            let plan = MetconWeekPlan.day(w.date, settings: settings)
            switch pos.phase {
            case .peak:
                XCTAssertLessThan(secs, 1260, "\(w.date)")
                if plan?.isHeaviest == true { XCTAssertNotEqual(s.format, .forTime, "\(w.date)") }
            case .test:
                XCTAssertTrue((720...1019).contains(secs), "\(w.date) \(secs)")
                XCTAssertTrue([.grind, .intervals].contains(s.stimulus!), "\(w.date)")
            case .deload:
                XCTAssertNotEqual(s.format, .forTime, "\(w.date)")
                if !Self.adjusted(w) { XCTAssertGreaterThanOrEqual(secs, 1020, "\(w.date)") }
                XCTAssertTrue(s.instructions.contains("Easy, steady pace."))
            default: break
            }
        }
    }

    /// MC-58, MC-59: with no weight shift, loaded moves carry the §19.2
    /// default (snapped); weights only move on days that say why.
    func testDefaultLoadsAndNoSilentProgression() {
        let snapper = ImplementSnapper(inventory: .homeGym)
        for w in MetconYearHarness.defaultYear.plans {
            guard let s = w.metabolicSection, s.benchmarkID == nil else { continue }
            let shifted = w.reasons.contains { ["metabolic.lighter", "metabolic.heavier", "metabolic.comeback"].contains($0.rule) }
            guard !shifted else { continue }
            for item in s.items {
                guard let m = MetconChecks.movement(item), let load = m.metcon.load, let weight = item.prescribedWeight else { continue }
                switch m.implement {
                case .dumbbell: XCTAssertEqual(weight, snapper.snapDumbbell(load, kettlebellAlternative: m.kettlebellAlternative)?.weight, "\(w.date) \(m.name)")
                case .kettlebell: XCTAssertEqual(weight, snapper.snapKettlebell(load)?.weight, "\(w.date) \(m.name)")
                case .barbell, .medicineBall: XCTAssertEqual(weight, load, "\(w.date) \(m.name)")
                default: break
                }
            }
        }
    }

    /// MC-69: adversarial ratings never break the hard rules or MC-52.
    func testAdversarialFeedbackKeepsTheRules() {
        let c = MetconYearHarness.config(MetconYearHarness.equipments[0], TrainingLimits(), MetconYearHarness.schedules[0])
        var v: [String] = []
        for f in [MetconYearHarness.Feedback.allHard, .allEasy, .alternating] {
            let r = MetconYearHarness.run(c, feedback: f)
            v += r.violations.map { "\(f): \($0)" }
        }
        report(v)
    }
}
