// wcplan: print the planner's workout for a date (developer tool).
//
//   swift run wcplan 2026-10-19 [--history path/to/history.json] [--days 5] [--simulate-done]
//
// --simulate-done appends each printed day to the history as done, so
// benchmarks progress across a multi-day run.
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
func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}
let historyPath = option("--history")
let days = Int(option("--days") ?? "1") ?? 1
let simulateDone = flag("--simulate-done")
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
if !history.isEmpty {
    let asOf = start
    print("Training maxes as of \(asOf) (block 1 starts \(settings.calendar.block1Start)):")
    for lift in Lift.allCases {
        if let e = TrainingMax.estimate(lift, history: history, asOf: min(asOf, settings.calendar.block1Start)) {
            print("  \(lift.displayName): \(formatPounds(e.trainingMax)) lb\(e.calibrating ? " (calibrating)" : "") from \(e.basis)")
        }
    }
    print("")
}
let benchmarks = BenchmarkProposer.propose(from: history)
if !benchmarks.isEmpty {
    print("Benchmarks: " + benchmarks.map { "\($0.name) (slot \($0.quarterSlot))" }.joined(separator: ", ") + "\n")
}
let planner = RulesWorkoutPlanner()
var d = start
var printed = 0
while printed < days {
    defer { d = d.adding(days: 1) }
    guard settings.rotation.isScheduled(d) else { continue }
    printed += 1
    do {
        var w = try planner.makePlan(PlanRequest(date: d, settings: settings, history: history, benchmarks: benchmarks))
        let pos = w.position!
        print("== \(d.shortDisplay) · block \(pos.block) week \(pos.week) (\(pos.phase.displayName)) · ~\(w.estimatedMinutes) min")
        if let n = w.coachNote { print("   \(n.title): \(n.message)") }
        for s in w.sections {
            var head = "-- \(s.kind.displayName)\(s.name.map { " [\($0)]" } ?? "")"
            if s.kind == .metabolic {
                let secs = s.estimatedSeconds
                head += " {\(s.stimulus?.rawValue ?? "-") · \(MetconBand.of(seconds: secs).rawValue) · \(secs) s"
                head += s.benchmarkID != nil ? " · benchmark}" : "}"
            }
            print("\(head): \(s.instructions.replacingOccurrences(of: "\n", with: " / "))")
            for i in s.items {
                let sets = i.plannedSets.map { "\($0.reps)@\(Int($0.weight))" }.joined(separator: " ")
                print("   \(i.letter): \(i.displayLine)\(i.weightLabel.map { " (\($0))" } ?? "") \(sets)")
            }
            for r in w.reasons(for: s.kind) { print("   why: \(r.text)") }
        }
        print("")
        if simulateDone {
            // Done as planned, with neutral feedback and a plausible score.
            w.status = .done
            w.feedback = WorkoutFeedback(energy: .okay, strengthDifficulty: 3, metabolicDifficulty: 3)
            if let i = w.sections.firstIndex(where: { $0.kind == .metabolic }) {
                let s = w.sections[i]
                let k = s.expectedScore ?? 0
                switch s.format {
                case .forTime: w.sections[i].roundLogs = [RoundLog(roundNumber: 1, timeSec: Int(k > 0 ? k : 900))]
                case .amrap, .amrapWithRest:
                    // On pace: the expected rounds, with the partial round as reps.
                    let whole = Int(max(k, 1)), partial = Int((max(k, 1) - Double(whole)) * Double(s.repsPerRound))
                    w.sections[i].roundLogs = (1...s.prescribedRounds).map { RoundLog(roundNumber: $0, rounds: whole, reps: partial) }
                default:
                    w.sections[i].roundLogs = (1...s.prescribedRounds).map { RoundLog(roundNumber: $0, reps: 20) }
                }
            }
            if let i = w.sections.firstIndex(where: { $0.kind == .strength }) {
                for j in w.sections[i].items.indices {
                    w.sections[i].items[j].setLogs = w.sections[i].items[j].plannedSets.map {
                        SetLog(setNumber: $0.setNumber, reps: $0.reps, weight: $0.weight)
                    }
                }
            }
            history.append(w)
        }
    } catch let e as PlannerError {
        print("Planning failed for \(d): \(e.userMessage)")
    } catch {
        print("Planning failed for \(d): \(error)")
    }
}
