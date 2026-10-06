import SwiftUI
import WorkoutCore

/// History as journal entries grouped by month, newest first. (SbJournal.dc.html)
@MainActor
struct JournalView: View {
    @Environment(AppStore.self) private var store
    @State private var selected: PlannedWorkout?
    @State private var missedChoice: MissedEntry?
    @State private var sickChoice: PlannedWorkout?

    /// Workouts, sick days and missed days, newest first.
    enum Item: Identifiable {
        case workout(PlannedWorkout)
        case missed(MissedEntry)

        var id: String {
            switch self {
            case .workout(let w): return w.id.uuidString
            case .missed(let m): return "missed-" + m.id
            }
        }
        var date: LocalDate {
            switch self {
            case .workout(let w): return w.date
            case .missed(let m): return m.to
            }
        }
    }

    var body: some View {
        let kept = store.visibleWorkouts.filter { $0.status == .done || $0.status == .excused }.map(Item.workout)
        let items = (kept + store.missedEntries.map(Item.missed)).sorted { $0.date > $1.date }
        let groups = Dictionary(grouping: items) { $0.date.year * 100 + $0.date.month }
        let keys = groups.keys.sorted(by: >)
        JournalPage {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("my journal").bodyText(32, .heavy).accessibilityAddTraits(.isHeader)
                    DrawnStroke(shape: Squiggle(), color: Palette.tangerine, lineWidth: 4).frame(width: 150, height: 12)
                }
                Spacer()
                if let first = store.doneWorkouts.first {
                    Text("\(store.doneWorkouts.count) workouts\nsince \(first.date.shortMonthName) '\(String(first.date.year).suffix(2))")
                        .hand(19, color: Palette.muted).multilineTextAlignment(.trailing)
                }
            }
            .padding(.top, 20)
            if keys.isEmpty {
                Text("Your finished workouts land here, sticker and all.").hand(20, color: Palette.muted)
            }
            ForEach(keys, id: \.self) { key in
                let entries = groups[key] ?? []
                Text(entries.first?.date.longMonthName ?? "").hand(26, color: Palette.tangerineDeep)
                ForEach(Array(entries.enumerated()), id: \.element.id) { i, item in
                    switch item {
                    case .missed(let m):
                        Button { missedChoice = m } label: { MissedRow(entry: m, index: i) }
                            .buttonStyle(.plain)
                            .id(m.isGroup && m.id == store.missedEntries.last(where: \.isGroup)?.id ? "missedGroup-latest" : m.id)
                            .accessibilityIdentifier(m.isGroup ? "missedGroup" : "missedDay")
                    case .workout(let w):
                        Button {
                            if w.status == .excused && w.sections.isEmpty { sickChoice = w } else { selected = w }
                        } label: { JournalEntry(workout: w, index: i) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if w.status == .done {
                                    Button("Mark as sick day") { store.markSick(w.date) }
                                } else {
                                    Button("Switch back to missed") { store.markMissed(w.date) }
                                }
                            }
                    }
                }
            }
        }
        .sheet(item: $selected) { w in WorkoutDetailView(workout: w) }
        .task {
            guard DebugRoute.open == "missedgroup" else { return }
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            missedChoice = store.missedEntries.first { $0.isGroup }
        }
        .confirmationDialog(missedChoice.map { $0.label } ?? "", isPresented: Binding(get: { missedChoice != nil }, set: { if !$0 { missedChoice = nil } }),
                            titleVisibility: .visible, presenting: missedChoice) { m in
            if m.isGroup {
                Button("Mark as a break") { store.addBreak(label: "break", from: m.from, to: m.to) }
            } else {
                if let planned = store.workout(on: m.from), !planned.sections.isEmpty {
                    Button("I did it, just didn't log it") { store.markDoneUnlogged(m.from) }
                    Button("See what was planned") { selected = planned }
                }
                Button("Mark as sick day") { store.markSick(m.from) }
            }
            // A plain button: popover-style dialogs hide cancel-role buttons.
            Button("Keep as missed") {}
        } message: { m in
            Text(m.isGroup ? "A break is planned time off: it won't count against your streak." : "Sick days are excused and don't break your streak.")
        }
        .confirmationDialog("Sick day", isPresented: Binding(get: { sickChoice != nil }, set: { if !$0 { sickChoice = nil } }),
                            titleVisibility: .visible, presenting: sickChoice) { w in
            Button("Switch back to missed") { store.markMissed(w.date) }
            Button("Keep as sick day") {}
        }
    }
}

/// A faded entry for scheduled days that passed without a workout.
struct MissedRow: View {
    var entry: MissedEntry
    var index: Int

    var body: some View {
        HStack(spacing: 10) {
            Circle().strokeBorder(Palette.dashed, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])).frame(width: 14, height: 14)
            Text.caveat(entry.label).hand(19, .regular, color: Palette.muted)
            Spacer(minLength: 0)
            Text(entry.isGroup ? "break?" : "sick?").bodyText(11, .bold, color: Palette.faint)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.dashed, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        .opacity(0.8)
        .rotationEffect(.degrees(index % 2 == 0 ? -0.4 : 0.4))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.label)
        .accessibilityHint(entry.isGroup ? "Mark as a break or keep as missed" : "Mark as sick day or keep as missed")
    }
}

