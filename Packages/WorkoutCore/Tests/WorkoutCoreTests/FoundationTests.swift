import XCTest
@testable import WorkoutCore

final class LocalDateTests: XCTestCase {
    func testParsesAndFormatsISO() throws {
        let d = try XCTUnwrap(LocalDate(iso: "2026-10-12"))
        XCTAssertEqual(d.year, 2026)
        XCTAssertEqual(d.month, 10)
        XCTAssertEqual(d.day, 12)
        XCTAssertEqual(d.iso, "2026-10-12")
    }

    func testRejectsInvalidDates() {
        XCTAssertNil(LocalDate(iso: "2025-02-30"))
        XCTAssertNil(LocalDate(iso: "2025-13-01"))
        XCTAssertNil(LocalDate(iso: "2025-1-01"))
        XCTAssertNil(LocalDate(iso: "20250101"))
        XCTAssertNil(LocalDate(iso: "abcd-ef-gh"))
        XCTAssertNil(LocalDate(iso: ""))
        XCTAssertNotNil(LocalDate(iso: "2024-02-29"))
        XCTAssertNil(LocalDate(iso: "2025-02-29"))
        XCTAssertNil(LocalDate(year: 3000, month: 1, day: 1))
    }

    func testWeekdays() {
        XCTAssertEqual(LocalDate(2026, 10, 12).weekday, .monday)
        XCTAssertEqual(LocalDate(2026, 10, 16).weekday, .friday)
        XCTAssertEqual(LocalDate(2027, 1, 11).weekday, .monday)
        XCTAssertEqual(LocalDate(1970, 1, 1).weekday, .thursday)
        XCTAssertEqual(LocalDate(2024, 2, 29).weekday, .thursday)
    }

    func testArithmeticRoundTrips() {
        let d = LocalDate(2026, 10, 19)
        XCTAssertEqual(d.adding(days: 84), LocalDate(2027, 1, 11))
        XCTAssertEqual(d.adding(days: -19), LocalDate(2026, 9, 30))
        XCTAssertEqual(d.days(until: LocalDate(2027, 1, 8)), 81)
        for offset in stride(from: -25_000, through: 60_000, by: 997) { // 1901...2134
            let x = LocalDate(daysSinceEpoch: offset)
            XCTAssertEqual(x.daysSinceEpoch, offset)
            XCTAssertEqual(LocalDate(iso: x.iso), x)
        }
    }

    func testStartOfWeekIsMonday() {
        XCTAssertEqual(LocalDate(2026, 10, 18).startOfWeek, LocalDate(2026, 10, 12))
        XCTAssertEqual(LocalDate(2026, 10, 12).startOfWeek, LocalDate(2026, 10, 12))
    }

    func testCodableUsesISOString() throws {
        let data = try JSONEncoder().encode([LocalDate(2026, 1, 2)])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "[\"2026-01-02\"]")
        XCTAssertEqual(try JSONDecoder().decode([LocalDate].self, from: data), [LocalDate(2026, 1, 2)])
        XCTAssertThrowsError(try JSONDecoder().decode([LocalDate].self, from: Data("[\"2026-02-31\"]".utf8)))
    }

    func testShortDisplay() {
        XCTAssertEqual(LocalDate(2026, 10, 5).shortDisplay, "Mon, Oct 5")
    }
}

final class SeededRandomTests: XCTestCase {
    func testSameSeedSameSequence() {
        var a = SeededRandom(seed: 42), b = SeededRandom(seed: 42)
        for _ in 0..<100 { XCTAssertEqual(a.next(), b.next()) }
    }

    func testDifferentSeedsDiffer() {
        var a = SeededRandom(seed: 1), b = SeededRandom(seed: 2)
        XCTAssertNotEqual((0..<5).map { _ in a.next() }, (0..<5).map { _ in b.next() })
    }

    func testDateSeedsAreStable() {
        var a = SeededRandom(date: LocalDate(2026, 10, 19), salt: 3)
        var b = SeededRandom(date: LocalDate(2026, 10, 19), salt: 3)
        var c = SeededRandom(date: LocalDate(2026, 10, 19), salt: 4)
        let x = a.next()
        XCTAssertEqual(x, b.next())
        XCTAssertNotEqual(x, c.next())
    }

    func testWeightedPickNeverPicksZeroWeight() {
        var rng = SeededRandom(seed: 9)
        for _ in 0..<200 {
            let v = [1, 2, 3].weightedPick(using: &rng) { $0 == 2 ? 0 : 1 }
            XCTAssertNotEqual(v, 2)
        }
        XCTAssertNil([1, 2].weightedPick(using: &rng) { _ in 0 })
        XCTAssertNil([Int]().weightedPick(using: &rng) { _ in 1 })
    }

    func testSeededShufflePermutes() {
        var rng = SeededRandom(seed: 5)
        let s = Array(0..<20).seededShuffled(using: &rng)
        XCTAssertEqual(s.sorted(), Array(0..<20))
    }

    func testSeededUUIDIsDeterministicV4() {
        var a = SeededRandom(seed: 7), b = SeededRandom(seed: 7)
        let u = UUID.seeded(&a)
        XCTAssertEqual(u, UUID.seeded(&b))
        let s = u.uuidString
        XCTAssertEqual(Array(s)[14], "4")
    }

    func testRoundingAndFormatting() {
        XCTAssertEqual(157.5.rounded(toNearest: 5), 160)
        XCTAssertEqual(156.0.rounded(toNearest: 5), 155)
        XCTAssertEqual(formatPounds(102.5), "102.5")
        XCTAssertEqual(formatPounds(105), "105")
    }
}
