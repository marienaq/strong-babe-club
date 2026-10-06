import Foundation
import Observation
import WorkoutCore

/// Result shown on the Finish screen after "stick it in my journal".
struct FinishSummary: Equatable {
    var streak: Int
    var prLifts: [Lift: Double]
    var benchmarkPR: Bool
    var isPRDay: Bool { !prLifts.isEmpty || benchmarkPR }
}

/// App state + actions. Holds value-type WorkoutCore models; persistence goes
/// through `Repository`. All planning goes through the `WorkoutPlanner`
/// protocol, so an AI planner can be swapped in later.
@MainActor
@Observable
final class AppStore {
    private(set) var settings: PlannerSettings = .default
    private(set) var workouts: [PlannedWorkout] = []
    private(set) var liftPrograms: [Lift: LiftProgram] = [:]
    private(set) var benchmarks: [Benchmark] = []
    private(set) var goals: [Goal] = []
    var lastError: String?
    private(set) var isPlanning = false
    /// Non-nil while a file import is being saved (done, total).
    private(set) var importProgress: (done: Int, total: Int)?
    static let importBatchSize = 50

    let planner: any WorkoutPlanner
    private let repo: Repository
    private let clock: () -> Date

    init(repository: Repository, planner: any WorkoutPlanner = RulesWorkoutPlanner(), clock: @escaping () -> Date = Date.init) {
        self.repo = repository
        self.planner = planner
        self.clock = clock
    }

    var now: Date { clock() }
    var today: LocalDate { LocalDate.today(clock()) }
    var calendar: ProgramCalendar { settings.calendar }
    /// Display/entry unit. Stored weights are canonical pounds.
    var unit: WeightUnit { settings.units }
    /// "135" or "61.2" for a canonical weight.
    func fmt(_ pounds: Double) -> String { unit.format(pounds: pounds) }
    /// "135 lb" or "61.2 kg".
    func label(_ pounds: Double) -> String { unit.label(pounds: pounds) }
    var visibleWorkouts: [PlannedWorkout] { workouts.filter { !$0.isDeleted } }

    // MARK: Loading

    func load() {
        do {
            let d = try repo.load()
            settings = d.settings.sanitized()
            workouts = d.workouts.sorted { $0.date < $1.date }
            liftPrograms = Dictionary(d.liftPrograms.map { ($0.lift, $0) }, uniquingKeysWith: { _, b in b })
            benchmarks = d.benchmarks
            goals = d.goals
            clearImportedStickers()
            migrateOnboarding()
            Log.store.info("loaded \(self.workouts.count, privacy: .public) workouts")
        } catch {
            fail("Couldn't open your journal.", error)
        }
    }

    /// Backfills missed days, rolls training maxes forward and makes sure the
    /// next workout is planned (re-planning untouched future plans).
    func prepare() async {
        guard settings.onboarded else { return } // nothing to plan until set up
        let t = today
        backfillMissedDays(through: t.adding(days: -1))
        rollTrainingMaxes(asOf: t)
        await ensurePlan(for: nextPlanDate(after: t))
    }

    func nextPlanDate(after t: LocalDate) -> LocalDate {
        let rotation = settings.rotation
        if let existing = workout(on: t), existing.status == .planned { return t }
        if rotation.isScheduled(t), workout(on: t) == nil { return t }
        return rotation.nextScheduledDate(onOrAfter: t.adding(days: 1))
    }

    private func backfillMissedDays(through end: LocalDate) {
        guard let last = visibleWorkouts.map(\.date).max(), last < end else { return }
        let from = max(last.adding(days: 1), end.adding(days: -60))
        let missing = MissedDays.backfill(schedule: settings.sortedSchedule, from: from, to: end, existing: visibleWorkouts)
        guard !missing.isEmpty else { return }
        let added = missing.map { PlannedWorkout(date: $0, status: .planned, source: "missed", sync: SyncStamp(createdAt: now)) }
        upsert(added)
    }

