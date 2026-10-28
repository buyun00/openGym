import Foundation
import XCTest
@testable import BodyCore

final class BodyAnalyticsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
    private func session(_ finished: Date?, started: Date? = nil, sets: [WorkoutSet] = []) -> WorkoutSession {
        WorkoutSession(id: UUID(), name: "训练", startedAt: started ?? finished ?? date(2026, 10, 23), finishedAt: finished,
                       exercises: [WorkoutExercise(id: UUID(), exerciseId: "bench", name: "卧推", sets: sets)])
    }
    private func set(_ rir: Int?, done: Bool = true) -> WorkoutSet {
        WorkoutSet(id: UUID(), weight: 60, reps: 8, done: done, rir: rir)
    }

    func testOldRecordsDecodeWithMissingOptionalMetrics() throws {
        let id = UUID().uuidString
        let oldSet = Data("{\"id\":\"\(id)\",\"weight\":60,\"reps\":8,\"done\":true}".utf8)
        XCTAssertNil(try JSONDecoder().decode(WorkoutSet.self, from: oldSet).rir)
        let oldWeight = Data("{\"id\":\"\(id)\",\"date\":0,\"kilograms\":85.5}".utf8)
        let weight = try JSONDecoder().decode(WeighIn.self, from: oldWeight)
        XCTAssertNil(weight.bodyFatPercent)
        XCTAssertNil(weight.leanKilograms)
    }

    func testNewMetricsRoundTripWithoutTurningMissingIntoZero() throws {
        let sample = WeighIn(id: UUID(), date: date(2026, 10, 23), kilograms: 85.5, bodyFatPercent: 25.6)
        let decoded = try JSONDecoder().decode(WeighIn.self, from: JSONEncoder().encode(sample))
        XCTAssertEqual(decoded, sample)
        XCTAssertEqual(try XCTUnwrap(decoded.leanKilograms), 63.612, accuracy: 0.001)
        let measure = BodyMeasurement(id: UUID(), date: sample.date, centimeters: ["腰围": 85])
        XCTAssertEqual(try JSONDecoder().decode(BodyMeasurement.self, from: JSONEncoder().encode(measure)), measure)
        let unrated = set(nil)
        XCTAssertNil(try JSONDecoder().decode(WorkoutSet.self, from: JSONEncoder().encode(unrated)).rir)
    }

    func testRollingRangeUsesTodayInsteadOfLastRecordedDate() {
        let now = date(2026, 10, 23)
        let entries = [23, 24].map { WeighIn(id: UUID(), date: date(2026, 9, $0, 0), kilograms: 88) }
            + [WeighIn(id: UUID(), date: date(2026, 10, 24, 0), kilograms: 85)]
        XCTAssertEqual(BodyAnalytics.weights(entries, range: .month, now: now, calendar: calendar).map(\.date), [date(2026, 9, 24, 0)])
        XCTAssertTrue(BodyAnalytics.weights(entries, range: .week, now: now, calendar: calendar).isEmpty)
        XCTAssertEqual(BodyAnalytics.weights(entries, range: .all, now: now, calendar: calendar).count, 2)
    }

    func testTrainingBelongsToCompletionDateAcrossMidnight() {
        let now = date(2026, 10, 23)
        let session = session(date(2026, 10, 19, 1), started: date(2026, 10, 18, 23))
        let summary = BodyAnalytics.summary([session], now: now, calendar: calendar)
        XCTAssertEqual(summary.week, 1)
        XCTAssertEqual(BodyAnalytics.recordDays(workouts: [session], weights: [], measurements: [], calendar: calendar), [date(2026, 10, 19, 0)])
    }

    func testStreakAllowsCurrentWeekInProgressAndStopsAtGap() {
        let now = date(2026, 10, 23)
        let sessions = [session(date(2026, 10, 12)), session(date(2026, 10, 5)), session(date(2026, 9, 21))]
        XCTAssertEqual(BodyAnalytics.summary(sessions, now: now, calendar: calendar).consecutiveWeeks, 2)
        XCTAssertEqual(BodyAnalytics.summary(sessions + [session(date(2026, 10, 20))], now: now, calendar: calendar).consecutiveWeeks, 3)
        XCTAssertEqual(BodyAnalytics.summary([session(date(2026, 10, 5))], now: now, calendar: calendar).consecutiveWeeks, 0)
    }

    func testIncompleteAndFutureWorkoutsNeverCount() {
        let now = date(2026, 10, 23)
        let sessions = [session(nil), session(date(2026, 10, 23, 18)), session(date(2026, 10, 24)), session(date(2026, 10, 20))]
        let filtered = BodyAnalytics.workouts(sessions, range: .month, now: now, calendar: calendar)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(BodyAnalytics.summary(sessions, now: now, calendar: calendar).month, 1)
    }

    func testUnratedDoesNotMeanFailureAndIncompleteSetsAreExcluded() {
        let result = BodyAnalytics.intensity([session(date(2026, 10, 23), sets: [set(nil), set(0), set(2), set(4), set(10), set(-1), set(11), set(0, done: false)])], calendar: calendar)
        XCTAssertEqual(result.total, 7)
        XCTAssertEqual(result.rated, 4)
        XCTAssertEqual(result.missing, 3)
        XCTAssertEqual(result.average, 4)
        XCTAssertEqual(result.hardShare, 0.5)
        XCTAssertEqual(result.buckets, [1, 0, 1, 0, 2])
    }

    func testEmptyIntensityKeepsSummaryAbsent() {
        let result = BodyAnalytics.intensity([session(date(2026, 10, 23), sets: [set(nil)])], calendar: calendar)
        XCTAssertNil(result.average)
        XCTAssertNil(result.hardShare)
        XCTAssertTrue(result.weeks.isEmpty)
        XCTAssertEqual(result.missing, 1)
    }

    func testWeeklyIntensityIsWeightedByRatedSets() {
        let result = BodyAnalytics.intensity([
            session(date(2026, 10, 20), sets: [set(0)]),
            session(date(2026, 10, 22), sets: [set(4), set(4), set(4), set(nil)])
        ], calendar: calendar)
        XCTAssertEqual(result.weeks.count, 1)
        XCTAssertEqual(result.weeks.first?.average, 3)
        XCTAssertEqual(result.weeks.first?.date, date(2026, 10, 19, 0))
    }

    func testMuscleLoadUsesContributionsAndOnlyCompletedSets() {
        let loads = BodyAnalytics.muscleLoads([
            session(date(2026, 10, 23), sets: [set(nil), set(3), set(2, done: false)]),
            session(nil, sets: [set(0)])
        ], muscles: ["bench": ["chest": 1, "triceps": 0.5]])
        XCTAssertEqual(loads.map(\.id), ["chest", "triceps"])
        XCTAssertEqual(loads.map(\.value), [2, 1])
    }

    func testCrunchAliasUsesBundledMuscleContributions() throws {
        struct Record: Decodable {
            let id: String
            let muscles: [String: Double]
        }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../App/App/Native/exercises.json").standardizedFileURL
        let records = try JSONDecoder().decode([Record].self, from: Data(contentsOf: url))
        let muscles = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.muscles) })
        let stamp = date(2026, 10, 23)
        let workout = WorkoutSession(id: UUID(), name: "训练", startedAt: stamp, finishedAt: stamp,
            exercises: [WorkoutExercise(id: UUID(), exerciseId: "2445", name: "卷腹", sets: [set(nil)])])
        let loads = BodyAnalytics.muscleLoads([workout], muscles: muscles)
        XCTAssertGreaterThan(loads.first(where: { $0.id == "abs" })?.value ?? 0, 0)
        XCTAssertGreaterThan(loads.first(where: { $0.id == "obliques" })?.value ?? 0, 0)
    }

    func testCalendarCombinesRecordsOnSameLocalDay() {
        let stamp = date(2026, 10, 23)
        let days = BodyAnalytics.recordDays(workouts: [session(stamp)],
            weights: [WeighIn(id: UUID(), date: date(2026, 10, 23, 0), kilograms: 85)],
            measurements: [BodyMeasurement(id: UUID(), date: date(2026, 10, 20), centimeters: ["腰围": 85])], calendar: calendar)
        XCTAssertEqual(days, [date(2026, 10, 23, 0), date(2026, 10, 20, 0)])
    }

    func testCalendarDayWindowAcrossDSTAndYearBoundary() {
        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = la.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 12))!
        let cutoff = la.date(from: DateComponents(year: 2026, month: 10, day: 28))!
        XCTAssertTrue(BodyRange.week.contains(cutoff, now: now, calendar: la))
        XCTAssertFalse(BodyRange.week.contains(cutoff.addingTimeInterval(-1), now: now, calendar: la))
        let summary = BodyAnalytics.summary([session(date(2025, 12, 29)), session(date(2026, 1, 5))], now: date(2026, 1, 6), calendar: calendar)
        XCTAssertEqual(summary.consecutiveWeeks, 2)
        XCTAssertEqual(summary.month, 1)
    }
}
