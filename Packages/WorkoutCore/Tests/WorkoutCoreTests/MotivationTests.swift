import XCTest
@testable import WorkoutCore

final class StreakTests: XCTestCase {
    let today = LocalDate(2026, 10, 30)

    func days(_ statuses: [WorkoutStatus], endingBefore end: LocalDate) -> [PlannedWorkout] {
        statuses.enumerated().map { i, s in TestData.simple(end.adding(days: -2 * (statuses.count - i)), s) }
    }

    func testCountsConsecutiveDone() {
        let w = days([.done, .skipped, .done, .done, .done], endingBefore: today)
        XCTAssertEqual(Motivation.streak(w, today: today), StreakSummary(current: 3, best: 3))
    }

    func testExcusedDoesNotBreakOrCount() {
        let w = days([.done, .done, .excused, .done], endingBefore: today)
        XCTAssertEqual(Motivation.streak(w, today: today).current, 3)
    }

    func testPastPlannedCountsAsMissedButTodayDoesNot() {
        var w = days([.done, .done, .planned, .done], endingBefore: today)
        XCTAssertEqual(Motivation.streak(w, today: today).current, 1)
        XCTAssertEqual(Motivation.streak(w, today: today).best, 2)
        w.append(TestData.simple(today, .planned))
        XCTAssertEqual(Motivation.streak(w, today: today).current, 1)
    }

    func testIgnoresFutureAndDeleted() {
        var w = days([.done, .done], endingBefore: today)
        w.append(TestData.simple(today.adding(days: 3), .skipped))
        var deleted = TestData.simple(today.adding(days: -1), .skipped)
        deleted.sync.deletedAt = Date()
        w.append(deleted)
        XCTAssertEqual(Motivation.streak(w, today: today).current, 2)
    }

    func testDuplicateDatePrefersDone() {
        let w = [TestData.simple(today.adding(days: -1), .skipped), TestData.simple(today.adding(days: -1), .done)]
        XCTAssertEqual(Motivation.streak(w, today: today).current, 1)
    }

    func testBestStreak() {
        let w = days([.done, .done, .done, .done, .skipped, .done], endingBefore: today)
        XCTAssertEqual(Motivation.streak(w, today: today), StreakSummary(current: 1, best: 4))
        XCTAssertEqual(Motivation.streak([], today: today), StreakSummary(current: 0, best: 0))
    }
}

final class CompletionTests: XCTestCase {
    let today = LocalDate(2026, 10, 30)

    func testElevenOfTwelveWithSickDayExcused() {
        var w: [PlannedWorkout] = []
        for i in 0..<11 { w.append(TestData.simple(today.adding(days: -2 * i - 1), .done)) }
        w.append(TestData.simple(today.adding(days: -24), .skipped))
        w.append(TestData.simple(today.adding(days: -26), .excused))
        let c = Motivation.completion(w, today: today)
        XCTAssertEqual(c.done, 11)
        XCTAssertEqual(c.planned, 12)
        XCTAssertEqual(c.excused, 1)
        XCTAssertEqual(c.percent, 92)
    }

    func testWindowAndTodayHandling() {
        let w = [TestData.simple(today.adding(days: -30), .skipped), // outside 30-day window
                 TestData.simple(today.adding(days: -29), .done),
                 TestData.simple(today, .planned)]
        let c = Motivation.completion(w, today: today)
        XCTAssertEqual(c.planned, 1)
        XCTAssertEqual(c.percent, 100)
        XCTAssertNil(Motivation.completion([], today: today).fraction)
    }
}

final class CoachNoteTests: XCTestCase {
    let today = LocalDate(2026, 11, 30) // Monday, week B -> Front Squat

    func testSteadyByDefault() {
        let note = CoachNoteSelector.select(history: [], today: today, todaysLift: .frontSquat)
        XCTAssertEqual(note.kind, .steady)
        XCTAssertFalse(note.makesPlanLighter)
    }

    func testJustShowUpAfterThreeRoughSessions() {
        let rough = WorkoutFeedback(energy: .sleepy, strengthDifficulty: 3)
        let w = (1...3).map { TestData.simple(today.adding(days: -2 * $0), .done, feedback: rough) }
        let note = CoachNoteSelector.select(history: w, today: today, todaysLift: .frontSquat)
        XCTAssertEqual(note.kind, .justShowUp)
        XCTAssertTrue(note.makesPlanShorter)
        XCTAssertTrue(note.makesPlanLighter)
    }

