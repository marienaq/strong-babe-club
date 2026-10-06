import SwiftUI
import UniformTypeIdentifiers
import WorkoutCore

/// Settings: name, schedule, limits, equipment, program, benchmarks, data.
@MainActor
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var draft = PlannerSettings.default
    @State private var showImporter = false
    @State private var exportDoc: ExportDocument?
    @State private var exportType: UTType = .json
    @State private var showExporter = false
    @State private var message: String?
    @State private var confirmDelete = false
    @AppStorage(TimerSound.defaultsKey) private var timerSounds = true
    @AppStorage(TimerSound.packKey) private var soundPack: SoundPack = .boxing
    @AppStorage(Animal.storageKey) private var animal: Animal = .bear

    var body: some View {
        NavigationStack {
            Form {
                Section("You") {
                    TextField("Display name (optional)", text: $draft.displayName)
                        .textContentType(.nickname)
                        .accessibilityHint("Used only for the greeting. Stays on this phone.")
                }
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Animal.allCases) { a in
                                Button { animal = a } label: {
                                    VStack(spacing: 2) {
                                        BearView(lift: .frontSquat, size: 64, frozenAt: 0.45, animal: a)
                                        Text(a.displayName).font(Typeface.hand(16)).foregroundStyle(Palette.ink)
                                    }
                                    .padding(6)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(animal == a ? Palette.sunnyPale : .clear))
                                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(animal == a ? Palette.sunny : .clear, lineWidth: 2))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(a.displayName)
                                .accessibilityAddTraits(animal == a ? .isSelected : [])
                                .accessibilityIdentifier("animal-\(a.rawValue)")
                            }
                        }
                    }
                } header: { Text("Your lifting buddy") } footer: {
                    Text("They act out every lift on Today and during workouts. Kettle stays your coach.")
                }
                Section("Schedule") {
                    ForEach(Weekday.allCases, id: \.self) { day in
                        Toggle(day.rawValue.capitalized, isOn: Binding(
                            get: { draft.schedule.contains(day) },
                            set: { on in
                                if on { draft.schedule.append(day) } else { draft.schedule.removeAll { $0 == day } }
                            }))
                    }
                    Stepper("Target length: \(draft.targetMinutes) min", value: $draft.targetMinutes, in: 30...90, step: 5)
                }
                Section {
                    Toggle("Timer sounds", isOn: $timerSounds)
                        .accessibilityIdentifier("timerSoundsToggle")
                    ForEach(SoundPack.allCases, id: \.self) { pack in
                        HStack {
                            Button {
                                soundPack = pack
                            } label: {
                                HStack {
                                    Image(systemName: soundPack == pack ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(soundPack == pack ? Palette.tangerine : Palette.faint)
                                    Text(pack.displayName).foregroundStyle(Palette.ink)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(soundPack == pack ? .isSelected : [])
                            Spacer()
                            Button {
                                TimerSound.shared.play(.roundEndRest, pack: pack)
                            } label: {
                                Label("Preview", systemImage: "play.circle").labelStyle(.iconOnly).font(.title3)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Preview \(pack.displayName)")
                        }
                        .disabled(!timerSounds)
                        .accessibilityIdentifier("pack-\(pack.rawValue)")
                    }
                } header: { Text("Timers") } footer: {
                    Text("Each pack has a round-over sound, a \"go\" cue for work and a calmer cue for rest. Tap play to preview. Sounds play over your music and with the silent switch on; the phone always buzzes too.")
                }
                Section {
                    Toggle("Avoid jumping", isOn: $draft.limits.avoidJumping)
                    Toggle("Go easy on the knee", isOn: $draft.limits.easyOnKnee)
                    Toggle("Go easy on the wrist", isOn: $draft.limits.easyOnWrist)
                } header: { Text("Limits") } footer: {
                    Text("Box jumps become step-ups, burpees become up/downs, and so on. Benchmarks with a swapped move are marked \"modified\".")
                }
                Section {
                    Picker("Units", selection: Binding(get: { store.unit }, set: { u in
                        store.switchUnits(to: u)
                        draft = store.settings
                    })) {
                        Text("lb").tag(WeightUnit.lb)
                        Text("kg").tag(WeightUnit.kg)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("unitsPicker")
                } header: { Text("Units") } footer: {
                    Text("Switching loads a typical \(store.unit == .lb ? "kg" : "lb") gym you can edit below. Your logged history is kept exactly; it's just shown in the new unit.")
                }
                Section("Equipment (\(draft.equipment.unit.symbol))") {
                    let u = draft.equipment.unit.symbol
                    Toggle("Barbell + plates", isOn: $draft.equipment.hasBarbell)
                    Picker("Bar", selection: $draft.equipment.barWeight) {
                        ForEach(Array(Set(EquipmentInventory.barOptions(draft.equipment.unit) + [draft.equipment.barWeight])).sorted(by: >), id: \.self) {
                            Text("\(formatWeight($0)) \(u)").tag($0)
                        }
                    }
                    NumberListField(title: "Plate pairs (\(u))", values: $draft.equipment.platePairs, allowDuplicates: true)
                    NumberListField(title: "Dumbbells (\(u))", values: $draft.equipment.dumbbells)
                    NumberListField(title: "Kettlebells (\(u))", values: $draft.equipment.kettlebells)
                    NumberListField(title: "Boxes (in)", values: Binding(get: { draft.equipment.boxHeights.map(Double.init) },
                                                                        set: { draft.equipment.boxHeights = $0.map { Int($0) } }))
                    Toggle("Medicine ball (\(draft.equipment.unit == .kg ? "6 kg" : "12 lb"))", isOn: Binding(get: { draft.equipment.medicineBall != nil },
                                                                 set: { draft.equipment.medicineBall = $0 ? (draft.equipment.unit == .kg ? 6 : 12) : nil }))
                    Toggle("Bench", isOn: $draft.equipment.hasBench)
                    Toggle("Bar for Australian pull-ups", isOn: $draft.equipment.hasLowBar)
                    Toggle("Bike", isOn: $draft.equipment.hasBike)
                    let calc = PlateCalculator(inventory: draft.equipment)
                    Text("Heaviest barbell load: \(formatWeight(calc.maxLoadable)) \(u) · smallest jump \(formatWeight(calc.smallestStep)) \(u)")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Program") {
                    DatePicker("First test week", selection: dateBinding(\.testWeekStart), displayedComponents: .date)
                    NavigationLink("Training maxes") { TrainingMaxView() }
                    NavigationLink("Benchmarks (\(store.benchmarks.filter(\.active).count) active)") { BenchmarksView() }
                    NavigationLink("Breaks (\(store.settings.breaks.count))") { BreaksView() }
                        .accessibilityIdentifier("breaksLink")
                }
                Section {
                    Button("Import history or backup (JSON)…") { showImporter = true }
                    Button("Export backup (JSON)…") { export(json: true) }
                    Button("Export set logs (CSV)…") { export(json: false) }
                    Button("Delete all data…", role: .destructive) { confirmDelete = true }
                } header: { Text("Data") } footer: {
                    Text("Everything stays on this iPhone, encrypted while it's locked. Nothing is uploaded; exports only happen when you choose to share them.")
                }
            }
            .navigationTitle("Settings")
            .disabled(store.importProgress != nil)
            .overlay {
                if let p = store.importProgress {
                    VStack(spacing: 10) {
                        Text("Importing your history…").font(.headline)
                        ProgressView(value: Double(p.done), total: Double(max(p.total, 1)))
                        Text("\(p.done) of \(p.total) workouts").font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .frame(maxWidth: 280)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.regularMaterial))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("importProgress")
                }
            }
            .onAppear { draft = store.settings }
            .onDisappear { if draft != store.settings { store.updateSettings(draft) } }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.updateSettings(draft); message = "Saved." }.disabled(draft == store.settings)
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                handleImport(result)
            }
            .fileExporter(isPresented: $showExporter, document: exportDoc, contentType: exportType,
                          defaultFilename: exportType == .json ? "strong-babe-club-backup" : "strong-babe-club-sets") { result in
                if case .failure = result { message = "Export didn't finish." }
                exportDoc = nil
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
            .confirmationDialog("Delete every workout, log and setting on this phone?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete all data", role: .destructive) { store.deleteAllData(); draft = store.settings }
            }
        }
    }

    func dateBinding(_ key: WritableKeyPath<PlannerSettings, LocalDate>) -> Binding<Date> {
        Binding(
            get: {
                let d = draft[keyPath: key]
                return Calendar.current.date(from: DateComponents(year: d.year, month: d.month, day: d.day)) ?? Date()
            },
            set: { draft[keyPath: key] = LocalDate.today($0).startOfWeek })
    }

    /// Reads a user-picked file with security-scoped access, a size cap and
    /// strict decoding (WorkoutCore validates and bounds every value).
    func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= ImportLimits.standard.maxBytes else {
                throw ImportError.tooLarge(bytes: size, limit: ImportLimits.standard.maxBytes)
            }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            Task {
                do {
                    message = try await store.importFile(data)
                    await store.prepare()
                } catch let e as ImportError {
                    message = e.description
                } catch let e as StoreError {
                    message = e.description
                } catch {
                    message = "Couldn't import that file."
                    Log.importer.error("import failed [\(Log.kind(error), privacy: .public)]")
                }
            }
        } catch let e as ImportError {
            message = e.description
        } catch {
            message = "Couldn't read that file."
            Log.importer.error("import failed [\(Log.kind(error), privacy: .public)]")
        }
    }

    func export(json: Bool) {
        do {
            if json {
                exportDoc = ExportDocument(data: try store.exportBackup())
                exportType = .json
            } else {
                exportDoc = ExportDocument(data: Data(store.exportCSV().utf8))
                exportType = .commaSeparatedText
            }
            showExporter = true
        } catch {
            message = "Couldn't prepare the export."
        }
    }
}