    private func rollTrainingMaxes(asOf date: LocalDate) {
        let next = TrainingMaxBook.programs(asOf: date, current: liftPrograms, history: visibleWorkouts, calendar: calendar,
                                            barWeight: settings.equipment.barWeight)
        guard next != liftPrograms else { return }
        liftPrograms = next
        persist { try repo.save(liftPrograms: Array(next.values).sorted { $0.lift < $1.lift }) }
    }

    func request(for date: LocalDate, salts: SectionSalts = SectionSalts(), id: UUID? = nil) -> PlanRequest {
        PlanRequest(date: date, settings: settings, history: visibleWorkouts,
                    trainingMaxes: liftPrograms.mapValues(\.trainingMax), benchmarks: benchmarks,
                    salts: salts, now: now, workoutID: id)
    }

    func ensurePlan(for date: LocalDate) async {
        let existing = workout(on: date)
        if let existing, existing.status != .planned || hasLogs(existing) || existing.source != "rules-v1" && existing.source != "missed" {
            return
        }
        isPlanning = true
        defer { isPlanning = false }
        do {
            var w = try await planner.plan(request(for: date, salts: existing?.salts ?? SectionSalts(), id: existing?.id))
            if let existing { w.sync = SyncStamp(createdAt: existing.sync.createdAt, updatedAt: now) }
            if w != existing { upsert([w]) }
        } catch {
            fail("Couldn't plan the next workout.", error)
        }
    }

    // MARK: Queries

    func workout(id: UUID) -> PlannedWorkout? { workouts.first { $0.id == id } }
    func workout(on date: LocalDate) -> PlannedWorkout? {
        let sameDay = visibleWorkouts.filter { $0.date == date }
        return sameDay.first { $0.status == .done } ?? sameDay.first
    }

    /// The workout the Today screen offers (today's, or the next planned one).
    var nextWorkout: PlannedWorkout? {
        let t = today
        if let w = workout(on: t), w.status == .planned { return w }
        return visibleWorkouts.first { $0.date > t && $0.status == .planned && !$0.sections.isEmpty }
    }

    var todayIsDone: Bool { workout(on: today)?.status == .done }
    var streak: StreakSummary { Motivation.streak(visibleWorkouts, today: today, schedule: settings.sortedSchedule, breaks: settings.breaks) }
    var completion: CompletionSummary {
        Motivation.completion(visibleWorkouts, today: today, schedule: settings.sortedSchedule, breaks: settings.breaks)
    }
    /// Missed scheduled days for the Journal (long gaps grouped).
    var missedEntries: [MissedEntry] {
        MissedLog.entries(visibleWorkouts, today: today, schedule: settings.sortedSchedule, breaks: settings.breaks)
    }
    var stickerSlots: [StickerSlot] { StickerPage.slots(visibleWorkouts, today: today) }
    var doneWorkouts: [PlannedWorkout] { visibleWorkouts.filter { $0.status == .done } }

    func hasLogs(_ w: PlannedWorkout) -> Bool {
        w.sections.contains { s in !s.roundLogs.isEmpty || s.items.contains { !$0.setLogs.isEmpty } }
    }

    func lastSession(of lift: Lift, before date: LocalDate) -> LiftSession? {
        LiftHistory.sessions(of: lift, in: visibleWorkouts.filter { $0.date < date }).last
    }

    func bestTop(of lift: Lift, before date: LocalDate) -> Double? {
        LiftHistory.sessions(of: lift, in: visibleWorkouts.filter { $0.date < date }).compactMap(\.topWeight).max()
    }

    /// Previous like-for-like result for a benchmark section, or the last
    /// time the same-named piece was done.
    func previousResult(for section: WorkoutSection, before date: LocalDate) -> (date: LocalDate, logs: [RoundLog])? {
        if let id = section.benchmarkID,
           let r = PRDetector.previousBenchmarkResult(id, before: date, history: visibleWorkouts, calendar: calendar) {
            return (r.date, r.roundLogs)
        }
        guard let name = section.name else { return nil }
        let prior = doneWorkouts.last { $0.date < date && $0.metabolicSection?.name == name }
        return prior.flatMap { w in w.metabolicSection.map { (w.date, $0.roundLogs) } }
    }

