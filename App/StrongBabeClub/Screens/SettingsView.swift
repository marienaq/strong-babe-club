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

    var body: some View {
        NavigationStack {
            Form {
                Section("You") {
                    TextField("Display name (optional)", text: $draft.displayName)
                        .textContentType(.nickname)
                        .accessibilityHint("Used only for the greeting. Stays on this phone.")
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
                    Toggle("Avoid jumping", isOn: $draft.limits.avoidJumping)
                    Toggle("Go easy on the knee", isOn: $draft.limits.easyOnKnee)
                    Toggle("Go easy on the wrist", isOn: $draft.limits.easyOnWrist)
                } header: { Text("Limits") } footer: {
                    Text("Box jumps become step-ups, burpees become up/downs, and so on. Benchmarks with a swapped move are marked \"modified\".")
                }
                Section("Equipment") {
                    Toggle("Barbell + plates", isOn: $draft.equipment.hasBarbell)
                    Stepper("Bar: \(formatPounds(draft.equipment.barWeight)) lb", value: $draft.equipment.barWeight, in: 15...55, step: 5)
                    NumberListField(title: "Plate pairs (lb)", values: $draft.equipment.platePairs, allowDuplicates: true)
                    NumberListField(title: "Dumbbells (lb)", values: $draft.equipment.dumbbells)
                    NumberListField(title: "Kettlebells (lb)", values: $draft.equipment.kettlebells)
                    NumberListField(title: "Boxes (in)", values: Binding(get: { draft.equipment.boxHeights.map(Double.init) },
                                                                        set: { draft.equipment.boxHeights = $0.map { Int($0) } }))
                    Toggle("Medicine ball (12 lb)", isOn: Binding(get: { draft.equipment.medicineBall != nil },
                                                                 set: { draft.equipment.medicineBall = $0 ? 12 : nil }))
                    Toggle("Bench", isOn: $draft.equipment.hasBench)
                    Toggle("Bar for Australian pull-ups", isOn: $draft.equipment.hasLowBar)
                    Toggle("Bike", isOn: $draft.equipment.hasBike)
                    let calc = PlateCalculator(inventory: draft.equipment)
                    Text("Heaviest barbell load: \(formatPounds(calc.maxLoadable)) lb · smallest jump \(formatPounds(calc.smallestStep)) lb")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Program") {
                    DatePicker("First test week", selection: dateBinding(\.testWeekStart), displayedComponents: .date)
                    DatePicker("A Monday of week A", selection: dateBinding(\.rotationAnchor), displayedComponents: .date)
                    NavigationLink("Training maxes") { TrainingMaxView() }
                    NavigationLink("Benchmarks (\(store.benchmarks.filter(\.active).count) active)") { BenchmarksView() }
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
            message = try store.importFile(data)
            Task { await store.prepare() }
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
        .onAppear { text = values.map(formatPounds).joined(separator: ", ") }
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
        List {
            Section {
                ForEach(Lift.allCases, id: \.self) { lift in
                    let p = store.liftPrograms[lift]
                    Stepper(value: Binding(get: { p?.trainingMax ?? 45 }, set: { store.setTrainingMax(lift, $0) }), in: 45...600, step: 5) {
                        VStack(alignment: .leading) {
                            Text(lift.displayName)
                            Text("\(formatPounds(p?.trainingMax ?? 0)) lb · from \(p?.source.rawValue ?? "history")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("Training max = 90% of your estimated 1-rep max. It goes up +10 lb (lower body) or +5 lb (presses, Olympic lifts) each block, or resets from the week-13 test, whichever is lower.")
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
