import Foundation
import XCTest
@testable import WellnessCore

final class DrinkRecordTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private let now = ISO8601DateFormatter().date(from: "2026-10-23T12:00:00Z")!

    func testLegacyArchiveLoadsAsWaterAndSurvivesNextSave() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        var state = WellnessState()
        let id = try XCTUnwrap(state.addWater(290, at: now, calendar: calendar))
        state.settings.waterGoalML = 2600
        let dose = state.instances(for: .b, on: now, calendar: calendar)[0]
        XCTAssertTrue(state.recordDose(dose, at: now, calendar: calendar))
        try WellnessPersistence.write(state, to: url)
        var oldJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var rows = try XCTUnwrap(oldJSON["water"] as? [[String: Any]])
        rows[0].removeValue(forKey: "drink")
        oldJSON["water"] = rows
        try JSONSerialization.data(withJSONObject: oldJSON).write(to: url)

        var restored = try XCTUnwrap(WellnessPersistence.read(from: url))
        XCTAssertEqual(restored, state)
        XCTAssertEqual(restored.water[0].drink, .water)
        XCTAssertEqual(restored.water[0].id, id)
        _ = restored.addWater(180, at: now, calendar: calendar, drink: .coffee)
        try WellnessPersistence.write(restored, to: url)
        XCTAssertEqual(try WellnessPersistence.read(from: url), restored)
        XCTAssertEqual(restored.doses, state.doses)
        XCTAssertEqual(restored.settings, state.settings)
    }

    func testEveryDrinkPersistsWithActualVolumeAndContributesToWaterLevel() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        var state = WellnessState()
        state.settings.waterGoalML = 2000
        for drink in DrinkKind.allCases {
            XCTAssertNotNil(state.addWater(150, at: now, calendar: calendar, drink: drink))
        }
        try WellnessPersistence.write(state, to: url)
        let restored = try XCTUnwrap(WellnessPersistence.read(from: url))
        XCTAssertEqual(restored, state)
        XCTAssertEqual(restored.water.map(\.drink), DrinkKind.allCases)
        XCTAssertEqual(restored.waterTotal(on: now, calendar: calendar), DrinkKind.allCases.count * 150)
        XCTAssertEqual(restored.waterFill(on: now, calendar: calendar),
                       Double(DrinkKind.allCases.count * 150) / 2000, accuracy: 0.00001)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        XCTAssertEqual(restored.waterTotal(on: tomorrow, calendar: calendar), 0)
    }

    func testUnknownDrinkDoesNotMakeExistingArchiveUnreadable() throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","date":"2026-10-23T12:00:00Z","day":"2026-10-23","milliliters":350,"drink":"future-category"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(WaterEntry.self, from: Data(json.utf8))
        XCTAssertEqual(record.drink, .other)
        XCTAssertEqual(record.id, id)
        XCTAssertEqual(record.milliliters, 350)
        XCTAssertEqual(record.day, "2026-10-23")
    }

    func testDrinkCorrectionUndoAndVolumeValidation() throws {
        var state = WellnessState()
        let id = try XCTUnwrap(state.addWater(250, at: now, calendar: calendar, drink: .tea))
        XCTAssertNil(state.addWater(0, at: now, calendar: calendar, drink: .milk))
        XCTAssertNil(state.addWater(5001, at: now, calendar: calendar, drink: .juice))
        XCTAssertNil(state.addWater(250, at: now, id: id, calendar: calendar, drink: .coffee))
        state.water[0].drink = .coffee
        state.water[0].milliliters = 350
        let encoder = JSONEncoder()
        let corrected = try JSONDecoder().decode(WellnessState.self, from: encoder.encode(state))
        XCTAssertEqual(corrected.water[0].drink, .coffee)
        XCTAssertEqual(corrected.waterTotal(on: now, calendar: calendar), 350)
        state.water.removeAll { $0.id == id }
        XCTAssertEqual(state.waterFill(on: now, calendar: calendar), 0)
    }
}
