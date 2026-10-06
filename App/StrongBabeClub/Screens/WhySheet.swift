import SwiftUI
import WorkoutCore

/// "Why this workout?": the reasons per section, shuffle per section, and
/// shuffle everything. (SbWhy.dc.html)
@MainActor
struct WhySheet: View {
    var workoutID: UUID
    var onStart: () -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning: SectionKind?

    var body: some View {
        ZStack {
            PaperBackground(showMargin: false)
            ScrollView {
                if let w = store.workout(id: workoutID) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("why this workout?").hand(32)
                                .accessibilityAddTraits(.isHeader)
                            Spacer()
                            Button("done") { dismiss() }.bodyText(15, .heavy, color: Palette.muted)
                        }
                        Text("Picked from your last 6 weeks: what you trained, how hard it felt, and your notes.")
                            .bodyText(14, .semibold, color: Palette.muted)
                        ForEach(Array(w.sections.enumerated()), id: \.element.id) { i, s in
                            card(s, index: i, workout: w)
                        }
                        HStack(spacing: 10) {
                            Button {
                                Task { await store.shuffle(workout: workoutID, section: nil) }
                            } label: {
                                Text("shuffle everything").bodyText(16, .heavy)
                                    .frame(maxWidth: .infinity, minHeight: 54)
                                    .background(RoundedRectangle(cornerRadius: 22).fill(.white).shadow(color: Palette.ink.opacity(0.1), radius: 4, y: 3))
                            }
                            .accessibilityIdentifier("shuffleAll")
                            Button(action: onStart) {
                                Text("let's lift!").bodyText(17, .heavy)
                                    .frame(maxWidth: .infinity, minHeight: 54)
                                    .background(RoundedRectangle(cornerRadius: 24).fill(Palette.tangerine))
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                    .padding(20)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    func card(_ s: WorkoutSection, index i: Int, workout w: PlannedWorkout) -> some View {
        let reasons = w.reasons(for: s.kind)
        return PaperCard(rotation: [-1, 0.8, -0.6, 1][i % 4],
                         tape: WashiTape.forKind(s.kind, width: 58, angle: i % 2 == 0 ? -4 : 4),
                         tapeAlignment: i % 2 == 0 ? .topLeading : .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(s.kind.displayName).hand(21, color: s.kind.deepColor)
                    Spacer()
                    Button {
                        spinning = s.kind
                        Task {
                            await store.shuffle(workout: workoutID, section: s.kind)
                            spinning = nil
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .rotationEffect(.degrees(spinning == s.kind && !reduceMotion ? 180 : 0))
                                .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: spinning)
                            Text("shuffle")
                        }
                        .bodyText(13, .heavy)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Capsule().fill(s.kind.color))
                        .overlay(Capsule().strokeBorder(.white, lineWidth: 2.5))
                        .stickerShadow()
                        .rotationEffect(.degrees(i % 2 == 0 ? -3 : 3))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Shuffle \(s.kind.displayName)")
                    .disabled(w.status != .planned)
                }
                Text(summary(s)).bodyText(16, .heavy)
                ForEach(reasons, id: \.self) { r in
                    Text(r.text).hand(19, .semibold, color: Palette.note)
                }
            }
        }
    }

    func summary(_ s: WorkoutSection) -> String {
        switch s.kind {
        case .strength:
            let lifts = s.items.map(\.movementName).joined(separator: " + ")
            return "\(lifts) · \(s.shortSummary)\(s.intervalSec.map { " every \($0 / 60) min" } ?? "")"
        case .metabolic:
            return (s.name ?? s.format.nameStructure) + (s.benchmarkID != nil ? " (benchmark)" : "")
        default:
            return s.items.map { $0.movementName.lowercased() }.joined(separator: " · ")
        }
    }
}