/// In-memory document handed to `fileExporter` (no temp files left behind).
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

/// Comma-separated numbers, validated on commit.
@MainActor
struct NumberListField: View {
    var title: String
    @Binding var values: [Double]
    var allowDuplicates = false
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
            TextField("e.g. 10, 15, 20", text: $text)
                .numberKeyboard()
                .onSubmit(commit)
                .onChange(of: text) { _, _ in commit() }
        }
        .onAppear { text = values.map(formatWeight).joined(separator: ", ") }
    }

    func commit() {
        var parsed = text.split(whereSeparator: { $0 == "," || $0 == " " })
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            .filter { $0.isFinite && $0 > 0 && $0 <= 200 }
        if !allowDuplicates { parsed = Array(Set(parsed)) }
        values = Array(parsed.sorted().prefix(30))
    }
}

@MainActor
struct TrainingMaxView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let unit = store.unit
        List {
            Section {
                ForEach(Lift.allCases, id: \.self) { lift in
                    let p = store.liftPrograms[lift]
                    let shown = unit.fromPounds(p?.trainingMax ?? unit.toPounds(unit == .kg ? 20 : 45))
                    Stepper(value: Binding(get: { shown }, set: { store.setTrainingMax(lift, unit.toPounds($0)) }),
                            in: (unit == .kg ? 20 : 45)...(unit == .kg ? 300 : 600), step: unit.roundingStep) {
                        VStack(alignment: .leading) {
                            Text(lift.displayName)
                            Text("\(formatWeight(shown)) \(unit.symbol) · from \(p?.source.rawValue ?? "history")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text(unit == .kg
                     ? "Training max = 90% of your estimated 1-rep max. It goes up about 4.5 kg (lower body) or 2.5 kg (presses, Olympic lifts) each block, or resets from the week-13 test, whichever is lower."
                     : "Training max = 90% of your estimated 1-rep max. It goes up +10 lb (lower body) or +5 lb (presses, Olympic lifts) each block, or resets from the week-13 test, whichever is lower.")
            }
        }
        .navigationTitle("Training maxes")
    }
}

@MainActor
struct BenchmarksView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        List {
            Section {
                ForEach(store.benchmarks) { b in
                    Toggle(isOn: Binding(get: { b.active }, set: { store.setBenchmark(b.id, active: $0) })) {
                        VStack(alignment: .leading) {
                            Text(b.name).font(.headline)
                            Text("due from block week \(BenchmarkScheduler.dueWeek(forSlot: b.quarterSlot)) · \(b.template.instructions)")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
            } footer: {
                Text("Each benchmark repeats exactly once a quarter so you can beat your score.")
            }
            Section {
                Button("Propose 6 from my history") { store.proposeBenchmarks() }
            }
        }
        .navigationTitle("Benchmarks")
    }
}

/// Planned breaks (vacations): scheduled days inside are excused, so they
/// neither break nor extend the streak. Nothing is added automatically.
@MainActor
struct BreaksView: View {
    @Environment(AppStore.self) private var store
    @State private var label = ""
    @State private var from = Date()
    @State private var to = Date().addingTimeInterval(7 * 86_400)

    var body: some View {
        JournalPage {
            Text("breaks").bodyText(32, .heavy).padding(.top, 8).accessibilityAddTraits(.isHeader)
            Text("Planned time off: days inside a break don't count against your streak or your 30-day %.")
                .bodyText(14, .semibold, color: Palette.muted)
            if store.settings.breaks.isEmpty {
                Text.caveat("no breaks yet").hand(20, color: Palette.muted)
            }
            ForEach(Array(store.settings.breaks.enumerated()), id: \.element.id) { i, b in
                PaperCard(rotation: i % 2 == 0 ? -0.8 : 0.8, tape: WashiTape.forKind(.cooldown, width: 50, angle: i % 2 == 0 ? -4 : 4)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text.caveat(b.label).hand(22)
                            Text("\(b.from.shortDisplay) – \(b.to.shortDisplay)").bodyText(13, .semibold, color: Palette.muted)
                        }
                        Spacer()
                        Button(role: .destructive) { store.removeBreak(b.id) } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(Palette.faint)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(b.label)")
                    }
                }
            }
            PaperCard(rotation: 0.6, tape: WashiTape(color: Palette.sunny, stripe: Palette.sunnyLight, width: 60, angle: -3)) {
                VStack(alignment: .leading, spacing: 8) {
                    Text.caveat("add a break").hand(22, color: Palette.tangerineDeep)
                    TextField("label, e.g. holiday", text: $label)
                        .font(Typeface.hand(20, .regular))
                        .padding(.vertical, 4)
                        .overlay(alignment: .bottom) { Rectangle().fill(Palette.inputLine).frame(height: 2) }
                        .accessibilityIdentifier("breakLabel")
                    DatePicker("from", selection: $from, displayedComponents: .date).font(Typeface.hand(19))
                    DatePicker("to", selection: $to, in: from..., displayedComponents: .date).font(Typeface.hand(19))
                    Button {
                        store.addBreak(label: label, from: LocalDate.today(from), to: LocalDate.today(to))
                        label = ""
                    } label: {
                        Text("add break").bodyText(16, .heavy)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: 20).fill(Palette.mint))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("addBreak")
                }
            }
        }
        .navigationTitle("Breaks")
        .inlineNavigationTitle()
    }
}
