import XCTest
@testable import WorkoutCore

final class ProgressChartTests: XCTestCase {
    func lp(_ y: Int, _ m: Int, _ d: Int, _ w: Double, volume: Double? = nil) -> LiftPoint {
        LiftPoint(date: LocalDate(y, m, d), topWeight: w, volume: volume ?? w * 25)
    }

    /// ~2.5 years of fortnightly sessions with a summer break in 2026.
    var history: [LiftPoint] {
        var out: [LiftPoint] = []
        var d = LocalDate(2024, 5, 31)
        var w = 60.0
        while d <= LocalDate(2026, 10, 5) {
            let summerBreak = d >= LocalDate(2026, 6, 15) && d < LocalDate(2026, 8, 10)
            if !summerBreak { out.append(LiftPoint(date: d, topWeight: w, volume: w * 25)) }
            w = min(w + 2.5, 125)
            d = d.adding(days: 14)
        }
        out.append(lp(2026, 10, 5, 120))
        return out
    }

    func testDateHelpers() {
        XCTAssertEqual(LocalDate(2026, 10, 5).startOfMonth, LocalDate(2026, 10, 1))
        XCTAssertEqual(LocalDate(2026, 1, 31).adding(months: 1), LocalDate(2026, 2, 28))
        XCTAssertEqual(LocalDate(2026, 1, 15).adding(months: -2), LocalDate(2025, 11, 15))
        XCTAssertEqual(LocalDate(2026, 12, 15).adding(months: 13), LocalDate(2028, 1, 15))
        XCTAssertEqual(LocalDate(2026, 1, 1).dayOfYear, 1)
        XCTAssertEqual(LocalDate(2024, 12, 31).dayOfYear, 366)
    }

    func testGapSplitsSegments() {
        let pts = [lp(2026, 5, 1, 100), lp(2026, 5, 15, 105), lp(2026, 6, 5, 110), // 21 days: same line
                   lp(2026, 8, 10, 80), lp(2026, 8, 24, 90)] // 66-day gap: new line
        let seg = ProgressChart.segmented(pts.shuffled(), metric: .topSet)
        XCTAssertEqual(seg.map(\.date), pts.map(\.date), "sorted by date")
        XCTAssertEqual(seg.map(\.segment), [0, 0, 0, 1, 1])
        XCTAssertEqual(ProgressChart.segmented([lp(2026, 5, 1, 1), lp(2026, 5, 23, 1)], metric: .topSet).map(\.segment), [0, 1])
        XCTAssertEqual(ProgressChart.segmented(pts, metric: .volume).first?.value, 2500)
        XCTAssertTrue(ProgressChart.segmented([], metric: .topSet).isEmpty)
    }

    func testVisibleDomainEndsAtLatestData() throws {
        let seg = ProgressChart.segmented(history, metric: .topSet)
        let last = try XCTUnwrap(seg.last?.date)
        XCTAssertEqual(last, LocalDate(2026, 10, 5))
        for range in ChartRange.allCases {
            let d = try XCTUnwrap(ProgressChart.visibleDomain(range, points: seg))
            XCTAssertTrue(d.contains(last), range.rawValue)
            XCTAssertEqual(d.upperBound, LocalDate(2026, 10, 12))
            if let days = range.days { XCTAssertEqual(d.lowerBound.days(until: d.upperBound), days) }
        }
        let all = try XCTUnwrap(ProgressChart.visibleDomain(.all, points: seg))
        XCTAssertEqual(all.lowerBound, LocalDate(2024, 5, 24))
        let full = try XCTUnwrap(ProgressChart.fullDomain(.threeMonths, points: seg))
        XCTAssertEqual(full, all, "scrolling reaches all the way back")
        // Short history: the full domain is still at least one window wide.
        let short = ProgressChart.segmented([lp(2026, 10, 1, 100)], metric: .topSet)
        let shortFull = try XCTUnwrap(ProgressChart.fullDomain(.oneYear, points: short))
        XCTAssertEqual(shortFull.lowerBound.days(until: shortFull.upperBound), 366)
        XCTAssertNil(ProgressChart.visibleDomain(.all, points: []))
    }

