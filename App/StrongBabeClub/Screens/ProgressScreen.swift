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
    /// Single-select: one lift on the chart at a time.
    @AppStorage("progress.lift") private var liftRaw: String = ""
    /// Last chosen range chip (3M / 6M / 1Y / All) and the year-vs-year toggle.
    @AppStorage("progress.range") private var rangeRaw: String = ChartRange.threeMonths.rawValue
    @AppStorage("progress.byYear") private var byYear = false
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
                        Text.caveat(m.rawValue).hand(22, color: mode == m ? Palette.ink : Palette.faint)
                            .overlay(alignment: .bottom) {
                                if mode == m { Squiggle().stroke(Palette.tangerine, style: StrokeStyle(lineWidth: 3, lineCap: .round)).frame(height: 8).offset(y: 6) }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(mode == m ? .isSelected : [])
                }
            }
            // No card tilt here: rotating a horizontally scrolling chart skews the plot against its axis.
            PaperCard(rotation: 0, tape: WashiTape(color: Palette.bubblegum, stripe: Palette.bubblegumLight, width: 60, angle: -4),
                      tapeAlignment: .topLeading, padding: EdgeInsets(top: 12, leading: 8, bottom: 6, trailing: 8)) {
                switch mode {
                case .maxWeight, .volume: liftChart
                case .benchmarks: benchmarkTable
                }
            }
            if mode != .benchmarks {
                ChartRangeControls(range: Binding(get: { ChartRange(rawValue: rangeRaw) ?? .threeMonths }, set: { rangeRaw = $0.rawValue }),
                                   byYear: $byYear)
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

    /// The chosen lift, else the most recently logged one, else Front Squat.
    var selectedLift: Lift {
        if let l = Lift(rawValue: liftRaw) { return l }
        let latest = Lift.allCases.compactMap { lift in
            ProgressSeries.lift(lift, workouts: store.visibleWorkouts).last.map { (lift, $0.date) }
        }.max { $0.1 < $1.1 }
        return latest?.0 ?? .frontSquat
    }

    var liftChart: some View {
        // Full history: every session's top set (imported and logged in the app).
        let lift = selectedLift
        let metric: ChartMetric = mode == .volume ? .volume : .topSet
        let factor = store.unit.fromPounds(1)
        let sessions = ProgressSeries.lift(lift, workouts: store.visibleWorkouts)
            .map { LiftPoint(date: $0.date, topWeight: $0.topWeight * factor, volume: $0.volume * factor) }
        let range = ChartRange(rawValue: rangeRaw) ?? .threeMonths
        let color = Self.liftColors[lift] ?? Palette.tangerine
        return Group {
            if sessions.isEmpty {
                Text("No \(lift.displayName.lowercased()) sets logged yet. Check off your sets and the line starts drawing here.")
                    .hand(19, color: Palette.muted).frame(maxWidth: .infinity, minHeight: 210)
            } else if byYear {
                YearOverlayChart(years: ProgressChart.byYear(sessions, metric: metric), metric: metric)
                    .frame(height: 230)
            } else {
                LiftTimelineChart(points: ProgressChart.segmented(sessions, metric: metric), metric: metric, range: range, color: color)
                    .id("\(lift.rawValue)-\(metric.rawValue)-\(range.rawValue)")
                    .frame(height: 210)
            }
        }
        .padding(.top, 14)
    }

    var liftChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(Lift.allCases, id: \.self) { lift in
                let on = selectedLift == lift
                Button {
                    liftRaw = lift.rawValue
                } label: {
                    Text(lift.displayName).bodyText(13, on ? .heavy : .bold, color: on ? Palette.ink : Palette.muted)
                        .padding(.horizontal, 12).frame(height: 32)
                        .background(Capsule().fill(on ? (Self.liftColors[lift] ?? Palette.sky) : .clear))
                        .overlay(Capsule().strokeBorder(on ? .white : Palette.dashed, style: StrokeStyle(lineWidth: on ? 2.5 : 2, dash: on ? [] : [4, 3])))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("chip-\(lift.rawValue)")
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

    /// 14 cells: 12 training weeks + 2 test weeks.
    var blockStrip: some View {
        let cal = store.calendar
        let pos = cal.position(on: store.today)
        let strip = ProgressSeries.blockStrip()
        let title = pos.block == 0 ? (pos.phase == .test ? "test weeks" : "block 1") : "block \(pos.block)"
        let detail: String = {
            switch (pos.block, pos.phase) {
            case (0, .preProgram):
                return cal.initialTestWeeks > 0
                    ? "test weeks from \(cal.testWeekStart.shortMonthName) \(cal.testWeekStart.day) · block 1 \(cal.block1Start.shortMonthName) \(cal.block1Start.day)"
                    : "starts \(cal.block1Start.shortDisplay)"
            case (0, _): return "test week \(pos.week - 12) of 2 · block 1 \(cal.block1Start.shortMonthName) \(cal.block1Start.day)"
            default: return "week \(pos.week) of 14 · \(pos.phase.displayName)"
            }
        }()
        let currentIndex: Int? = pos.block >= 1 ? pos.week - 1 : nil
        return PaperCard(rotation: 0.8, tape: WashiTape(color: Palette.sunny, stripe: Palette.sunnyLight, width: 60, angle: -2)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text.caveat(title).hand(22)
                    Spacer()
                    Text(detail).bodyText(13, .bold, color: Palette.muted).lineLimit(1).minimumScaleFactor(0.8)
                }
                HStack(spacing: 3) {
                    ForEach(Array(strip.enumerated()), id: \.offset) { i, phase in
                        RoundedRectangle(cornerRadius: 5).fill(color(phase))
                            .frame(height: 22)
                            .overlay { if phase == .test { Text("T").hand(13) } }
                            .overlay { if i == currentIndex { RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.ink, lineWidth: 2) } }
                    }
                }
                HStack {
                    ForEach(["volume", "strength", "peak", "deload", "test"], id: \.self) { Text($0); if $0 != "test" { Spacer() } }
                }
                .hand(16, color: Palette.muted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(pos.block >= 1 ? "Block \(pos.block), week \(pos.week) of 14, \(pos.phase.displayName) phase" : "\(title), \(detail)")
        .accessibilityIdentifier("blockStrip")
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
                Button { showNewGoal = true } label: { Text.caveat("+ new goal").hand(20, color: Palette.berry) }
            }
            if store.goals.isEmpty { Text("Set a goal, like Deadlift \(store.unit == .kg ? "90 kg" : "200 lb") by Jan 15.").hand(18, color: Palette.muted) }
            ForEach(store.goals) { g in
                let p = ProgressSeries.goal(g, workouts: store.visibleWorkouts)
                let color = Self.liftColors[g.lift] ?? Palette.sky
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(g.lift.displayName) \(store.label(g.targetWeight))").bodyText(14, .heavy)
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
    /// In the display unit.
    @State private var weight: Double?
    @State private var hasDate = true
    @State private var date = Date().addingTimeInterval(90 * 86_400)

    var body: some View {
        let unit = store.unit
        let value = weight ?? (unit == .kg ? 90 : 200)
        NavigationStack {
            Form {
                Picker("Lift", selection: $lift) { ForEach(Lift.allCases, id: \.self) { Text($0.displayName).tag($0) } }
                Stepper("\(formatWeight(value)) \(unit.symbol)", value: Binding(get: { value }, set: { weight = $0 }),
                        in: unit == .kg ? 20...250 : 45...550, step: unit.roundingStep)
                Toggle("Target date", isOn: $hasDate)
                if hasDate { DatePicker("By", selection: $date, displayedComponents: .date) }
            }
            .navigationTitle("New goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.addGoal(Goal(lift: lift, targetWeight: unit.toPounds(value), byDate: hasDate ? LocalDate.today(date) : nil))
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
