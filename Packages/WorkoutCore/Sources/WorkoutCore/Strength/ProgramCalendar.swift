import Foundation

public enum BlockPhase: String, Codable, Sendable, CaseIterable {
    /// Before the first test week (uses history-based TMs, volume-style work).
    case preProgram = "pre_program"
    case volume, strength, peak, deload
    /// Week 13 (and the initial test week): test + benchmarks.
    case test

    public var displayName: String {
        switch self {
        case .preProgram: return "warm-up weeks"
        case .volume: return "volume"
        case .strength: return "strength"
        case .peak: return "peak"
        case .deload: return "deload"
        case .test: return "test"
        }
    }

    /// Phase for a week number 1...13 of a block.
    public static func forBlockWeek(_ week: Int) -> BlockPhase {
        switch week {
        case ...4: return .volume
        case 5...8: return .strength
        case 9...11: return .peak
        case 12: return .deload
        default: return .test
        }
    }

    /// Block weeks belonging to the phase.
    public var weeks: ClosedRange<Int> {
        switch self {
        case .volume, .preProgram: return 1...4
        case .strength: return 5...8
        case .peak: return 9...11
        case .deload: return 12...12
        case .test: return 13...13
        }
    }
}

/// Where a date falls in the quarterly program.
public struct BlockPosition: Codable, Hashable, Sendable {
    /// 0 = before block 1 (pre-program weeks and the initial test week).
    public var block: Int
    /// 1...13 inside a block (13 = test week). 0 for pre-program.
    public var week: Int
    public var phase: BlockPhase
    /// True when the week was swapped to a deload in Settings.
    public var isDeloadOverride: Bool

    public init(block: Int, week: Int, phase: BlockPhase, isDeloadOverride: Bool = false) {
        self.block = block
        self.week = week
        self.phase = phase
        self.isDeloadOverride = isDeloadOverride
    }

    public var isTestWeek: Bool { phase == .test }

    /// Index used for "per block" bookkeeping (benchmarks, TM resets). The
    /// initial test week belongs to block 0.
    public var quarterKey: Int { block }
}

/// 13-week blocks anchored on the first test week.
///
/// Test week (Oct 12-16 2026) -> block 1 weeks 1-12 (Oct 19 - Jan 8) -> week 13
/// test + benchmarks (Jan 11-15 2027) -> block 2 ...
public struct ProgramCalendar: Hashable, Sendable {
    public static let blockLengthWeeks = 13
    public let testWeekStart: LocalDate
    public let deloadWeeks: Set<LocalDate>

    public init(testWeekStart: LocalDate = LocalDate(2026, 10, 12), deloadWeeks: Set<LocalDate> = []) {
        self.testWeekStart = testWeekStart.startOfWeek
        self.deloadWeeks = deloadWeeks
    }

    public var block1Start: LocalDate { testWeekStart.adding(days: 7) }

    public func startOfBlock(_ n: Int) -> LocalDate {
        precondition(n >= 1)
        return block1Start.adding(days: (n - 1) * ProgramCalendar.blockLengthWeeks * 7)
    }

    /// Monday of week `week` (1...13) in block `n`.
    public func startOfWeek(block n: Int, week: Int) -> LocalDate {
        if n == 0 { return testWeekStart }
        return startOfBlock(n).adding(days: (week - 1) * 7)
    }

    /// All dates (inclusive) of a block, used to decide "done this quarter".
    public func dateRange(ofBlock n: Int) -> ClosedRange<LocalDate> {
        if n <= 0 { return LocalDate(1900, 1, 1)...block1Start.adding(days: -1) }
        let s = startOfBlock(n)
        return s...s.adding(days: ProgramCalendar.blockLengthWeeks * 7 - 1)
    }

    /// User-facing block context: "test week", "block 1 · week 3 · volume",
    /// or "test week starts Oct 12" before the program begins.
    public func contextLabel(on date: LocalDate) -> String {
        let p = position(on: date)
        switch p.phase {
        case .preProgram: return "test week starts \(testWeekStart.shortMonthName) \(testWeekStart.day)"
        case .test: return p.block == 0 ? "test week" : "block \(p.block) · test week"
        default:
            let phase = p.isDeloadOverride ? "deload (swapped)" : p.phase.displayName
            return "block \(p.block) · week \(p.week) · \(phase)"
        }
    }

    public func position(on date: LocalDate) -> BlockPosition {
        if date < testWeekStart { return BlockPosition(block: 0, week: 0, phase: .preProgram) }
        if date < block1Start { return BlockPosition(block: 0, week: 13, phase: .test) }
        let d = block1Start.days(until: date)
        let blockDays = ProgramCalendar.blockLengthWeeks * 7
        let block = d / blockDays + 1
        let week = (d % blockDays) / 7 + 1
        let base = BlockPhase.forBlockWeek(week)
        if base != .test, deloadWeeks.contains(date.startOfWeek) {
            return BlockPosition(block: block, week: week, phase: .deload, isDeloadOverride: true)
        }
        return BlockPosition(block: block, week: week, phase: base)
    }
}

/// Two-week lift rotation (Mon squat, Wed hip/pull, Fri overhead).
public struct LiftRotation: Hashable, Sendable {
    public enum Week: String, Codable, Sendable { case a = "A", b = "B" }

    public static let weekA: [Lift] = [.backSquat, .deadlift, .pushPress]
    public static let weekB: [Lift] = [.frontSquat, .hangPowerClean, .pushJerk]
    /// Test week pairs (Lift A, Lift B) per slot.
    public static let testWeekPairs: [(Lift, Lift)] = [(.backSquat, .pushPress), (.deadlift, .pushJerk), (.frontSquat, .hangPowerClean)]

    public let anchor: LocalDate
    public let schedule: [Weekday]

    public init(anchor: LocalDate, schedule: [Weekday]) {
        self.anchor = anchor.startOfWeek
        let s = Array(Set(schedule)).sorted()
        self.schedule = s.isEmpty ? [.monday, .wednesday, .friday] : s
    }

    public func week(for date: LocalDate) -> Week {
        let weeks = anchor.days(until: date.startOfWeek) / 7
        return ((weeks % 2) + 2) % 2 == 0 ? .a : .b
    }

    public func isScheduled(_ date: LocalDate) -> Bool { schedule.contains(date.weekday) }

    /// Slot (0 squat, 1 hip/pull, 2 overhead) for a date. Unscheduled days take
    /// the slot after the last scheduled day before them in the same week.
    public func slotIndex(for date: LocalDate) -> Int {
        let earlier = schedule.filter { $0 < date.weekday }.count
        return earlier % 3
    }

    public func lift(for date: LocalDate) -> Lift {
        let lifts = week(for: date) == .a ? LiftRotation.weekA : LiftRotation.weekB
        return lifts[slotIndex(for: date)]
    }

    public func testLifts(for date: LocalDate) -> (Lift, Lift) {
        LiftRotation.testWeekPairs[slotIndex(for: date)]
    }

    /// Next scheduled date on or after `date`.
    public func nextScheduledDate(onOrAfter date: LocalDate) -> LocalDate {
        var d = date
        for _ in 0..<7 where !isScheduled(d) { d = d.adding(days: 1) }
        return d
    }
}
