import SwiftUI
import WorkoutCore

/// The live workout: section tabs, the section's screen, next/finish buttons.
/// (SbWorkout.dc.html, SbMetabolic.dc.html)
@MainActor
struct WorkoutSessionView: View {
    var workoutID: UUID
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var current: SectionKind = DebugRoute.section.flatMap(SectionKind.init(rawValue:)) ?? .warmup
    @State private var startedAt = Date()
    @State private var showFinish = DebugRoute.open == "finish"

    var body: some View {
        if let w = store.workout(id: workoutID) {
            ZStack {
                PaperBackground()
                VStack(spacing: 0) {
                    header(w)
                    ScrollViewReader { proxy in
                        ScrollView {
                            content(w)
                                .padding(.leading, 44)
                                .padding(.trailing, 20)
                                .padding(.vertical, 8)
                            Color.clear.frame(height: 1).id("session-bottom")
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .task(id: current) {
                            guard DebugRoute.scrollBottom else { return }
                            try? await Task.sleep(nanoseconds: 1_200_000_000)
                            proxy.scrollTo("session-bottom", anchor: .bottom)
                        }
                    }
                    footer(w)
                }
            }
            .sheet(isPresented: $showFinish) {
                FinishView(workoutID: workoutID, minutes: max(1, Int(Date().timeIntervalSince(startedAt) / 60))) {
                    showFinish = false
                    dismiss()
                }
            }
        } else {
            Text("This workout is gone.").onAppear { dismiss() }
        }
    }

    func header(_ w: PlannedWorkout) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Button { dismiss() } label: { Image(systemName: "chevron.down").bodyText(16, .heavy, color: Palette.muted) }
                    .accessibilityLabel("Close workout")
                Text("\(w.date.shortDisplay) · \(w.mainLift?.displayName.lowercased() ?? "workout") day").hand(21, .semibold, color: Palette.muted)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { tl in
                    Text(formatClock(Int(tl.date.timeIntervalSince(startedAt)))).bodyText(14, .heavy, color: Palette.muted).monospacedDigit()
                }
                .accessibilityLabel("Elapsed time")
            }
            HStack(spacing: 6) {
                ForEach(Array(w.sections.enumerated()), id: \.element.id) { i, s in
                    let isCurrent = s.kind == current
                    let isDone = (w.sections.firstIndex { $0.kind == current } ?? 0) > i
                    Button { current = s.kind } label: {
                        Text(s.kind.displayName + (isDone ? " ✓" : ""))
                            .hand(18)
                            .frame(maxWidth: .infinity, minHeight: isCurrent ? 34 : 30)
                            .background(isCurrent ? s.kind.color : (isDone ? s.kind.color.opacity(0.55) : s.kind.paleColor))
                            .shadow(color: isCurrent ? Palette.ink.opacity(0.2) : .clear, radius: 2, y: 2)
                            .rotationEffect(.degrees([-1, 1.5, -1.5, 1][i % 4]))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isCurrent ? .isSelected : [])
                }
            }
        }
        .padding(.leading, 44)
        .padding(.trailing, 20)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    @ViewBuilder func content(_ w: PlannedWorkout) -> some View {
        if let s = w.section(current) {
            switch s.kind {
            case .strength: StrengthSectionView(workout: w, section: s).id(s.id)
            case .metabolic: MetabolicSectionView(workout: w, section: s).id(s.id)
            default: SimpleSectionView(workout: w, section: s).id(s.id)
            }
        }
    }

    func footer(_ w: PlannedWorkout) -> some View {
        let kinds = w.sections.map(\.kind)
        let idx = kinds.firstIndex(of: current) ?? 0
        let next = idx + 1 < kinds.count ? kinds[idx + 1] : nil
        return HStack(spacing: 10) {
            if let next {
                Button { current = next } label: {
                    Text("next: \(next.displayName) →").bodyText(16, .heavy)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(RoundedRectangle(cornerRadius: 22).fill(.white).shadow(color: Palette.ink.opacity(0.1), radius: 4, y: 3))
                }
                .accessibilityIdentifier("nextSection")
            }
            Button { showFinish = true } label: {
                Text("finish").bodyText(17, .heavy)
                    .frame(width: next == nil ? nil : 110, height: 52)
                    .frame(maxWidth: next == nil ? .infinity : nil)
                    .background(RoundedRectangle(cornerRadius: 24).fill(Palette.tangerine))
            }
            .accessibilityIdentifier("finishWorkout")
        }
        .buttonStyle(.plain)
        .padding(.leading, 44)
        .padding(.trailing, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }
}

// MARK: - Timer ring

@MainActor
struct TimerRing: View {
    var progress: Double
    var color: Color
    var track: Color
    var label: String
    var sublabel: String?
    var size: CGFloat
    var lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle().trim(from: 0, to: max(0.001, 1 - progress))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(label).bodyText(size * 0.2, .heavy).monospacedDigit()
                if let sublabel { Text(sublabel).hand(size * 0.13, color: Palette.skyDeep) }
            }
        }
        .frame(width: size, height: size)
    }
}

@MainActor
struct RoundIconButton: View {
    var systemName: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Palette.cream)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Palette.ink))
                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                .stickerShadow()
                .rotationEffect(.degrees(-6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Keeps a timer model alive per section and forwards app lifecycle.
struct ScenePhaseTimerBridge: ViewModifier {
    var timer: IntervalTimerModel?
    @Environment(\.scenePhase) private var phase

    func body(content: Content) -> some View {
        content.onChange(of: phase) { _, newPhase in
            switch newPhase {
            case .background: timer?.didEnterBackground()
            case .active: timer?.willEnterForeground()
            default: break
            }
        }
    }
}

// MARK: - Notes field

@MainActor
struct NotesField: View {
    var workoutID: UUID
    var section: WorkoutSection
    var prompt: String
    @Environment(AppStore.self) private var store
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("notes to self").hand(20)
            TextField(prompt, text: $text, axis: .vertical)
                .font(Typeface.hand(21, .semibold))
                .foregroundStyle(Palette.ink)
                .padding(.vertical, 6)
                .overlay(alignment: .bottom) {
                    Rectangle().stroke(style: StrokeStyle(lineWidth: 2, dash: [5, 4])).foregroundStyle(Palette.dashed).frame(height: 1)
                }
                .onSubmit { save() }
                .onChange(of: text) { _, _ in save() }
        }
        .onAppear { text = section.athleteNote }
    }

    func save() {
        if text != section.athleteNote { store.setNote(workout: workoutID, section: section.id, text: text) }
    }
}