    /// Regression: with ~2.5 years of data the last label read "Jun 26" and
    /// the line looked like it stopped there.
    func testTicksAlwaysIncludeLatestMonth() throws {
        let seg = ProgressChart.segmented(history, metric: .topSet)
        let latest = seg.last!.date
        for range in ChartRange.allCases {
            let domain = try XCTUnwrap(ProgressChart.visibleDomain(range, points: seg))
            let step = ProgressChart.tickMonths(range, spanDays: domain.lowerBound.days(until: domain.upperBound))
            let ticks = ProgressChart.ticks(in: domain, latest: latest, everyMonths: step)
            XCTAssertEqual(ticks.last, LocalDate(2026, 10, 1), range.rawValue)
            XCTAssertTrue(ticks.allSatisfy { domain.contains($0) && $0.day == 1 })
            XCTAssertEqual(ticks, ticks.sorted())
            XCTAssertLessThanOrEqual(ticks.count, 7, "\(range.rawValue): \(ticks)")
        }
        XCTAssertEqual(ProgressChart.tickMonths(.threeMonths, spanDays: 92), 1)
        XCTAssertEqual(ProgressChart.tickMonths(.oneYear, spanDays: 366), 3)
        XCTAssertEqual(ProgressChart.tickMonths(.all, spanDays: 870), 6)
        XCTAssertEqual(ProgressChart.tickMonths(.all, spanDays: 1500), 12)
        let all = ProgressChart.ticks(in: LocalDate(2024, 5, 24)...LocalDate(2026, 10, 12), latest: latest, everyMonths: 6)
        XCTAssertEqual(all, [LocalDate(2024, 10, 1), LocalDate(2025, 4, 1), LocalDate(2025, 10, 1), LocalDate(2026, 4, 1), LocalDate(2026, 10, 1)])
    }

    func testYDomain() {
        let d = ProgressChart.yDomain([100, 105, 120])
        XCTAssertLessThanOrEqual(d.lowerBound, 100)
        XCTAssertGreaterThanOrEqual(d.upperBound, 120)
        XCTAssertEqual(d.lowerBound.truncatingRemainder(dividingBy: 10), 0)
        XCTAssertEqual(d.upperBound.truncatingRemainder(dividingBy: 10), 0)
        XCTAssertGreaterThan(d.lowerBound, 0, "tight around the data, not from zero")
        XCTAssertEqual(ProgressChart.yDomain([5, 8]).lowerBound, 0, "never negative")
        XCTAssertEqual(ProgressChart.yDomain([]), 0...100)
        let flat = ProgressChart.yDomain([135, 135])
        XCTAssertTrue(flat.contains(135) && flat.upperBound > flat.lowerBound)
        let volume = ProgressChart.yDomain([1500, 2925, 4100])
        XCTAssertEqual(volume.lowerBound.truncatingRemainder(dividingBy: 100), 0)
    }

    func testYTicksAreRoundAndInside() {
        XCTAssertEqual(ProgressChart.yTicks(60...130), [60, 80, 100, 120])
        XCTAssertEqual(ProgressChart.yTicks(50...175), [50, 75, 100, 125, 150, 175])
        for d in [ProgressChart.yDomain([100, 120]), ProgressChart.yDomain([1500, 4100]), ProgressChart.yDomain([45, 230])] {
            let t = ProgressChart.yTicks(d)
            XCTAssertTrue((2...6).contains(t.count), "\(d) \(t)")
            XCTAssertTrue(t.allSatisfy { d.contains($0) })
        }
        XCTAssertEqual(ProgressChart.yTicks(5...5), [5])
    }

    func testByYearSplitsCalendarYearsOnSharedAxis() throws {
        let years = ProgressChart.byYear(history, metric: .topSet)
        XCTAssertEqual(years.map(\.year), [2024, 2025, 2026])
        for y in years {
            XCTAssertTrue(y.points.allSatisfy { $0.date.year == ProgressChart.referenceYear })
            XCTAssertEqual(y.points.map(\.date), y.points.map(\.date).sorted())
        }
        let y2026 = try XCTUnwrap(years.last)
        XCTAssertEqual(y2026.points.last?.date, LocalDate(2000, 10, 5))
        // The 2026 summer break splits that year's line; 2025 is continuous.
        XCTAssertEqual(Set(y2026.points.map(\.segment)).count, 2)
        XCTAssertEqual(Set(years[1].points.map(\.segment)).count, 1)
        // No line joins Dec 31 to Jan 1 of the next year: years are separate series.
        XCTAssertEqual(history.count, years.reduce(0) { $0 + $1.points.count })
        XCTAssertEqual(ProgressChart.byYear(history, metric: .topSet, lastYears: 2).map(\.year), [2025, 2026])
        XCTAssertEqual(ProgressChart.reference(LocalDate(2024, 2, 29)), LocalDate(2000, 2, 29))
    }

    func testAnnotation() {
        let p = ChartPoint(date: LocalDate(2026, 10, 5), value: 120, segment: 0)
        XCTAssertEqual(ProgressChart.annotation(p, metric: .topSet), "120 · Oct 5")
        XCTAssertEqual(ProgressChart.annotation(ChartPoint(date: LocalDate(2026, 10, 5), value: 2925, segment: 0), metric: .volume), "2,925 · Oct 5")
    }
}