    func plateCeilingWarnings() -> [PlateCeilingWarning] {
        WeightUnit.$current.withValue(unit) {
            PlateCeilingWarning.forecast(trainingMaxes: liftPrograms.mapValues { unit.fromPounds($0.trainingMax) },
                                         calculator: PlateCalculator(inventory: settings.equipment))
        }
    }

    func stickerContext(for w: PlannedWorkout) -> StickerContext {
        var done = w
        done.status = .done
        let others = visibleWorkouts.filter { $0.id != w.id }
        let streakAfter = Motivation.streak(others + [done], today: max(today, w.date), schedule: settings.sortedSchedule,
                                            breaks: settings.breaks).current
        return StickerContext(isPRDay: PRDetector.isPRDay(w, history: others, calendar: calendar), streakAfterWorkout: streakAfter)
    }

    // MARK: Logging a workout

    func mutate(_ id: UUID, _ change: (inout PlannedWorkout) -> Void) {
        guard var w = workout(id: id) else { return }
        change(&w)
        w.sync.updatedAt = now
        upsert([w])
    }

    func logSet(workout id: UUID, section: UUID, item: UUID, setNumber: Int, reps: Int, weight: Double) {
        guard (1...30).contains(setNumber), (0...1000).contains(reps), weight.isFinite, (0...1000).contains(weight) else { return }
        mutate(id) { w in
            guard let si = w.sections.firstIndex(where: { $0.id == section }),
                  let ii = w.sections[si].items.firstIndex(where: { $0.id == item }) else { return }
            var logs = w.sections[si].items[ii].setLogs.filter { $0.setNumber != setNumber }
            logs.append(SetLog(setNumber: setNumber, reps: reps, weight: weight, completedAt: now))
            w.sections[si].items[ii].setLogs = logs.sorted { $0.setNumber < $1.setNumber }
        }
    }

    func unlogSet(workout id: UUID, section: UUID, item: UUID, setNumber: Int) {
        mutate(id) { w in
            guard let si = w.sections.firstIndex(where: { $0.id == section }),
                  let ii = w.sections[si].items.firstIndex(where: { $0.id == item }) else { return }
            w.sections[si].items[ii].setLogs.removeAll { $0.setNumber == setNumber }
        }
    }

    func logRound(workout id: UUID, section: UUID, round: Int, rounds: Int?, reps: Int?, timeSec: Int?) {
        guard (1...60).contains(round) else { return }
        let clean = { (v: Int?, max: Int) in v.flatMap { (0...max).contains($0) ? $0 : nil } }
        mutate(id) { w in
            guard let si = w.sections.firstIndex(where: { $0.id == section }) else { return }
            var logs = w.sections[si].roundLogs.filter { $0.roundNumber != round }
            let log = RoundLog(roundNumber: round, rounds: clean(rounds, 500), reps: clean(reps, 1000), timeSec: clean(timeSec, 4 * 3600))
            if !log.isEmpty { logs.append(log) }
            w.sections[si].roundLogs = logs.sorted { $0.roundNumber < $1.roundNumber }
        }
    }

    func setNote(workout id: UUID, section: UUID, text: String) {
        mutate(id) { w in
            guard let si = w.sections.firstIndex(where: { $0.id == section }) else { return }
            w.sections[si].athleteNote = String(text.prefix(4000))
        }
    }

    func shuffle(workout id: UUID, section: SectionKind?) async {
        guard let w = workout(id: id), w.status == .planned else { return }
        do {
            var s = try await planner.shuffle(w, section: section, request: request(for: w.date, salts: w.salts, id: w.id))
            s.sections = s.sections.map { new in
                // Keep anything already logged in sections that weren't shuffled.
                if let section, new.kind != section, let old = w.section(new.kind) { return old }
                return new
            }
            upsert([s])
            Haptics.play(.tap)
        } catch {
            fail("Couldn't shuffle that.", error)
        }
    }

