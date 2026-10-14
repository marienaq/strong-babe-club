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
            formats[i] = pool.weightedPick(using: &rng) { f in
                (MetconCatalog.formatWeights[f] ?? 1) * (f == sameWeekdayLastWeek ? 0.5 : 1)
            } ?? .amrap
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
