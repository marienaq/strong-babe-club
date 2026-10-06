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

    /// Streak in *planned workouts* done in a row. Excused (sick) days neither
    /// break nor extend it. A past workout left "planned" counts as missed;
    /// today's not-yet-done workout does not break it.
    public static func streak(_ workouts: [PlannedWorkout], today: LocalDate) -> StreakSummary {
        var run = 0, best = 0
        for w in relevant(workouts, today: today) {
            switch w.status {
            case .done:
                run += 1
                best = max(best, run)
            case .excused:
                continue
            case .skipped:
                run = 0
            case .planned:
                if w.date < today { run = 0 }
            }
        }
        return StreakSummary(current: run, best: best)
    }

    /// % of planned workouts done in the last `days` days (today included).
    /// Excused days are left out of the denominator; today's still-planned
    /// workout is not counted yet.
    public static func completion(_ workouts: [PlannedWorkout], today: LocalDate, days: Int = 30) -> CompletionSummary {
        let start = today.adding(days: -(days - 1))
        var done = 0, planned = 0, excused = 0
        for w in relevant(workouts, today: today) where w.date >= start {
            switch w.status {
            case .done: done += 1; planned += 1
            case .skipped: planned += 1
            case .excused: excused += 1
            case .planned: if w.date < today { planned += 1 }
            }
        }
        return CompletionSummary(done: done, planned: planned, excused: excused)
    }

    /// Past planned workouts that were missed (skipped or never logged).
    public static func misses(_ workouts: [PlannedWorkout], today: LocalDate, withinDays days: Int) -> Int {
        let start = today.adding(days: -days)
        return relevant(workouts, today: today).filter {
            $0.date >= start && $0.date < today && ($0.status == .skipped || $0.status == .planned)
        }.count
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
    public static func select(history: [PlannedWorkout], today: LocalDate, todaysLift: Lift?) -> CoachNote {
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
        let misses = Motivation.misses(history, today: today, withinDays: 14)
        let daysSinceDone = done.last.map { $0.date.days(until: today) }
        if misses >= 2 || (misses >= 1 && (daysSinceDone ?? 0) >= 10) {
            return CoachNote(kind: .comeback, title: "Kettle says: today restarts it",
                             message: "A few sessions slipped by, and that's okay. Today is a little lighter so you can find your rhythm again.")
        }

        // Push: consistent and today's lift has stalled for 3 sessions.
        let completion = Motivation.completion(history, today: today, days: 30)
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

/// One square on the "my sticker page" grid.
public enum StickerSlot: Hashable, Sendable {
    case sticker(StickerID, date: LocalDate)
    /// Done, but no sticker picked.
    case done(date: LocalDate)
    case excused(date: LocalDate)
    case missed(date: LocalDate)
    case today
}

public enum StickerPage {
    /// The last `count` workouts (oldest first), ending with "today?" when
    /// today's workout is still to do.
    public static func slots(_ workouts: [PlannedWorkout], today: LocalDate, count: Int = 12) -> [StickerSlot] {
        let rel = Motivation.relevant(workouts, today: today)
        var out: [StickerSlot] = []
        for w in rel {
            switch w.status {
            case .done: out.append(w.sticker.map { .sticker($0, date: w.date) } ?? .done(date: w.date))
            case .excused: out.append(.excused(date: w.date))
            case .skipped: out.append(.missed(date: w.date))
            case .planned: out.append(w.date == today ? .today : .missed(date: w.date))
            }
        }
        return Array(out.suffix(count))
    }
}