    @discardableResult
    func finish(workout id: UUID, feedback: WorkoutFeedback, sticker: StickerID?, minutes: Int?) -> FinishSummary? {
        guard let w = workout(id: id) else { return nil }
        let context = stickerContext(for: w)
        let others = visibleWorkouts.filter { $0.id != id }
        let prs = PRDetector.strengthPRs(in: w, history: others)
        let benchPR = w.sections.contains { PRDetector.isBenchmarkPR(section: $0, date: w.date, history: others, calendar: calendar) }
        mutate(id) { w in
            w.status = .done
            w.feedback = feedback
            w.sticker = sticker.flatMap { StickerCatalog.canPick($0, context: context) ? $0 : nil }
            w.durationMin = minutes.map { min(max($0, 1), 600) }
        }
        // Persist a two-miss TM drop the planner applied to this session.
        if let s = w.strengthSection, let lift = s.lift, let used = s.trainingMax,
           let current = liftPrograms[lift], used < current.trainingMax, !(w.position?.isTestWeek ?? false) {
            var p = current
            p.trainingMax = used
            p.source = .progression
            liftPrograms[lift] = p
            persist { try repo.save(liftPrograms: Array(liftPrograms.values).sorted { $0.lift < $1.lift }) }
        }
        Haptics.play(.success)
        Task { await ensurePlan(for: nextPlanDate(after: today)) }
        return FinishSummary(streak: streak.current, prLifts: prs, benchmarkPR: benchPR)
    }

    func setStatus(_ status: WorkoutStatus, on date: LocalDate) {
        if let w = workout(on: date) {
            mutate(w.id) {
                $0.status = status
                // The owner's decision on an imported day survives re-imports.
                if $0.source == "import" { $0.source = "import-edited" }
            }
        } else {
            upsert([PlannedWorkout(date: date, status: status, source: "manual", sync: SyncStamp(createdAt: now))])
        }
        Task { await ensurePlan(for: nextPlanDate(after: today)) }
    }

    /// Migration: imported history never has stickers (only picks on the
    /// Finish screen do). Clears any that slipped onto imported workouts.
    private func clearImportedStickers() {
        let stray = workouts.filter { $0.source.hasPrefix("import") && $0.sticker != nil }
        guard !stray.isEmpty else { return }
        upsert(stray.map { var w = $0; w.sticker = nil; return w })
        Log.store.info("cleared \(stray.count, privacy: .public) imported stickers")
    }

    // MARK: Onboarding

    /// A brand-new install (installs with data are migrated to onboarded on load).
    var needsOnboarding: Bool { !settings.onboarded }

    /// Existing installs (data already there) skip onboarding for good, with
    /// their settings as they are. Test mode skips it unless asked for.
    private func migrateOnboarding() {
        guard !settings.onboarded else { return }
        let testModeSkip = DebugRoute.enabled && !DebugRoute.flag("-sbc-onboarding")
        guard !workouts.isEmpty || testModeSkip else { return }
        settings.onboarded = true
        persist { try repo.save(settings: settings) }
    }

    enum StartChoice: Equatable, Sendable {
        /// Next Monday is a test week.
        case testWeek
        /// Training maxes from a recent heavy set of 5 per lift (display unit).
        case manual([Lift: Double])
        /// Light, bar-based training maxes.
        case startLight
    }

    struct OnboardingChoices: Sendable {
        var name = ""
        var unit: WeightUnit = .lb
        var schedule: [Weekday] = [.monday, .wednesday, .friday]
        var lifts: [Lift] = Lift.allCases
        var limits = TrainingLimits()
        var start: StartChoice = .startLight
    }

    func completeOnboarding(_ c: OnboardingChoices) {
        let thisMonday = today.startOfWeek
        var s = PlannerSettings(displayName: c.name, schedule: c.schedule, equipment: .preset(c.unit), limits: c.limits,
                                rotationAnchor: thisMonday, lifts: c.lifts, onboarded: true)
        switch c.start {
        case .testWeek:
            // Next Monday tests; block 1 follows a week later.
            s.testWeekStart = thisMonday.adding(days: 7)
        case .manual, .startLight:
            // Block 1 starts this week; no test week.
            s.testWeekStart = thisMonday.adding(days: -7)
        }
        updateSettings(s)
        let bar = s.equipment.barWeight
        switch c.start {
        case .startLight:
            for lift in Lift.allCases {
                let tm = lift.isLowerBody ? bar + (c.unit == .kg ? 10 : 20) : bar
                setTrainingMax(lift, c.unit.toPounds(tm))
            }
        case .manual(let sets):
            for (lift, weight) in sets where weight > 0 {
                setTrainingMax(lift, c.unit.toPounds(TrainingMax.fromSet(weight: weight, reps: 5)))
            }
        case .testWeek:
            break
        }
        Task { await prepare() }
    }

