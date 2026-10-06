import Charts
import SwiftUI
import WorkoutCore

/// LocalDate -> Date at local noon (stable across time zones / DST).
func chartDate(_ d: LocalDate) -> Date {
    Calendar(identifier: .gregorian).date(from: DateComponents(year: d.year, month: d.month, day: d.day, hour: 12)) ?? .now
}

private func monthLabel(_ d: LocalDate, withYear: Bool) -> String {
    withYear || d.month == 1 ? "\(d.shortMonthName) ’\(String(d.year).suffix(2))" : d.shortMonthName
}

/// Scrollable timeline of one lift: the last 3M / 6M / 1Y on screen
/// (swipe back through everything), or All at once. Gaps over ~3 weeks
/// break the line. The latest session is a sticker with a note.
@MainActor
struct LiftTimelineChart: View {
    let points: [ChartPoint]
    let metric: ChartMetric
    let range: ChartRange
    let color: Color
    @State private var scrollX: Date

    private let full: ClosedRange<LocalDate>
    private let visible: ClosedRange<LocalDate>
    private let ticks: [LocalDate]
    private let tickYears: Bool

    init(points: [ChartPoint], metric: ChartMetric, range: ChartRange, color: Color) {
        self.points = points
        self.metric = metric
        self.range = range
        self.color = color
        let visible = ProgressChart.visibleDomain(range, points: points) ?? LocalDate(2026, 1, 1)...LocalDate(2026, 1, 2)
        let full = ProgressChart.fullDomain(range, points: points) ?? visible
        self.visible = visible
        self.full = full
        let step = ProgressChart.tickMonths(range, spanDays: visible.lowerBound.days(until: visible.upperBound))
        self.ticks = ProgressChart.ticks(in: full, latest: points.last?.date ?? visible.upperBound, everyMonths: step)
        self.tickYears = step >= 3
        _scrollX = State(initialValue: chartDate(visible.lowerBound))
    }

    var visibleSeconds: TimeInterval {
        TimeInterval(visible.lowerBound.days(until: visible.upperBound)) * 86_400
    }

    /// Y fits what's on screen (snapped to round numbers, so it moves rarely).
    var yDomain: ClosedRange<Double> {
        let start = LocalDate.today(scrollX)
        let window = start...start.adding(days: visible.lowerBound.days(until: visible.upperBound))
        let shown = ProgressChart.points(points, in: range == .all ? full : window).map(\.value)
        return ProgressChart.yDomain(shown.isEmpty ? points.map(\.value) : shown)
    }

    var body: some View {
        let latest = points.last
        let yDomain = self.yDomain
        let yTicks = ProgressChart.yTicks(yDomain)
        Chart {
            // Gridlines live inside the plot so they scroll with it.
            ForEach(yTicks, id: \.self) { v in
                RuleMark(y: .value("grid", v))
                    .foregroundStyle(Palette.dot)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 5]))
            }
            ForEach(points, id: \.date) { p in
                LineMark(x: .value("Date", chartDate(p.date)), y: .value(metric == .volume ? "Volume" : "Top set", p.value),
                         series: .value("Stretch", p.segment))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                PointMark(x: .value("Date", chartDate(p.date)), y: .value("lb", p.value))
                    .foregroundStyle(color)
                    .symbolSize(range == .all ? 16 : 36)
            }
            if let latest {
                PointMark(x: .value("Date", chartDate(latest.date)), y: .value("lb", latest.value))
                    .foregroundStyle(.white)
                    .symbolSize(260)
                PointMark(x: .value("Date", chartDate(latest.date)), y: .value("lb", latest.value))
                    .foregroundStyle(color)
                    .symbolSize(120)
                    // .overlay reserves no layout space in the scrolling plot; lift it by hand.
                    .annotation(position: .overlay, alignment: .bottomTrailing) {
                        LatestNote(text: ProgressChart.annotation(latest, metric: metric))
                            .offset(x: 6, y: -16)
                    }
            }
        }
        .chartXScale(domain: chartDate(full.lowerBound)...chartDate(full.upperBound))
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: ticks.map(chartDate)) { value in
                let d = value.as(Date.self).map { LocalDate.today($0) }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 5])).foregroundStyle(Palette.dot)
                // The newest month sits near the right edge: label it to the left of its tick.
                AxisValueLabel(anchor: d == ticks.last ? .topTrailing : .top, collisionResolution: .disabled) {
                    if let d {
                        Text(monthLabel(d, withYear: tickYears)).font(Typeface.hand(15)).foregroundStyle(Palette.muted)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: yTicks) { _ in
                AxisValueLabel().font(Typeface.hand(15))
            }
        }
        .chartScrollableAxes(range == .all ? [] : .horizontal)
        // Keep the page's scroll content margins out of the chart's own scroll view.
        .contentMargins(0, for: .scrollContent)
        .chartXVisibleDomain(length: range == .all ? TimeInterval(full.lowerBound.days(until: full.upperBound)) * 86_400 : visibleSeconds)
        .chartScrollPosition(x: $scrollX)
        .accessibilityIdentifier("chart-timeline")
        .accessibilityLabel("\(metric == .volume ? "Volume" : "Top set") per session, \(range.label) view")
        .accessibilityValue(latest.map { "latest \(ProgressChart.annotation($0, metric: metric))" } ?? "")
    }
}

/// "this year vs last year": each calendar year as its own line on Jan-Dec.
@MainActor
struct YearOverlayChart: View {
    let years: [YearSeries]
    let metric: ChartMetric

    static let colors: [Color] = [Palette.tangerine, Palette.sky, Palette.mint, Palette.bubblegum]

