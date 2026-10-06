import XCTest
@testable import WorkoutCore

/// Streak and completion measured against the Mon/Wed/Fri schedule.
final class ScheduleStreakTests: XCTestCase {
    let mwf: [Weekday] = [.monday, .wednesday, .friday]

    /// Done workouts on every scheduled day in [from, to].
    func done(_ from: LocalDate, _ to: LocalDate, schedule: [Weekday]? = nil, source: String = "import") -> [PlannedWorkout] {
        var out: [PlannedWorkout] = []
        var d = from
        while d <= to {
            if (schedule ?? mwf).contains(d.weekday) {
                var w = TestData.simple(d, .done)
                w.source = source
                out.append(w)
            }
            d = d.adding(days: 1)
        }
        return out
    }

    func streak(_ w: [PlannedWorkout], _ today: LocalDate, breaks: [TrainingBreak] = []) -> StreakSummary {
        Motivation.streak(w, today: today, schedule: mwf, breaks: breaks)
    }

    /// The owner's report: imported history only has done days, so a
    /// 4-week summer gap used to be invisible ("366 in a row").
    func testFourWeekGapResetsStreakAndBestIsPreGapRun() {
        let before = done(LocalDate(2026, 4, 6), LocalDate(2026, 7, 3))   // 13 weeks
        let after = done(LocalDate(2026, 8, 3), LocalDate(2026, 10, 2))   // 9 weeks
        let s = streak(before + after, LocalDate(2026, 10, 5))
        XCTAssertEqual(before.count, 39)
        XCTAssertEqual(after.count, 27)
        XCTAssertEqual(s, StreakSummary(current: 27, best: 39))
        XCTAssertNotEqual(s.current, before.count + after.count, "the old record-only count")
    }

    func testSwappingAScheduledDayIsNotAMiss() {
        var w = done(LocalDate(2026, 9, 7), LocalDate(2026, 9, 25))
        w.removeAll { $0.date == LocalDate(2026, 9, 16) }               // skip Wed
        w.append(TestData.simple(LocalDate(2026, 9, 17), .done))        // ...train Thu
        XCTAssertEqual(streak(w, LocalDate(2026, 9, 28)).current, 9)
    }

    func testTwoOfThreeInAWeekResets() {
        var w = done(LocalDate(2026, 9, 7), LocalDate(2026, 9, 16))     // Mon 7 ... Wed 16
        w.append(TestData.simple(LocalDate(2026, 9, 21), .done))        // Fri 18 missed
        let s = streak(w, LocalDate(2026, 9, 22))
        XCTAssertEqual(s.current, 1)
        XCTAssertEqual(s.best, 5)
    }

    func testExtraWorkoutsAddButCannotCoverAnotherWeek() {
        var w = done(LocalDate(2026, 9, 7), LocalDate(2026, 9, 11))
        w.append(TestData.simple(LocalDate(2026, 9, 12), .done))        // extra Saturday
        w += done(LocalDate(2026, 9, 14), LocalDate(2026, 9, 16))       // Fri 18 missed
        let s = streak(w, LocalDate(2026, 9, 21))
        XCTAssertEqual(s.best, 6, "extra Saturday counts")
        XCTAssertEqual(s.current, 0, "but can't cancel next week's miss")
    }

    func testExcusedDaysNeitherBreakNorExtend() {
        var w = done(LocalDate(2026, 9, 7), LocalDate(2026, 9, 25))
        w.removeAll { $0.date == LocalDate(2026, 9, 16) }
        w.append(TestData.simple(LocalDate(2026, 9, 16), .excused))
        XCTAssertEqual(streak(w, LocalDate(2026, 9, 28)).current, 8)
    }

    func testPlannedBreakNeitherBreaksNorExtends() {
        let w = done(LocalDate(2026, 6, 1), LocalDate(2026, 7, 3)) + done(LocalDate(2026, 8, 3), LocalDate(2026, 8, 14))
        let spain = TrainingBreak(label: "Spain", from: LocalDate(2026, 7, 6), to: LocalDate(2026, 7, 31))
        XCTAssertEqual(streak(w, LocalDate(2026, 8, 17)).current, 6)
        XCTAssertEqual(streak(w, LocalDate(2026, 8, 17), breaks: [spain]).current, 15 + 6)
    }

    func testTodayAndRestOfTheWeekDontCountYet() {
        var w = done(LocalDate(2026, 9, 28), LocalDate(2026, 10, 2))
        w.append(TestData.simple(LocalDate(2026, 10, 5), .done))        // Mon done
        w.append(TestData.simple(LocalDate(2026, 10, 7), .planned))     // today, open
        XCTAssertEqual(streak(w, LocalDate(2026, 10, 7)).current, 4, "today open, Fri ahead")
        // A missed Monday in the current week does count once it has passed.
        let missedMon = done(LocalDate(2026, 9, 28), LocalDate(2026, 10, 2)) + [TestData.simple(LocalDate(2026, 10, 7), .done)]
        XCTAssertEqual(streak(missedMon, LocalDate(2026, 10, 9)).current, 0)
    }