    // MARK: Missed, sick, skipped, moved

    /// Journal: mark a missed day as a sick day (excused).
    func markSick(_ date: LocalDate) { setStatus(.excused, on: date) }

    /// Journal: an imported day that was done but never logged in the sheet.
    /// Marked done with no sticker.
    func markDoneUnlogged(_ date: LocalDate) {
        guard let w = workout(on: date) else { return }
        mutate(w.id) {
            $0.status = .done
            $0.sticker = nil
            if $0.source == "import" { $0.source = "import-edited" }
        }
    }

    /// Journal: turn a sick day (or any non-done day) back into a miss.
    func markMissed(_ date: LocalDate) { setStatus(.skipped, on: date) }

    /// Journal: a long missed stretch becomes a planned break.
    func addBreak(label: String, from: LocalDate, to: LocalDate) {
        var s = settings
        s.breaks.append(TrainingBreak(label: label, from: from, to: to))
        updateSettings(s)
    }

    func removeBreak(_ id: UUID) {
        var s = settings
        s.breaks.removeAll { $0.id == id }
        updateSettings(s)
    }

    enum TodayChange: Equatable { case sick, skipped, moved(LocalDate) }

    /// How today was changed with "can't make it today?" (undoable today).
    var todayChange: TodayChange? {
        let t = today
        let records = visibleWorkouts.filter { $0.date == t }
        if let marker = records.first(where: { $0.source == "moved" }),
           let moved = visibleWorkouts.first(where: { $0.id.uuidString == marker.reasons.first?.text }) {
            return .moved(moved.date)
        }
        if records.contains(where: { $0.status == .excused }) { return .sick }
        if records.contains(where: { $0.status == .skipped && !$0.sections.isEmpty }) { return .skipped }
        return nil
    }

    /// The next free, non-training day later this week (for "move to …").
    var moveTarget: LocalDate? {
        let t = today
        guard let w = workout(on: t), w.status == .planned, !w.sections.isEmpty else { return nil }
        let end = t.startOfWeek.adding(days: 6)
        var d = t.adding(days: 1)
        while d <= end {
            if !settings.sortedSchedule.contains(d.weekday), workout(on: d) == nil { return d }
            d = d.adding(days: 1)
        }
        return nil
    }

    func sickToday() { changeToday(.excused) }
    func skipToday() { changeToday(.skipped) }

    private func changeToday(_ status: WorkoutStatus) {
        guard let w = workout(on: today), w.status == .planned else { return }
        mutate(w.id) { $0.status = status }
    }

    /// Shifts today's workout to a free day later this week; today keeps a
    /// small marker so it isn't planned again.
    func moveToday() {
        guard let target = moveTarget, let w = workout(on: today) else { return }
        mutate(w.id) { $0.date = target }
        upsert([PlannedWorkout(date: today, status: .skipped,
                               reasons: [PlanReason(section: nil, rule: "moved", text: w.id.uuidString)],
                               source: "moved", sync: SyncStamp(createdAt: now))])
    }

    /// Undo today's sick / skip / move (only for today).
    func undoTodayChange() {
        let t = today
        for r in visibleWorkouts where r.date == t {
            if r.source == "moved" {
                if let id = UUID(uuidString: r.reasons.first?.text ?? ""), workout(id: id) != nil {
                    mutate(id) { $0.date = t }
                }
                mutate(r.id) { $0.sync.deletedAt = now }
            } else if r.status == .excused || r.status == .skipped {
                if r.sections.isEmpty { mutate(r.id) { $0.sync.deletedAt = now } } else { mutate(r.id) { $0.status = .planned } }
            }
        }
    }

