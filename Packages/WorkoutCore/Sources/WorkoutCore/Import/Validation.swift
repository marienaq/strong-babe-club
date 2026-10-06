import Foundation

/// Hard bounds applied to everything that comes from a file. Values outside
/// these ranges are dropped (and reported), never trusted.
public struct ImportLimits: Sendable {
    public var maxBytes = 20 * 1024 * 1024
    public var maxWorkouts = 5_000
    public var maxSectionsPerWorkout = 8
    public var maxItemsPerSection = 30
    public var maxSetsPerItem = 30
    public var maxRoundsPerSection = 60
    public var maxStringLength = 4_000
    public var weightRange: ClosedRange<Double> = 0...1_000
    public var repsRange: ClosedRange<Int> = 0...1_000
    public var secondsRange: ClosedRange<Int> = 0...(4 * 3600)
    public var roundsRange: ClosedRange<Int> = 0...500
    public var dateRange: ClosedRange<LocalDate> = LocalDate(2000, 1, 1)...LocalDate(2100, 12, 31)
    /// Fail the whole import if more than this share of records is invalid.
    public var maxInvalidFraction = 0.5

    public init() {}
    public static let standard = ImportLimits()
}

public struct ImportIssue: Hashable, Sendable, CustomStringConvertible {
    public var path: String
    public var message: String
    public var description: String { "\(path): \(message)" }
}

public enum ImportError: Error, Equatable, CustomStringConvertible {
    case empty
    case tooLarge(bytes: Int, limit: Int)
    case notJSON
    case wrongShape(String)
    case tooManyRecords(count: Int, limit: Int)
    case tooManyInvalid(invalid: Int, total: Int)
    case unsupportedVersion(Int)

    public var description: String {
        switch self {
        case .empty: return "The file is empty."
        case .tooLarge(let b, let l): return "The file is too large (\(b / 1024) KB; the limit is \(l / 1024) KB)."
        case .notJSON: return "The file isn't valid JSON."
        case .wrongShape(let s): return "The file doesn't look like a workout history (\(s))."
        case .tooManyRecords(let c, let l): return "Too many workouts (\(c); the limit is \(l))."
        case .tooManyInvalid(let i, let t): return "\(i) of \(t) workouts were invalid, so nothing was imported."
        case .unsupportedVersion(let v): return "Backup version \(v) isn't supported by this app version."
        }
    }
}

/// Clamps / cleans values. Shared by the coach-history importer and backups.
struct Sanitizer {
    let limits: ImportLimits
    var issues: [ImportIssue] = []

    init(limits: ImportLimits) { self.limits = limits }

    /// Trims, removes control characters (except newlines/tabs), bounds length.
    func text(_ s: String?) -> String? {
        guard let s else { return nil }
        let cleaned = String(String.UnicodeScalarView(s.unicodeScalars.filter { u in
            u == "\n" || u == "\t" || !(CharacterSet.controlCharacters.contains(u) || u.properties.generalCategory == .format && u != "\u{200D}")
        }))
        let t = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        return String(t.prefix(limits.maxStringLength))
    }

    mutating func weight(_ w: Double?, _ path: String) -> Double? {
        guard let w else { return nil }
        guard w.isFinite, limits.weightRange.contains(w) else {
            issues.append(ImportIssue(path: path, message: "weight \(w) out of range, dropped"))
            return nil
        }
        return w
    }

    mutating func reps(_ r: Int?, _ path: String) -> Int? {
        guard let r else { return nil }
        guard limits.repsRange.contains(r) else {
            issues.append(ImportIssue(path: path, message: "reps \(r) out of range, dropped"))
            return nil
        }
        return r
    }

    mutating func seconds(_ s: Int?, _ path: String) -> Int? {
        guard let s else { return nil }
        guard limits.secondsRange.contains(s) else {
            issues.append(ImportIssue(path: path, message: "duration \(s) s out of range, dropped"))
            return nil
        }
        return s
    }

    mutating func rounds(_ r: Int?, _ path: String) -> Int? {
        guard let r else { return nil }
        guard limits.roundsRange.contains(r) else {
            issues.append(ImportIssue(path: path, message: "rounds \(r) out of range, dropped"))
            return nil
        }
        return r
    }

