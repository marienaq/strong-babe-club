import Foundation

public struct ImportResult: Sendable {
    public var workouts: [PlannedWorkout]
    public var issues: [ImportIssue]
    /// Records in the file that were not imported.
    public var skipped: Int
    /// Why records were skipped, e.g. ["future-dated placeholder": 2].
    public var skippedReasons: [String: Int] = [:]
    /// Total records in the file.
    public var total: Int = 0

    public var doneCount: Int { workouts.filter { $0.status == .done }.count }
    public var notLoggedCount: Int { workouts.filter { $0.status == .skipped }.count }
    public var sickCount: Int { workouts.filter { $0.status == .excused }.count }

    /// "Imported 372 of 376 workouts: 309 done, 6 sick days, 57 not logged → missed
    /// (skipped 4: 2 future-dated placeholders, 2 with no usable sections)."
    public func summary(imported: Int? = nil, alreadyPresent: Int = 0) -> String {
        let n = imported ?? workouts.count
        var text = "Imported \(n) of \(total) workouts"
        var split = ["\(doneCount) done"]
        if sickCount > 0 { split.append("\(sickCount) sick day\(sickCount == 1 ? "" : "s")") }
        if notLoggedCount > 0 { split.append("\(notLoggedCount) not logged → missed") }
        text += ": " + split.joined(separator: ", ")
        var notes: [String] = []
        if skipped > 0 {
            let reasons = skippedReasons.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
                .map { "\($0.value) \($0.value == 1 ? $0.key : ImportResult.plural($0.key))" }
            notes.append("skipped \(skipped): " + reasons.joined(separator: ", "))
        }
        if alreadyPresent > 0 { notes.append("\(alreadyPresent) already in your journal") }
        if !notes.isEmpty { text += " (" + notes.joined(separator: "; ") + ")" }
        return text + "."
    }

    static func plural(_ reason: String) -> String {
        switch reason {
        case "future-dated placeholder": return "future-dated placeholders"
        case "invalid record": return "invalid records"
        case "record with an invalid date": return "records with an invalid date"
        default: return reason
        }
    }
}

/// Imports the coach-sheet history produced by `tools/import_sheet.py`.
///
/// Safety: input size is checked before parsing, the shape is decoded into
/// strict DTOs (unknown keys ignored, known keys must have the right type),
/// every number is range-checked and every string is cleaned and truncated.
/// Nothing in the file is ever executed or interpreted as code.
public struct HistoryImporter: Sendable {
    public let limits: ImportLimits

    public init(limits: ImportLimits = .standard) { self.limits = limits }

