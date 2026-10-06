import Foundation

/// Keeps each lift's training max current as blocks roll over.
///
/// - Before block 1: TM comes from history (or an earlier manual value).
/// - Block 1: TM = the initial test week's result (90% of the Epley e1RM of the
///   best logged test set). Untested lifts keep the history estimate.
/// - Block n >= 2: TM = min(previous TM + increment, week-13 test result).
public enum TrainingMaxBook {
    public static func programs(asOf date: LocalDate, current: [Lift: LiftProgram], history: [PlannedWorkout],
                                calendar: ProgramCalendar, barWeight: Double = 45) -> [Lift: LiftProgram] {
        let pos = calendar.position(on: date)
        let fallback = TrainingMax.resolve(programs: current.mapValues(\.trainingMax), history: history.filter { $0.date < date },
                                           barWeight: barWeight)
        var out: [Lift: LiftProgram] = [:]
        for lift in Lift.allCases {
            var program = current[lift] ?? LiftProgram(lift: lift, trainingMax: fallback[lift]!, source: .history)
            let startBlock = program.blockStartDate.map { calendar.position(on: $0).block } ?? 0
            if pos.block > startBlock {
                for b in (startBlock + 1)...pos.block {
                    let testRange = testWeekRange(beforeBlock: b, calendar: calendar)
                    let testTM = testResult(lift, in: history, range: testRange)
                    let tm: Double
                    if b == 1 {
                        tm = testTM ?? program.trainingMax
                    } else {
                        tm = TrainingMax.nextBlock(current: program.trainingMax, lift: lift, testResult: testTM)
                    }
                    program = LiftProgram(lift: lift, trainingMax: tm, blockStartDate: calendar.startOfBlock(b), blockWeek: 1,
                                          phase: .volume, source: b == 1 && testTM != nil ? .test : (b == 1 ? program.source : .progression))
                }
            }
            if pos.block >= 1 {
                program.blockWeek = pos.week
                program.phase = pos.phase
            }
            out[lift] = program
        }
        return out
    }

    /// The test week that precedes block `b` (initial test week for block 1).
    public static func testWeekRange(beforeBlock b: Int, calendar: ProgramCalendar) -> ClosedRange<LocalDate> {
        let start = b <= 1 ? calendar.testWeekStart : calendar.startOfWeek(block: b - 1, week: 13)
        return start...start.adding(days: 6)
    }

    static func testResult(_ lift: Lift, in history: [PlannedWorkout], range: ClosedRange<LocalDate>) -> Double? {
        let sets = history.filter { range.contains($0.date) && $0.status == .done && !$0.isDeleted }
            .compactMap(\.strengthSection)
            .flatMap(\.items)
            .filter { Lift(movementName: $0.movementName) == lift || $0.movementID == lift.movementID }
            .flatMap(\.setLogs)
        return TrainingMax.fromSets(sets)
    }
}

public enum MissedDays {
    /// Scheduled dates in [from, to] with no workout record. The app stores
    /// them as past "planned" workouts so the streak counts real misses.
    public static func backfill(schedule: [Weekday], from: LocalDate, to: LocalDate, existing: [PlannedWorkout]) -> [LocalDate] {
        guard from <= to, from.days(until: to) <= 400 else { return [] }
        let have = Set(existing.filter { !$0.isDeleted }.map(\.date))
        let days = Set(schedule)
        var out: [LocalDate] = []
        var d = from
        while d <= to {
            if days.contains(d.weekday) && !have.contains(d) { out.append(d) }
            d = d.adding(days: 1)
        }
        return out
    }
}
