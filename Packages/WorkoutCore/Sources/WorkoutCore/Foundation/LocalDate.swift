import Foundation

/// A calendar date with no time or time zone ("2026-10-12").
///
/// Workouts are planned per day, so the engine works on plain civil dates.
/// All arithmetic is done on a day count (days since 1970-01-01), which keeps
/// the planner deterministic and free of time-zone / DST surprises.
public struct LocalDate: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Creates a date, returning nil for impossible dates (e.g. Feb 30).
    public init?(year: Int, month: Int, day: Int) {
        guard (1900...2200).contains(year), (1...12).contains(month),
              (1...LocalDate.daysInMonth(year: year, month: month)).contains(day) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Unchecked initializer for literals known to be valid.
    public init(_ year: Int, _ month: Int, _ day: Int) {
        guard let d = LocalDate(year: year, month: month, day: day) else {
            preconditionFailure("Invalid LocalDate \(year)-\(month)-\(day)")
        }
        self = d
    }

    /// Parses `YYYY-MM-DD` strictly.
    public init?(iso: String) {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard iso.count == 10, parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public init(daysSinceEpoch z: Int) {
        // Howard Hinnant's civil_from_days.
        let z = z + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        self.year = m <= 2 ? y + 1 : y
        self.month = m
        self.day = d
    }

    /// Today's date in the given calendar/time zone.
    public static func today(_ now: Date = Date(), calendar: Calendar = .current) -> LocalDate {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return LocalDate(c.year ?? 2000, c.month ?? 1, c.day ?? 1)
    }

    public var daysSinceEpoch: Int {
        // Howard Hinnant's days_from_civil.
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = month > 2 ? month - 3 : month + 9
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    public func adding(days: Int) -> LocalDate { LocalDate(daysSinceEpoch: daysSinceEpoch + days) }
    public func days(until other: LocalDate) -> Int { other.daysSinceEpoch - daysSinceEpoch }

    public var weekday: Weekday {
        // 1970-01-01 was a Thursday.
        let idx = ((daysSinceEpoch % 7) + 7 + 3) % 7 // 0 = Monday
        return Weekday.allCases[idx]
    }

    /// The Monday on or before this date.
    public var startOfWeek: LocalDate { adding(days: -weekday.mondayIndex) }

    public var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public var description: String { iso }

    public static func < (a: LocalDate, b: LocalDate) -> Bool { a.daysSinceEpoch < b.daysSinceEpoch }

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let d = LocalDate(iso: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid date"))
        }
        self = d
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(iso)
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    private static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private static let longMonthNames = ["January", "February", "March", "April", "May", "June", "July",
                                         "August", "September", "October", "November", "December"]
    public var shortMonthName: String { LocalDate.monthNames[month - 1] }

    /// First day of this date's month.
    public var startOfMonth: LocalDate { LocalDate(year, month, 1) }

    /// Same day `n` months later (clamped to the month's length).
    public func adding(months n: Int) -> LocalDate {
        let total = year * 12 + (month - 1) + n
        let y = total / 12, m = total % 12 + 1
        return LocalDate(y, m, min(day, LocalDate.daysInMonth(year: y, month: m)))
    }

    /// 1...366
    public var dayOfYear: Int { LocalDate(year, 1, 1).days(until: self) + 1 }
    public var longMonthName: String { LocalDate.longMonthNames[month - 1] }
    /// "Mon, Oct 5"
    public var shortDisplay: String { "\(weekday.shortName), \(shortMonthName) \(day)" }
}

public enum Weekday: String, CaseIterable, Codable, Sendable, Comparable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday

    public var mondayIndex: Int { Weekday.allCases.firstIndex(of: self)! }
    public var shortName: String { String(rawValue.prefix(3)).capitalized }
    public static func < (a: Weekday, b: Weekday) -> Bool { a.mondayIndex < b.mondayIndex }
}