    /// Newest year gets tangerine; older years step through the palette.
    func color(_ year: Int) -> Color {
        let rank = (years.map(\.year).sorted(by: >).firstIndex(of: year)) ?? 0
        return Self.colors[rank % Self.colors.count]
    }

    var body: some View {
        let ref = ProgressChart.referenceYear
        let newest = years.last
        VStack(alignment: .leading, spacing: 4) {
            Chart {
                ForEach(years, id: \.year) { y in
                    ForEach(y.points, id: \.date) { p in
                        LineMark(x: .value("Day", chartDate(p.date)), y: .value("lb", p.value),
                                 series: .value("Year", "\(y.year)-\(p.segment)"))
                            .foregroundStyle(color(y.year))
                            .lineStyle(StrokeStyle(lineWidth: y.year == newest?.year ? 3.5 : 2.5, lineCap: .round, lineJoin: .round))
                        PointMark(x: .value("Day", chartDate(p.date)), y: .value("lb", p.value))
                            .foregroundStyle(color(y.year))
                            .symbolSize(18)
                    }
                }
                if let y = newest, let last = y.points.last {
                    PointMark(x: .value("Day", chartDate(last.date)), y: .value("lb", last.value))
                        .foregroundStyle(.white).symbolSize(260)
                    PointMark(x: .value("Day", chartDate(last.date)), y: .value("lb", last.value))
                        .foregroundStyle(color(y.year)).symbolSize(120)
                        .annotation(position: .top, alignment: .trailing, spacing: 6,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            LatestNote(text: ProgressChart.annotation(last, metric: metric, date: LocalDate(y.year, last.date.month, last.date.day)))
                        }
                }
            }
            .chartXScale(domain: chartDate(LocalDate(ref, 1, 1))...chartDate(LocalDate(ref, 12, 31)))
            .chartYScale(domain: ProgressChart.yDomain(years.flatMap { $0.points.map(\.value) }))
            .chartXAxis {
                AxisMarks(values: stride(from: 1, through: 11, by: 2).map { chartDate(LocalDate(ref, $0, 1)) }) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 5])).foregroundStyle(Palette.dot)
                    AxisValueLabel {
                        if let d = value.as(Date.self) { Text(LocalDate.today(d).shortMonthName).font(Typeface.hand(15)).foregroundStyle(Palette.muted) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: ProgressChart.yTicks(ProgressChart.yDomain(years.flatMap { $0.points.map(\.value) }))) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1.5, dash: [4, 5])).foregroundStyle(Palette.dot)
                    AxisValueLabel().font(Typeface.hand(15))
                }
            }
            .accessibilityIdentifier("chart-years")
            .accessibilityLabel("\(metric == .volume ? "Volume" : "Top set") by calendar year")

            HStack(spacing: 6) {
                ForEach(Array(years.enumerated()), id: \.element.year) { i, y in
                    if i > 0 { Text("·").hand(17, color: Palette.muted) }
                    HStack(spacing: 4) {
                        Circle().fill(color(y.year)).frame(width: 9, height: 9)
                        Text(String(y.year)).hand(18, color: Palette.ink)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("legend-\(y.year)")
                }
            }
            .padding(.leading, 28)
        }
    }
}

/// Handwritten note on a little white sticker for the latest point.
struct LatestNote: View {
    var text: String
    var body: some View {
        Text(text)
            .hand(16, color: Palette.ink)
            .padding(.horizontal, 7).padding(.vertical, 1)
            .background(Capsule().fill(.white))
            .overlay(Capsule().strokeBorder(Palette.sunny, lineWidth: 2))
            .rotationEffect(.degrees(-4))
            .stickerShadow()
            .fixedSize()
    }
}

/// 3M · 6M · 1Y · All, plus the year-vs-year toggle, as stickers.
@MainActor
struct ChartRangeControls: View {
    @Binding var range: ChartRange
    @Binding var byYear: Bool

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(ChartRange.allCases.enumerated()), id: \.element) { i, r in
                let on = !byYear && r == range
                Button {
                    byYear = false
                    range = r
                    Haptics.play(.tap)
                } label: {
                    Text.caveat(r.label).hand(19, color: on ? Palette.ink : Palette.muted)
                        .fixedSize()
                        .padding(.horizontal, 11)
                        .frame(minWidth: 40, minHeight: 32)
                        .background(Capsule().fill(on ? Palette.sunny : .white.opacity(0.6)))
                        .overlay(Capsule().strokeBorder(on ? .white : Palette.dashed, style: StrokeStyle(lineWidth: on ? 2.5 : 1.5, dash: on ? [] : [3, 3])))
                        .rotationEffect(.degrees(on ? [-4, 3, -3, 4][i] : 0))
                        .shadow(color: on ? Palette.ink.opacity(0.2) : .clear, radius: 2, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(r.label)")
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("range-\(r.label)")
            }
            Spacer(minLength: 4)
            Button {
                byYear.toggle()
                Haptics.play(.tap)
            } label: {
                Text.caveat("this year vs last").hand(18, color: byYear ? Palette.ink : Palette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 10).frame(minHeight: 32)
                    .background(Capsule().fill(byYear ? Palette.mint : .white.opacity(0.6)))
                    .overlay(Capsule().strokeBorder(byYear ? .white : Palette.dashed, style: StrokeStyle(lineWidth: byYear ? 2.5 : 1.5, dash: byYear ? [] : [3, 3])))
                    .rotationEffect(.degrees(byYear ? 3 : 0))
                    .shadow(color: byYear ? Palette.ink.opacity(0.2) : .clear, radius: 2, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("This year versus last year")
            .accessibilityAddTraits(byYear ? .isSelected : [])
            .accessibilityIdentifier("yearToggle")
        }
    }
}

