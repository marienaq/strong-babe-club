import Foundation
import XCTest
@testable import WorkoutCore

/// Catalog, duration math, timer, importer and stored data (spec §5, §18).
final class MetconFormatTests: XCTestCase {
    func items(_ n: Int) -> [SectionItem] {
        (0..<n).map { SectionItem(letter: ["A", "B", "C", "D", "E"][$0], movementID: "m\($0)", movementName: "M\($0)") }
    }

    /// Seconds and band of every catalog shape (30/30 for intervals; Tabata per owner decision Q2).
    static let expected: [String: (Int, MetconBand)] = [
        "amrap-12": (720, .short), "amrap-14": (840, .short), "amrap-15": (900, .short), "amrap-16": (960, .short),
        "amrap-18": (1080, .middle), "amrap-20": (1200, .middle),
        "emom-3x4": (720, .short), "emom-4x3": (720, .short), "emom-3x5": (900, .short), "emom-5x3": (900, .short),
        "emom-4x4": (960, .short), "emom-3x6": (1080, .middle), "emom-4x5": (1200, .middle), "emom-5x4": (1200, .middle),
        "rest-3x4": (840, .short), "rest-4x3": (900, .short), "rest-3x5": (1020, .middle), "rest-5x3": (1140, .middle),
        "rest-4x4": (1140, .middle), "rest-8x2": (1170, .middle), "rest-3x6": (1200, .middle), "rest-6x3": (1380, .long),
        "rest-4x5": (1380, .long), "rest-5x4": (1440, .long),
        "stations-3x4": (840, .short), "stations-4x3": (900, .short), "stations-3x5": (1020, .middle), "stations-5x3": (1140, .middle),
        "stations-4x4": (1140, .middle), "stations-6x3": (1380, .long), "stations-4x5": (1380, .long), "stations-5x4": (1440, .long),
        "interval-3x5-30-30": (870, .short), "interval-5x3-30-30": (870, .short), "interval-4x4-30-30": (930, .short),
        "interval-3x6-30-30": (1050, .middle), "interval-4x5-30-30": (1170, .middle), "interval-5x4-30-30": (1170, .middle),
        "interval-3x7-30-30": (1230, .middle), "interval-4x6-30-30": (1410, .long), "interval-3x8-30-30": (1410, .long),
        "tabata-3x5": (880, .short), "tabata-4x4": (940, .short), "tabata-3x6": (1060, .middle), "tabata-4x5": (1180, .middle),
        "tabata-5x4": (1180, .middle), "tabata-3x7": (1240, .middle), "tabata-4x6": (1420, .long),
    ]

    /// MC-6: every shape is 12-24 min with 3-5 moves, in its listed band.
    func testCatalogValidity() {
        for shape in MetconCatalog.shapes where shape.format != .forTime {
            XCTAssertTrue(shape.moveCounts.allSatisfy((3...5).contains), shape.id)
            for n in shape.moveCounts {
                let secs = shape.seconds(moves: n)!
                XCTAssertTrue((720...1440).contains(secs), "\(shape.id) \(n): \(secs)")
            }
            let n = shape.moves ?? 3
            if let (secs, band) = Self.expected[shape.id] {
                XCTAssertEqual(shape.seconds(moves: n), secs, shape.id)
                XCTAssertEqual(MetconBand.of(seconds: secs), band, shape.id)
            } else {
                // 40/20 intervals are 10 s longer than 30/30 and stay in the same band.
                let twin = Self.expected[shape.id.replacingOccurrences(of: "-40-20", with: "-30-30")]
                XCTAssertNotNil(twin, shape.id)
                XCTAssertEqual(MetconBand.of(seconds: shape.seconds(moves: n)!), twin?.1, shape.id)
            }
        }
        XCTAssertEqual(MetconCatalog.shapes(.forTime).map(\.id), ["ft-21-15-9", "ft-15-3", "ft-10-2", "ft-10-1", "ft-1-10", "ft-21-3"])
        XCTAssertEqual(MetconCatalog.formatWeights.values.reduce(0, +), 100)
    }

