import SwiftUI
import WorkoutCore

// MARK: - History panel

/// Collapsible "view history" list; renders nothing when there's no history.
@MainActor
struct HistoryPanel: View {
    struct Row: Identifiable {
        var id: String
        var date: String
        var title: String?
        var detail: String
    }

    var rows: [Row]
    var tint: Color
    @State private var expanded = DebugRoute.expandHistory

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .heavy))
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                        Text(expanded ? "hide history" : "view history").hand(21)
                        Text("· last \(rows.count)").hand(18, color: Palette.muted)
                        Spacer()
                    }
                    .foregroundStyle(tint)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("viewHistory")
                .accessibilityLabel(expanded ? "Hide history" : "View history, last \(rows.count) sessions")
                if expanded {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(row.date).hand(19)
                                if let title = row.title { Text(title).bodyText(12, .bold, color: Palette.muted).lineLimit(1) }
                            }
                            Text(row.detail).bodyText(14, .semibold, color: Palette.note)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.85)))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

// MARK: - Strength

@MainActor
struct StrengthSectionView: View {
    var workout: PlannedWorkout
    var section: WorkoutSection
    @Environment(AppStore.self) private var store
    @State private var timer: IntervalTimerModel?
    @State private var weights: [String: String] = [:]
    @FocusState private var focused: String?

