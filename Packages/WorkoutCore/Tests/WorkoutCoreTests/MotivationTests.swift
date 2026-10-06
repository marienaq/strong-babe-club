import XCTest
@testable import WorkoutCore

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
}
