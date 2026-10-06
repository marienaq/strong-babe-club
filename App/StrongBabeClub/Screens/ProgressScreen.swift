import Charts
import SwiftUI
import WorkoutCore

/// Progress: max weight / volume / benchmarks charts, block strip, goals.
/// (SbProgress.dc.html)
@MainActor
struct ProgressScreen: View {
    @Environment(AppStore.self) private var store
    /// Remembered chart tab (a UI preference; the only UserDefaults use, see PrivacyInfo.xcprivacy).
    @AppStorage("progress.mode") private var modeRaw: String = Mode.maxWeight.rawValue
    @State private var selectedLifts: Set<Lift> = [.frontSquat, .deadlift]
    @State private var showNewGoal = false

    enum Mode: String, CaseIterable { case maxWeight = "max weight", volume, benchmarks }

    var mode: Mode {
        get { Mode(rawValue: modeRaw) ?? .maxWeight }
        nonmutating set { modeRaw = newValue.rawValue }
    }

    static let liftColors: [Lift: Color] = [.frontSquat: Palette.tangerine, .deadlift: Palette.sky, .backSquat: Palette.mint,
                                            .pushPress: Palette.bubblegum, .pushJerk: Palette.sunny, .hangPowerClean: Palette.berry]

    var body: some View {
        JournalPage {
            Text("progress").bodyText(32, .heavy).padding(.top, 20).accessibilityAddTraits(.isHeader)
            HStack(spacing: 18) {
                ForEach(Mode.allCases, id: \.self) { m in
                    Button { mode = m } label: {
                        Text(m.rawValue).hand(22, color: mode == m ? Palette.ink : Palette.faint)
                            .overlay(alignment: .bottom) {
                                if mode == m { Squiggle().stroke(Palette.tangerine, style: StrokeStyle(lineWidth: 3, lineCap: .round)).frame(height: 8).offset(y: 6) }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(mode == m ? .isSelected : [])
                }
            }
            PaperCard(rotation: -0.6, tape: WashiTape(color: Palette.bubblegum, stripe: Palette.bubblegumLight, width: 60, angle: -4),
                      tapeAlignment: .topLeading, padding: EdgeInsets(top: 12, leading: 8, bottom: 6, trailing: 8)) {
                switch mode {
                case .maxWeight, .volume: liftChart
                case .benchmarks: benchmarkTable
                }
            }
            if mode != .benchmarks { liftChips }
            ForEach(store.plateCeilingWarnings(), id: \.lift) { w in
                Text(w.message).hand(18, color: Palette.berry)
            }
            blockStrip
            goals
        }
        .sheet(isPresented: $showNewGoal) { NewGoalSheet() }
    }

    var liftChart: some View {
        let since = store.today.adding(days: -200)
        let series = Lift.allCases.filter(selectedLifts.contains).map { lift in
            (lift, ProgressSeries.lift(lift, workouts: store.visibleWorkouts, since: since))
        }
        return Group {
            if series.allSatisfy({ $0.1.isEmpty }) {
                Text("Log a few strength days and your lines start drawing here.").hand(19, color: Palette.muted).frame(height: 184)
            } else {
                Chart {
                    ForEach(series, id: \.0) { lift, points in
                        ForEach(points, id: \.date) { p in
                            let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: p.date.year, month: p.date.month, day: p.date.day)) ?? .now
                            LineMark(x: .value("Date", date), y: .value(mode == .volume ? "Volume (lb)" : "Top set (lb)", mode == .volume ? p.volume : p.topWeight))
                                .foregroundStyle(by: .value("Lift", lift.displayName))
                                .lineStyle(StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                            PointMark(x: .value("Date", date), y: .value("lb", mode == .volume ? p.volume : p.topWeight))
                                .foregroundStyle(by: .value("Lift", lift.displayName))
                        }
                    }
                }
                .chartForegroundStyleScale(domain: series.map { $0.0.displayName }, range: series.map { Self.liftColors[$0.0] ?? Palette.ink })
                .chartLegend(.hidden)
                .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine(stroke: StrokeStyle(lineWidth: 1.5, dash: [4, 5])).foregroundStyle(Palette.dot); AxisValueLabel().font(Typeface.hand(15)) } }
                .chartXAxis { AxisMarks(values: .stride(by: .month, count: 2)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)).font(Typeface.hand(15)) } }
                .frame(height: 184)
                .accessibilityLabel(mode == .volume ? "Volume per session" : "Top set per session")
            }
        }
    }

    var liftChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(Lift.allCases, id: \.self) { lift in
                let on = selectedLifts.contains(lift)
                Button {
                    if on { selectedLifts.remove(lift) } else { selectedLifts.insert(lift) }
                } label: {
                    Text(lift.displayName).bodyText(13, on ? .heavy : .bold, color: on ? Palette.ink : Palette.muted)
                        .padding(.horizontal, 12).frame(height: 32)
                        .background(Capsule().fill(on ? (Self.liftColors[lift] ?? Palette.sky) : .clear))
                        .overlay(Capsule().strokeBorder(on ? .white : Palette.dashed, style: StrokeStyle(lineWidth: on ? 2.5 : 2, dash: on ? [] : [4, 3])))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    var benchmarkTable: some View {
        let rows = ProgressSeries.benchmarks(store.benchmarks, workouts: store.visibleWorkouts, calendar: store.calendar)
        let blocks = Array(Set(rows.flatMap { $0.byBlock.keys })).sorted().suffix(4)
        return VStack(alignment: .leading, spacing: 6) {
            if rows.isEmpty {
                Text("No benchmarks yet. Import your history or propose them in Settings.").hand(19, color: Palette.muted)
            } else {
                HStack {
                    Text("benchmark").frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(Array(blocks), id: \.self) { b in Text(b == 0 ? "pre" : "Q\(b)").frame(width: 56) }
                }
                .hand(17, color: Palette.muted)
                ForEach(rows, id: \.benchmark.id) { row in
                    HStack {
                        Text(row.benchmark.name).bodyText(13, .heavy).lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(Array(blocks), id: \.self) { b in
                            Text(row.byBlock[b].map { $0.score.description + ($0.modified ? "*" : "") } ?? "–").hand(18).frame(width: 56)
                        }
                    }
                }
                Text("* modified for a limit, not compared like for like").bodyText(11, .semibold, color: Palette.muted)
            }
        }
        .padding(6)
    }

    var blockStrip: some View {
        let pos = store.calendar.position(on: store.today)
        let strip = ProgressSeries.blockStrip()
        return PaperCard(rotation: 0.8, tape: WashiTape(color: Palette.sunny, stripe: Palette.sunnyLight, width: 60, angle: -2)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(pos.block == 0 ? "block 1" : "block \(pos.block)").hand(22)
                    Spacer()
                    Text(pos.block == 0 ? "test week \(store.calendar.testWeekStart.shortMonthName) \(store.calendar.testWeekStart.day) · starts \(store.calendar.block1Start.shortMonthName) \(store.calendar.block1Start.day)" : "week \(pos.week) · \(pos.phase.displayName)")
                        .bodyText(13, .bold, color: Palette.muted)
                }
                // Cell 0 is the test week before the block; cells 1-12 are block weeks 1-12.
                let currentIndex = (pos.block == 0 || pos.week == 13) ? 0 : pos.week
                HStack(spacing: 3) {
                    ForEach(Array(([BlockPhase.test] + strip.dropLast()).enumerated()), id: \.offset) { i, phase in
                        let current = i == currentIndex
                        RoundedRectangle(cornerRadius: 5).fill(color(phase))
                            .frame(height: 22)
                            .overlay { if i == 0 { Text("T").hand(13) } }
                            .overlay { if current { RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.ink, lineWidth: 2) } }
                    }
                }
                HStack {
                    ForEach(["test", "volume", "strength", "peak", "deload"], id: \.self) { Text($0); if $0 != "deload" { Spacer() } }
                }
                .hand(16, color: Palette.muted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Block \(max(pos.block, 1)), week \(pos.week), \(pos.phase.displayName) phase")
    }

    func color(_ p: BlockPhase) -> Color {
        switch p {
        case .test: return Palette.bubblegum
        case .volume, .preProgram: return Palette.sunnyPale
        case .strength: return Color(hex: 0xFFC9B5)
        case .peak: return Palette.tangerineLight
        case .deload: return Palette.mintPale
        }
    }

    var goals: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("goals").hand(24)
                Spacer()
                Button("+ new goal") { showNewGoal = true }.font(Typeface.hand(20)).foregroundStyle(Palette.berry)
            }
            if store.goals.isEmpty { Text("Set a goal, like Deadlift 200 lb by Jan 15.").hand(18, color: Palette.muted) }
            ForEach(store.goals) { g in
                let p = ProgressSeries.goal(g, workouts: store.visibleWorkouts)
                let color = Self.liftColors[g.lift] ?? Palette.sky
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(g.lift.displayName) \(formatPounds(g.targetWeight)) lb").bodyText(14, .heavy)
                        Spacer()
                        if let d = g.byDate { Text("by \(d.shortMonthName) \(d.day)").hand(18, color: Palette.muted) }
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 7).fill(color.opacity(0.2))
                            RoundedRectangle(cornerRadius: 7).fill(color).frame(width: geo.size.width * p.fraction)
                        }
                    }
                    .frame(height: 14)
                    .accessibilityLabel("\(Int(p.fraction * 100)) percent of the way")
                }
                .contextMenu { Button("Remove goal", role: .destructive) { store.removeGoal(g.id) } }
            }
        }
    }
}

@MainActor
struct NewGoalSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var lift: Lift = .deadlift
    @State private var weight = 200.0
    @State private var hasDate = true
    @State private var date = Date().addingTimeInterval(90 * 86_400)

    var body: some View {
        NavigationStack {
            Form {
                Picker("Lift", selection: $lift) { ForEach(Lift.allCases, id: \.self) { Text($0.displayName).tag($0) } }
                Stepper("\(formatPounds(weight)) lb", value: $weight, in: 45...500, step: 5)
                Toggle("Target date", isOn: $hasDate)
                if hasDate { DatePicker("By", selection: $date, displayedComponents: .date) }
            }
            .navigationTitle("New goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.addGoal(Goal(lift: lift, targetWeight: weight, byDate: hasDate ? LocalDate.today(date) : nil))
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Simple wrapping layout for the lift chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
