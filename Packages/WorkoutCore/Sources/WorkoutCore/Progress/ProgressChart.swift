import Foundation

/// Visible window of the progress timeline.
public enum ChartRange: String, CaseIterable, Sendable {
    case threeMonths = "3M", sixMonths = "6M", oneYear = "1Y", all = "All"

    /// Visible length in days; nil = everything.
    public var days: Int? {
        switch self {
        case .threeMonths: return 92
        case .sixMonths: return 183
        case .oneYear: return 366
        case .all: return nil
        }
    }

    public var label: String { rawValue }
}

public enum ChartMetric: String, Sendable {
    case topSet, volume
}

/// One plotted point. Points with the same `segment` are joined by a line;
/// a new segment starts after a gap (so breaks aren't drawn across).
public struct ChartPoint: Hashable, Sendable {
    public var date: LocalDate
    public var value: Double
    public var segment: Int
}

/// One calendar year of a lift, for "this year vs last year".
public struct YearSeries: Hashable, Sendable {
    public var year: Int
    /// `date` is mapped into the reference leap year (`ProgressChart.referenceYear`)
    /// so every year shares a Jan-Dec axis.
    public var points: [ChartPoint]
}

/// Pure chart logic behind the Progress screen (domains, ticks, gaps, years).
public enum ProgressChart {
    /// Sessions further apart than this are not joined by a line.
    public static let maxGapDays = 21
    /// A leap year so Feb 29 always fits.
    public static let referenceYear = 2000

    public static func value(_ p: LiftPoint, _ metric: ChartMetric) -> Double {
        metric == .volume ? p.volume : p.topWeight
    }

    /// Date-sorted points, split into segments at gaps longer than `maxGap`.
    public static func segmented(_ points: [LiftPoint], metric: ChartMetric, maxGap: Int = maxGapDays) -> [ChartPoint] {
        var out: [ChartPoint] = []
        var segment = 0
        var previous: LocalDate?
        for p in points.sorted(by: { $0.date < $1.date }) {
            if let prev = previous, prev.days(until: p.date) > maxGap { segment += 1 }
            out.append(ChartPoint(date: p.date, value: value(p, metric), segment: segment))
            previous = p.date
        }
        return out
    }

    /// The x-range shown for a range chip, ending a few days after the
    /// latest point (room for the highlighted marker). `All` spans everything.
    public static func visibleDomain(_ range: ChartRange, points: [ChartPoint], padDays: Int = 7) -> ClosedRange<LocalDate>? {
        guard let first = points.first?.date, let last = points.last?.date else { return nil }
        let end = last.adding(days: padDays)
        guard let days = range.days else { return first.adding(days: -padDays)...end }
        return end.adding(days: -days)...end
    }

    /// Full scrollable x-range: all data, padded, and at least one window wide.
    public static func fullDomain(_ range: ChartRange, points: [ChartPoint], padDays: Int = 7) -> ClosedRange<LocalDate>? {
        guard let visible = visibleDomain(range, points: points, padDays: padDays), let first = points.first?.date else { return nil }
        return min(first.adding(days: -padDays), visible.lowerBound)...visible.upperBound
    }

    /// Month step between axis labels: monthly at 3M/6M, quarterly at 1Y,
    /// half-yearly or yearly at All depending on the span.
    public static func tickMonths(_ range: ChartRange, spanDays: Int) -> Int {
        switch range {
        case .threeMonths, .sixMonths: return 1
        case .oneYear: return 3
        case .all: return spanDays > 3 * 365 ? 12 : spanDays > 400 ? 6 : spanDays > 180 ? 3 : 1
        }
    }

    /// Axis ticks (first of the month), counted back from the latest month so
    /// the newest month is always labelled.
    public static func ticks(in domain: ClosedRange<LocalDate>, latest: LocalDate, everyMonths step: Int) -> [LocalDate] {
        var out: [LocalDate] = []
        var t = latest.startOfMonth
        if t > domain.upperBound { t = domain.upperBound.startOfMonth }
        while t >= domain.lowerBound {
            out.append(t)
            t = t.adding(months: -max(1, step))
        }
        return out.reversed()
    }

    /// A tidy y-range around the values: padded, snapped to a round step,
    /// never below zero. Stable across small changes in the visible data.
    public static func yDomain(_ values: [Double]) -> ClosedRange<Double> {
        guard let lo = values.min(), let hi = values.max() else { return 0...100 }
        let span = max(hi - lo, 1)
        let step: Double = span > 2000 ? 500 : span > 400 ? 100 : span > 120 ? 25 : 10
        let lower = max(0, ((lo - span * 0.15) / step).rounded(.down) * step)
        // Extra headroom on top for the latest-point note.
        var upper = ((hi + span * 0.3) / step).rounded(.up) * step
        if upper <= lower { upper = lower + step }
        return lower...upper
    }

    /// 3-6 round y-axis values inside a domain (explicit, so the axis and the
    /// marks always share one scale, even while scrolling).
    public static func yTicks(_ domain: ClosedRange<Double>) -> [Double] {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else { return [domain.lowerBound] }
        let candidates: [Double] = [5, 10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000, 2500, 5000]
        let step = candidates.first { span / $0 <= 5 } ?? span / 4
        var out: [Double] = []
        var v = (domain.lowerBound / step).rounded(.up) * step
        while v <= domain.upperBound + 0.0001 {
            out.append(v)
            v += step
        }
        return out
    }

    public static func points(_ points: [ChartPoint], in domain: ClosedRange<LocalDate>) -> [ChartPoint] {
        points.filter { domain.contains($0.date) }
    }

    /// Splits sessions by calendar year onto a shared Jan-Dec axis, newest
    /// year last. Gaps inside a year still break the line.
    public static func byYear(_ points: [LiftPoint], metric: ChartMetric, maxGap: Int = maxGapDays, lastYears: Int = 4) -> [YearSeries] {
        let years = Dictionary(grouping: points) { $0.date.year }
        return years.keys.sorted().suffix(lastYears).map { year in
            let seg = segmented(years[year]!, metric: metric, maxGap: maxGap).map { p in
                ChartPoint(date: reference(p.date), value: p.value, segment: p.segment)
            }
            return YearSeries(year: year, points: seg)
        }
    }

    /// Same month/day in the reference year.
    public static func reference(_ d: LocalDate) -> LocalDate { LocalDate(referenceYear, d.month, d.day) }

    /// "120 · Oct 5" / "2,925 · Oct 5"
    public static func annotation(_ p: ChartPoint, metric: ChartMetric, date: LocalDate? = nil) -> String {
        let d = date ?? p.date
        let v = metric == .volume ? p.value.formatted(.number.grouping(.automatic).precision(.fractionLength(0))) : formatPounds(p.value)
        return "\(v) · \(d.shortMonthName) \(d.day)"
    }
}
