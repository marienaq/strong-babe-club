import Foundation

public struct StreakSummary: Hashable, Sendable {
    public var current: Int
    public var best: Int
}

public struct CompletionSummary: Hashable, Sendable {
    public var done: Int
    public var planned: Int
    public var excused: Int

    /// nil when nothing was planned in the window.
    public var fraction: Double? { planned > 0 ? Double(done) / Double(planned) : nil }
    public var percent: Int? { fraction.map { Int(($0 * 100).rounded()) } }
}

public enum Motivation {
    /// Workouts that count for motivation stats (not deleted, on or before today).
    static func relevant(_ workouts: [PlannedWorkout], today: LocalDate) -> [PlannedWorkout] {
        // One record per date: prefer a done workout over others.
        var byDate: [LocalDate: PlannedWorkout] = [:]
        for w in workouts where !w.isDeleted && w.date <= today {
            if let existing = byDate[w.date] {
                if rank(w.status) > rank(existing.status) { byDate[w.date] = w }
            } else {
                byDate[w.date] = w
            }
        }
        return byDate.values.sorted { $0.date < $1.date }
    }

    private static func rank(_ s: WorkoutStatus) -> Int {
        switch s {
        case .done: return 3
        case .excused: return 2
        case .skipped: return 1
        case .planned: return 0
        }
    }

    /// One ISO week of the schedule, compared with what happened.
    public struct WeekTally: Hashable, Sendable {
        public var weekStart: LocalDate
        /// Scheduled days that count (in range, already passed or done today, not in a break).
        public var expected: Int
        /// Done workouts in the week (any day, extra days included), oldest first.
        public var doneDates: [LocalDate]
        /// Excused (sick) days.
        public var excused: Int
        /// Scheduled days inside a planned break.
        public var onBreak: Int

        public var done: Int { doneDates.count }
        /// Forgiving: a swapped day isn't a miss; extra workouts can't cover another week.
        public var misses: Int { max(0, expected - excused - done) }
    }

    /// Week-by-week tallies from `from` to `to` (inclusive), measured against
    /// the schedule. A scheduled day counts as expected once it has passed;
    /// today only counts if it's already done, so today's open workout and the
    /// rest of the current week never count as misses.
    public static func weeks(_ workouts: [PlannedWorkout], today: LocalDate, schedule: [Weekday],
                             breaks: [TrainingBreak] = [], from: LocalDate, to: LocalDate? = nil) -> [WeekTally] {
        let end = min(to ?? today, today)
        guard from <= end else { return [] }
        let rel = relevant(workouts, today: end).filter { $0.date >= from }
        let byDate = Dictionary(uniqueKeysWithValues: rel.map { ($0.date, $0) })
        let days = Set(schedule.isEmpty ? [.monday, .wednesday, .friday] : schedule)
        var out: [WeekTally] = []
        var weekStart = from.startOfWeek
        while weekStart <= end {
            var tally = WeekTally(weekStart: weekStart, expected: 0, doneDates: [], excused: 0, onBreak: 0)
            for i in 0..<7 {
                let d = weekStart.adding(days: i)
                guard d >= from, d <= end else { continue }
                let record = byDate[d]
                if record?.status == .done { tally.doneDates.append(d) }
                if record?.status == .excused { tally.excused += 1 }
                guard days.contains(d.weekday) else { continue }
                if breaks.contains(where: { $0.contains(d) }) {
                    tally.onBreak += 1
                    continue
                }
                if d < today || record?.status == .done { tally.expected += 1 }
            }
            // Excused records only offset expected days.
            tally.excused = min(tally.excused, tally.expected)
            out.append(tally)
            weekStart = weekStart.adding(days: 7)
        }
        return out
    }

    /// First day that counts: the earliest workout on record.
    static func firstDay(_ workouts: [PlannedWorkout], today: LocalDate) -> LocalDate? {
        relevant(workouts, today: today).first?.date
    }

    /// Streak in planned workouts done in a row, measured against the
    /// schedule. Each done workout adds one; a week with misses ends at zero
    /// (misses sit at the end of their week). Excused days and planned breaks
    /// neither break nor extend it.
    public static func streak(_ workouts: [PlannedWorkout], today: LocalDate, schedule: [Weekday] = [.monday, .wednesday, .friday],
                              breaks: [TrainingBreak] = []) -> StreakSummary {
        guard let start = firstDay(workouts, today: today) else { return StreakSummary(current: 0, best: 0) }
        var run = 0, best = 0
        for week in weeks(workouts, today: today, schedule: schedule, breaks: breaks, from: start) {
            run += week.done
            best = max(best, run)
            if week.misses > 0 { run = 0 }
        }
        return StreakSummary(current: run, best: best)
    }

