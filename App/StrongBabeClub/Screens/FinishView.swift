import SwiftUI
import WorkoutCore

/// Finish: pick today's sticker, strength + metabolic summary, energy,
/// difficulty ratings and notes. (SbFinish.dc.html)
@MainActor
struct FinishView: View {
    var workoutID: UUID
    var minutes: Int
    var onDone: () -> Void
    @Environment(AppStore.self) private var store
    @State private var sticker: StickerID?
    @State private var energy: Energy?
    @State private var strength: Int?
    @State private var metabolic: Int?
    @State private var notes = ""

    var body: some View {
        if let w = store.workout(id: workoutID) {
            let ctx = store.stickerContext(for: w)
            JournalPage {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(w.date.shortDisplay) · \(minutes) min · streak is now \(ctx.streakAfterWorkout)").hand(21, .semibold, color: Palette.muted)
                    Text("you did it!").bodyText(32, .heavy).accessibilityAddTraits(.isHeader)
                }
                .padding(.top, 16)
                stickerPicker(ctx)
                summaryCards(w, isPR: ctx.isPRDay)
                energyPicker
                difficulty
                VStack(alignment: .leading, spacing: 0) {
                    Text("dear diary…").hand(22)
                    TextField("knee felt great!", text: $notes, axis: .vertical)
                        .font(Typeface.hand(21, .semibold))
                        .lineLimit(2...6)
                        .padding(.vertical, 4)
                        .background(RuledLines(spacing: 30))
                }
                Button {
                    store.finish(workout: workoutID,
                                 feedback: WorkoutFeedback(energy: energy, strengthDifficulty: strength, metabolicDifficulty: metabolic, notes: notes),
                                 sticker: sticker, minutes: minutes)
                    onDone()
                } label: {
                    Text("stick it in my journal").bodyText(18, .heavy)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(RoundedRectangle(cornerRadius: 24).fill(Palette.tangerine))
                }
                .buttonStyle(.plain)
                .jiggle()
                .accessibilityIdentifier("stickInJournal")
            }
        }
    }

    func stickerPicker(_ ctx: StickerContext) -> some View {
        let options = StickerCatalog.available(ctx)
        return PaperCard(rotation: -0.6, tape: WashiTape(color: Palette.sunny, stripe: Palette.sunnyLight, width: 64, angle: -3),
                         padding: EdgeInsets(top: 12, leading: 10, bottom: 10, trailing: 10)) {
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("pick today's sticker").hand(23)
                    Spacer()
                    Text(sticker.map { "\($0.displayName.lowercased()) ✓" } ?? "tap one!").hand(18, color: Palette.berry)
                }
                .padding(.horizontal, 4)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(options, id: \.id) { def in
                            let on = sticker == def.id
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { sticker = def.id }
                                Haptics.play(.tap)
                            } label: {
                                StickerView(id: def.id, size: on ? 58 : 46)
                                    .rotationEffect(.degrees(on ? 8 : -4))
                                    .opacity(on || sticker == nil ? 1 : 0.75)
                                    .overlay(alignment: .topTrailing) {
                                        if let tag = def.unlockLabel {
                                            Text(tag).font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                                                .padding(.horizontal, 5).padding(.vertical, 2)
                                                .background(RoundedRectangle(cornerRadius: 8).fill(Palette.berry))
                                                .rotationEffect(.degrees(12)).offset(x: 12, y: -10)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .frame(height: 70)
                            .accessibilityLabel(def.name + (def.isRare ? ", rare" : ""))
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 6)
                }
            }
        }
    }

    func summaryCards(_ w: PlannedWorkout, isPR: Bool) -> some View {
        let strength = ProgressSeries.strengthSummary(w.strengthSection)
        let m = w.metabolicSection
        let score = m.flatMap { MetabolicScore.from($0.roundLogs, format: $0.format) }
        let prev = m.flatMap { store.previousResult(for: $0, before: w.date) }
        let prevScore = prev.flatMap { p in m.flatMap { MetabolicScore.from(p.logs, format: $0.format) } }
        let diff = (score != nil && prevScore != nil && m != nil) ? score!.improvement(over: prevScore!, repsPerRound: m!.repsPerRound) : nil
        return HStack(alignment: .top, spacing: 14) {
            PaperCard(rotation: -1.5, tape: WashiTape.forKind(.strength, width: 52), tapeAlignment: .topLeading,
                      padding: EdgeInsets(top: 14, leading: 12, bottom: 10, trailing: 12)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("strength").hand(20, color: Palette.tangerineDeep)
                    Text("top set").bodyText(13, .bold, color: Palette.muted)
                    Text(strength.map { "\(formatPounds($0.top)) lb" } ?? "–").bodyText(24, .heavy)
                    Text("total lifted").bodyText(13, .bold, color: Palette.muted).padding(.top, 4)
                    Text(strength.map { "\($0.total.formatted(.number.grouping(.automatic))) lb" } ?? "–").bodyText(20, .heavy)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isPR {
                    VStack(spacing: 0) {
                        StarIcon().frame(width: 18, height: 18)
                        Text("PR!").bodyText(12, .heavy)
                    }
                    .frame(width: 50, height: 50)
                    .background(UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 25, bottomTrailingRadius: 12, topTrailingRadius: 25)
                        .fill(Palette.mint))
                    .overlay(UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 25, bottomTrailingRadius: 12, topTrailingRadius: 25)
                        .strokeBorder(.white, lineWidth: 3))
                    .stickerShadow()
                    .slapOn(rotation: 12, delay: 0.9, from: 2.2)
                    .offset(x: 12, y: 22)
                    .accessibilityLabel("Personal record")
                }
            }
            PaperCard(rotation: 1.2, tape: WashiTape.forKind(.metabolic, width: 52, angle: 4), tapeAlignment: .topTrailing,
                      padding: EdgeInsets(top: 14, leading: 12, bottom: 10, trailing: 12)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("metabolic").hand(20, color: Palette.skyDeep)
                    Text(m?.name ?? "–").bodyText(13, .bold, color: Palette.muted).lineLimit(1).minimumScaleFactor(0.7)
                    Text(score?.description ?? "–").bodyText(24, .heavy)
                    Text(prev.map { "vs \($0.date.longMonthName)" } ?? "first time!").bodyText(13, .bold, color: Palette.muted).padding(.top, 4)
                    if let diff {
                        Text(diff > 0 ? "+\(diff) \(m?.format.lowerIsBetter == true ? "s faster" : "reps")!" : diff == 0 ? "tied!" : "\(diff)")
                            .hand(22, color: Palette.skyDeep)
                    }
                }
            }
        }
    }

    var energyPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("how was your energy?").hand(22)
            HStack {
                ForEach([(Energy.high, "high!", Palette.tangerine), (.okay, "okay", Palette.sunnyPale), (.sleepy, "sleepy", Color(hex: 0xD3E1FF))], id: \.0) { e, label, color in
                    let on = energy == e
                    Button { energy = e; Haptics.play(.tap) } label: {
                        VStack(spacing: 2) {
                            Image(systemName: e == .high ? "face.smiling" : e == .okay ? "minus.circle" : "moon.zzz")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                                .frame(width: on ? 56 : 50, height: on ? 56 : 50)
                                .background(Circle().fill(on ? Palette.tangerine : color))
                                .overlay(Circle().strokeBorder(on ? .white : .clear, lineWidth: 3))
                                .rotationEffect(.degrees(on ? -6 : 0))
                            Text(label).hand(19, color: on ? Palette.ink : Palette.muted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Energy \(label)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    var difficulty: some View {
        VStack(alignment: .leading, spacing: 4) {
            (Text("how hard was it? ") + Text("(1 easy · 5 brutal)").foregroundColor(Palette.muted)).hand(22)
            ratingRow("strength", color: Palette.tangerine, deep: Palette.tangerineDeep, value: $strength)
            ratingRow("metabolic", color: Palette.sky, deep: Palette.skyDeep, value: $metabolic)
        }
    }

    func ratingRow(_ label: String, color: Color, deep: Color, value: Binding<Int?>) -> some View {
        HStack(spacing: 0) {
            Text(label).hand(19, color: deep).frame(width: 86, alignment: .leading)
            ForEach(1...5, id: \.self) { n in
                Button { value.wrappedValue = n; Haptics.play(.tap) } label: {
                    ZStack {
                        Text("\(n)").hand(26)
                        if value.wrappedValue == n {
                            DrawnStroke(shape: HandCircle(), color: color, lineWidth: 5, delay: 0, duration: 0.5).frame(width: 44, height: 40)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(label) difficulty \(n) of 5")
                .accessibilityAddTraits(value.wrappedValue == n ? .isSelected : [])
            }
        }
    }
}