    public func importCoachHistory(_ data: Data, now: Date = Date()) throws -> ImportResult {
        guard !data.isEmpty else { throw ImportError.empty }
        guard data.count <= limits.maxBytes else { throw ImportError.tooLarge(bytes: data.count, limit: limits.maxBytes) }
        let decoded: [Lossy<WorkoutDTO>]
        do {
            decoded = try JSONDecoder().decode([Lossy<WorkoutDTO>].self, from: data)
        } catch DecodingError.typeMismatch {
            throw ImportError.wrongShape("expected a list of workouts")
        } catch {
            if (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil {
                throw ImportError.wrongShape("expected a list of workouts")
            }
            throw ImportError.notJSON
        }
        guard decoded.count <= limits.maxWorkouts else { throw ImportError.tooManyRecords(count: decoded.count, limit: limits.maxWorkouts) }

        var sanitizer = Sanitizer(limits: limits)
        var workouts: [PlannedWorkout] = []
        var skipped = 0
        var invalid = 0
        var reasons: [String: Int] = [:]
        var rng = SeededRandom(seed: 0x1_4B0)
        for (i, entry) in decoded.enumerated() {
            let path = "[\(i)]"
            guard let dto = entry.value else {
                skipped += 1
                invalid += 1
                reasons["invalid record", default: 0] += 1
                sanitizer.issues.append(ImportIssue(path: path, message: "not a valid workout (\(entry.error ?? "decode error"))"))
                continue
            }
            // Future-dated rows are cloned placeholders from the sheet, not history.
            if dto.flags?.contains("future_date") == true {
                skipped += 1
                reasons["future-dated placeholder", default: 0] += 1
                sanitizer.issues.append(ImportIssue(path: path, message: "future-dated placeholder, ignored"))
                continue
            }
            if LocalDate(iso: dto.date).map(limits.dateRange.contains) != true {
                skipped += 1
                invalid += 1
                reasons["record with an invalid date", default: 0] += 1
                sanitizer.issues.append(ImportIssue(path: path, message: "invalid date"))
                continue
            }
            if let w = map(dto, path: path, sanitizer: &sanitizer, rng: &rng, now: now) {
                workouts.append(w)
            } else {
                skipped += 1
                reasons["with no usable sections", default: 0] += 1
            }
        }
        if !decoded.isEmpty, Double(invalid) / Double(decoded.count) > limits.maxInvalidFraction {
            throw ImportError.tooManyInvalid(invalid: invalid, total: decoded.count)
        }
        workouts.sort { $0.date < $1.date }
        return ImportResult(workouts: workouts, issues: sanitizer.issues, skipped: skipped, skippedReasons: reasons, total: decoded.count)
    }

    // MARK: Mapping

    func map(_ dto: WorkoutDTO, path: String, sanitizer: inout Sanitizer, rng: inout SeededRandom, now: Date) -> PlannedWorkout? {
        guard let date = LocalDate(iso: dto.date), limits.dateRange.contains(date) else {
            sanitizer.issues.append(ImportIssue(path: path, message: "invalid date"))
            return nil
        }
        let flags = Set(dto.flags ?? [])
        // Done only if the athlete logged something; coach-programmed days
        // with no log become missed (programmed content kept).
        var status: WorkoutStatus = Self.hasAthleteLog(dto) ? .done : .skipped
        if flags.contains("athlete_reported_skip_or_sick") { status = .excused }

        var sections: [WorkoutSection] = []
        var seenKinds: Set<SectionKind> = []
        for (si, sdto) in (dto.sections ?? []).prefix(limits.maxSectionsPerWorkout).enumerated() {
            let sp = "\(path).sections[\(si)]"
            guard let kind = Self.kind(sdto.kind), !seenKinds.contains(kind) else { continue }
            seenKinds.insert(kind)
            sections.append(mapSection(sdto, kind: kind, path: sp, sanitizer: &sanitizer, rng: &rng,
                                       ignoreLogs: status == .planned || (sdto.athleteNoteDuplicate ?? false)))
        }
        guard !sections.isEmpty else {
            sanitizer.issues.append(ImportIssue(path: path, message: "no usable sections"))
            return nil
        }
        sections.sort { SectionKind.allCases.firstIndex(of: $0.kind)! < SectionKind.allCases.firstIndex(of: $1.kind)! }
        return PlannedWorkout(id: UUID.seeded(&rng), date: date, status: status, sections: sections, source: "import",
                              sync: SyncStamp(createdAt: now))
    }

    /// An athlete note (not a copy of last week's), logged weights or scores.
    static func hasAthleteLog(_ dto: WorkoutDTO) -> Bool {
        (dto.sections ?? []).contains { s in
            guard s.athleteNoteDuplicate != true else { return false }
            let note = s.athleteNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !note.isEmpty || !(s.loggedWeightsLb ?? []).isEmpty || !(s.loggedScores ?? []).isEmpty
        }
    }

    static func kind(_ raw: String?) -> SectionKind? {
        switch raw {
        case "warmup": return .warmup
        case "strength": return .strength
        case "metabolic": return .metabolic
        case "accessory", "cooldown": return .cooldown
        default: return nil
        }
    }

    static func format(_ f: FormatDTO?, kind: SectionKind) -> SectionFormat {
        let t = f?.type ?? ""
        switch kind {
        case .warmup: return .rounds
        case .strength:
            return t == "sets" ? .setsGoingUp : .everyNMin
        case .metabolic:
            switch t {
            case "amrap": return (f?.rounds ?? 1) > 1 ? .amrapWithRest : .amrap
            case "interval": return .interval
            case "for_time", "ladder": return .forTime
            case "every_n_min", "emom": return .emom
            case "tabata": return .tabata
            default: return .other
            }
        case .cooldown:
            return t == "emom" ? .emom : .sets
        }
    }

    func mapSection(_ s: SectionDTO, kind: SectionKind, path: String, sanitizer: inout Sanitizer, rng: inout SeededRandom,
                    ignoreLogs: Bool) -> WorkoutSection {
        let format = Self.format(s.format, kind: kind)
        var instructions = sanitizer.text(s.raw) ?? ""
        if let c = sanitizer.text(s.coachNote) { instructions += (instructions.isEmpty ? "" : "\n") + "Coach: " + c }
        instructions = String(instructions.prefix(limits.maxStringLength))
        let duration = s.format?.durationMin.flatMap { (0...240).contains($0) ? $0 : nil }
        var section = WorkoutSection(
            id: UUID.seeded(&rng), kind: kind, format: format, instructions: instructions,
            rounds: sanitizer.rounds(s.format?.rounds ?? s.format?.sets, path + ".rounds"),
            workSec: sanitizer.seconds(s.format?.workSec ?? (format == .amrapWithRest ? duration.map { $0 * 60 } : nil), path + ".work"),
            restSec: sanitizer.seconds(s.format?.restSec ?? s.format?.restBetweenRoundsSec, path + ".rest"),
            intervalSec: sanitizer.seconds(s.format?.intervalMin.map { $0 * 60 }, path + ".interval"),
            durationMin: format == .amrapWithRest ? nil : duration,
            lift: kind == .strength ? (s.items ?? []).first.flatMap { Lift(movementName: $0.movement ?? "") } : nil,
            athleteNote: (s.athleteNoteDuplicate ?? false) ? "" : (sanitizer.text(s.athleteNote) ?? ""))

        let letters = ["A", "B", "C", "D", "E", "F", "G", "H"]
        section.items = (s.items ?? []).prefix(limits.maxItemsPerSection).enumerated().compactMap { ii, it in
            let ip = "\(path).items[\(ii)]"
            guard let name = sanitizer.text(it.movement).map({ String($0.prefix(120)) }) else { return nil }
            return SectionItem(id: UUID.seeded(&rng), letter: sanitizer.text(it.letter).map { String($0.prefix(2)) } ?? letters[min(ii, letters.count - 1)],
                               movementID: MovementLibrary.slug(name), movementName: name,
                               reps: sanitizer.reps(it.reps, ip + ".reps"),
                               repsScheme: sanitizer.text(it.repsScheme).map { String($0.prefix(40)) },
                               timeSec: sanitizer.seconds(it.timeSec, ip + ".time"),
                               prescribedWeight: sanitizer.weight(it.weightLb, ip + ".weight"))
        }

        guard !ignoreLogs else { return section }

        // Strength: the athlete's set-by-set weights belong to item A.
        if kind == .strength, let weights = s.loggedWeightsLb, !weights.isEmpty, !section.items.isEmpty {
            if weights.count > limits.maxSetsPerItem || weights.contains(where: { !$0.isFinite || !limits.weightRange.contains($0) || $0 <= 0 }) {
                sanitizer.issues.append(ImportIssue(path: path + ".logged_weights_lb", message: "out-of-range weights, log dropped"))
            } else {
                // Ladders ("10-8-6-4-2") give each set its own reps.
                let scheme = (section.items[0].repsScheme ?? "").split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                    .filter { limits.repsRange.contains($0) && $0 > 0 }
                let reps = section.items[0].reps ?? 5
                section.items[0].setLogs = weights.enumerated().map { i, w in
                    SetLog(id: UUID.seeded(&rng), setNumber: i + 1, reps: scheme.isEmpty ? reps : scheme[min(i, scheme.count - 1)], weight: w)
                }
            }
        }

        // Metabolic: scores per round.
        if kind == .metabolic, let scores = s.loggedScores {
            var logs: [RoundLog] = []
            for (ri, raw) in scores.prefix(limits.maxRoundsPerSection).enumerated() {
                guard let log = Self.parseScore(raw, round: ri + 1, format: format, limits: limits, rng: &rng) else {
                    sanitizer.issues.append(ImportIssue(path: "\(path).logged_scores[\(ri)]", message: "unrecognized score, skipped"))
                    continue
                }
                logs.append(log)
            }
            section.roundLogs = logs
        }
        return section
    }

    /// "14:25" -> time, "5+2" -> rounds + reps, "10" -> rounds (AMRAP) or reps.
    static func parseScore(_ raw: String, round: Int, format: SectionFormat, limits: ImportLimits, rng: inout SeededRandom) -> RoundLog? {
        let s = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ";", with: ":")
        guard !s.isEmpty, s.count <= 20 else { return nil }
        let parts = s.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 2, let m = Int(parts[0]), let sec = Int(parts[1]), parts[1].count == 2, sec < 60, m >= 0 {
            let total = m * 60 + sec
            guard limits.secondsRange.contains(total) else { return nil }
            return RoundLog(id: UUID.seeded(&rng), roundNumber: round, timeSec: total)
        }
        let plus = s.split(separator: "+", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        if plus.count == 2, let r = Int(plus[0]), let x = Int(plus[1]) {
            guard limits.roundsRange.contains(r), limits.repsRange.contains(x) else { return nil }
            return RoundLog(id: UUID.seeded(&rng), roundNumber: round, rounds: r, reps: x)
        }
        if let n = Int(s) {
            if format == .amrap || format == .amrapWithRest {
                guard limits.roundsRange.contains(n) else { return nil }
                return RoundLog(id: UUID.seeded(&rng), roundNumber: round, rounds: n, reps: 0)
            }
            guard limits.repsRange.contains(n) else { return nil }
            return RoundLog(id: UUID.seeded(&rng), roundNumber: round, reps: n)
        }
        return nil
    }
}

// MARK: - DTOs (the history.json shape)

/// Decodes an element, capturing (not throwing) its error.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    let error: String?

