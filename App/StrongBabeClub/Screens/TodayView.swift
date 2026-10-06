import SwiftUI
import WorkoutCore

/// Today: greeting, sticker page, streak + 30 days, "Let's lift!", Kettle's
/// note, today's list with the bear. (Scrapbook.dc.html)
@MainActor
struct TodayView: View {
    @Environment(AppStore.self) private var store
    @State private var showWorkout = DebugRoute.open == "session" || DebugRoute.open == "finish"
    @State private var showWhy = DebugRoute.open == "why"

    var body: some View {
        let workout = store.nextWorkout
        JournalPage {
            header(workout)
            stickerPage
            statCards
            if store.todayIsDone { doneForToday }
            if let workout {
                startButton(workout)
                if let note = workout.coachNote { KettleNote(note: note) }
                todaysList(workout)
            } else if store.isPlanning {
                Text("planning your workout…").hand(22, color: Palette.muted)
            }
        }
        .fullScreen(isPresented: $showWorkout) {
            if let id = workout?.id { WorkoutSessionView(workoutID: id) }
        }
        .sheet(isPresented: $showWhy) {
            if let id = workout?.id { WhySheet(workoutID: id, onStart: { showWhy = false; showWorkout = true }) }
        }
    }

    // MARK: Pieces

    func header(_ workout: PlannedWorkout?) -> some View {
        let t = store.today
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                let context = store.calendar.contextLabel(on: t)
                ViewThatFits(in: .horizontal) {
                    Text("\(t.shortDisplay) · \(context)").lineLimit(1)
                    VStack(alignment: .leading, spacing: -2) {
                        Text(t.shortDisplay)
                        Text(context).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                .hand(21, .semibold, color: Palette.muted)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("blockContext")
                Text("Hey, \(store.settings.greetingName)")
                    .bodyText(30, .heavy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                DrawnStroke(shape: Squiggle(), color: Palette.tangerine, lineWidth: 4)
                    .frame(width: 160, height: 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Circle().fill(Palette.bubblegum)
                .overlay(Circle().strokeBorder(.white, lineWidth: 4))
                .overlay(KettleFace().frame(width: 58, height: 60).offset(y: -2))
                .frame(width: 88, height: 88)
                .stickerShadow()
                .slapOn(rotation: 10, delay: 0.4)
                .padding(.trailing, 2)
                .accessibilityLabel("Kettle sticker")
        }
        .padding(.top, 24)
        .padding(.bottom, 6)
    }

    var stickerPage: some View {
        PaperCard(rotation: -1, tape: WashiTape(color: Palette.sunny, stripe: Palette.sunnyLight, width: 80, height: 20, angle: -3)) {
            VStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("my sticker page").hand(24)
                    Spacer()
                    Text("last 12 workouts").hand(18, .semibold, color: Palette.muted)
                }
                let slots = store.stickerSlots
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                    ForEach(Array(slots.enumerated()), id: \.offset) { i, slot in
                        StickerSlotView(slot: slot, index: i)
                    }
                }
                if slots.isEmpty {
                    Text("Finish a workout to stick your first sticker!").hand(18, .semibold, color: Palette.muted)
                }
            }
        }
    }

    var statCards: some View {
        let streak = store.streak
        let c = store.completion
        return HStack(alignment: .top, spacing: 14) {
            PaperCard(rotation: -2, tape: WashiTape(color: Palette.bubblegum, stripe: Palette.bubblegumLight, width: 56, angle: 4),
                      tapeAlignment: .topLeading, ruled: 22, padding: EdgeInsets(top: 14, leading: 12, bottom: 10, trailing: 12)) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("streak").hand(21, color: Palette.tangerineDeep)
                    Text("\(streak.current)").bodyText(48, .heavy)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 70, minHeight: 62)
                        .background {
                            // The hand-drawn loop grows with the number.
                            DrawnStroke(shape: HandCircle(), color: Palette.tangerine, lineWidth: 3, delay: 1.3)
                                .padding(.horizontal, -2)
                        }
                        .frame(maxWidth: 120, alignment: .leading)
                    Text("workouts in a row").hand(19)
                    Text("best ever: \(streak.best)").hand(19, color: Palette.muted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Streak: \(streak.current) workouts in a row. Best ever \(streak.best).")
            }
            PaperCard(rotation: 1.5, tape: WashiTape(color: Palette.mint, stripe: Palette.mintLight, width: 56, angle: -5),
                      tapeAlignment: .topTrailing, ruled: 22, padding: EdgeInsets(top: 14, leading: 12, bottom: 10, trailing: 12)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("last 30 days").hand(21, color: Palette.skyDeep)
                    if let percent = c.percent {
                        Text("\(percent)%")
                            .bodyText(44, .heavy)
                            .background(alignment: .bottom) { Highlighter().frame(height: 22).padding(.horizontal, -5).offset(y: -4) }
                        Text("\(c.done) of \(c.planned) planned").hand(19)
                        Text(c.excused > 0 ? "sick days excused" : "sick days don't count").hand(19, color: Palette.muted)
                    } else {
                        Text("new!")
                            .bodyText(44, .heavy)
                            .background(alignment: .bottom) { Highlighter().frame(height: 22).padding(.horizontal, -5).offset(y: -4) }
                        Text("your first month\nstarts now").hand(19)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(c.percent.map { "Last 30 days: \($0) percent, \(c.done) of \(c.planned) planned workouts done." }
                                    ?? "Last 30 days: new. Your first month starts now.")
            }
        }
        .padding(.top, 4)
    }