    /// % of scheduled workouts done in the last `days` days (today included
    /// only once it's done). Excused days and breaks leave the denominator;
    /// extra workouts can't push a week past 100%.
    public static func completion(_ workouts: [PlannedWorkout], today: LocalDate, days: Int = 30,
                                  schedule: [Weekday] = [.monday, .wednesday, .friday],
                                  breaks: [TrainingBreak] = []) -> CompletionSummary {
        guard let first = firstDay(workouts, today: today) else { return CompletionSummary(done: 0, planned: 0, excused: 0) }
        let start = max(first, today.adding(days: -(days - 1)))
        var done = 0, planned = 0, excused = 0
        for week in weeks(workouts, today: today, schedule: schedule, breaks: breaks, from: start) {
            let due = week.expected - week.excused
            planned += due
            done += min(week.done, due)
            excused += week.excused + week.onBreak
        }
        return CompletionSummary(done: done, planned: planned, excused: excused)
    }

    /// Scheduled workouts missed in the last `days` days (before today).
    public static func misses(_ workouts: [PlannedWorkout], today: LocalDate, withinDays days: Int,
                              schedule: [Weekday] = [.monday, .wednesday, .friday], breaks: [TrainingBreak] = []) -> Int {
        guard let first = firstDay(workouts, today: today) else { return 0 }
        let start = max(first, today.adding(days: -days))
        return weeks(workouts, today: today, schedule: schedule, breaks: breaks, from: start, to: today.adding(days: -1))
            .reduce(0) { $0 + $1.misses }
    }
}

/// A planned break (holiday, travel): scheduled days inside it are excused.
public struct TrainingBreak: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var label: String
    public var from: LocalDate
    public var to: LocalDate

    public init(id: UUID = UUID(), label: String, from: LocalDate, to: LocalDate) {
        self.id = id
        self.label = label
        self.from = min(from, to)
        self.to = max(from, to)
    }

    public func contains(_ d: LocalDate) -> Bool { d >= from && d <= to }

    /// Bounded copy (labels trimmed, dates ordered).
    public func sanitized() -> TrainingBreak {
        let l = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return TrainingBreak(id: id, label: String((l.isEmpty ? "break" : l).prefix(40)), from: from, to: to)
    }
}

// MARK: - Coach's note

public enum CoachNoteKind: String, Codable, Sendable, CaseIterable {
    /// Consistent, but a lift has stalled: plan set heavier.
    case push
    /// Recent missed workouts: plan set lighter.
    case comeback
    /// Low energy / high difficulty several times in a row: lighter and shorter.
    case justShowUp = "just_show_up"
    /// Nothing special: keep going.
    case steady
}

public struct CoachNote: Codable, Hashable, Sendable {
    public var kind: CoachNoteKind
    public var title: String
    public var message: String
    public var lift: Lift?

    public init(kind: CoachNoteKind, title: String, message: String, lift: Lift? = nil) {
        self.kind = kind
        self.title = title
        self.message = message
        self.lift = lift
    }

    public var makesPlanLighter: Bool { kind == .comeback || kind == .justShowUp }
    public var makesPlanShorter: Bool { kind == .justShowUp }
}

public enum CoachNoteSelector {
    public static let lookbackDays = 42

