import Foundation
@testable import WorkoutCore

/// Builders for synthetic (invented) workout history used across tests.
enum TestData {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    static func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
    }

    static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: fixtureURL(name))
    }

    /// A done workout with one strength lift logged as ramping sets.
    static func strengthDay(_ date: LocalDate, _ lift: Lift, weights: [Double], reps: Int = 5,
                            planned: [PlannedSet]? = nil, status: WorkoutStatus = .done,
                            difficulty: Int? = nil, energy: Energy? = nil, sticker: StickerID? = nil,
                            metabolic: WorkoutSection? = nil) -> PlannedWorkout {
        let logs = weights.enumerated().map { SetLog(setNumber: $0.offset + 1, reps: reps, weight: $0.element) }
        let item = SectionItem(letter: "A", movementID: lift.movementID, movementName: lift.displayName, reps: reps,
                               plannedSets: planned ?? [], setLogs: status == .done ? logs : [])
        var sections = [WorkoutSection(kind: .strength, format: .everyNMin, instructions: "", lift: lift, items: [item])]
        if let metabolic { sections.append(metabolic) }
        return PlannedWorkout(date: date, status: status, sections: sections,
                              sticker: sticker,
                              feedback: WorkoutFeedback(energy: energy, strengthDifficulty: difficulty))
    }

    static func simple(_ date: LocalDate, _ status: WorkoutStatus, feedback: WorkoutFeedback? = nil) -> PlannedWorkout {
        PlannedWorkout(date: date, status: status, sections: [], feedback: feedback)
    }

    /// Done workouts on every Mon/Wed/Fri between two dates (inclusive), with
    /// lifts following the rotation and gently rising weights.
    static func consistentHistory(from start: LocalDate, to end: LocalDate, settings: PlannerSettings = .default) -> [PlannedWorkout] {
        var out: [PlannedWorkout] = []
        var d = start
        var n = 0.0
        while d <= end {
            if settings.rotation.isScheduled(d) {
                let lift = settings.rotation.lift(for: d)
                let base = lift.isLowerBody ? 95.0 : 45.0
                let top = base + 5 * (n / 6).rounded(.down)
                out.append(strengthDay(d, lift, weights: [base - 20, base - 10, base, top].map { max(45, $0) }, difficulty: 3, energy: .okay))
                n += 1
            }
            d = d.adding(days: 1)
        }
        return out
    }

    static func amrapSection(benchmarkID: UUID? = nil, rounds: [(Int, Int)], modified: Bool = false) -> WorkoutSection {
        WorkoutSection(kind: .metabolic, format: .amrapWithRest, name: "amrap-5-4-fungi", instructions: "", rounds: 5,
                       workSec: 240, restSec: 60, benchmarkID: benchmarkID, isModified: modified,
                       items: [SectionItem(letter: "A", movementID: "kb-swing", movementName: "KB Swings", reps: 5),
                               SectionItem(letter: "B", movementID: "push-up", movementName: "Push-Ups", reps: 4)],
                       roundLogs: rounds.enumerated().map { RoundLog(roundNumber: $0.offset + 1, rounds: $0.element.0, reps: $0.element.1) })
    }

    static func benchmark(slot: Int, name: String = "amrap-5-4-fungi") -> Benchmark {
        let id = UUID()
        var t = amrapSection(benchmarkID: id, rounds: [])
        t.name = name
        return Benchmark(id: id, name: name, template: t, quarterSlot: slot)
    }
}