    /// MC-7 (catalog) and owner decision Q2: Tabata is 40/20, one move at a time, 3 × 6 = 18 min.
    func testTabataIsFortyTwenty() {
        for shape in MetconCatalog.shapes(.tabata) {
            XCTAssertEqual(shape.workSec, 40)
            XCTAssertEqual(shape.restSec, 20)
            XCTAssertEqual(shape.roundRestSec, 0)
            XCTAssertEqual(shape.seconds(moves: shape.moves!), shape.moves! * shape.rounds * 60 - 20)
        }
        var s = MetconCatalog.shapes.first { $0.id == "tabata-3x6" }!.section()
        s.items = items(3)
        XCTAssertEqual(WorkoutDuration.estimate(s), 18)
        XCTAssertFalse(MetconCatalog.shapes.contains { $0.id == "tabata-3x4" }, "3 × 4 is under 12 min")
    }

    /// MC-8: the timer equals the estimate; work periods per §5.4.
    func testTimerEqualsEstimate() {
        for shape in MetconCatalog.shapes {
            let counts = shape.format == .forTime ? [3] : shape.moveCounts
            let caps = shape.format == .forTime ? Array(MetconCatalog.forTimeCaps) : [0]
            for n in counts {
                for cap in caps {
                    var s = shape.section(capMinutes: cap)
                    s.items = items(n)
                    let plan = IntervalPlan.forSection(s)!
                    XCTAssertEqual(plan.totalDuration, WorkoutDuration.estimateSeconds(s), "\(shape.id) \(n)")
                    let work = plan.phases.filter { $0.kind == .work }.count
                    let r = s.rounds ?? 1
                    switch s.format {
                    case .amrap, .forTime: XCTAssertEqual(work, 1)
                    case .emom: XCTAssertEqual(work, s.durationMin)
                    case .amrapWithRest: XCTAssertEqual(work, r)
                    case .stations, .interval, .tabata: XCTAssertEqual(work, r * n, shape.id)
                    default: XCTFail("\(s.format)")
                    }
                    let rows: Int
                    switch s.format {
                    case .tabata: rows = r * n
                    case .forTime, .amrap: rows = 1
                    case .emom: rows = s.durationMin ?? 0
                    default: rows = r
                    }
                    XCTAssertEqual(s.prescribedRounds, rows, shape.id)
                }
            }
        }
    }

    /// MC-9 / R5: interval rounds are full circuits.
    func testIntervalRoundsAreCircuits() {
        let s = WorkoutSection(kind: .metabolic, format: .interval, instructions: "", rounds: 6, workSec: 40, restSec: 20, items: items(3))
        XCTAssertEqual(WorkoutDuration.estimateSeconds(s), 1060)
        XCTAssertEqual(WorkoutDuration.estimate(s), 18)
        let plan = IntervalPlan.forSection(s)!
        XCTAssertEqual(plan.totalDuration, 1060)
        XCTAssertEqual(plan.phases.filter { $0.kind == .work }.count, 18)
    }

    static let stationsJSON = """
    [{"date": "2025-03-03", "sections": [
      {"kind": "metabolic", "raw": "4 rounds of stations", "format": {"type": "interval", "rounds": 4, "work_sec": 60, "per_station": true,
       "rest_between_rounds_sec": 60}, "items": [{"letter": "A", "movement": "KB Swing"}, {"letter": "B", "movement": "Push Up"},
       {"letter": "C", "movement": "Air Squat"}, {"letter": "D", "movement": "Sit Up"}], "logged_scores": ["40", "42"]},
      {"kind": "strength", "format": {"type": "every_n_min", "interval_min": 2}, "items": [{"movement": "Back Squat", "reps": 5}],
       "logged_weights_lb": [95, 105]}]},
     {"date": "2025-03-05", "sections": [
      {"kind": "metabolic", "raw": "6 rounds 40/20", "format": {"type": "interval", "rounds": 6, "work_sec": 40, "rest_sec": 20},
       "items": [{"movement": "Burpee"}, {"movement": "Lunge"}, {"movement": "Push Up"}], "logged_scores": ["20"]}]}]
    """

