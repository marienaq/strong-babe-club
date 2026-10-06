import Foundation

/// Full app backup (export on user action; import re-validates everything).
public struct AppBackup: Codable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var exportedAt: Date
    public var settings: PlannerSettings
    public var workouts: [PlannedWorkout]
    public var liftPrograms: [LiftProgram]
    public var benchmarks: [Benchmark]
    public var goals: [Goal]

    public init(version: Int = AppBackup.currentVersion, exportedAt: Date, settings: PlannerSettings, workouts: [PlannedWorkout],
                liftPrograms: [LiftProgram], benchmarks: [Benchmark], goals: [Goal]) {
        self.version = version
        self.exportedAt = exportedAt
        self.settings = settings
        self.workouts = workouts
        self.liftPrograms = liftPrograms
        self.benchmarks = benchmarks
        self.goals = goals
    }
}

public enum BackupCodec {
    public static func encode(_ backup: AppBackup) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return try e.encode(backup)
    }

    /// What kind of JSON a user-picked file holds.
    public enum Kind: Equatable, Sendable { case appBackup, coachHistory }

    public static func sniff(_ data: Data) -> Kind? {
        guard let first = data.first(where: { !" \n\r\t".utf8.contains($0) }) else { return nil }
        if first == UInt8(ascii: "[") { return .coachHistory }
        if first == UInt8(ascii: "{") { return .appBackup }
        return nil
    }

    public static func decode(_ data: Data, limits: ImportLimits = .standard) throws -> (backup: AppBackup, issues: [ImportIssue]) {
        guard !data.isEmpty else { throw ImportError.empty }
        guard data.count <= limits.maxBytes else { throw ImportError.tooLarge(bytes: data.count, limit: limits.maxBytes) }
        struct VersionProbe: Decodable { let version: Int }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        let probe: VersionProbe
        do { probe = try d.decode(VersionProbe.self, from: data) } catch {
            if (try? JSONSerialization.jsonObject(with: data)) == nil { throw ImportError.notJSON }
            throw ImportError.wrongShape("missing backup version")
        }
        guard (1...AppBackup.currentVersion).contains(probe.version) else { throw ImportError.unsupportedVersion(probe.version) }
        var backup: AppBackup
        do { backup = try d.decode(AppBackup.self, from: data) } catch {
            throw ImportError.wrongShape("not a Strong Babe Club backup")
        }
        guard backup.workouts.count <= limits.maxWorkouts else {
            throw ImportError.tooManyRecords(count: backup.workouts.count, limit: limits.maxWorkouts)
        }
        var s = Sanitizer(limits: limits)
        backup.settings = backup.settings.sanitized()
        let total = backup.workouts.count
        backup.workouts = backup.workouts.enumerated().compactMap { i, w in s.workout(w, "workouts[\(i)]") }
        if total > 0, Double(total - backup.workouts.count) / Double(total) > limits.maxInvalidFraction {
            throw ImportError.tooManyInvalid(invalid: total - backup.workouts.count, total: total)
        }
        backup.liftPrograms = backup.liftPrograms.prefix(Lift.allCases.count * 20).compactMap { p in
            guard p.trainingMax.isFinite, limits.weightRange.contains(p.trainingMax), p.trainingMax > 0 else { return nil }
            return p
        }
        backup.benchmarks = Array(backup.benchmarks.prefix(50)).compactMap { b in
            let probe = PlannedWorkout(date: LocalDate(2000, 1, 1), sections: [b.template])
            guard let clean = s.workout(probe, "benchmark"), let t = clean.sections.first else { return nil }
            let name = WorkoutNamer.isValid(b.name) ? b.name : String(b.name.prefix(60))
            return Benchmark(id: b.id, name: name, template: t, active: b.active, quarterSlot: min(max(b.quarterSlot, 0), 50))
        }
        backup.goals = Array(backup.goals.prefix(100)).filter { $0.targetWeight.isFinite && limits.weightRange.contains($0.targetWeight) }
        return (backup, s.issues)
    }
}
