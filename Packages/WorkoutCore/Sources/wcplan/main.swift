// wcplan: print the planner's workout for a date (developer tool).
//
//   swift run wcplan 2026-10-19 [--history path/to/history.json] [--days 5]
//
// Reads only the files you pass; prints to stdout; never writes anything.
import Foundation
import WorkoutCore

var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    defer { args.removeSubrange(i...(i + 1)) }
    return args[i + 1]
}
let historyPath = option("--history")
let days = Int(option("--days") ?? "1") ?? 1
let start = args.first.flatMap(LocalDate.init(iso:)) ?? LocalDate.today()

var history: [PlannedWorkout] = []
if let historyPath {
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: historyPath))
        let result = try HistoryImporter().importCoachHistory(data)
        history = result.workouts
        print("Imported \(result.workouts.count) workouts (\(result.skipped) skipped, \(result.issues.count) issues)\n")
    } catch {
        print("Import failed: \(error)")
        exit(1)
    }
}
let settings = PlannerSettings.default
let benchmarks = BenchmarkProposer.propose(from: history)
let planner = RulesWorkoutPlanner()
var d = start
var printed = 0
while printed < days {
    defer { d = d.adding(days: 1) }
    guard settings.rotation.isScheduled(d) else { continue }
    printed += 1
    do {
        let w = try planner.makePlan(PlanRequest(date: d, settings: settings, history: history, benchmarks: benchmarks))
        let pos = w.position!
        print("== \(d.shortDisplay) · block \(pos.block) week \(pos.week) (\(pos.phase.displayName)) · ~\(w.estimatedMinutes) min")
        if let n = w.coachNote { print("   \(n.title): \(n.message)") }
        for s in w.sections {
            print("-- \(s.kind.displayName)\(s.name.map { " [\($0)]" } ?? ""): \(s.instructions.replacingOccurrences(of: "\n", with: " / "))")
            for i in s.items {
                let sets = i.plannedSets.map { "\($0.reps)@\(Int($0.weight))" }.joined(separator: " ")
                print("   \(i.letter): \(i.displayLine)\(i.weightLabel.map { " (\($0))" } ?? "") \(sets)")
            }
            for r in w.reasons(for: s.kind) { print("   why: \(r.text)") }
        }
        print("")
    } catch {
        print("Planning failed for \(d): \(error)")
    }
}