    /// MC-10 / R5 / R6: the importer keeps stations; circuits are timed as circuits.
    func testImporterKeepsStationsAndCircuits() throws {
        let r = try HistoryImporter().importCoachHistory(Data(Self.stationsJSON.utf8), now: TestData.now)
        let st = try XCTUnwrap(r.workouts[0].metabolicSection)
        XCTAssertEqual(st.format, .stations)
        XCTAssertEqual(st.workSec, 60)
        XCTAssertEqual(st.restSec, 0)
        XCTAssertEqual(st.roundRestSec, 60)
        XCTAssertEqual(st.stimulus, .repeat)
        XCTAssertEqual(st.estimatedSeconds, 1140)
        XCTAssertEqual(WorkoutDuration.estimate(st), 19)
        XCTAssertEqual(IntervalPlan.forSection(st)?.totalDuration, 1140)
        XCTAssertEqual(st.prescribedRounds, 4)
        let iv = try XCTUnwrap(r.workouts[1].metabolicSection)
        XCTAssertEqual(iv.format, .interval)
        XCTAssertEqual(WorkoutDuration.estimate(iv), 18)
        XCTAssertEqual(IntervalPlan.forSection(iv)?.totalDuration, 1060)
        XCTAssertEqual(IntervalPlan.forSection(iv)?.phases.filter { $0.kind == .work }.count, 18)
    }

    /// MC-11: stations stored earlier as 60/60 intervals are read as stations; nothing else changes.
    func testLegacyStationsMigration() {
        let legacy = WorkoutSection(kind: .metabolic, format: .interval, instructions: "coach text", rounds: 4, workSec: 60, restSec: 60, items: items(4))
        let w = PlannedWorkout(date: LocalDate(2025, 3, 3), status: .done, sections: [legacy], source: "import")
        let migrated = try! XCTUnwrap(SectionMigration.migrate(w))
        let s = migrated.metabolicSection!
        XCTAssertEqual(s.format, .stations)
        XCTAssertEqual(s.roundRestSec, 60)
        XCTAssertEqual(s.estimatedSeconds, 1140)
        XCTAssertEqual(s.instructions, "coach text")
        XCTAssertEqual(s.items, legacy.items)
        // Not imported, or a real circuit: untouched.
        var planned = w
        planned.source = "rules-v1"
        XCTAssertNil(SectionMigration.migrate(planned))
        var circuit = w
        circuit.sections[0].workSec = 40
        circuit.sections[0].restSec = 20
        XCTAssertNil(SectionMigration.migrate(circuit))
    }

    /// MC-12: sections, benchmarks and settings saved before v2 still decode;
    /// the new fields round-trip.
    func testStoredDataDecodesAndRoundTrips() throws {
        let old = """
        {"id": "2C3B0A3A-1B0D-4E4C-9B0B-0E7E1B5C0A11", "kind": "metabolic", "format": "tabata", "name": "tabata-8-8-fig",
         "instructions": "old", "rounds": 8, "workSec": 20, "restSec": 10, "isModified": false, "athleteNote": "", "items": [], "roundLogs": []}
        """
        let s = try JSONDecoder().decode(WorkoutSection.self, from: Data(old.utf8))
        XCTAssertNil(s.roundRestSec)
        XCTAssertNil(s.stimulus)
        XCTAssertNil(s.expectedScore)
        XCTAssertEqual(s.rounds, 8)

        var new = s
        new.format = .stations
        new.roundRestSec = 60
        new.stimulus = .repeat
        new.expectedScore = 4.25
        XCTAssertEqual(try JSONDecoder().decode(WorkoutSection.self, from: JSONEncoder().encode(new)), new)

        let oldBenchmark = """
        {"id": "2C3B0A3A-1B0D-4E4C-9B0B-0E7E1B5C0A12", "name": "tabata-8-8-fig", "active": true, "quarterSlot": 2, "template": \(old)}
        """
        let b = try JSONDecoder().decode(Benchmark.self, from: Data(oldBenchmark.utf8))
        XCTAssertNil(b.retiredReason)
        XCTAssertNil(b.replacesID)
        XCTAssertFalse(b.isRetired)

        let settings = try JSONDecoder().decode(PlannerSettings.self, from: Data("{\"targetMinutes\": 45}".utf8))
        XCTAssertTrue(settings.autoReplaceRetiredBenchmarks)
    }