    func testComebackAfterMisses() {
        let w = [TestData.simple(today.adding(days: -12), .done),
                 TestData.simple(today.adding(days: -5), .skipped),
                 TestData.simple(today.adding(days: -3), .planned)]
        XCTAssertEqual(CoachNoteSelector.select(history: w, today: today, todaysLift: nil).kind, .comeback)
        // Excused sick days are not misses.
        let sick = [TestData.simple(today.adding(days: -5), .excused), TestData.simple(today.adding(days: -3), .excused)]
        XCTAssertEqual(CoachNoteSelector.select(history: sick, today: today, todaysLift: nil).kind, .steady)
    }

    func testPushWhenConsistentAndStalled() {
        var w: [PlannedWorkout] = []
        // Front squat stuck at 115 for its last 3 sessions, everything else done.
        for (i, d) in [-28, -14, -2].enumerated() {
            w.append(TestData.strengthDay(today.adding(days: d), .frontSquat, weights: [75, 95, 115], difficulty: 3))
            _ = i
        }
        for d in [-26, -24, -21, -19, -17, -12, -10, -7, -5] {
            w.append(TestData.simple(today.adding(days: d), .done))
        }
        let note = CoachNoteSelector.select(history: w, today: today, todaysLift: .frontSquat)
        XCTAssertEqual(note.kind, .push)
        XCTAssertEqual(note.lift, .frontSquat)
        XCTAssertTrue(note.message.contains("115"))
        // Not stalled on another lift's day: steady.
        XCTAssertEqual(CoachNoteSelector.select(history: w, today: today, todaysLift: .deadlift).kind, .steady)
    }

    func testPriorityJustShowUpBeatsComeback() {
        let rough = WorkoutFeedback(strengthDifficulty: 5)
        var w = (3...5).map { TestData.simple(today.adding(days: -2 * $0), .done, feedback: rough) }
        w.append(TestData.simple(today.adding(days: -3), .skipped))
        w.append(TestData.simple(today.adding(days: -1), .skipped))
        XCTAssertEqual(CoachNoteSelector.select(history: w, today: today, todaysLift: nil).kind, .justShowUp)
    }
}

final class StickerTests: XCTestCase {
    func testCommonsAlwaysAvailableRaresOnlyOnSpecialDays() {
        let plain = StickerCatalog.available(StickerContext(isPRDay: false, streakAfterWorkout: 3))
        XCTAssertEqual(plain.map(\.id), [.barbell, .kettle, .dumbbell, .bear, .flame])
        XCTAssertFalse(StickerCatalog.canPick(.star, context: StickerContext(isPRDay: false, streakAfterWorkout: 3)))
        XCTAssertTrue(StickerCatalog.canPick(.star, context: StickerContext(isPRDay: true, streakAfterWorkout: 3)))
    }

    func testStreakMilestonesUnlockOnTheDay() {
        XCTAssertTrue(StickerCatalog.canPick(.crown, context: StickerContext(isPRDay: false, streakAfterWorkout: 10)))
        XCTAssertFalse(StickerCatalog.canPick(.crown, context: StickerContext(isPRDay: false, streakAfterWorkout: 11)))
        XCTAssertTrue(StickerCatalog.canPick(.rainbow, context: StickerContext(isPRDay: false, streakAfterWorkout: 5)))
        XCTAssertEqual(StickerCatalog.streakMilestones, [5, 10, 25, 50, 100])
        XCTAssertEqual(StickerCatalog.definition(.star).unlockLabel, "PR only")
        XCTAssertTrue(StickerCatalog.definition(.trophy).isRare)
    }

    func testStickerPageSlots() {
        let today = LocalDate(2026, 10, 30)
        var w = (1...14).map { i in
            TestData.strengthDay(today.adding(days: -2 * i), .deadlift, weights: [100], sticker: i % 2 == 0 ? .barbell : nil)
        }
        w.append(TestData.simple(today.adding(days: -1), .excused))
        w.append(TestData.simple(today, .planned))
        let slots = StickerPage.slots(w, today: today)
        XCTAssertEqual(slots.count, 12)
        XCTAssertEqual(slots.last, .today)
        XCTAssertEqual(slots[slots.count - 2], .excused(date: today.adding(days: -1)))
        XCTAssertTrue(slots.contains(.sticker(.barbell, date: today.adding(days: -4))))
        XCTAssertTrue(slots.contains(.done(date: today.adding(days: -2))))
    }
}
