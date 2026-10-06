import Foundation

/// Generic history template for people without a coach spreadsheet:
///
///     date,lift,set,reps,weight,unit
///     2026-09-28,Back Squat,1,5,135,lb
///     2026-09-28,Back Squat,2,5,145,lb
///
/// One row per logged set. `lift` is one of the six main lifts (singular or
/// plural); `unit` is lb or kg (default lb). Extra columns are ignored, the
/// header order doesn't matter, and every value is bounded like any import.
/// Each date becomes one done workout (one strength section per lift).
public enum CSVHistoryImporter {
    public static let template = "date,lift,set,reps,weight,unit\n"

    /// True when the data starts with the template header.
    public static func looksLikeTemplate(_ data: Data) -> Bool {
        guard let head = String(data: data.prefix(200), encoding: .utf8) else { return false }
        let first = head.split(whereSeparator: \.isNewline).first.map { String($0).lowercased() } ?? ""
        let cols = Set(first.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        return cols.isSuperset(of: ["date", "lift", "reps", "weight"])
    }

    public static func importCSV(_ data: Data, limits: ImportLimits = .standard, now: Date = Date()) throws -> ImportResult {
        guard !data.isEmpty else { throw ImportError.empty }
        guard data.count <= limits.maxBytes else { throw ImportError.tooLarge(bytes: data.count, limit: limits.maxBytes) }
        guard let text = String(data: data, encoding: .utf8) else { throw ImportError.wrongShape("not UTF-8 text") }
        var lines = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { throw ImportError.empty }
        let header = lines.removeFirst().lowercased().split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        func col(_ name: String) -> Int? { header.firstIndex(of: name) }
        guard let dateCol = col("date"), let liftCol = col("lift"), let repsCol = col("reps"), let weightCol = col("weight") else {
            throw ImportError.wrongShape("missing date, lift, reps or weight column")
        }
        let setCol = col("set"), unitCol = col("unit")
        guard lines.count <= limits.maxWorkouts * limits.maxSetsPerItem else {
            throw ImportError.tooManyRecords(count: lines.count, limit: limits.maxWorkouts * limits.maxSetsPerItem)
        }

        var issues: [ImportIssue] = []
        var reasons: [String: Int] = [:]
        var byDay: [LocalDate: [Lift: [SetLog]]] = [:]
        var bad = 0
        var rng = SeededRandom(seed: 0xC5F)
        for (i, line) in lines.enumerated() {
            let cells = line.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            func cell(_ c: Int?) -> String? { c.flatMap { $0 < cells.count ? cells[$0] : nil } }
            let path = "row \(i + 2)"
            guard let date = cell(dateCol).flatMap(LocalDate.init(iso:)), limits.dateRange.contains(date) else {
                bad += 1; reasons["row with an invalid date", default: 0] += 1
                issues.append(ImportIssue(path: path, message: "invalid date")); continue
            }
            guard let lift = cell(liftCol).flatMap(Lift.init(movementName:)) else {
                bad += 1; reasons["row with an unknown lift", default: 0] += 1
                issues.append(ImportIssue(path: path, message: "unknown lift")); continue
            }
            let unit = cell(unitCol).flatMap { WeightUnit(rawValue: $0.lowercased()) } ?? .lb
            guard let reps = cell(repsCol).flatMap(Int.init), limits.repsRange.contains(reps), reps > 0,
                  let raw = cell(weightCol).flatMap(Double.init), raw.isFinite, raw >= 0 else {
                bad += 1; reasons["row with invalid reps or weight", default: 0] += 1
                issues.append(ImportIssue(path: path, message: "invalid reps or weight")); continue
            }
            let pounds = unit.toPounds(raw)
            guard limits.weightRange.contains(pounds) else {
                bad += 1; reasons["row with invalid reps or weight", default: 0] += 1
                issues.append(ImportIssue(path: path, message: "weight out of range")); continue
            }
            var sets = byDay[date, default: [:]][lift, default: []]
            guard sets.count < limits.maxSetsPerItem else { continue }
            let n = cell(setCol).flatMap(Int.init).map { min(max($0, 1), limits.maxSetsPerItem) } ?? sets.count + 1
            sets.append(SetLog(id: UUID.seeded(&rng), setNumber: n, reps: reps, weight: pounds))
            byDay[date, default: [:]][lift] = sets
        }
        if !lines.isEmpty, Double(bad) / Double(lines.count) > limits.maxInvalidFraction {
            throw ImportError.tooManyInvalid(invalid: bad, total: lines.count)
        }
        let workouts = byDay.keys.sorted().prefix(limits.maxWorkouts).map { date -> PlannedWorkout in
            let lifts = byDay[date]!.keys.sorted()
            let items = lifts.enumerated().map { k, lift in
                SectionItem(id: UUID.seeded(&rng), letter: ["A", "B", "C", "D", "E", "F"][min(k, 5)], movementID: lift.movementID,
                            movementName: lift.displayName, reps: byDay[date]![lift]!.first?.reps,
                            setLogs: byDay[date]![lift]!.sorted { $0.setNumber < $1.setNumber })
            }
            let section = WorkoutSection(id: UUID.seeded(&rng), kind: .strength, format: .setsGoingUp, instructions: "Imported sets",
                                         lift: lifts.first, items: items)
            return PlannedWorkout(id: UUID.seeded(&rng), date: date, status: .done, sections: [section], source: "import",
                                  sync: SyncStamp(createdAt: now))
        }
        return ImportResult(workouts: Array(workouts), issues: issues, skipped: bad, skippedReasons: reasons, total: workouts.count + 0)
    }
}