    /// Picks one note from the last 4-6 weeks. Priority: just show up >
    /// comeback > push > steady.
    public static func select(history: [PlannedWorkout], today: LocalDate, todaysLift: Lift?,
                              schedule: [Weekday] = [.monday, .wednesday, .friday], breaks: [TrainingBreak] = []) -> CoachNote {
        let windowStart = today.adding(days: -lookbackDays)
        let recent = Motivation.relevant(history, today: today.adding(days: -1)).filter { $0.date >= windowStart }
        let done = recent.filter { $0.status == .done }

        // Just show up: the last 3 completed workouts all felt rough.
        let lastThree = done.suffix(3)
        if lastThree.count == 3, lastThree.allSatisfy({ $0.feedback?.wasRough == true }) {
            return CoachNote(kind: .justShowUp, title: "Kettle says: showing up is the win",
                             message: "The last few sessions felt heavy. Today is lighter and shorter. Just show up and move.")
        }

        // Comeback: two or more misses in the last 2 weeks, or a long gap after a miss.
        let misses = Motivation.misses(history, today: today, withinDays: 14, schedule: schedule, breaks: breaks)
        let daysSinceDone = done.last.map { $0.date.days(until: today) }
        if misses >= 2 || (misses >= 1 && (daysSinceDone ?? 0) >= 10) {
            return CoachNote(kind: .comeback, title: "Kettle says: today restarts it",
                             message: "A few sessions slipped by, and that's okay. Today is a little lighter so you can find your rhythm again.")
        }

        // Push: consistent and today's lift has stalled for 3 sessions.
        let completion = Motivation.completion(history, today: today, days: 30, schedule: schedule, breaks: breaks)
        if let lift = todaysLift, (completion.fraction ?? 0) >= 0.8 {
            let sessions = LiftHistory.sessions(of: lift, in: history).filter { $0.date >= windowStart && $0.date < today }
            let tops = sessions.suffix(3).compactMap(\.topWeight)
            if tops.count == 3, let first = tops.first, tops.max() == first, sessions.suffix(3).allSatisfy({ !$0.missedRep }) {
                return CoachNote(kind: .push, title: "Kettle says: push a little!",
                                 message: "\(lift.displayName)'s been stuck at \(formatPounds(first)) for 3 sessions. Today goes a bit heavier.",
                                 lift: lift)
            }
        }

        let summary: String
        if let p = completion.percent, completion.planned > 0 {
            summary = "You've done \(completion.done) of your last \(completion.planned) planned workouts (\(p)%). Same plan, good form."
        } else {
            summary = "Fresh page. Warm up well and enjoy it."
        }
        return CoachNote(kind: .steady, title: "Kettle says: nice and steady", message: summary)
    }
}

// MARK: - Stickers

public enum StickerID: String, Codable, Sendable, CaseIterable {
    case barbell, kettle, dumbbell, bear, flame
    /// Rare: only on PR days.
    case star
    /// Rare: streak milestones.
    case rainbow, crown, trophy, rocket, diamond
}

public struct StickerDefinition: Hashable, Sendable {
    public enum Unlock: Hashable, Sendable {
        case always
        case prDay
        case streak(Int)
    }

    public var id: StickerID
    public var name: String
    public var unlock: Unlock

    public var isRare: Bool { unlock != .always }

    public var unlockLabel: String? {
        switch unlock {
        case .always: return nil
        case .prDay: return "PR only"
        case .streak(let n): return "\(n) in a row"
        }
    }
}

public struct StickerContext: Hashable, Sendable {
    public var isPRDay: Bool
    /// Streak including the workout being finished.
    public var streakAfterWorkout: Int

    public init(isPRDay: Bool, streakAfterWorkout: Int) {
        self.isPRDay = isPRDay
        self.streakAfterWorkout = streakAfterWorkout
    }
}

public enum StickerCatalog {
    public static let all: [StickerDefinition] = [
        StickerDefinition(id: .barbell, name: "Barbell", unlock: .always),
        StickerDefinition(id: .kettle, name: "Kettle", unlock: .always),
        StickerDefinition(id: .dumbbell, name: "Dumbbell", unlock: .always),
        StickerDefinition(id: .bear, name: "Squat bear", unlock: .always),
        StickerDefinition(id: .flame, name: "Flame", unlock: .always),
        StickerDefinition(id: .star, name: "PR star", unlock: .prDay),
        StickerDefinition(id: .rainbow, name: "Rainbow", unlock: .streak(5)),
        StickerDefinition(id: .crown, name: "Crown", unlock: .streak(10)),
        StickerDefinition(id: .trophy, name: "Trophy", unlock: .streak(25)),
        StickerDefinition(id: .rocket, name: "Rocket", unlock: .streak(50)),
        StickerDefinition(id: .diamond, name: "Diamond", unlock: .streak(100)),
    ]

    public static func definition(_ id: StickerID) -> StickerDefinition { all.first { $0.id == id }! }

    public static let streakMilestones: [Int] = all.compactMap {
        if case .streak(let n) = $0.unlock { return n }
        return nil
    }

    /// Rare stickers unlock only on the special day itself: the PR star on a
    /// PR day, a milestone sticker on the day the streak reaches it.
    public static func isUnlocked(_ def: StickerDefinition, context: StickerContext) -> Bool {
        switch def.unlock {
        case .always: return true
        case .prDay: return context.isPRDay
        case .streak(let n): return context.streakAfterWorkout == n
        }
    }

    /// Stickers on today's sheet: all commons plus any rare unlocked today.
    public static func available(_ context: StickerContext) -> [StickerDefinition] {
        all.filter { isUnlocked($0, context: context) }
    }

