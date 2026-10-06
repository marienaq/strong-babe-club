import Foundation
import WorkoutCore

/// Small invented dataset for UI tests and previews (no personal data).
enum UITestSeed {
    static func data() -> StoredData {
        var workouts: [PlannedWorkout] = []
        let start = LocalDate(2026, 9, 28)
        let lifts: [Lift] = [.backSquat, .deadlift, .pushPress, .frontSquat, .hangPowerClean, .pushJerk]
        for (i, offset) in [0, 2, 4, 7, 9, 11, 14, 16].enumerated() {
            let lift = lifts[i % lifts.count]
            let base: Double = lift.isLowerBody ? 95 : 45
            let logs = (1...5).map { SetLog(setNumber: $0, reps: 5, weight: base + Double($0 - 1) * 10) }
            let item = SectionItem(letter: "A", movementID: lift.movementID, movementName: lift.displayName, reps: 5, setLogs: logs)
            workouts.append(PlannedWorkout(date: start.adding(days: offset), status: .done,
                                           sections: [WorkoutSection(kind: .strength, format: .everyNMin, instructions: "", lift: lift, items: [item])],
                                           sticker: [.barbell, .kettle, .dumbbell, .flame][i % 4],
                                           feedback: WorkoutFeedback(energy: .okay, strengthDifficulty: 3, metabolicDifficulty: 3),
                                           source: "import"))
        }
        return StoredData(workouts: workouts)
    }
}
