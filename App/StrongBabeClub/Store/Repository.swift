import Foundation
import WorkoutCore

/// Everything the app persists.
struct StoredData: Sendable {
    var settings: PlannerSettings = .default
    var workouts: [PlannedWorkout] = []
    var liftPrograms: [LiftProgram] = []
    var benchmarks: [Benchmark] = []
    var goals: [Goal] = []
}

/// Persistence boundary. The app uses `SwiftDataRepository` (encrypted at
/// rest with complete file protection); UI tests and previews use
/// `InMemoryRepository`. Views never touch SwiftData directly.
@MainActor
protocol Repository: AnyObject {
    func load() throws -> StoredData
    func save(workouts: [PlannedWorkout]) throws
    func save(settings: PlannerSettings) throws
    func save(liftPrograms: [LiftProgram]) throws
    func save(benchmarks: [Benchmark]) throws
    func save(goals: [Goal]) throws
    func replaceAll(_ data: StoredData) throws
    func deleteAll() throws
    /// Inserts new workouts and commits; on failure nothing from this batch is kept.
    func insert(batch: [PlannedWorkout]) throws
    /// Removes workouts (used to undo a partially imported file).
    func delete(workoutIDs: [UUID]) throws
}

@MainActor
final class InMemoryRepository: Repository {
    private var data: StoredData

    init(_ data: StoredData = StoredData()) { self.data = data }

    func load() throws -> StoredData { data }

    func save(workouts: [PlannedWorkout]) throws {
        for w in workouts {
            if let i = data.workouts.firstIndex(where: { $0.id == w.id }) { data.workouts[i] = w } else { data.workouts.append(w) }
        }
    }

    func save(settings: PlannerSettings) throws { data.settings = settings }
    func save(liftPrograms: [LiftProgram]) throws { data.liftPrograms = liftPrograms }
    func save(benchmarks: [Benchmark]) throws { data.benchmarks = benchmarks }
    func save(goals: [Goal]) throws { data.goals = goals }
    func replaceAll(_ d: StoredData) throws { data = d }
    func deleteAll() throws { data = StoredData() }

    /// Test hook: throw when inserting the Nth batch (1-based).
    var failOnBatch: Int?
    private var batches = 0

    func insert(batch: [PlannedWorkout]) throws {
        batches += 1
        if batches == failOnBatch { throw CocoaError(.fileWriteUnknown) }
        data.workouts.append(contentsOf: batch)
    }

    func delete(workoutIDs: [UUID]) throws {
        let ids = Set(workoutIDs)
        data.workouts.removeAll { ids.contains($0.id) }
    }
}
