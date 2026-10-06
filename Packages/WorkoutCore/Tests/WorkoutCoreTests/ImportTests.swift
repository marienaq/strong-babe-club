import XCTest
@testable import WorkoutCore

final class HistoryImporterTests: XCTestCase {
    let importer = HistoryImporter()

    func importFixture() throws -> ImportResult {
        try importer.importCoachHistory(try TestData.fixture("sample_history.json"), now: TestData.now)
    }

    func testFixtureImport() throws {
        let r = try importFixture()
        XCTAssertEqual(r.workouts.count, 5)
        XCTAssertEqual(r.skipped, 2) // invalid date + wrong type
        XCTAssertEqual(r.workouts.map(\.date.iso), ["2025-03-03", "2025-03-05", "2025-03-07", "2025-03-10", "2025-03-12"])
        XCTAssertEqual(r.workouts.map(\.status), [.done, .done, .excused, .done, .done])
        XCTAssertTrue(r.issues.contains { $0.message.contains("future-dated") })
        XCTAssertTrue(r.workouts.allSatisfy { $0.source == "import" })
    }

    func testSectionsAndFormats() throws {
        let w = try importFixture().workouts[0]
        XCTAssertEqual(w.sections.map(\.kind), [.warmup, .strength, .metabolic, .cooldown])
        XCTAssertEqual(w.metabolicSection?.format, .amrapWithRest)
        XCTAssertEqual(w.metabolicSection?.workSec, 180)
        XCTAssertEqual(w.metabolicSection?.restSec, 60)
        XCTAssertEqual(w.metabolicSection?.items.first?.movementID, "kb-swing")
        XCTAssertEqual(w.metabolicSection?.items.first?.prescribedWeight, 26)
        XCTAssertEqual(w.strengthSection?.lift, .backSquat)
        XCTAssertEqual(w.strengthSection?.intervalSec, 120)
        XCTAssertTrue(w.metabolicSection?.instructions.contains("Coach: A = 26lb") ?? false)
        XCTAssertEqual(w.section(.cooldown)?.items.first?.repsScheme, "15-15-15")
    }

    func testStrengthLogsBecomeSets() throws {
        let w = try importFixture().workouts[0]
        let logs = try XCTUnwrap(w.strengthSection?.items.first?.setLogs)
        XCTAssertEqual(logs.map(\.weight), [50, 60, 70, 80, 90])
        XCTAssertEqual(Set(logs.map(\.reps)), [5])
        XCTAssertEqual(TrainingMax.fromHistory(.backSquat, workouts: try importFixture().workouts), TrainingMax.fromSet(weight: 90, reps: 5))
    }

    func testOutOfRangeLogIsDropped() throws {
        let r = try importFixture()
        let fs = r.workouts[3]
        XCTAssertEqual(fs.strengthSection?.items.first?.setLogs, [])
        XCTAssertTrue(r.issues.contains { $0.path.contains("logged_weights_lb") })
    }

    func testScoresParsed() throws {
        let r = try importFixture()
        XCTAssertEqual(MetabolicScore.from(r.workouts[0].metabolicSection!.roundLogs, format: .amrapWithRest), .roundsReps(rounds: 12, reps: 7))
        XCTAssertEqual(r.workouts[1].metabolicSection?.roundLogs.first?.timeSec, 12 * 60 + 41)
        // "7" -> 7 rounds; "15.3" is ambiguous and skipped.
        XCTAssertEqual(r.workouts[3].metabolicSection?.roundLogs.count, 1)
        XCTAssertEqual(r.workouts[3].metabolicSection?.roundLogs.first?.rounds, 7)
        XCTAssertTrue(r.issues.contains { $0.message.contains("unrecognized score") })
    }

    func testParseScoreVariants() {
        var rng = SeededRandom(seed: 1)
        let l = ImportLimits.standard
        XCTAssertEqual(HistoryImporter.parseScore("21;07", round: 1, format: .forTime, limits: l, rng: &rng)?.timeSec, 1267)
        XCTAssertEqual(HistoryImporter.parseScore("4 + 7", round: 1, format: .amrap, limits: l, rng: &rng)?.reps, 7)
        XCTAssertEqual(HistoryImporter.parseScore("30", round: 1, format: .interval, limits: l, rng: &rng)?.reps, 30)
        XCTAssertNil(HistoryImporter.parseScore("157146186", round: 1, format: .interval, limits: l, rng: &rng))
        XCTAssertNil(HistoryImporter.parseScore("12:99", round: 1, format: .forTime, limits: l, rng: &rng))
        XCTAssertNil(HistoryImporter.parseScore("-3", round: 1, format: .interval, limits: l, rng: &rng))
        XCTAssertNil(HistoryImporter.parseScore("", round: 1, format: .interval, limits: l, rng: &rng))
        XCTAssertNil(HistoryImporter.parseScore("felt great", round: 1, format: .interval, limits: l, rng: &rng))
        XCTAssertNil(HistoryImporter.parseScore(String(repeating: "9", count: 50), round: 1, format: .interval, limits: l, rng: &rng))
    }