    var calc: PlateCalculator { PlateCalculator(inventory: store.settings.equipment) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            liftCard
            timerRow
            ForEach(section.items) { item in setTable(item) }
            HistoryPanel(rows: historyRows, tint: Palette.tangerineDeep)
            NotesField(workoutID: workout.id, section: section, prompt: "knee felt good today…")
        }
        .onAppear {
            if timer == nil, let plan = IntervalPlan.forSection(section) {
                timer = IntervalTimerModel(plan: plan, title: "\(section.lift?.displayName ?? "Strength") timer")
            }
        }
        // Leaving a weight field (next field, tap elsewhere, Done) logs that set.
        .onChange(of: focused) { old, new in
            if let old, old != new { commitTyped(old) }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }.fontWeight(.heavy)
            }
        }
        .modifier(ScenePhaseTimerBridge(timer: timer))
    }

    var historyRows: [HistoryPanel.Row] {
        section.items.compactMap { item -> [HistoryPanel.Row]? in
            guard let lift = Lift(movementName: item.movementName) else { return nil }
            return RecentHistory.liftSessions(lift, before: workout.date, in: store.visibleWorkouts).map { s in
                HistoryPanel.Row(id: "\(lift.rawValue)-\(s.date.iso)", date: s.date.shortDisplay,
                                 title: section.items.count > 1 ? lift.displayName : nil,
                                 detail: s.sets.map { "\(store.fmt($0.weight)) × \($0.reps)" }.joined(separator: " · "))
            }
        }.flatMap { $0 }
    }

    var liftCard: some View {
        PaperCard(rotation: -0.8, tape: WashiTape.forKind(.strength, width: 64), tapeAlignment: .topLeading) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("strength").hand(20, color: Palette.tangerineDeep)
                    Text(section.items.map(\.movementName).joined(separator: " + ")).bodyText(26, .heavy)
                        .accessibilityAddTraits(.isHeader)
                    Text(section.instructions).bodyText(14, .semibold).lineSpacing(2)
                }
                Spacer(minLength: 0)
                if let lift = section.lift { BearView(lift: lift, size: 86, fill: .white) }
            }
        }
    }

    @ViewBuilder var timerRow: some View {
        if let timer {
            let snap = timer.snapshot
            let total = section.items.first?.plannedSets.count ?? 1
            let nextSet = min((snap.phase?.round ?? 1) + (timer.isRunning ? 1 : 0), total)
            let upcoming = section.items.first?.plannedSets.first { $0.setNumber == nextSet }
            HStack(spacing: 14) {
                TimerRing(progress: snap.isFinished ? 1 : snap.phaseProgress, color: Palette.tangerine, track: Palette.dot,
                          label: formatClock(snap.remainingInPhase), sublabel: nil, size: 78, lineWidth: 9)
                    .accessibilityLabel("\(snap.remainingInPhase) seconds until set \(nextSet)")
                VStack(alignment: .leading, spacing: 0) {
                    Text(snap.isFinished ? "all sets done!" : timer.isRunning ? "set \(nextSet) starts soon" : "log set 1 to start")
                        .hand(22)
                    if let upcoming, let load = calc.loadout(for: store.unit.fromPounds(upcoming.weight)) {
                        Text("\(store.label(upcoming.weight)) = \(load.description)").bodyText(13, .semibold, color: Palette.muted)
                    }
                }
                Spacer(minLength: 0)
                RoundIconButton(systemName: timer.isRunning ? "pause.fill" : "play.fill",
                                label: timer.isRunning ? "Pause timer" : "Start timer") { timer.toggle() }
                    .accessibilityIdentifier("strengthTimer")
            }
            .padding(.horizontal, 4)
        }
    }

    func setTable(_ item: SectionItem) -> some View {
        let lift = Lift(movementName: item.movementName)
        let last = lift.flatMap { store.lastSession(of: $0, before: workout.date) }
        let best = lift.flatMap { store.bestTop(of: $0, before: workout.date) } ?? 0
        return PaperCard(ruled: 44, padding: EdgeInsets(top: 10, leading: 12, bottom: 6, trailing: 12)) {
            VStack(alignment: .leading, spacing: 0) {
                if section.items.count > 1 { Text("\(item.letter): \(item.movementName)").hand(20, color: Palette.tangerineDeep) }
                // Plain Grid (not lazy): every row stays in the hierarchy while the keyboard is up.
                Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 0) {
                    GridRow {
                        Text("set").frame(width: 34, alignment: .leading)
                        Text("reps").frame(width: 40, alignment: .leading)
                        Text("last time").frame(maxWidth: .infinity, alignment: .leading)
                        Text(store.unit.symbol).frame(width: 74)
                        Text("").frame(width: 44)
                    }
                    .hand(17, color: Palette.muted)
                    .frame(height: 24)
                    ForEach(item.plannedSets, id: \.setNumber) { p in
                        GridRow { setRow(item: item, planned: p, last: last) }
                            .frame(height: 44)
                    }
                }
                if let top = item.plannedSets.last?.weight, best > 0, top > best {
                    Text("← PR if you hit it!").hand(18, color: Palette.berry).rotationEffect(.degrees(-8))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    static func key(_ item: SectionItem, _ setNumber: Int) -> String { "\(item.id.uuidString)|\(setNumber)" }

    @ViewBuilder
    func setRow(item: SectionItem, planned p: PlannedSet, last: LiftSession?) -> some View {
        let key = Self.key(item, p.setNumber)
        let logged = item.setLogs.first { $0.setNumber == p.setNumber }
        let lastW = last?.sets.first { $0.setNumber == p.setNumber }?.weight
        Text("\(p.setNumber)").hand(24, color: logged == nil ? Palette.faint : Palette.ink).frame(width: 34, height: 44)
        Text("×\(p.reps)").bodyText(16, .bold, color: Palette.muted).frame(width: 40, alignment: .leading)
        Text(lastW.map(store.fmt) ?? "–").hand(19, .semibold, color: Palette.faint).frame(maxWidth: .infinity, alignment: .leading)
        if let logged {
            Text(store.fmt(logged.weight)).hand(27).frame(width: 74)
                .accessibilityIdentifier("logged-\(item.letter)-\(p.setNumber)")
        } else {
            TextField(store.fmt(p.weight), text: Binding(get: { weights[key] ?? "" }, set: { weights[key] = $0 }))
                .font(Typeface.hand(26))
                .multilineTextAlignment(.center)
                .numberKeyboard()
                .submitLabel(.done)
                .focused($focused, equals: key)
                .onSubmit { commitTyped(key) }
                .padding(.bottom, 2)
                .overlay(alignment: .bottom) { Rectangle().fill(focused == key ? Palette.tangerine : Palette.inputLine).frame(height: 2.5) }
                .frame(width: 74)
                .accessibilityLabel("Weight for set \(p.setNumber)")
                .accessibilityIdentifier("weight-\(item.letter)-\(p.setNumber)")
        }
        Button {
            if let logged {
                weights[key] = store.fmt(logged.weight)
                store.unlogSet(workout: workout.id, section: section.id, item: item.id, setNumber: p.setNumber)
            } else {
                log(item: item, planned: p, typed: weights[key])
            }
        } label: {
            if logged != nil {
                Image(systemName: "checkmark").font(.system(size: 17, weight: .heavy)).foregroundStyle(Palette.ink)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Palette.tangerine))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                    .stickerShadow()
                    .slapOn(rotation: [-8, 6, -4][p.setNumber % 3], delay: 0)
            } else {
                DoodleSquare().stroke(Palette.ink, lineWidth: 1.8).frame(width: 32, height: 32)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 44)
        .accessibilityLabel(logged != nil ? "Set \(p.setNumber) done" : "Mark set \(p.setNumber) done")
        .accessibilityIdentifier("set-\(item.letter)-\(p.setNumber)")
    }

    /// A weight was typed and the field was left: mark that set done.
    func commitTyped(_ key: String) {
        guard let typed = weights[key]?.trimmingCharacters(in: .whitespaces), !typed.isEmpty else { return }
        let parts = key.split(separator: "|")
        guard parts.count == 2, let setNumber = Int(parts[1]),
              let item = section.items.first(where: { $0.id.uuidString == parts[0] }),
              let planned = item.plannedSets.first(where: { $0.setNumber == setNumber }),
              !item.setLogs.contains(where: { $0.setNumber == setNumber }) else { return }
        log(item: item, planned: planned, typed: typed)
    }

    func log(item: SectionItem, planned p: PlannedSet, typed: String?) {
        // Typed in the display unit; stored as canonical pounds.
        let parsed = typed.flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
        let weight = parsed.flatMap { $0.isFinite && $0 >= 0 && $0 <= 1000 ? store.unit.toPounds($0) : nil } ?? p.weight
        store.logSet(workout: workout.id, section: section.id, item: item.id, setNumber: p.setNumber, reps: p.reps, weight: weight)
        Haptics.play(.tap)
        // Start the countdown to the next set if the clock isn't running yet.
        if let timer, !timer.isRunning, !timer.snapshot.isFinished { timer.start() }
    }
}

// MARK: - Metabolic

@MainActor
struct MetabolicSectionView: View {
    var workout: PlannedWorkout
    var section: WorkoutSection
    @Environment(AppStore.self) private var store
    @State private var timer: IntervalTimerModel?
    @State private var inputs: [Int: (String, String)] = [:]

    /// One log row per prescribed round (matches the timer).
    var roundCount: Int { section.prescribedRounds }
    var isTime: Bool { section.format == .forTime || section.format == .ladder }
    var isRounds: Bool { section.format == .amrap || section.format == .amrapWithRest }

    var body: some View {
        let previous = store.previousResult(for: section, before: workout.date)
        VStack(alignment: .leading, spacing: 12) {
            card
            timerRow
            roundsTable(previous)
            HistoryPanel(rows: historyRows, tint: Palette.skyDeep)
            NotesField(workoutID: workout.id, section: section, prompt: "felt strong on the swings…")
        }
        .onAppear {
            if timer == nil, let plan = IntervalPlan.forSection(section) {
                timer = IntervalTimerModel(plan: plan, title: section.name ?? "Metabolic timer")
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { hideKeyboard() }.fontWeight(.heavy)
            }
        }
        .modifier(ScenePhaseTimerBridge(timer: timer))
    }

    var historyRows: [HistoryPanel.Row] {
        RecentHistory.metabolic(for: section, before: workout.date, in: store.visibleWorkouts).map { e in
            let rounds = e.roundLogs.map(describe).joined(separator: ", ")
            let detail = e.roundLogs.count > 1 ? "\(rounds) = \(e.score)" : e.score.description
            return HistoryPanel.Row(id: e.date.iso + e.name, date: e.date.shortDisplay,
                                    title: e.match == .sameFormat ? e.name : nil, detail: detail)
        }
    }

    var card: some View {
        PaperCard(rotation: 0.8, tape: WashiTape.forKind(.metabolic, width: 64, angle: 4), tapeAlignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 6) {
                Text("metabolic").hand(20, color: Palette.skyDeep)
                Text(section.name ?? section.format.nameStructure).bodyText(22, .heavy).accessibilityAddTraits(.isHeader)
                    .padding(.trailing, section.benchmarkID != nil ? 64 : 0)
                Text(section.instructions).bodyText(14, .semibold)
                ForEach(section.items) { item in
                    HStack(spacing: 10) {
                        Text(item.letter).hand(22, color: Palette.skyDeep).frame(width: 14)
                        Text(item.displayLine.lowercased()).bodyText(15)
                        Spacer(minLength: 4)
                        if let label = item.weightLabel {
                            Text(label).bodyText(12, .heavy)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Capsule().fill(item.movementID.hasPrefix("kb") ? Palette.bubblegum : Palette.sky))
                                .overlay(Capsule().strokeBorder(.white, lineWidth: 2.5))
                                .stickerShadow()
                                .rotationEffect(.degrees(-4))
                        }
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if section.benchmarkID != nil {
                VStack(spacing: 0) {
                    Text("BENCH\nMARK").font(.system(size: 9, weight: .heavy)).tracking(0.7).multilineTextAlignment(.center)
                    Text(section.isModified ? "mod" : "Q\((workout.date.month - 1) / 3 + 1)").hand(16)
                }
                .foregroundStyle(Palette.skyDeep)
                .frame(width: 64, height: 64)
                .overlay(Circle().strokeBorder(Palette.skyDeep, lineWidth: 2.5))
                .slapOn(rotation: -12, delay: 0.5)
                .padding(.top, 16).padding(.trailing, 10)
                .accessibilityLabel(section.isModified ? "Benchmark, modified" : "Quarterly benchmark")
            }
        }
    }

    @ViewBuilder var timerRow: some View {
        if let timer {
            let snap = timer.snapshot
            let isRest = snap.phase?.kind == .rest
            let roundsTotal = timer.plan.phases.filter { $0.kind == .work }.count
            HStack(spacing: 16) {
                TimerRing(progress: snap.isFinished ? 1 : snap.phaseProgress, color: isRest ? Palette.mint : Palette.sky,
                          track: Color(hex: 0xE3ECFF), label: formatClock(snap.isFinished ? 0 : snap.remainingInPhase),
                          sublabel: snap.isFinished ? "done!" : (isRest ? "rest" : "work!"), size: 130, lineWidth: 10)
                    .accessibilityElement()
                    .accessibilityLabel(snap.isFinished ? "Timer done" : "\(snap.remainingInPhase) seconds left, \(isRest ? "rest" : "work")")
                VStack(alignment: .leading, spacing: 8) {
                    Text("round \(min(snap.phase?.round ?? roundsTotal, roundsTotal)) of \(roundsTotal)").hand(24)
                        .accessibilityIdentifier("roundOfTotal")
                    Text(section.restSec.map { "then \(formatClock($0)) rest. Bell at each round, phone buzzes too." } ?? "Bell at each round, phone buzzes too.")
                        .bodyText(13, .semibold, color: Palette.muted)
                    HStack(spacing: 10) {
                        Button(timer.isRunning ? "pause" : "start") { timer.toggle() }
                            .bodyText(15, .heavy, color: Palette.cream)
                            .padding(.horizontal, 16).frame(height: 44)
                            .background(Capsule().fill(Palette.ink))
                            .rotationEffect(.degrees(-3))
                            .accessibilityIdentifier("metabolicTimer")
                        Button("reset") { timer.reset() }
                            .bodyText(15, .heavy)
                            .padding(.horizontal, 16).frame(height: 44)
                            .background(Capsule().fill(Palette.sunny))
                            .rotationEffect(.degrees(3))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    var todayHeader: String {
        if section.format == .ladder || (section.format == .forTime && roundCount > 1) { return "split" }
        return isTime ? "time" : isRounds ? "rounds + reps" : "reps"
    }

    func roundsTable(_ previous: (date: LocalDate, logs: [RoundLog])?) -> some View {
        PaperCard(ruled: 38, padding: EdgeInsets(top: 8, leading: 14, bottom: 4, trailing: 14)) {
            VStack(spacing: 0) {
                HStack {
                    Text(roundCount > 1 && isTime ? "rung" : "round").frame(width: 54, alignment: .leading)
                    Text(todayHeader).frame(maxWidth: .infinity)
                    Text(previous.map { "last time (\($0.date.shortMonthName))" } ?? "last time").frame(maxWidth: .infinity, alignment: .trailing)
                }
                .hand(17, color: Palette.muted).frame(height: 26)
                ForEach(1...max(1, roundCount), id: \.self) { r in
                    let logged = section.roundLogs.first { $0.roundNumber == r }
                    let prev = previous?.logs.first { $0.roundNumber == r }
                    HStack {
                        Text("\(r)").hand(22).frame(width: 54)
                        Group {
                            if isTime {
                                field(r, 0, placeholder: logged?.timeSec.map(formatClock) ?? "mm:ss")
                            } else if isRounds {
                                HStack(spacing: 4) {
                                    field(r, 0, placeholder: logged?.rounds.map(String.init) ?? "5")
                                    Text("+").hand(22)
                                    field(r, 1, placeholder: logged?.reps.map(String.init) ?? "0")
                                }
                            } else {
                                field(r, 1, placeholder: logged?.reps.map(String.init) ?? "reps")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        Text(prev.map(describe) ?? "–").hand(20, .semibold, color: Palette.faint).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(height: 38)
                    .accessibilityIdentifier("logRow-\(r)")
                }
                if let previous, let ahead = aheadBy(previous.logs) {
                    Text(ahead > 0 ? "+\(ahead) ahead!" : ahead == 0 ? "neck and neck!" : "\(ahead) behind, keep going!")
                        .hand(17, color: Palette.berry).rotationEffect(.degrees(-6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    func field(_ round: Int, _ slot: Int, placeholder: String) -> some View {
        TextField(placeholder, text: Binding(
            get: { slot == 0 ? (inputs[round]?.0 ?? "") : (inputs[round]?.1 ?? "") },
            set: { v in
                var pair = inputs[round] ?? ("", "")
                if slot == 0 { pair.0 = v } else { pair.1 = v }
                inputs[round] = pair
                commit(round, pair)
            }))
            .font(Typeface.hand(24))
            .multilineTextAlignment(.center)
            .numberKeyboard(decimal: false)
            .frame(width: isTime ? 70 : 40, height: 30)
            .overlay(alignment: .bottom) { Rectangle().fill(slot == 0 ? Palette.sky : Palette.inputLine).frame(height: 2.5) }
            .accessibilityLabel("Round \(round) \(slot == 0 ? (isTime ? "time" : "rounds") : "reps")")
    }

    func commit(_ round: Int, _ pair: (String, String)) {
        if isTime {
            let parts = pair.0.split(separator: ":").compactMap { Int($0) }
            let secs = parts.count == 2 ? parts[0] * 60 + parts[1] : parts.first
            store.logRound(workout: workout.id, section: section.id, round: round, rounds: nil, reps: nil, timeSec: secs)
        } else if isRounds {
            store.logRound(workout: workout.id, section: section.id, round: round, rounds: Int(pair.0), reps: Int(pair.1) ?? 0, timeSec: nil)
        } else {
            store.logRound(workout: workout.id, section: section.id, round: round, rounds: nil, reps: Int(pair.1), timeSec: nil)
        }
    }

    func describe(_ r: RoundLog) -> String {
        if let t = r.timeSec { return formatClock(t) }
        if let rounds = r.rounds { return "\(rounds) + \(r.reps ?? 0)" }
        return r.reps.map(String.init) ?? "–"
    }

    /// Reps ahead of last time over the rounds logged so far.
    func aheadBy(_ previous: [RoundLog]) -> Int? {
        let done = section.roundLogs.map(\.roundNumber)
        guard !done.isEmpty else { return nil }
        let prev = previous.filter { done.contains($0.roundNumber) }
        guard let a = MetabolicScore.from(section.roundLogs, format: section.format),
              let b = MetabolicScore.from(prev, format: section.format) else { return nil }
        return a.improvement(over: b, repsPerRound: section.repsPerRound)
    }
}


// MARK: - Warm-up / cool-down

@MainActor
struct SimpleSectionView: View {
    var workout: PlannedWorkout
    var section: WorkoutSection
    @State private var roundsDone = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PaperCard(rotation: section.kind == .warmup ? -0.8 : 0.8, tape: WashiTape.forKind(section.kind, width: 64)) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.kind.displayName).hand(20, color: section.kind.deepColor)
                    Text(section.instructions).bodyText(15, .semibold)
                    ForEach(section.items) { item in
                        HStack(spacing: 10) {
                            Text(item.letter).hand(22, color: section.kind.deepColor).frame(width: 14)
                            Text(item.displayLine.lowercased()).bodyText(15)
                            Spacer(minLength: 4)
                            if let w = item.weightLabel { Text(w).bodyText(12, .heavy, color: Palette.muted) }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if let rounds = section.rounds, rounds > 1 {
                HStack(spacing: 12) {
                    Text("rounds").hand(20)
                    ForEach(1...rounds, id: \.self) { r in
                        Button {
                            roundsDone = roundsDone == r ? r - 1 : r
                            Haptics.play(.tap)
                        } label: {
                            ZStack {
                                Circle().fill(r <= roundsDone ? section.kind.color : .white)
                                Circle().strokeBorder(r <= roundsDone ? .white : Palette.inputLine, lineWidth: 3)
                                Text("\(r)").hand(20)
                            }
                            .frame(width: 40, height: 40)
                            .stickerShadow()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Round \(r) \(r <= roundsDone ? "done" : "not done")")
                    }
                }
            }
            NotesField(workoutID: workout.id, section: section, prompt: "how did it feel?")
        }
    }
}
