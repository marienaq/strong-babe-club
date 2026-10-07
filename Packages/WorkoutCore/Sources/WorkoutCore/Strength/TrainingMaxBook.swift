import Foundation

/// Keeps each lift's training max current as blocks roll over.
///
/// - Before block 1: TM comes from history (or an earlier manual value).
/// - Block 1: TM = the initial test week's result (90% of the Epley e1RM of the
///   best logged test set). Untested lifts keep the history estimate.
/// - Block n >= 2: TM = min(previous TM + increment, week-13 test result).
public enum TrainingMaxBook {
    /// Training maxes as of `date`.
    ///
    /// - Before and at the start of block 1: 90% of the best e1RM over the
    ///   28 days before block 1 (or before `date`, if earlier), recomputed as
    ///   new logs arrive. Lifts without a recent log come from a related lift
    ///   and are "calibrating" until their first rated session.
    /// - If an initial test period ran, its heavy triples win.
    /// - Block n >= 2: min(previous TM + increment, the weeks 13-14 test).
    /// Manual, test and progression values are kept as they are.
    public static func programs(asOf date: LocalDate, current: [Lift: LiftProgram], history: [PlannedWorkout],
                                calendar: ProgramCalendar, barWeight: Double = 45) -> [Lift: LiftProgram] {
        let pos = calendar.position(on: date)
        let estimateDate = min(date, calendar.block1Start)
        let fixed = current.filter { $0.value.source != .history && $0.value.source != .calibrating }
        var out: [Lift: LiftProgram] = [:]
        for lift in Lift.allCases {
            var program: LiftProgram
            if let f = fixed[lift] {
                program = f
            } else if let e = TrainingMax.estimate(lift, history: history.filter { $0.date < estimateDate }, asOf: estimateDate) {
                program = LiftProgram(lift: lift, trainingMax: e.trainingMax, source: e.calibrating ? .calibrating : .history)
            } else {
                program = LiftProgram(lift: lift, trainingMax: max(barWeight, 45) + 20, source: .calibrating)
            }
            let startBlock = program.blockStartDate.map { calendar.position(on: $0).block } ?? 0
            if pos.block > startBlock {
                for b in (startBlock + 1)...pos.block {
                    let testTM = testWeekRange(beforeBlock: b, calendar: calendar).flatMap { testResult(lift, in: history, range: $0) }
                    let tm: Double
                    var source = program.source
                    if b == 1 {
                        tm = testTM ?? program.trainingMax
                        if testTM != nil { source = .test }
                    } else {
                        tm = TrainingMax.nextBlock(current: program.trainingMax, lift: lift, testResult: testTM)
                        source = .progression
                    }
                    program = LiftProgram(lift: lift, trainingMax: tm, blockStartDate: calendar.startOfBlock(b), blockWeek: 1,
                                          phase: .volume, source: source)
                }
            }
            // A calibrating lift settles after its first rated session in block 1.
            if program.source == .calibrating, pos.block >= 1 {
                let c = TrainingMax.calibrated(program.trainingMax, lift: lift, history: history, from: calendar.block1Start)
                if c.adjusted {
                    program.trainingMax = c.tm
                    program.source = .progression
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

    /// The test period before block `b`: the initial test weeks for block 1
    /// (nil when block 1 starts without one), weeks 13-14 of block b-1 otherwise.
    public static func testWeekRange(beforeBlock b: Int, calendar: ProgramCalendar) -> ClosedRange<LocalDate>? {
        if b <= 1 {
            guard calendar.initialTestWeeks > 0 else { return nil }
            return calendar.testWeekStart...calendar.block1Start.adding(days: -1)
        }
        let start = calendar.startOfWeek(block: b - 1, week: 13)
        return start...start.adding(days: 7 * ProgramCalendar.testWeeks - 1)
    }

    static func testResult(_ lift: Lift, in history: [PlannedWorkout], range: ClosedRange<LocalDate>) -> Double? {
        let sets = history.filter { range.contains($0.date) && $0.status == .done && !$0.isDeleted }
            .compactMap(\.strengthSection)
            .flatMap(\.items)
            .filter { Lift(movementName: $0.movementName) == lift || $0.movementID == lift.movementID }
            .flatMap(\.setLogs)
        return sets.map { TrainingMax.epley(weight: $0.weight, reps: $0.reps) }.max().map(TrainingMax.fromE1RM)
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