    // MARK: Settings, goals, benchmarks

    /// Switch lb/kg: loads that unit's preset gym; TMs and goals are
    /// re-rounded to the new unit's step. Logged history is untouched.
    func switchUnits(to new: WeightUnit) {
        guard new != unit else { return }
        var s = settings.switchingUnits(to: new)
        s.displayName = settings.displayName
        updateSettings(s)
        liftPrograms = liftPrograms.mapValues { var p = $0; p.trainingMax = new.rounded(pounds: p.trainingMax); return p }
        goals = goals.map { var g = $0; g.targetWeight = new.rounded(pounds: g.targetWeight); return g }
        persist { try repo.save(liftPrograms: Array(liftPrograms.values).sorted { $0.lift < $1.lift }) }
        persist { try repo.save(goals: goals) }
    }

    func updateSettings(_ s: PlannerSettings) {
        settings = s.sanitized()
        persist { try repo.save(settings: settings) }
        Task { await ensurePlan(for: nextPlanDate(after: today)) }
    }

    /// `tm` in canonical pounds; re-rounded to the display unit's step.
    func setTrainingMax(_ lift: Lift, _ tm: Double) {
        guard tm.isFinite, (20...1000).contains(tm) else { return }
        var p = liftPrograms[lift] ?? LiftProgram(lift: lift, trainingMax: tm)
        p.trainingMax = unit.rounded(pounds: tm)
        p.source = .manual
        liftPrograms[lift] = p
        persist { try repo.save(liftPrograms: Array(liftPrograms.values).sorted { $0.lift < $1.lift }) }
    }

    func addGoal(_ g: Goal) {
        guard g.targetWeight.isFinite, (1...1000).contains(g.targetWeight) else { return }
        goals.append(g)
        persist { try repo.save(goals: goals) }
    }

    func removeGoal(_ id: UUID) {
        goals.removeAll { $0.id == id }
        persist { try repo.save(goals: goals) }
    }

    func proposeBenchmarks() {
        benchmarks = BenchmarkProposer.propose(from: doneWorkouts)
        persist { try repo.save(benchmarks: benchmarks) }
    }

    func setBenchmark(_ id: UUID, active: Bool) {
        guard let i = benchmarks.firstIndex(where: { $0.id == id }) else { return }
        benchmarks[i].active = active
        persist { try repo.save(benchmarks: benchmarks) }
    }

    /// UI-testing only: shuffle the next workout's metabolic piece until it
    /// has the requested format (deterministic, bounded).
    func debugForceMetabolic(_ formatRaw: String) async {
        guard DebugRoute.enabled, let target = SectionFormat(rawValue: formatRaw) else { return }
        for _ in 0..<60 {
            guard let w = nextWorkout, w.metabolicSection?.format != target else { return }
            await shuffle(workout: w.id, section: .metabolic)
        }
    }

    // MARK: Import / export

    /// Imports a user-picked JSON file: either the coach-sheet history
    /// (tools/import_sheet.py output) or an app backup. Returns a summary.
    ///
    /// Coach history is decoded off the main thread, then saved in batches.
    /// The import is all-or-nothing: if any batch fails to save, the batches
    /// already written are removed again and the error is thrown (shown to
    /// the user), so a half-imported journal is never left behind.
    func importFile(_ data: Data) async throws -> String {
        if CSVHistoryImporter.looksLikeTemplate(data) {
            let stamp = now
            let result = try await Task.detached(priority: .userInitiated) {
                try CSVHistoryImporter.importCSV(data, now: stamp)
            }.value
            return try await saveImported(result)
        }
        switch BackupCodec.sniff(data) {
        case .coachHistory:
            let stamp = now
            let result = try await Task.detached(priority: .userInitiated) {
                try HistoryImporter().importCoachHistory(data, now: stamp)
            }.value
            return try await saveImported(result)
        case .appBackup:
            let (backup, issues) = try BackupCodec.decode(data)
            let d = StoredData(settings: backup.settings, workouts: backup.workouts, liftPrograms: backup.liftPrograms,
                               benchmarks: backup.benchmarks, goals: backup.goals)
            try repo.replaceAll(d)
            load()
            Log.importer.info("restored backup, \(issues.count, privacy: .public) issues")
            return "Restored \(backup.workouts.count) workouts from the backup."
        case nil:
            throw ImportError.notJSON
        }
    }