    func testDuplicateNoteIgnored() throws {
        let json = """
        [{"date": "2025-01-06", "sections": [{"kind": "strength", "athlete_note": "copied", "athlete_note_duplicate_of_previous_week": true,
          "items": [{"letter": "A", "reps": 5, "movement": "Deadlift"}], "logged_weights_lb": [100, 120]}]}]
        """
        let w = try importer.importCoachHistory(Data(json.utf8)).workouts[0]
        XCTAssertEqual(w.strengthSection?.athleteNote, "")
        XCTAssertEqual(w.strengthSection?.items.first?.setLogs, [])
    }

    // MARK: Malformed input

    func testRejectsEmptyAndNonJSON() {
        XCTAssertThrowsError(try importer.importCoachHistory(Data())) { XCTAssertEqual($0 as? ImportError, .empty) }
        XCTAssertThrowsError(try importer.importCoachHistory(Data("not json {".utf8))) { XCTAssertEqual($0 as? ImportError, .notJSON) }
        XCTAssertThrowsError(try importer.importCoachHistory(Data([0xFF, 0xFE, 0x00]))) { XCTAssertEqual($0 as? ImportError, .notJSON) }
    }

    func testRejectsWrongTopLevelShape() {
        XCTAssertThrowsError(try importer.importCoachHistory(Data("{\"date\": \"2025-01-01\"}".utf8))) { error in
            guard case .wrongShape = error as? ImportError else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try importer.importCoachHistory(Data("42".utf8)))
    }

    func testRejectsTooLarge() {
        var limits = ImportLimits()
        limits.maxBytes = 100
        let big = Data(("[" + String(repeating: " ", count: 200) + "]").utf8)
        XCTAssertThrowsError(try HistoryImporter(limits: limits).importCoachHistory(big)) { error in
            guard case .tooLarge = error as? ImportError else { return XCTFail("\(error)") }
        }
    }

    func testRejectsTooManyRecords() {
        var limits = ImportLimits()
        limits.maxWorkouts = 2
        let json = "[" + Array(repeating: "{\"date\": \"2025-01-06\", \"sections\": []}", count: 3).joined(separator: ",") + "]"
        XCTAssertThrowsError(try HistoryImporter(limits: limits).importCoachHistory(Data(json.utf8))) { error in
            XCTAssertEqual(error as? ImportError, .tooManyRecords(count: 3, limit: 2))
        }
    }

    func testRejectsMostlyInvalid() {
        let json = "[{\"date\": 5}, {\"nope\": true}, {\"date\": \"2025-01-06\", \"sections\": [{\"kind\": \"warmup\", \"items\": []}]}]"
        XCTAssertThrowsError(try importer.importCoachHistory(Data(json.utf8))) { error in
            XCTAssertEqual(error as? ImportError, .tooManyInvalid(invalid: 2, total: 3))
        }
    }

    func testBoundsAndCleaning() throws {
        let longNote = String(repeating: "x", count: 10_000)
        let json = """
        [{"date": "2025-01-06", "sections": [{"kind": "metabolic", "athlete_note": "\(longNote)",
          "raw": "AMRAP\\u0000\\u0007 in 12",
          "format": {"type": "amrap", "duration_min": 99999, "rounds": -4},
          "items": [{"letter": "A", "reps": 1000000, "movement": "KB Swing", "weight_lb": -50, "time_sec": 99999999},
                    {"letter": "B", "reps": 5, "movement": "   "}],
          "logged_scores": ["5", "6"], "extra_unknown_key": {"ignored": true}}]}]
        """
        let r = try importer.importCoachHistory(Data(json.utf8))
        let s = try XCTUnwrap(r.workouts.first?.metabolicSection)
        XCTAssertEqual(s.athleteNote.count, ImportLimits.standard.maxStringLength)
        XCTAssertFalse(s.instructions.unicodeScalars.contains { $0.value < 0x20 && $0 != "\n" })
        XCTAssertNil(s.durationMin)
        XCTAssertNil(s.rounds)
        XCTAssertEqual(s.items.count, 1, "blank movement names are dropped")
        XCTAssertNil(s.items[0].reps)
        XCTAssertNil(s.items[0].prescribedWeight)
        XCTAssertNil(s.items[0].timeSec)
        XCTAssertGreaterThanOrEqual(r.issues.count, 4)
    }

    func testWrongTypesInsideAnEntryAreIsolated() throws {
        let json = """
        [{"date": "2025-01-06", "sections": [{"kind": "warmup", "items": [{"movement": "Air Squat", "reps": "ten"}]}]},
         {"date": "2025-01-08", "sections": [{"kind": "warmup", "items": [{"movement": "Air Squat", "reps": 10}]}]}]
        """
        let r = try importer.importCoachHistory(Data(json.utf8))
        XCTAssertEqual(r.workouts.count, 1)
        XCTAssertEqual(r.skipped, 1)
        XCTAssertTrue(r.issues.first?.message.contains("wrong type") ?? false)
    }

