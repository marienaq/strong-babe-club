import Foundation

/// One scheduled day's metcon plan: how long, which format, which arms.
public struct DayMetconPlan: Hashable, Sendable {
    public enum LightDay: String, Hashable, Sendable {
        /// A short piece (12-16 min).
        case short
        /// Weights one step lighter.
        case lighterWeights
    }

    public var date: LocalDate
    /// The rotation lift for the day (before any no-repeat swap).
    public var lift: Lift
    public var phase: BlockPhase
    /// Target length in seconds (before coach-note and budget adjustments).
    public var window: ClosedRange<Int>
    public var format: SectionFormat
    /// Formats allowed this week (by phase); a re-pick stays inside them.
    public var allowedFormats: [SectionFormat]
    /// The day with the heaviest lift gets the shortest piece of the week.
    public var isHeaviest: Bool
    /// The arms slot is filled with a pull move on this day.
    public var isPullDay: Bool
    /// About 1 week in 4 the last scheduled day is lighter.
    public var lightDay: LightDay?
    /// Formats planned for the week's other days.
    public var otherFormats: [SectionFormat]
}

/// Decides each scheduled day's metcon length and format for one week
/// (spec §6.2 with owner decision Q7). Depends only on settings and dates,
/// so it is stable under shuffles, re-plans and history.
///
/// Days are about the same length, like the coach's: each week has one
/// 3-minute window around the middle band. The heaviest lift's day gets
/// the lower half, the others the upper half.
public enum MetconWeekPlan {
    static let salt: UInt64 = 0x3E7B
    /// Spread of the week's lengths (3 min).
    public static let spread = 180

    /// Strength load used to find the heaviest day.
    public static func load(_ lift: Lift) -> Int {
        switch lift {
        case .deadlift, .backSquat: return 3
        case .frontSquat, .pushPress: return 2
        case .hangPowerClean, .pushJerk: return 1
        }
    }

    /// Start of the week's window, by phase (peak a little shorter, deload a
    /// little longer, test weeks short).
    static func weekStart(phase: BlockPhase, rng: inout SeededRandom) -> Int {
        switch phase {
        case .preProgram, .volume, .strength: return [1020, 1050][Int(rng.next() % 2)]
        case .peak: return [960, 990][Int(rng.next() % 2)]
        case .deload: return 1080
        case .test: return 780
        }
    }

    /// Stimulus weights per phase. Test weeks (2 in 14) only allow grind and
    /// intervals, so the other weeks lean a little more on repeat and race
    /// to keep the year's mix at grind 20 / repeat 45 / race 17 / intervals 18.
    public static func stimulusWeights(phase: BlockPhase) -> [MetconStimulus: Double] {
        switch phase {
        case .test: return [.grind: 20, .intervals: 18]
        default: return [.grind: 12, .repeat: 54, .race: 24, .intervals: 10]
        }
    }

    public static func allowedFormats(phase: BlockPhase) -> [SectionFormat] {
        switch phase {
        case .deload: return MetconCatalog.formats.filter { $0 != .forTime }
        case .test: return [.amrap, .emom, .interval, .tabata]
        default: return MetconCatalog.formats
        }
    }

    public static func make(weekStart: LocalDate, settings: PlannerSettings) -> [LocalDate: DayMetconPlan] {
        let key = WeekKey(weekStart: weekStart.startOfWeek, settings: settings)
        if let hit = cache.get(key) { return hit }
        let plan = make(weekStart: weekStart.startOfWeek, settings: settings, lookBack: true)
        cache.set(key, plan)
        return plan
    }

    struct WeekKey: Hashable {
        var weekStart: LocalDate
        var settings: PlannerSettings
    }

    /// Plans are pure functions of the key, so they are remembered.
    final class Cache: @unchecked Sendable {
        private var plans: [WeekKey: [LocalDate: DayMetconPlan]] = [:]
        private let lock = NSLock()

        func get(_ k: WeekKey) -> [LocalDate: DayMetconPlan]? {
            lock.lock()
            defer { lock.unlock() }
            return plans[k]
        }

        func set(_ k: WeekKey, _ v: [LocalDate: DayMetconPlan]) {
            lock.lock()
            defer { lock.unlock() }
            if plans.count > 500 { plans.removeAll() }
            plans[k] = v
        }
    }