    func startButton(_ w: PlannedWorkout) -> some View {
        let isToday = w.date == store.today
        return VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 4) {
                Text(isToday ? "you've got this!" : "next up: \(w.date.weekday.shortName)").hand(22, color: Palette.berry)
                DrawnStroke(shape: DoodleArrow(), color: Palette.berry, lineWidth: 2.5, delay: 0)
                    .frame(width: 28, height: 30)
                    .nudge()
            }
            .padding(.trailing, 78) // stay clear of the barbell sticker on the button
            Button {
                showWorkout = true
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(isToday ? "Let's lift!" : "Preview \(w.date.weekday.shortName)").bodyText(26, .heavy)
                    Text("\(w.mainLift?.displayName ?? "Workout") day · then pick your sticker").bodyText(14).opacity(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
                .background(UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 30, bottomTrailingRadius: 24, topTrailingRadius: 28)
                    .fill(Palette.tangerine))
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Palette.sunny)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 3.5))
                        .overlay(BarbellIcon(plate: Palette.tangerine).frame(width: 34))
                        .frame(width: 58, height: 58)
                        .stickerShadow()
                        .rotationEffect(.degrees(-12))
                        .pulse()
                        .offset(x: -14, y: -14)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .jiggle()
            .accessibilityIdentifier("startWorkout")
            .accessibilityHint("Opens today's workout")
        }
    }

    func todaysList(_ w: PlannedWorkout) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("today's list").hand(25)
                    Button("why this? / shuffle") { showWhy = true }
                        .font(Typeface.hand(19))
                        .foregroundStyle(Palette.berry)
                        .accessibilityIdentifier("whyThis")
                }
                ForEach(w.sections) { s in
                    HStack(spacing: 10) {
                        ZStack {
                            DoodleSquare().fill(s.kind.color)
                            DoodleSquare().stroke(Palette.ink, lineWidth: 2)
                        }
                        .frame(width: 20, height: 20)
                        Text(s.kind.displayName.capitalizedFirst).bodyText(15).fixedSize()
                        ViewThatFits(in: .horizontal) {
                            Text(s.todayDetail(compact: false)).lineLimit(1)
                            Text(s.todayDetail(compact: true)).lineLimit(1)
                            Text(s.todayDetail(compact: true)).lineLimit(1).minimumScaleFactor(0.75)
                        }
                        .bodyText(15, .medium, color: Palette.muted)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Spacer(minLength: 0)
            if let lift = w.mainLift {
                VStack(spacing: -4) {
                    BearView(lift: lift, size: 112)
                    Text("bear says:\n\(lift.displayName.lowercased())!").hand(17).multilineTextAlignment(.center)
                }
                .offset(x: 8)
            }
        }
        .frame(minHeight: 130)
    }

    var doneForToday: some View {
        PaperCard(rotation: 0.8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("done for today!").hand(26, color: Palette.mintDeep)
                Text("Rest up. Your next workout gets planned after your sticker goes on.").bodyText(14, .semibold)
            }
        }
    }
}

/// Kettle's pink ticket note.
@MainActor
struct KettleNote: View {
    var note: CoachNote

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.title).hand(21, color: Palette.berry)
            Text(note.message).bodyText(14).lineSpacing(3)
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 18, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.pinkPaper)
        .clipShape(ZigzagBottom())
        .rotationEffect(.degrees(1))
        .accessibilityElement(children: .combine)
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