@MainActor
struct JournalEntry: View {
    var workout: PlannedWorkout
    var index: Int
    @Environment(AppStore.self) private var store

    var body: some View {
        let w = workout
        let energy = w.feedback?.energy
        let tape = energy == .sleepy ? Palette.sky : energy == .okay ? Palette.sunny : Palette.tangerine
        // Heaviest logged set (weight, and reps when known).
        let heaviest = w.strengthSection?.items.flatMap(\.setLogs).max { ($0.weight, $0.reps) < ($1.weight, $1.reps) }
        let isPR = !PRDetector.strengthPRs(in: w, history: store.visibleWorkouts).isEmpty
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text(w.date.weekday.shortName.lowercased()).hand(17, color: Palette.muted)
                Text("\(w.date.day)").bodyText(26, .heavy)
            }
            .frame(width: 42)
            VStack(alignment: .leading, spacing: 2) {
                if w.status == .excused {
                    Text("sick day").bodyText(16, .heavy, color: Palette.muted)
                } else {
                    (Text(w.mainLift?.displayName ?? w.strengthSection?.items.first?.movementName ?? "Workout") + Text(heaviest.map { " · heaviest: \(store.label($0.weight))\($0.reps > 0 ? " × \($0.reps)" : "")" } ?? "").foregroundColor(Palette.muted))
                        .bodyText(16, .heavy)
                    if let m = w.metabolicSection {
                        let scores = m.roundLogs.map { r in r.timeSec.map(formatClock) ?? r.rounds.map { "\($0)+\(r.reps ?? 0)" } ?? "\(r.reps ?? 0)" }
                        Text(([m.name ?? m.format.displayName] + (scores.isEmpty ? [] : [scores.joined(separator: ", ")])).joined(separator: " · "))
                            .bodyText(13, .semibold, color: Palette.muted).lineLimit(2)
                    }
                    if let note = w.feedback?.notes, !note.isEmpty {
                        Text(note).hand(19, .semibold, color: Palette.note).lineLimit(2)
                    }
                    if w.source.hasPrefix("import") {
                        Text("from coach's sheet").bodyText(10, .bold, color: Palette.faint)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .overlay(Capsule().strokeBorder(Palette.dot, lineWidth: 1))
                            .padding(.top, 2)
                    }
                }
            }
            Spacer(minLength: 24)
        }
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 10, trailing: 12))
        .background(Palette.card.shadow(.drop(color: Palette.ink.opacity(0.08), radius: 4, y: 3)))
        .overlay(alignment: .topLeading) {
            Rectangle().fill(tape.opacity(0.85)).frame(width: 16, height: 40).rotationEffect(.degrees(-6)).offset(x: -8, y: 12)
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: -4) {
                if isPR {
                    Text("PR!").bodyText(11, .heavy).padding(.horizontal, 8).frame(height: 26)
                        .background(Capsule().fill(Palette.sunny)).overlay(Capsule().strokeBorder(.white, lineWidth: 2.5))
                        .rotationEffect(.degrees(8)).stickerShadow()
                }
                if let s = w.sticker { StickerView(id: s, size: 40).rotationEffect(.degrees(index % 2 == 0 ? -8 : 10)) }
            }
            .offset(x: 6, y: -8)
        }
        .rotationEffect(.degrees(index % 2 == 0 ? -0.8 : 0.8))
        .riseIn(delay: 0.2 + 0.08 * Double(min(index, 10)))
        .accessibilityElement(children: .combine)
    }
}

/// Read-only detail of a past workout.
@MainActor
struct WorkoutDetailView: View {
    var workout: PlannedWorkout
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(workout.sections) { s in
                    Section(s.kind.displayName) {
                        if let name = s.name { Text(name).font(.headline) }
                        Text(s.instructions).font(.subheadline)
                        ForEach(s.items) { item in
                            VStack(alignment: .leading) {
                                Text("\(item.letter): \(item.displayLine)")
                                if !item.setLogs.isEmpty {
                                    Text(item.setLogs.map { (l: SetLog) -> String in "\(l.reps)×\(store.label(l.weight))" }.joined(separator: ", "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if !s.athleteNote.isEmpty { Text(s.athleteNote).italic() }
                    }
                }
                if let f = workout.feedback {
                    Section("feedback") {
                        if let e = f.energy { Text("Energy: \(e.rawValue)") }
                        if let d = f.strengthDifficulty { Text("Strength: \(d)/5") }
                        if let d = f.metabolicDifficulty { Text("Metabolic: \(d)/5") }
                        if !f.notes.isEmpty { Text(f.notes) }
                    }
                }
            }
            .navigationTitle(workout.date.shortDisplay)
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