    func testNoHistory() {
        XCTAssertEqual(streak([], LocalDate(2026, 10, 5)), StreakSummary(current: 0, best: 0))
        XCTAssertNil(Motivation.completion([], today: LocalDate(2026, 10, 5), schedule: mwf).fraction)
    }

    func testCompletionWithGapBreakAndExtras() {
        let w = done(LocalDate(2026, 6, 1), LocalDate(2026, 7, 3)) + done(LocalDate(2026, 8, 3), LocalDate(2026, 8, 14))
        // Window Jul 19 - Aug 17: 6 missed (Jul 20-31) + 6 done; Mon Aug 17 not done yet.
        let c = Motivation.completion(w, today: LocalDate(2026, 8, 17), schedule: mwf)
        XCTAssertEqual(c.planned, 12)
        XCTAssertEqual(c.done, 6)
        XCTAssertEqual(c.percent, 50)
        let spain = TrainingBreak(label: "Spain", from: LocalDate(2026, 7, 6), to: LocalDate(2026, 7, 31))
        let b = Motivation.completion(w, today: LocalDate(2026, 8, 17), schedule: mwf, breaks: [spain])
        XCTAssertEqual(b.planned, 6)
        XCTAssertEqual(b.percent, 100)
        XCTAssertEqual(b.excused, 6)
        // Today counts once it's done; extras never push past 100%.
        let extra = w + [TestData.simple(LocalDate(2026, 8, 17), .done), TestData.simple(LocalDate(2026, 8, 15), .done)]
        let e = Motivation.completion(extra, today: LocalDate(2026, 8, 17), schedule: mwf, breaks: [spain])
        XCTAssertEqual(e.planned, 7)
        XCTAssertEqual(e.done, 7)
    }

    func testCompletionExcusesSickDays() {
        var w = done(LocalDate(2026, 9, 7), LocalDate(2026, 10, 2))
        w.removeAll { $0.date == LocalDate(2026, 9, 23) }
        w.append(TestData.simple(LocalDate(2026, 9, 23), .excused))
        let c = Motivation.completion(w, today: LocalDate(2026, 10, 5), schedule: mwf)
        XCTAssertEqual(c.excused, 1)
        XCTAssertEqual(c.planned, 11)
        XCTAssertEqual(c.percent, 100)
    }

    func testMissesInWindow() {
        let w = done(LocalDate(2026, 9, 7), LocalDate(2026, 9, 18))
        XCTAssertEqual(Motivation.misses(w, today: LocalDate(2026, 9, 30), withinDays: 14, schedule: mwf), 4) // Sep 21, 23, 25, 28 (today not yet)
    }

    func testSettingsDecodeWithoutBreaks() throws {
        var s = PlannerSettings.default
        s.displayName = "Sam"
        s.breaks = [TrainingBreak(label: "Spain", from: LocalDate(2026, 7, 31), to: LocalDate(2026, 7, 6))]
        XCTAssertEqual(s.breaks[0].from, LocalDate(2026, 7, 6), "dates are ordered")
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as! [String: Any]
        XCTAssertEqual(try JSONDecoder().decode(PlannerSettings.self, from: JSONEncoder().encode(s)), s)
        json.removeValue(forKey: "breaks")
        let old = try JSONDecoder().decode(PlannerSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.displayName, "Sam")
        XCTAssertTrue(old.breaks.isEmpty)
        var long = s
        long.breaks = [TrainingBreak(label: String(repeating: "x", count: 99), from: LocalDate(2026, 1, 1), to: LocalDate(2026, 1, 2)),
                       TrainingBreak(label: "  ", from: LocalDate(2026, 2, 1), to: LocalDate(2026, 2, 2))]
        XCTAssertEqual(long.sanitized().breaks.map(\.label.count), [40, 5])
    }
}

final class MissedLogTests: XCTestCase {
    let mwf: [Weekday] = [.monday, .wednesday, .friday]

    func done(_ dates: [LocalDate]) -> [PlannedWorkout] { dates.map { TestData.simple($0, .done) } }

    func mwfDays(_ from: LocalDate, _ to: LocalDate) -> [LocalDate] {
        var out: [LocalDate] = []
        var d = from
        while d <= to { if mwf.contains(d.weekday) { out.append(d) }; d = d.adding(days: 1) }
        return out
    }

