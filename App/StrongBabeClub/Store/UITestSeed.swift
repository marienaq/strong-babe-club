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
            var sections = [WorkoutSection(kind: .strength, format: .everyNMin, instructions: "", lift: lift, items: [item])]
            if i % 2 == 0 { sections.append(metabolic(i)) }
            workouts.append(PlannedWorkout(date: start.adding(days: offset), status: .done,
                                           sections: sections,
                                           sticker: [.barbell, .kettle, .dumbbell, .flame][i % 4],
                                           feedback: WorkoutFeedback(energy: .okay, strengthDifficulty: 3, metabolicDifficulty: 3),
                                           source: "import"))
        }
        return StoredData(workouts: workouts)
    }

    /// Invented metabolic pieces with scores (tabata / amrap) for history panels.
    static func metabolic(_ i: Int) -> WorkoutSection {
        let moves = [SectionItem(letter: "A", movementID: "kb-swing", movementName: "KB Swings", reps: 10),
                     SectionItem(letter: "B", movementID: "push-up", movementName: "Push-Ups", reps: 6)]
        if i % 4 == 0 {
            return WorkoutSection(kind: .metabolic, format: .tabata, name: "tabata-8-8-seed\(i)", instructions: "", rounds: 8,
                                  workSec: 20, restSec: 10, durationMin: 8, items: moves,
                                  roundLogs: (1...16).map { RoundLog(roundNumber: $0, reps: 8 + ($0 + i) % 4) })
        }
        return WorkoutSection(kind: .metabolic, format: .amrapWithRest, name: "amrap-5-4-seed\(i)", instructions: "", rounds: 5,
                              workSec: 240, restSec: 60, items: moves,
                              roundLogs: (1...5).map { RoundLog(roundNumber: $0, rounds: 4 + ($0 % 2), reps: (i + $0) % 6) })
    }
}