    func testDeeplyNestedGarbageDoesNotCrash() {
        let nested = String(repeating: "[", count: 400) + String(repeating: "]", count: 400)
        XCTAssertThrowsError(try importer.importCoachHistory(Data(nested.utf8)))
    }
}

final class BackupTests: XCTestCase {
    func sampleBackup() throws -> AppBackup {
        let workouts = try HistoryImporter().importCoachHistory(try TestData.fixture("sample_history.json"), now: TestData.now).workouts
        return AppBackup(exportedAt: TestData.now, settings: .default, workouts: workouts,
                         liftPrograms: [LiftProgram(lift: .deadlift, trainingMax: 195)],
                         benchmarks: [TestData.benchmark(slot: 0)], goals: [Goal(lift: .deadlift, targetWeight: 200, byDate: LocalDate(2027, 1, 15))])
    }

    func testRoundTrip() throws {
        let b = try sampleBackup()
        let data = try BackupCodec.encode(b)
        let (decoded, issues) = try BackupCodec.decode(data)
        XCTAssertTrue(issues.isEmpty, "\(issues)")
        XCTAssertEqual(decoded.workouts, b.workouts)
        XCTAssertEqual(decoded.liftPrograms, b.liftPrograms)
        XCTAssertEqual(decoded.goals, b.goals)
        XCTAssertEqual(decoded.benchmarks.first?.name, "amrap-5-4-fungi")
        XCTAssertEqual(BackupCodec.sniff(data), .appBackup)
        XCTAssertEqual(BackupCodec.sniff(Data("  [ ]".utf8)), .coachHistory)
        XCTAssertNil(BackupCodec.sniff(Data("hello".utf8)))
    }

    func testRejectsUnknownVersionAndShape() throws {
        XCTAssertThrowsError(try BackupCodec.decode(Data("{\"version\": 99}".utf8))) {
            XCTAssertEqual($0 as? ImportError, .unsupportedVersion(99))
        }
        XCTAssertThrowsError(try BackupCodec.decode(Data("{\"version\": 1}".utf8))) { error in
            guard case .wrongShape = error as? ImportError else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try BackupCodec.decode(Data("{}".utf8)))
        XCTAssertThrowsError(try BackupCodec.decode(Data("nope".utf8))) { XCTAssertEqual($0 as? ImportError, .notJSON) }
    }

    func testSanitizesHostileValues() throws {
        var b = try sampleBackup()
        b.workouts[0].sections[1].items[0].setLogs[0].weight = 50_000
        b.workouts[0].sections[1].items[0].setLogs[1].reps = -1
        b.workouts[0].feedback = WorkoutFeedback(strengthDifficulty: 3, notes: String(repeating: "n", count: 9000))
        b.liftPrograms.append(LiftProgram(lift: .pushJerk, trainingMax: -10))
        b.settings.targetMinutes = 100_000
        b.goals.append(Goal(lift: .pushJerk, targetWeight: 1e9))
        let (decoded, issues) = try BackupCodec.decode(try BackupCodec.encode(b))
        XCTAssertEqual(decoded.workouts[0].sections[1].items[0].setLogs.count, 3)
        XCTAssertEqual(decoded.liftPrograms.count, 1)
        XCTAssertEqual(decoded.settings.targetMinutes, 120)
        XCTAssertEqual(decoded.goals.count, 1)
        XCTAssertLessThanOrEqual(decoded.workouts[0].feedback?.notes.count ?? 0, 4000)
        XCTAssertFalse(issues.isEmpty)
    }

    func testCSVNeutralisesFormulas() throws {
        var w = TestData.strengthDay(LocalDate(2026, 10, 5), .frontSquat, weights: [95])
        w.sections[0].items[0].movementName = "=HYPERLINK(\"http://x\",\"y\")"
        let csv = CSVExporter.setLogs([w])
        XCTAssertTrue(csv.hasPrefix("date,section,letter,movement,set,reps,weight_lb\n"))
        XCTAssertTrue(csv.contains("\"'=HYPERLINK(\"\"http://x\"\",\"\"y\"\")\""), csv)
        XCTAssertEqual(CSVExporter.field("-5"), "-5")
        XCTAssertEqual(CSVExporter.field("@cmd"), "'@cmd")
        XCTAssertEqual(CSVExporter.field("a,b"), "\"a,b\"")
        let rounds = CSVExporter.roundLogs([PlannedWorkout(date: LocalDate(2026, 10, 5), status: .done,
                                                           sections: [TestData.amrapSection(rounds: [(5, 2)])])])
        XCTAssertTrue(rounds.contains("2026-10-05,amrap-5-4-fungi,1,5,2,"), rounds)
    }
}