    /// Saves an import atomically in batches (coach JSON or CSV template).
    private func saveImported(_ result: ImportResult) async throws -> String {
        // Days logged in the app win; earlier imports are replaced (re-importing
        // a newer file fixes or updates them).
        let appLogged = Set(visibleWorkouts.filter {
            $0.source == "import-edited" || ($0.source != "import" && ($0.status == .done || $0.status == .excused))
        }.map(\.date))
        let fresh = result.workouts.filter { !appLogged.contains($0.date) }
        let freshDates = Set(fresh.map(\.date))
        // Statuses of earlier imported days are refreshed; days the owner
        // edited ("import-edited") or logged in the app are kept.
        let replaced = visibleWorkouts.filter { $0.source == "import" && freshDates.contains($0.date) }
        importProgress = (0, fresh.count)
        defer { importProgress = nil }
        var inserted: [UUID] = []
        do {
            try repo.delete(workoutIDs: replaced.map(\.id))
        } catch {
            throw StoreError.importNotSaved
        }
        do {
            var start = 0
            while start < fresh.count {
                let batch = Array(fresh[start..<min(start + Self.importBatchSize, fresh.count)])
                try repo.insert(batch: batch)
                inserted += batch.map(\.id)
                start += batch.count
                importProgress = (start, fresh.count)
                await Task.yield()
            }
        } catch {
            // All or nothing: drop what was written and put back what was replaced.
            try? repo.delete(workoutIDs: inserted)
            try? repo.insert(batch: replaced)
            Log.importer.error("import rolled back [\(Log.kind(error), privacy: .public)]")
            throw StoreError.importNotSaved
        }
        let replacedIDs = Set(replaced.map(\.id))
        workouts.removeAll { replacedIDs.contains($0.id) }
        workouts.append(contentsOf: fresh)
        workouts.sort { $0.date < $1.date }
        if benchmarks.isEmpty { proposeBenchmarks() }
        rollTrainingMaxes(asOf: today)
        Log.importer.info("imported \(fresh.count, privacy: .public) workouts, \(result.issues.count, privacy: .public) issues")
        var summary = result.summary(imported: fresh.count, alreadyPresent: result.workouts.count - fresh.count)
        if !replaced.isEmpty { summary += " \(replaced.count) earlier imported workouts were updated." }
        return summary
    }

    func exportBackup() throws -> Data {
        try BackupCodec.encode(AppBackup(exportedAt: now, settings: settings, workouts: workouts,
                                         liftPrograms: Array(liftPrograms.values).sorted { $0.lift < $1.lift },
                                         benchmarks: benchmarks, goals: goals))
    }

    func exportCSV() -> String { CSVExporter.setLogs(visibleWorkouts) }

    func deleteAllData() {
        persist { try repo.deleteAll() }
        settings = .default
        workouts = []
        liftPrograms = [:]
        benchmarks = []
        goals = []
    }

    // MARK: Helpers

    private func upsert(_ changed: [PlannedWorkout]) {
        guard !changed.isEmpty else { return }
        for w in changed {
            if let i = workouts.firstIndex(where: { $0.id == w.id }) { workouts[i] = w } else { workouts.append(w) }
        }
        workouts.sort { $0.date < $1.date }
        persist { try repo.save(workouts: changed) }
    }

    private func persist(_ body: () throws -> Void) {
        do { try body() } catch { fail("Couldn't save. Your last change may not be stored.", error) }
    }

    private func fail(_ message: String, _ error: Error) {
        lastError = message
        Log.store.error("\(message, privacy: .public) [\(Log.kind(error), privacy: .public)]")
    }
}

enum StoreError: Error, CustomStringConvertible {
    case importNotSaved

    var description: String {
        switch self {
        case .importNotSaved: return "Couldn't save the import, so nothing was changed. Please try again."
        }
    }
}

