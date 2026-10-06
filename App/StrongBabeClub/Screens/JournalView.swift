import SwiftUI
import WorkoutCore

/// History as journal entries grouped by month, newest first. (SbJournal.dc.html)
@MainActor
struct JournalView: View {
    @Environment(AppStore.self) private var store
    @State private var selected: PlannedWorkout?

    var body: some View {
        let done = store.visibleWorkouts.filter { $0.status == .done || $0.status == .excused }.reversed()
        let groups = Dictionary(grouping: done) { $0.date.year * 100 + $0.date.month }
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
                ForEach(Array(entries.enumerated()), id: \.element.id) { i, w in
                    Button { selected = w } label: { JournalEntry(workout: w, index: i) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if w.status == .done {
                                Button("Mark as sick day (excused)") { store.setStatus(.excused, on: w.date) }
                            } else {
                                Button("Mark as done") { store.setStatus(.done, on: w.date) }
                            }
                        }
                }
            }
        }
        .sheet(item: $selected) { w in WorkoutDetailView(workout: w) }
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
        let top = w.strengthSection?.items.compactMap(\.topLoggedWeight).max()
        let isPR = !PRDetector.strengthPRs(in: w, history: store.visibleWorkouts).isEmpty
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text(w.date.weekday.shortName.lowercased()).hand(17, color: Palette.muted)
                Text("\(w.date.day)").bodyText(26, .heavy)
            }
            .frame(width: 42)
            VStack(alignment: .leading, spacing: 2) {
                if w.status == .excused {
                    Text("sick day · excused").bodyText(16, .heavy, color: Palette.muted)
                } else {
                    (Text(w.mainLift?.displayName ?? "Workout") + Text(top.map { " · top \(formatPounds($0))" } ?? "").foregroundColor(Palette.muted))
                        .bodyText(16, .heavy)
                    if let m = w.metabolicSection {
                        let scores = m.roundLogs.map { r in r.timeSec.map(formatClock) ?? r.rounds.map { "\($0)+\(r.reps ?? 0)" } ?? "\(r.reps ?? 0)" }
                        Text(([m.name ?? m.format.nameStructure] + (scores.isEmpty ? [] : [scores.joined(separator: ", ")])).joined(separator: " · "))
                            .bodyText(13, .semibold, color: Palette.muted).lineLimit(2)
                    }
                    if let note = w.feedback?.notes, !note.isEmpty {
                        Text(note).hand(19, .semibold, color: Palette.note).lineLimit(2)
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
                                    Text(item.setLogs.map { "\($0.reps)×\(formatPounds($0.weight))" }.joined(separator: ", "))
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