    /// Re-validates a fully decoded workout (used for app backups).
    mutating func workout(_ w: PlannedWorkout, _ path: String) -> PlannedWorkout? {
        guard limits.dateRange.contains(w.date) else {
            issues.append(ImportIssue(path: path, message: "date \(w.date) out of range"))
            return nil
        }
        var out = w
        out.sections = Array(w.sections.prefix(limits.maxSectionsPerWorkout)).enumerated().map { si, s0 in
            var s = s0
            let sp = "\(path).sections[\(si)]"
            s.name = text(s.name).flatMap { WorkoutNamer.isValid($0) ? $0 : String($0.prefix(60)) }
            s.instructions = text(s.instructions) ?? ""
            s.athleteNote = text(s.athleteNote) ?? ""
            s.rounds = rounds(s.rounds, sp + ".rounds")
            s.workSec = seconds(s.workSec, sp + ".workSec")
            s.restSec = seconds(s.restSec, sp + ".restSec")
            s.intervalSec = seconds(s.intervalSec, sp + ".intervalSec")
            s.durationMin = s.durationMin.flatMap { (0...240).contains($0) ? $0 : nil }
            s.trainingMax = weight(s.trainingMax, sp + ".trainingMax")
            s.roundLogs = Array(s.roundLogs.prefix(limits.maxRoundsPerSection)).map { r0 in
                var r = r0
                r.roundNumber = min(max(r.roundNumber, 1), limits.maxRoundsPerSection)
                r.rounds = rounds(r.rounds, sp + ".roundLogs")
                r.reps = reps(r.reps, sp + ".roundLogs")
                r.timeSec = seconds(r.timeSec, sp + ".roundLogs")
                return r
            }
            s.items = Array(s.items.prefix(limits.maxItemsPerSection)).enumerated().map { ii, i0 in
                var i = i0
                let ip = "\(sp).items[\(ii)]"
                i.letter = String((text(i.letter) ?? "A").prefix(2))
                i.movementName = text(i.movementName).map { String($0.prefix(120)) } ?? "Movement"
                i.movementID = MovementLibrary.slug(i.movementID.isEmpty ? i.movementName : i.movementID)
                i.reps = reps(i.reps, ip + ".reps")
                i.repsScheme = text(i.repsScheme).map { String($0.prefix(40)) }
                i.timeSec = seconds(i.timeSec, ip + ".timeSec")
                i.prescribedWeight = weight(i.prescribedWeight, ip + ".weight")
                i.weightLabel = text(i.weightLabel).map { String($0.prefix(40)) }
                i.plannedSets = Array(i.plannedSets.prefix(limits.maxSetsPerItem)).compactMap { p in
                    guard let w = weight(p.weight, ip + ".plannedSets"), let r = reps(p.reps, ip + ".plannedSets") else { return nil }
                    return PlannedSet(setNumber: min(max(p.setNumber, 1), limits.maxSetsPerItem), reps: r, weight: w,
                                      percentOfTM: p.percentOfTM.flatMap { $0.isFinite && (0...2).contains($0) ? $0 : nil })
                }
                i.setLogs = Array(i.setLogs.prefix(limits.maxSetsPerItem)).compactMap { l in
                    guard let w = weight(l.weight, ip + ".setLogs"), let r = reps(l.reps, ip + ".setLogs") else { return nil }
                    return SetLog(id: l.id, setNumber: min(max(l.setNumber, 1), limits.maxSetsPerItem), reps: r, weight: w,
                                  completedAt: l.completedAt)
                }
                return i
            }
            return s
        }
        if let f = w.feedback {
            out.feedback = WorkoutFeedback(energy: f.energy, strengthDifficulty: f.strengthDifficulty,
                                           metabolicDifficulty: f.metabolicDifficulty, notes: text(f.notes) ?? "")
        }
        out.reasons = Array(w.reasons.prefix(40)).compactMap { r in
            text(r.text).map { PlanReason(section: r.section, rule: String(r.rule.prefix(60)), text: $0) }
        }
        out.source = String(w.source.prefix(40))
        out.durationMin = w.durationMin.flatMap { (0...600).contains($0) ? $0 : nil }
        return out
    }
}

/// CSV export of strength logs. Values that a spreadsheet would execute as a
/// formula are neutralised.
public enum CSVExporter {
    public static func setLogs(_ workouts: [PlannedWorkout]) -> String {
        var lines = ["date,section,letter,movement,set,reps,weight_lb"]
        for w in workouts.sorted(by: { $0.date < $1.date }) where !w.isDeleted {
            for s in w.sections {
                for i in s.items {
                    for l in i.setLogs.sorted(by: { $0.setNumber < $1.setNumber }) {
                        let row: [String] = [w.date.iso, s.kind.rawValue, i.letter, i.movementName, String(l.setNumber),
                                             String(l.reps), formatPounds(l.weight)]
                        lines.append(row.map(field).joined(separator: ","))
                    }
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func roundLogs(_ workouts: [PlannedWorkout]) -> String {
        var lines = ["date,name,round,rounds,reps,time_sec"]
        for w in workouts.sorted(by: { $0.date < $1.date }) where !w.isDeleted {
            guard let s = w.metabolicSection else { continue }
            for r in s.roundLogs {
                let name: String = s.name ?? s.format.rawValue
                let rounds: String = r.rounds.map { String($0) } ?? ""
                let reps: String = r.reps.map { String($0) } ?? ""
                let time: String = r.timeSec.map { String($0) } ?? ""
                let row: [String] = [w.date.iso, name, String(r.roundNumber), rounds, reps, time]
                lines.append(row.map(field).joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func field(_ raw: String) -> String {
        var v = raw
        if let first = v.first, "=+-@\t\r".contains(first), Double(v) == nil { v = "'" + v }
        if v.contains(",") || v.contains("\"") || v.contains("\n") || v.contains("\r") {
            v = "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return v
    }
}