    func testSummerGapIsOneGroupedEntryAndSingleMissesStaySingle() {
        var days = mwfDays(LocalDate(2026, 6, 1), LocalDate(2026, 7, 3)) + mwfDays(LocalDate(2026, 8, 3), LocalDate(2026, 10, 2))
        days.removeAll { $0 == LocalDate(2026, 9, 16) }
        let entries = MissedLog.entries(done(days), today: LocalDate(2026, 10, 5), schedule: mwf)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].label, "missed 4 weeks · Jul 6 – Jul 31")
        XCTAssertEqual(entries[0].days.count, 12)
        XCTAssertTrue(entries[0].isGroup)
        XCTAssertEqual(entries[1].label, "missed · Wed Sep 16")
        XCTAssertFalse(entries[1].isGroup)
    }

    func testShortRunsStayIndividual() {
        let days = mwfDays(LocalDate(2026, 9, 7), LocalDate(2026, 9, 11)) + mwfDays(LocalDate(2026, 9, 21), LocalDate(2026, 9, 25))
        let entries = MissedLog.entries(done(days), today: LocalDate(2026, 9, 28), schedule: mwf)
        XCTAssertEqual(entries.map(\.label), ["missed · Mon Sep 14", "missed · Wed Sep 16", "missed · Fri Sep 18"])
    }

    func testSwapsSickDaysBreaksAndTodayAreNotMisses() {
        var w = done(mwfDays(LocalDate(2026, 9, 7), LocalDate(2026, 10, 2)).filter { $0 != LocalDate(2026, 9, 16) && $0 != LocalDate(2026, 9, 23) })
        w.append(TestData.simple(LocalDate(2026, 9, 17), .done))       // Wed -> Thu
        w.append(TestData.simple(LocalDate(2026, 9, 23), .excused))    // sick
        XCTAssertTrue(MissedLog.entries(w, today: LocalDate(2026, 10, 5), schedule: mwf).isEmpty)
        // Today (Mon Oct 5) with no workout yet is not a miss either.
        XCTAssertFalse(MissedLog.days(w, today: LocalDate(2026, 10, 5), schedule: mwf).contains(LocalDate(2026, 10, 5)))
        let gap = done(mwfDays(LocalDate(2026, 6, 1), LocalDate(2026, 7, 3)) + mwfDays(LocalDate(2026, 8, 3), LocalDate(2026, 8, 14)))
        let spain = TrainingBreak(label: "Spain", from: LocalDate(2026, 7, 6), to: LocalDate(2026, 7, 31))
        XCTAssertTrue(MissedLog.entries(gap, today: LocalDate(2026, 8, 17), schedule: mwf, breaks: [spain]).isEmpty)
    }

    func testMarkingMissesChangesTheStreak() {
        var w = done(mwfDays(LocalDate(2026, 9, 7), LocalDate(2026, 10, 2)).filter { $0 != LocalDate(2026, 9, 23) })
        XCTAssertEqual(Motivation.streak(w, today: LocalDate(2026, 10, 5), schedule: mwf).current, 3, "the miss resets at the end of its week")
        w.append(TestData.simple(LocalDate(2026, 9, 23), .excused))     // mark as sick day
        XCTAssertEqual(Motivation.streak(w, today: LocalDate(2026, 10, 5), schedule: mwf).current, 11)
        w[w.count - 1].status = .skipped                                  // back to missed
        XCTAssertEqual(Motivation.streak(w, today: LocalDate(2026, 10, 5), schedule: mwf).current, 3)
        XCTAssertEqual(MissedLog.days(w, today: LocalDate(2026, 10, 5), schedule: mwf), [LocalDate(2026, 9, 23)])
    }
}

final class StickerPageTests: XCTestCase {
    func testImportedHistoryLeavesThePageEmpty() {
        let w = (0..<20).map { i -> PlannedWorkout in
            var x = TestData.strengthDay(LocalDate(2026, 9, 1).adding(days: i * 2), .deadlift, weights: [100])
            x.source = "import"
            if i == 3 { x.sticker = .barbell } // stray default sticker on an import is ignored
            return x
        }
        let slots = StickerPage.slots(w, today: LocalDate(2026, 10, 5))
        XCTAssertEqual(slots, Array(repeating: .empty, count: 12))
    }

    func testPickedStickersNewestLastThenTodayThenEmpty() {
        let today = LocalDate(2026, 10, 19)
        var w = [TestData.strengthDay(LocalDate(2026, 10, 12), .deadlift, weights: [100], sticker: .bear),
                 TestData.strengthDay(LocalDate(2026, 10, 14), .deadlift, weights: [100], sticker: .flame),
                 TestData.strengthDay(LocalDate(2026, 10, 16), .deadlift, weights: [100])]   // finished, no sticker picked
        w.append(TestData.simple(LocalDate(2026, 10, 17), .skipped))
        var open = TestData.strengthDay(today, .frontSquat, weights: [], status: .planned)
        open.sections[0].items[0].setLogs = []
        w.append(open)
        let slots = StickerPage.slots(w, today: today)
        XCTAssertEqual(Array(slots.prefix(3)), [.sticker(.bear, date: LocalDate(2026, 10, 12)), .sticker(.flame, date: LocalDate(2026, 10, 14)), .today])
        XCTAssertEqual(slots.count, 12)
        XCTAssertEqual(slots.filter { $0 == .empty }.count, 9)
        // Only the newest 11 stickers fit next to "today?".
        let many = (0..<15).map { TestData.strengthDay(LocalDate(2026, 9, 1).adding(days: $0), .deadlift, weights: [100], sticker: .kettle) }
        let full = StickerPage.slots(many + [open], today: today)
        XCTAssertEqual(full.count, 12)
        XCTAssertEqual(full.last, .today)
        XCTAssertEqual(full.first, .sticker(.kettle, date: LocalDate(2026, 9, 5)))
    }
}