    static let cache = Cache()

    /// The plan for one date (nil when the date isn't a scheduled day).
    public static func day(_ date: LocalDate, settings: PlannerSettings) -> DayMetconPlan? {
        make(weekStart: date.startOfWeek, settings: settings)[date]
    }

    static func make(weekStart: LocalDate, settings: PlannerSettings, lookBack: Bool) -> [LocalDate: DayMetconPlan] {
        let rotation = settings.rotation
        let calendar = settings.calendar
        let days = (0..<7).map { weekStart.adding(days: $0) }.filter(rotation.isScheduled)
        guard !days.isEmpty else { return [:] }
        var rng = SeededRandom(date: weekStart, salt: salt)
        let phase = calendar.position(on: weekStart).phase
        let lo = self.weekStart(phase: phase, rng: &rng)
        let lightWeek = phase != .test && rng.next() % 4 == 0
        let lightKind: DayMetconPlan.LightDay = rng.next() % 2 == 0 ? .short : .lighterWeights

        let lifts = days.map(rotation.lift(for:))
        // Heaviest first; ties go to the earlier day.
        let ranked = days.indices.sorted { (-load(lifts[$0]), $0) < (-load(lifts[$1]), $1) }
        let heaviest = ranked[0]
        let overheadDays = days.indices.filter { lifts[$0].slot == .overhead }
        let pullDays = Set(overheadDays.isEmpty ? [days.count - 1] : overheadDays)

        func window(_ i: Int) -> ClosedRange<Int> {
            if lightWeek, lightKind == .short, i == days.count - 1 { return MetconBand.short.range }
            if days.count == 1 { return lo...(lo + spread) }
            return i == heaviest ? lo...(lo + spread / 2) : (lo + spread / 2)...(lo + spread)
        }

        let allowed = allowedFormats(phase: phase)
        let lastWeek = lookBack ? make(weekStart: weekStart.adding(days: -7), settings: settings, lookBack: false) : [:]
        var formats: [Int: SectionFormat] = [:]
        for i in ranked {
            var options = allowed.filter { MetconCatalog.hasShape($0, in: window(i)) }
            // Peak weeks keep the heaviest day off a race.
            if phase == .peak && i == heaviest { options.removeAll { $0 == .forTime } }
            let fresh = options.filter { !formats.values.contains($0) }
            let pool = fresh.isEmpty ? options : fresh
            let sameWeekdayLastWeek = lastWeek[days[i].adding(days: -7)]?.format
            let weight = { (f: SectionFormat) in (MetconCatalog.formatWeights[f] ?? 1) * (f == sameWeekdayLastWeek ? 0.5 : 1) }
            // Stimulus first, then a format of it: two repeat days in a week
            // can still be AMRAP-with-rest and stations, so the yearly mix
            // stays close to §6.1 despite the no-repeat rule.
            let stimuli = MetconStimulus.allCases.filter { st in pool.contains { MetconStimulus(format: $0) == st } }
            let stimulus = stimuli.weightedPick(using: &rng) { st in
                let fs = st.formats.filter(pool.contains)
                let full = fs.reduce(0) { $0 + (MetconCatalog.formatWeights[$1] ?? 1) }
                return stimulusWeights(phase: phase)[st, default: 1] * (full > 0 ? fs.reduce(0) { $0 + weight($1) } / full : 1)
            }
            formats[i] = pool.filter { MetconStimulus(format: $0) == stimulus }.weightedPick(using: &rng, weight: weight) ?? .amrap
        }

        var out: [LocalDate: DayMetconPlan] = [:]
        for i in days.indices {
            out[days[i]] = DayMetconPlan(date: days[i], lift: lifts[i], phase: phase, window: window(i), format: formats[i]!,
                                         allowedFormats: allowed, isHeaviest: i == heaviest && days.count > 1,
                                         isPullDay: pullDays.contains(i),
                                         lightDay: lightWeek && i == days.count - 1 ? lightKind : nil,
                                         otherFormats: days.indices.filter { $0 != i }.map { formats[$0]! })
        }
        return out
    }
}
