import SwiftUI
import WorkoutCore

/// First-run setup for a new person: six short steps, all editable later in
/// Settings. Existing installs never see it.
@MainActor
struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @AppStorage(Animal.storageKey) private var animal: Animal = .bear
    @State private var step = 0
    @State private var c = AppStore.OnboardingChoices()
    @State private var startMode = 2 // 0 test week, 1 manual, 2 start light
    @State private var manual: [Lift: String] = [:]

    static let steps = ["hello", "units", "days", "lifts", "limits", "buddy & start"]

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("step \(step + 1) of \(Self.steps.count)").hand(18, color: Palette.muted)
                    Spacer()
                    if step < Self.steps.count - 1 {
                        Button("skip setup") { finish() }.font(Typeface.hand(18)).foregroundStyle(Palette.muted)
                            .accessibilityIdentifier("skipOnboarding")
                    }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) { page }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 10) {
                    if step > 0 {
                        Button { step -= 1 } label: {
                            Text("back").bodyText(16, .heavy).frame(maxWidth: .infinity, minHeight: 52)
                                .background(RoundedRectangle(cornerRadius: 22).fill(.white))
                        }
                    }
                    Button { step < Self.steps.count - 1 ? (step += 1) : finish() } label: {
                        Text(step < Self.steps.count - 1 ? "next" : "let's lift!").bodyText(17, .heavy)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(RoundedRectangle(cornerRadius: 24).fill(Palette.tangerine))
                    }
                    .disabled(step == 2 && c.schedule.isEmpty)
                    .accessibilityIdentifier("onboardingNext")
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 44).padding(.trailing, 20).padding(.vertical, 16)
        }
    }

    @ViewBuilder var page: some View {
        switch step {
        case 0:
            HStack(alignment: .center) {
                Text("hi! I'm Kettle.").bodyText(30, .heavy).accessibilityAddTraits(.isHeader)
                Spacer()
                Circle().fill(Palette.bubblegum).overlay(KettleFace().frame(width: 52)).frame(width: 78, height: 78).stickerShadow()
            }
            Text("I plan every workout for you: warm-up, strength, a sweaty metabolic piece and a cool-down. Let's set you up in a minute.")
                .bodyText(15, .semibold)
            Text.caveat("what should I call you?").hand(22)
            TextField("your name (optional)", text: $c.name)
                .font(Typeface.hand(24, .regular))
                .padding(.vertical, 6)
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.inputLine).frame(height: 2) }
                .accessibilityIdentifier("onboardingName")
        case 1:
            Text.caveat("pounds or kilos?").hand(28)
            Picker("Units", selection: $c.unit) {
                Text("lb").tag(WeightUnit.lb)
                Text("kg").tag(WeightUnit.kg)
            }
            .pickerStyle(.segmented)
            let preset = EquipmentInventory.preset(c.unit)
            PaperCard(rotation: -0.6) {
                VStack(alignment: .leading, spacing: 4) {
                    Text.caveat("starting gym (edit later in Settings)").hand(19, color: Palette.muted)
                    let u = c.unit.symbol
                    Text("Bar \(formatWeight(preset.barWeight)) \(u) · plates \(preset.platePairs.map(formatPounds).joined(separator: ", ")) \(u)").bodyText(14, .semibold)
                    Text("Dumbbells \(preset.dumbbells.map(formatWeight).joined(separator: ", ")) · kettlebells \(preset.kettlebells.map(formatWeight).joined(separator: ", ")) \(u)").bodyText(14, .semibold)
                }
            }
        case 2:
            Text.caveat("which days do you train?").hand(28)
            Text("Most people do 2-4 days. Your lifts rotate through whatever you pick.").bodyText(14, .semibold, color: Palette.muted)
            FlowLayout(spacing: 8) {
                ForEach(Weekday.allCases, id: \.self) { d in
                    let on = c.schedule.contains(d)
                    Button {
                        if on { c.schedule.removeAll { $0 == d } } else { c.schedule.append(d) }
                    } label: { chip(d.shortName, on: on) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(d.rawValue.capitalized)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        case 3:
            Text.caveat("your main lifts").hand(28)
            Text("Pick at least two. They take turns, one per training day.").bodyText(14, .semibold, color: Palette.muted)
            ForEach(Lift.allCases, id: \.self) { lift in
                let on = c.lifts.contains(lift)
                Toggle(lift.displayName, isOn: Binding(get: { on }, set: { v in
                    if v { c.lifts.append(lift) } else if c.lifts.count > 2 { c.lifts.removeAll { $0 == lift } }
                }))
                .font(Typeface.body(16))
                .tint(Palette.tangerine)
            }
        case 4:
            Text.caveat("anything to go easy on?").hand(28)
            Toggle("Avoid jumping", isOn: $c.limits.avoidJumping).tint(Palette.tangerine)
            Toggle("Go easy on the knee", isOn: $c.limits.easyOnKnee).tint(Palette.tangerine)
            Toggle("Go easy on the wrist", isOn: $c.limits.easyOnWrist).tint(Palette.tangerine)
            Text("Moves get swapped for friendlier versions (box jumps become step-ups, and so on).").bodyText(14, .semibold, color: Palette.muted)
        default:
            Text.caveat("pick a lifting buddy").hand(28)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Animal.allCases) { a in
                        Button { animal = a } label: {
                            VStack(spacing: 0) {
                                BearView(lift: .frontSquat, size: 60, frozenAt: 0.45, animal: a)
                                Text(a.displayName).hand(15)
                            }
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: 12).fill(animal == a ? Palette.sunnyPale : .clear))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(a.displayName)
                        .accessibilityAddTraits(animal == a ? .isSelected : [])
                    }
                }
            }
            Text.caveat("how do you want to start?").hand(24)
            Picker("Start", selection: $startMode) {
                Text("start light").tag(2)
                Text("I know my weights").tag(1)
                Text("test week").tag(0)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("startMode")
            switch startMode {
            case 0: Text("Two test weeks from next Monday: one lift per session, worked up to a heavy 3 (never a true max). Training starts after.").bodyText(14, .semibold)
            case 1:
                Text("Heaviest weight you can lift 5 times, per lift (\(c.unit.symbol)). Leave blank if unsure.").bodyText(14, .semibold)
                ForEach(c.lifts, id: \.self) { lift in
                    HStack {
                        Text(lift.displayName).bodyText(15)
                        Spacer()
                        TextField(c.unit.symbol, text: Binding(get: { manual[lift] ?? "" }, set: { manual[lift] = $0 }))
                            .numberKeyboard().multilineTextAlignment(.trailing).frame(width: 80)
                            .accessibilityLabel("\(lift.displayName) five-rep weight in \(c.unit.symbol)")
                    }
                }
            default: Text("Starts with an empty bar and builds up steadily. Perfect if you're new or coming back.").bodyText(14, .semibold)
            }
        }
    }

    func chip(_ text: String, on: Bool) -> some View {
        Text(text).bodyText(15, on ? .heavy : .bold, color: on ? Palette.ink : Palette.muted)
            .padding(.horizontal, 14).frame(minHeight: 40)
            .background(Capsule().fill(on ? Palette.sunny : .clear))
            .overlay(Capsule().strokeBorder(on ? .white : Palette.dashed, style: StrokeStyle(lineWidth: on ? 2.5 : 2, dash: on ? [] : [4, 3])))
    }

    func finish() {
        if c.schedule.isEmpty { c.schedule = [.monday, .wednesday, .friday] }
        switch startMode {
        case 0: c.start = .testWeek
        case 1:
            var sets: [Lift: Double] = [:]
            for (lift, text) in manual {
                if let v = Double(text.replacingOccurrences(of: ",", with: ".")), v.isFinite, v > 0, v < 600 { sets[lift] = v }
            }
            c.start = sets.isEmpty ? .startLight : .manual(sets)
        default: c.start = .startLight
        }
        store.completeOnboarding(c)
    }
}