    public static func canPick(_ id: StickerID, context: StickerContext) -> Bool {
        isUnlocked(definition(id), context: context)
    }
}

/// One square on "my sticker page".
public enum StickerSlot: Hashable, Sendable {
    /// A sticker the owner picked on the Finish screen.
    case sticker(StickerID, date: LocalDate)
    /// Waiting to be filled.
    case empty
    /// Today's workout is still to do.
    case today
}

public enum StickerPage {
    /// Only stickers the owner actually picked (imported history has none),
    /// newest last, then "today?" if today's workout is open, then empty
    /// spots up to `count`.
    public static func slots(_ workouts: [PlannedWorkout], today: LocalDate, count: Int = 12) -> [StickerSlot] {
        let rel = Motivation.relevant(workouts, today: today)
        let todayOpen = rel.contains { $0.date == today && $0.status == .planned && !$0.sections.isEmpty }
        let picked = rel.compactMap { w -> StickerSlot? in
            guard w.status == .done, w.source != "import", let s = w.sticker else { return nil }
            return .sticker(s, date: w.date)
        }
        var out = Array(picked.suffix(max(0, count - (todayOpen ? 1 : 0))))
        if todayOpen { out.append(.today) }
        while out.count < count { out.append(.empty) }
        return out
    }
}

/// A missed stretch for the Journal: one scheduled day, or a run longer
/// than a week grouped into one entry ("missed 4 weeks · Jul 6 – Jul 31").
public struct MissedEntry: Hashable, Sendable, Identifiable {
    public var from: LocalDate
    public var to: LocalDate
    /// Scheduled days missed in the stretch.
    public var days: [LocalDate]

    public var id: String { from.iso + "-" + to.iso }
    public var isGroup: Bool { days.count > 1 }
    public var weeks: Int { max(1, Int((Double(from.days(until: to) + 1) / 7).rounded(.up))) }

    public var label: String {
        if !isGroup { return "missed · \(from.weekday.shortName) \(from.shortMonthName) \(from.day)" }
        return "missed \(weeks) weeks · \(from.shortMonthName) \(from.day) – \(to.shortMonthName) \(to.day)"
    }
}

public enum MissedLog {
    /// Scheduled days that passed without a workout (before today), using the
    /// same forgiving week rule as the streak: a swapped day isn't a miss.
    /// Excused days and breaks are never misses.
    public static func days(_ workouts: [PlannedWorkout], today: LocalDate, schedule: [Weekday],
                            breaks: [TrainingBreak] = []) -> [LocalDate] {
        guard let first = Motivation.firstDay(workouts, today: today) else { return [] }
        let rel = Motivation.relevant(workouts, today: today)
        let status = Dictionary(uniqueKeysWithValues: rel.map { ($0.date, $0.status) })
        let sched = Set(schedule)
        var out: [LocalDate] = []
        for week in Motivation.weeks(workouts, today: today, schedule: schedule, breaks: breaks, from: first,
                                     to: today.adding(days: -1)) where week.misses > 0 {
            let open = (0..<7).map { week.weekStart.adding(days: $0) }.filter { d in
                d >= first && d < today && sched.contains(d.weekday) && !breaks.contains { $0.contains(d) }
                    && status[d] != .done && status[d] != .excused
            }
            out += open.suffix(week.misses)
        }
        return out
    }

    /// Missed days as Journal entries. Misses with no workout (or sick day)
    /// in between form a run; a run spanning more than a week becomes one
    /// grouped entry, shorter runs stay one entry per day.
    public static func entries(_ workouts: [PlannedWorkout], today: LocalDate, schedule: [Weekday],
                               breaks: [TrainingBreak] = []) -> [MissedEntry] {
        let missed = days(workouts, today: today, schedule: schedule, breaks: breaks)
        let active = Motivation.relevant(workouts, today: today)
            .filter { $0.status == .done || $0.status == .excused }.map(\.date)
        var runs: [[LocalDate]] = []
        for d in missed {
            if let last = runs.last?.last, !active.contains(where: { $0 > last && $0 < d }) {
                runs[runs.count - 1].append(d)
            } else {
                runs.append([d])
            }
        }
        var out: [MissedEntry] = []
        for run in runs {
            if run.count > 1, run.first!.days(until: run.last!) >= 7 {
                out.append(MissedEntry(from: run.first!, to: run.last!, days: run))
            } else {
                out += run.map { MissedEntry(from: $0, to: $0, days: [$0]) }
            }
        }
        return out
    }
}
