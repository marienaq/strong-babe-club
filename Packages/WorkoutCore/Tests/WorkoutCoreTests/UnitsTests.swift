import XCTest
@testable import WorkoutCore

final class UnitsTests: XCTestCase {
    func testConversionRoundTripsWithoutLoss() {
        for lb in stride(from: 0.0, through: 600, by: 2.5) {
            XCTAssertEqual(WeightUnit.kg.toPounds(WeightUnit.kg.fromPounds(lb)), lb, accuracy: 1e-9)
            XCTAssertEqual(WeightUnit.lb.fromPounds(lb), lb)
        }
        XCTAssertEqual(WeightUnit.kg.fromPounds(220.462_262_18), 100, accuracy: 1e-6)
    }

    func testFormatting() {
        XCTAssertEqual(WeightUnit.kg.label(pounds: 185), "83.9 kg")
        XCTAssertEqual(WeightUnit.lb.label(pounds: 185), "185 lb")
        XCTAssertEqual(WeightUnit.kg.format(pounds: WeightUnit.kg.toPounds(60)), "60")
        XCTAssertEqual(formatWeight(102.5), "102.5")
        XCTAssertEqual(formatWeight(61.2499), "61.2")
    }

    func testRoundingToUnitSteps() {
        XCTAssertEqual(WeightUnit.kg.fromPounds(WeightUnit.kg.rounded(pounds: 195)), 87.5, accuracy: 1e-9) // 88.45 -> 87.5
        XCTAssertEqual(WeightUnit.lb.rounded(pounds: 197), 195)
        XCTAssertEqual(WeightUnit.kg.roundingStep, 2.5)
    }

    func testKilogramPresetPlateMath() {
        let calc = PlateCalculator(inventory: .kilogramsPreset)
        XCTAssertEqual(calc.maxLoadable, 20 + 2 * (1.25 + 2.5 + 5 + 10 + 15 + 20))
        XCTAssertEqual(calc.smallestStep, 2.5)
        XCTAssertEqual(calc.loadout(for: 60)?.perSide, [20])
        XCTAssertEqual(calc.loadout(for: 32.5)?.description, "bar + 5 + 1.25 each side")
        XCTAssertEqual(calc.round(61).weight, 60)
        XCTAssertEqual(EquipmentInventory.barOptions(.kg), [20, 15])
        XCTAssertEqual(EquipmentInventory.barOptions(.lb), [45, 35])
    }

    func testOldInventoryDecodesAsPounds() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(EquipmentInventory.homeGym)) as! [String: Any]
        json.removeValue(forKey: "unit")
        let inv = try JSONDecoder().decode(EquipmentInventory.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(inv.unit, .lb)
        XCTAssertEqual(inv, .homeGym)
    }

    func testSwitchingUnitsLoadsPreset() {
        let kg = PlannerSettings.default.switchingUnits(to: .kg)
        XCTAssertEqual(kg.units, .kg)
        XCTAssertEqual(kg.equipment.barWeight, 20)
        XCTAssertEqual(kg.switchingUnits(to: .kg), kg)
        XCTAssertEqual(kg.switchingUnits(to: .lb).equipment, .homeGym)
    }

    /// A kg gym plans loadable kg weights; results stay canonical pounds.
    func testPlannerInKilograms() throws {
        var s = PlannerSettings.default.switchingUnits(to: .kg)
        s.limits = TrainingLimits()
        let history = [TestData.strengthDay(LocalDate(2026, 10, 2), .deadlift, weights: [85, 110, 135, 160, 185])]
        let w = try RulesWorkoutPlanner().makePlan(PlanRequest(date: LocalDate(2026, 10, 28), settings: s, history: history,
                                                              trainingMaxes: [.deadlift: 195], now: TestData.now))
        let calc = PlateCalculator(inventory: .kilogramsPreset)
        let sets = try XCTUnwrap(w.strengthSection?.items.first?.plannedSets)
        XCTAssertFalse(sets.isEmpty)
        for set in sets {
            let kg = WeightUnit.kg.fromPounds(set.weight)
            XCTAssertNotNil(calc.loadout(for: (kg * 1000).rounded() / 1000), "\(kg) kg not loadable")
        }
        // TM 195 lb = 88.45 kg; week 2 volume top ≈ 76.7% = 67.8 -> 67.5 kg.
        XCTAssertEqual(WeightUnit.kg.fromPounds(sets.last!.weight), 67.5, accuracy: 0.01)
        XCTAssertEqual(WeightUnit.kg.fromPounds(w.strengthSection!.trainingMax!), 88.45, accuracy: 0.01)
        // Text speaks kg, never lb.
        let text = w.reasons.map(\.text).joined() + w.sections.flatMap(\.items).compactMap(\.weightLabel).joined()
        XCTAssertFalse(text.contains(" lb"), text)
        // Metabolic DB/KB weights snap to the kg inventory.
        for item in w.sections.filter({ $0.kind != .strength }).flatMap(\.items) {
            guard let p = item.prescribedWeight, let m = MovementLibrary.standard[item.movementID] else { continue }
            let kg = (WeightUnit.kg.fromPounds(p) * 100).rounded() / 100
            switch m.implement {
            case .dumbbell: XCTAssertTrue(([4, 6, 8, 10] + [8, 12, 16]).contains(kg), "\(m.name) \(kg)")
            case .kettlebell: XCTAssertTrue([8, 12, 16].contains(kg), "\(m.name) \(kg)")
            default: break
            }
        }
    }

    func testPoundPlansUnchanged() throws {
        let a = try RulesWorkoutPlanner().makePlan(PlanRequest(date: LocalDate(2026, 10, 19), now: TestData.now))
        XCTAssertTrue(a.reasons.contains { $0.text.contains(" lb") })
    }
}
