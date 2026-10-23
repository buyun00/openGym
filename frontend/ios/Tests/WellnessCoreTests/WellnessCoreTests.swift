import Foundation
import XCTest
@testable import WellnessCore

final class WellnessCoreTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    func testFirstLaunchHasNoIllustrationDataOrAssumedGoal() {
        let state = WellnessState()
        XCTAssertNil(state.settings.waterGoalML)
        XCTAssertTrue(state.water.isEmpty)
        XCTAssertTrue(state.doses.isEmpty)
        XCTAssertEqual(state.progress(on: Date()), 0)
        XCTAssertEqual(state.waterFill(on: Date()), 0)
        XCTAssertFalse(state.settings.waterReminders)
        XCTAssertFalse(state.settings.supplementReminders)
        XCTAssertEqual(state.instances(for: .b, on: Date()).count, 3)
        XCTAssertTrue(state.instances(for: .d, on: Date()).isEmpty)
    }

    func testRecordedWaterIsVisibleBeforeAGoalIsSet() throws {
        let now = date("2026-10-23T13:00:00+08:00")
        let tomorrow = date("2026-10-24T13:00:00+08:00")
        var state = WellnessState()
        state.settings.waterReminders = true
        let before = WellnessReminderPlan.make(state: state, now: now, calendar: calendar)
        let first = try XCTUnwrap(state.addWater(1000, at: now, calendar: calendar))
        XCTAssertEqual(state.waterTotal(on: now, calendar: calendar), 1000)
        XCTAssertEqual(state.waterFill(on: now, calendar: calendar), 0.5, accuracy: 0.0001)
        XCTAssertEqual(state.waterScaleML, 2000)
        XCTAssertNil(state.settings.waterGoalML)
        XCTAssertEqual(state.progress(on: now, calendar: calendar), 0)
        XCTAssertEqual(state.waterFill(on: tomorrow, calendar: calendar), 0)
        XCTAssertEqual(WellnessReminderPlan.make(state: state, now: now, calendar: calendar), before)

        let next = try XCTUnwrap(state.addWater(1500, at: now, calendar: calendar))
        XCTAssertEqual(state.waterFill(on: now, calendar: calendar), 1)
        XCTAssertEqual(state.waterTotal(on: now, calendar: calendar), 2500)
        XCTAssertNil(state.settings.waterGoalML)
        // A full visual scale must not suppress reminders as though a goal were achieved.
        XCTAssertEqual(WellnessReminderPlan.make(state: state, now: now, calendar: calendar), before)
        state.water.removeAll { $0.id == next }
        XCTAssertEqual(state.waterFill(on: now, calendar: calendar), 0.5, accuracy: 0.0001)
        state.water.removeAll { $0.id == first }
        XCTAssertEqual(state.waterFill(on: now, calendar: calendar), 0)
    }

    func testWaterScaleFollowsGoalChangesWithoutChangingRecords() {
        let now = date("2026-10-23T13:00:00+08:00")
        var state = WellnessState()
        _ = state.addWater(1000, at: now, calendar: calendar)
        let entries = state.water
        state.settings.waterGoalML = 4000
        XCTAssertEqual(state.waterFill(on: now, calendar: calendar), 0.25, accuracy: 0.0001)
        XCTAssertEqual(state.progress(on: now, calendar: calendar), 0.25, accuracy: 0.0001)
        XCTAssertEqual(state.waterScaleML, 4000)
        state.settings.waterGoalML = 500
        XCTAssertEqual(state.waterFill(on: now, calendar: calendar), 1)
        XCTAssertEqual(state.progress(on: now, calendar: calendar), 2)
        state.settings.waterGoalML = nil
        XCTAssertEqual(state.waterFill(on: now, calendar: calendar), 0.5, accuracy: 0.0001)
        XCTAssertEqual(state.water, entries)
    }

    func testMidnightArchivesWaterAndRejectsOldDoseSheet() {
        let before = date("2026-10-23T23:59:00+08:00")
        let after = date("2026-10-24T00:01:00+08:00")
        var state = WellnessState()
        let old = state.instances(for: .b, on: before, calendar: calendar)[0]
        XCTAssertNotNil(state.addWater(250, at: before, calendar: calendar))
        XCTAssertEqual(state.waterTotal(on: before, calendar: calendar), 250)
        XCTAssertEqual(state.waterTotal(on: after, calendar: calendar), 0)
        XCTAssertFalse(state.recordDose(old, at: after, calendar: calendar))
    }

    func testDoseDeduplicationAndWeeklyScheduleChange() {
        let monday = date("2026-10-19T09:00:00+08:00")
        let friday = date("2026-10-23T09:00:00+08:00")
        let nextMonday = date("2026-10-26T09:00:00+08:00")
        var state = WellnessState()
        state.settings.dWeekday = 1
        let first = state.instances(for: .d, on: monday, calendar: calendar)[0]
        XCTAssertTrue(state.recordDose(first, at: monday, calendar: calendar))
        XCTAssertFalse(state.recordDose(first, at: monday, calendar: calendar))
        XCTAssertTrue(state.instances(for: .d, on: friday, calendar: calendar).isEmpty)
        state.settings.dWeekday = 5
        let shifted = state.instances(for: .d, on: friday, calendar: calendar)[0]
        XCTAssertEqual(shifted.id, first.id)
        XCTAssertNotNil(state.record(for: shifted))
        XCTAssertFalse(state.recordDose(shifted, at: friday, calendar: calendar))
        state.settings.dWeekday = 1
        XCTAssertNotEqual(state.instances(for: .d, on: nextMonday, calendar: calendar)[0].id, first.id)
    }

    func testThreeDailyInstancesAndUndoAreIndependent() {
        let now = date("2026-10-23T13:00:00+08:00")
        var state = WellnessState()
        let instances = state.instances(for: .b, on: now, calendar: calendar)
        for instance in instances { XCTAssertTrue(state.recordDose(instance, at: now, calendar: calendar)) }
        XCTAssertFalse(state.recordDose(instances[1], at: now, calendar: calendar))
        XCTAssertEqual(state.doses.count, 3)
        state.doses.removeAll { $0.id == instances[1].id }
        XCTAssertEqual(state.doses.count, 2)
        XCTAssertTrue(state.recordDose(instances[1], at: now, calendar: calendar))
    }

    func testPersistenceRelaunchCorrectionUndoAndUnrelatedArchive() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("wellness-state.json")
        let training = directory.appendingPathComponent("gym-state.json")
        let sentinel = Data("existing training and weight archive".utf8)
        try sentinel.write(to: training)
        let now = date("2026-10-23T13:00:00+08:00")
        var state = WellnessState()
        state.settings.waterGoalML = 2000
        let id = state.addWater(250, at: now, calendar: calendar)!
        XCTAssertNil(state.addWater(250, at: now, id: id, calendar: calendar))
        let instance = state.instances(for: .b, on: now, calendar: calendar)[0]
        XCTAssertTrue(state.recordDose(instance, at: now, calendar: calendar))
        try WellnessPersistence.write(state, to: url)
        var loaded = try XCTUnwrap(WellnessPersistence.read(from: url))
        XCTAssertEqual(loaded, state)
        loaded.water[0].milliliters = 400
        try WellnessPersistence.write(loaded, to: url)
        XCTAssertEqual(try WellnessPersistence.read(from: url)?.waterTotal(on: now, calendar: calendar), 400)
        loaded.water.removeAll { $0.id == id }
        try WellnessPersistence.write(loaded, to: url)
        XCTAssertEqual(try WellnessPersistence.read(from: url)?.waterTotal(on: now, calendar: calendar), 0)
        XCTAssertEqual(try Data(contentsOf: training), sentinel)
    }

    func testCorruptArchiveIsNotReplacedByRead() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data("{incomplete".utf8)
        try original.write(to: url)
        XCTAssertThrowsError(try WellnessPersistence.read(from: url))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testReminderPermissionIndependentPlanAndCompletionSuppression() {
        let now = date("2026-10-19T07:00:00+08:00")
        var state = WellnessState()
        state.settings.waterGoalML = 2000
        state.settings.dWeekday = 1
        state.settings.bTimesConfirmed = true
        XCTAssertTrue(WellnessReminderPlan.make(state: state, now: now, calendar: calendar).isEmpty)
        state.settings.waterReminders = true
        state.settings.supplementReminders = true
        let plan = WellnessReminderPlan.make(state: state, now: now, calendar: calendar)
        XCTAssertEqual(plan.count, 50)
        XCTAssertEqual(Set(plan.map(\.id)).count, plan.count)
        XCTAssertTrue(plan.allSatisfy { $0.date > now })
        let instance = state.instances(for: .b, on: now, calendar: calendar)[0]
        _ = state.recordDose(instance, at: now, calendar: calendar)
        _ = state.addWater(2100, at: now, calendar: calendar)
        let changed = WellnessReminderPlan.make(state: state, now: now, calendar: calendar)
        XCTAssertEqual(changed.count, 45)
        XCTAssertFalse(changed.contains { $0.id == WellnessReminderPlan.prefix + instance.id })
        XCTAssertEqual(state.progress(on: now, calendar: calendar), 1.05, accuracy: 0.0001)
        state.settings.waterReminders = false
        XCTAssertFalse(WellnessReminderPlan.make(state: state, now: now, calendar: calendar).contains { $0.id.contains(".water.") })
    }

    func testDSTAndYearBoundaryUseCivilDays() {
        var newYork = calendar
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let a = date("2026-11-01T01:30:00-04:00")
        let b = date("2026-11-01T01:30:00-05:00")
        XCTAssertEqual(WellnessDay.key(a, calendar: newYork), WellnessDay.key(b, calendar: newYork))
        XCTAssertEqual(WellnessDay.weekKey(date("2027-01-01T12:00:00+08:00"), calendar: calendar), "2026-12-28")
    }

    func testVolumeConservationAtAllProgressLevelsAndTilts() {
        for fill in [0.0, 0.005, 0.25, 0.5, 0.75, 0.995, 1.0, 1.5] {
            for slope in [-3.0, -1.0, 0.0, 1.0, 3.0] {
                let surface = WaterSurface(fill: fill, slope: slope, swell: 0.06, ripple: 0.0025, phase: 2.7)
                // Independent high-resolution integration of the visible cross-section.
                XCTAssertEqual(surface.area(base: surface.base, samples: 8192), min(1, fill), accuracy: 0.0002)
            }
        }
    }

    func testSpringRetargetingSettlesWithoutFrameRateDependence() {
        for fps in [30.0, 60.0, 120.0] {
            var spring = WaterSpring(response: 1.55, dampingRatio: 0.43)
            for _ in 0..<Int(fps) { spring.advance(to: 0.6, dt: 1 / fps) }
            XCTAssertGreaterThan(abs(spring.value), 0.1)
            for _ in 0..<Int(fps * 8) { spring.advance(to: 0, dt: 1 / fps) }
            XCTAssertEqual(spring.value, 0, accuracy: 0.00001)
            XCTAssertEqual(spring.velocity, 0, accuracy: 0.0001)
        }
    }
}