    init(from decoder: Decoder) throws {
        do {
            value = try T(from: decoder)
            error = nil
        } catch let DecodingError.typeMismatch(_, ctx) {
            value = nil
            error = "wrong type at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
        } catch let DecodingError.keyNotFound(key, _) {
            value = nil
            error = "missing \(key.stringValue)"
        } catch _ {
            value = nil
            self.error = "invalid"
        }
    }
}

struct WorkoutDTO: Decodable {
    let date: String
    let sections: [SectionDTO]?
    let flags: [String]?
}

struct SectionDTO: Decodable {
    let kind: String?
    let raw: String?
    let coachNote: String?
    let athleteNote: String?
    let format: FormatDTO?
    let items: [ItemDTO]?
    let loggedWeightsLb: [Double]?
    let loggedScores: [String]?
    let athleteNoteDuplicate: Bool?

    enum CodingKeys: String, CodingKey {
        case kind, raw, format, items
        case coachNote = "coach_note"
        case athleteNote = "athlete_note"
        case loggedWeightsLb = "logged_weights_lb"
        case loggedScores = "logged_scores"
        case athleteNoteDuplicate = "athlete_note_duplicate_of_previous_week"
    }
}

struct FormatDTO: Decodable {
    let type: String?
    let rounds: Int?
    let sets: Int?
    let intervalMin: Int?
    let durationMin: Int?
    let restBetweenRoundsSec: Int?
    let workSec: Int?
    let restSec: Int?

    enum CodingKeys: String, CodingKey {
        case type, rounds, sets
        case intervalMin = "interval_min"
        case durationMin = "duration_min"
        case restBetweenRoundsSec = "rest_between_rounds_sec"
        case workSec = "work_sec"
        case restSec = "rest_sec"
    }
}

struct ItemDTO: Decodable {
    let letter: String?
    let movement: String?
    let reps: Int?
    let repsScheme: String?
    let timeSec: Int?
    let weightLb: Double?

    enum CodingKeys: String, CodingKey {
        case letter, movement, reps
        case repsScheme = "reps_scheme"
        case timeSec = "time_sec"
        case weightLb = "weight_lb"
    }
}