    /// MC-56, MC-57: work density and rest rules hold for every shape.
    func testDensityAndRestRules() {
        for shape in MetconCatalog.shapes where shape.format != .forTime {
            for n in shape.moveCounts {
                var s = shape.section()
                s.items = items(n)
                let d = MetconCatalog.density(s)
                switch shape.format {
                case .amrapWithRest, .stations: XCTAssertTrue((0.67...0.90).contains(d), "\(shape.id) \(d)")
                case .interval, .tabata: XCTAssertTrue((0.50...0.75).contains(d), "\(shape.id) \(d)")
                case .amrap: XCTAssertLessThanOrEqual(shape.minutes!, 20)
                default: break
                }
                if shape.format == .amrapWithRest {
                    XCTAssertGreaterThanOrEqual(shape.restSec!, shape.workSec! >= 180 ? 60 : 30, shape.id)
                }
                if shape.format == .stations { XCTAssertGreaterThanOrEqual(shape.roundRestSec!, 60, shape.id) }
            }
        }
    }

    /// §7.6 copy and §11.6 name numbers.
    func testInstructionsAndNames() {
        func section(_ id: String, _ n: Int) -> WorkoutSection {
            var s = MetconCatalog.shapes.first { $0.id == id }!.section(capMinutes: 16)
            s.items = items(n)
            return s
        }
        XCTAssertEqual(MetconCatalog.instructions(section("rest-5x3", 3)), "5 rounds · as many as you can in 3 min · rest 1 min")
        XCTAssertEqual(MetconCatalog.instructions(section("rest-8x2", 3)), "8 rounds · as many as you can in 2 min · rest 30 s")
        XCTAssertEqual(MetconCatalog.instructions(section("stations-4x4", 4)),
                       "4 rounds · 60 s at each station, no rest between stations · rest 1 min after each round")
        XCTAssertEqual(MetconCatalog.instructions(section("amrap-15", 4), deload: true), "As many rounds as you can in 15 min\nEasy, steady pace.")
        XCTAssertEqual(MetconCatalog.instructions(section("ft-10-1", 4), scheme: "10-9-8-7-6-5-4-3-2-1"),
                       "10-9-8-7-6-5-4-3-2-1 for time · cap 16 min")
        XCTAssertTrue(MetconCatalog.nameNumbers(section("rest-5x3", 3)) == (5, 3))
        XCTAssertTrue(MetconCatalog.nameNumbers(section("stations-4x4", 4)) == (4, 19))
        XCTAssertTrue(MetconCatalog.nameNumbers(section("tabata-3x6", 3)) == (6, 18))
        XCTAssertTrue(MetconCatalog.nameNumbers(section("emom-3x5", 3)) == (15, 15))
        XCTAssertTrue(MetconCatalog.nameNumbers(section("amrap-15", 3)) == (1, 15))
        XCTAssertTrue(MetconCatalog.nameNumbers(section("ft-10-1", 3)) == (1, 16))
        XCTAssertEqual(SectionFormat.stations.nameStructure, "stations")
    }
}
