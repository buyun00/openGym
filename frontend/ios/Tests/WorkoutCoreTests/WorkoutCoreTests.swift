import XCTest
@testable import BodyCore

final class WorkoutCoreTests: XCTestCase {
    private func exercise(_ key: String = "2259", mode: WorkoutMode = .cardio, done: Bool = false) -> WorkoutExercise {
        var set = WorkoutLogic.seed(mode: mode)
        set.done = done
        return WorkoutExercise(id: UUID(), exerciseId: key, name: "测试动作", sets: [set], mode: mode)
    }
    private func session(_ entries: [WorkoutExercise], finished: Bool = false, time: Double = 100) -> WorkoutSession {
        WorkoutSession(id: UUID(), name: "训练", startedAt: Date(timeIntervalSince1970: time),
                       finishedAt: finished ? Date(timeIntervalSince1970: time + 60) : nil, exercises: entries)
    }

    func testLegacySessionStillDecodesWithoutNewFields() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","name":"旧训练","startedAt":0,
         "exercises":[{"id":"00000000-0000-0000-0000-000000000002","exerciseId":"0001","name":"卷腹",
          "sets":[{"id":"00000000-0000-0000-0000-000000000003","weight":20,"reps":8,"done":true}]}]}
        """
        let value = try JSONDecoder().decode(WorkoutSession.self, from: Data(json.utf8))
        XCTAssertEqual(value.exercises[0].sets[0].reps, 8)
        XCTAssertNil(value.exercises[0].mode)
        XCTAssertNil(value.exercises[0].sets[0].rir)
        XCTAssertNil(value.note)
        XCTAssertNil(value.restEndsAt)
    }

    func testCardioRoundTripKeepsMinutesSpeedInclineAndNotes() throws {
        var entry = exercise()
        entry.sets[0].minutes = 5
        entry.sets[0].speed = 4.5
        entry.sets[0].incline = 2.5
        entry.note = "热身"
        entry.notePinned = true
        var value = session([entry])
        value.note = "本次备注"
        value.selectedExerciseId = entry.id
        value.layout = .compact
        value.restEndsAt = Date(timeIntervalSince1970: 999)
        XCTAssertEqual(try JSONDecoder().decode(WorkoutSession.self, from: JSONEncoder().encode(value)), value)
        XCTAssertEqual(WorkoutLogic.summary(entry.sets[0], mode: .cardio), "5 min @ 4.5 km/h · 坡度 2.5%")
    }

    func testMetricsRejectNonfiniteAndKeepUnsetInclineDistinctFromFlat() {
        var set = WorkoutLogic.seed(mode: .cardio)
        WorkoutMetric.incline.apply(nil, to: &set)
        XCTAssertNil(set.incline)
        WorkoutMetric.incline.apply(0, to: &set)
        XCTAssertEqual(set.incline, 0)
        WorkoutMetric.incline.apply(99, to: &set)
        XCTAssertEqual(set.incline, 40)
        WorkoutMetric.speed.apply(.nan, to: &set)
        XCTAssertEqual(set.speed, 8)
        WorkoutMetric.incline.apply(2.26, to: &set)
        XCTAssertEqual(set.incline, 2.5)
    }

    func testCopyRetainsAllTargetsButClearsCompletionAndEffort() {
        var set = WorkoutLogic.seed(mode: .cardio)
        set.done = true; set.rir = 2; set.completedAt = Date(); set.incline = 3
        let copy = WorkoutLogic.copy(set)
        XCTAssertNotEqual(set.id, copy.id)
        XCTAssertFalse(copy.done)
        XCTAssertNil(copy.rir)
        XCTAssertNil(copy.completedAt)
        XCTAssertEqual(copy.minutes, set.minutes)
        XCTAssertEqual(copy.speed, set.speed)
        XCTAssertEqual(copy.incline, 3)
    }

    func testExclusionSkipsProgressionButKeepsVisibleHistory() {
        let eligible = session([exercise(done: true)], finished: true)
        var excluded = session([exercise(done: true)], finished: true, time: 200)
        WorkoutLogic.setExcluded(true, session: &excluded)
        let history = [eligible, excluded]
        XCTAssertEqual(WorkoutLogic.previous("2259", mode: .cardio, in: history, forProgression: true)?.0, eligible.startedAt)
        XCTAssertEqual(WorkoutLogic.previous("2259", mode: .cardio, in: history, forProgression: false)?.0, excluded.startedAt)
    }

    func testNewExercisesInheritSessionExclusionAndInsertAfterCurrent() {
        let a = exercise("a"), b = exercise("b"), c = exercise("c")
        var value = session([a, b])
        WorkoutLogic.setExcluded(true, session: &value)
        WorkoutLogic.insert([c], after: a.id, into: &value)
        XCTAssertEqual(value.exercises.map(\.exerciseId), ["a", "c", "b"])
        XCTAssertEqual(value.selectedExerciseId, c.id)
        XCTAssertTrue(value.exercises.allSatisfy { $0.noProgression == true })
        WorkoutLogic.setExcluded(false, session: &value)
        XCTAssertFalse(value.exercises.contains { $0.noProgression == true })
    }

    func testRemoveCurrentSelectsNeighbourAndClearsItsRest() {
        let a = exercise("a"), b = exercise("b")
        var value = session([a, b]); value.selectedExerciseId = a.id
        value.restOwner = a.id; value.restEndsAt = Date()
        WorkoutLogic.remove(a.id, from: &value)
        XCTAssertEqual(value.selectedExerciseId, b.id)
        XCTAssertNil(value.restEndsAt)
        WorkoutLogic.remove(b.id, from: &value)
        XCTAssertNil(value.selectedExerciseId)
        XCTAssertTrue(value.exercises.isEmpty)
    }

    func testFinishDropsUntouchedExercisesAndPreservesActualRecords() {
        var logged = exercise(done: true)
        logged.note = "保留备注"; logged.noProgression = true
        var value = session([logged, exercise("untouched")])
        value.note = "会话备注"; value.restEndsAt = Date(); value.restOwner = logged.id
        let end = Date(timeIntervalSince1970: 300)
        let result = WorkoutLogic.finished(value, at: end)
        XCTAssertEqual(result.exercises, [logged])
        XCTAssertEqual(result.note, "会话备注")
        XCTAssertEqual(result.finishedAt, end)
        XCTAssertNil(result.restEndsAt)
        XCTAssertNil(result.restOwner)
        XCTAssertNil(value.finishedAt)
    }

    func testEmptyFinishDoesNotInventCompletedWork() {
        let result = WorkoutLogic.finished(session([exercise()]), at: Date())
        XCTAssertTrue(result.exercises.isEmpty)
        XCTAssertNotNil(result.finishedAt)
    }

    func testSkippingHealthClearsPreviouslyAttachedRecord() {
        var active = session([exercise(done: true)])
        active.health = WorkoutHealth(status: "available", window_start: 1, window_end: 2, queried_at: 3,
                                      workout_id: "previous", heart_rate_avg_bpm: 120)
        let finished = WorkoutLogic.finished(active, at: Date(timeIntervalSince1970: 300), health: nil)
        XCTAssertNil(finished.health)
        XCTAssertEqual(active.health?.workout_id, "previous")
        XCTAssertEqual(finished.id, active.id)
    }

    func testExplicitHealthChoiceKeepsItsOwnWindowAndSurvivesPersistence() throws {
        let active = session([exercise(done: true)])
        let chosen = WorkoutHealth(status: "available", window_start: 500_000, window_end: 600_000,
                                   queried_at: 700_000, workout_id: "selected-by-user",
                                   heart_rate_avg_bpm: 123, heart_rate_max_bpm: 160, active_energy_kcal: 250)
        let finished = WorkoutLogic.finished(active, at: Date(timeIntervalSince1970: 300), health: chosen)
        let restored = try JSONDecoder().decode(WorkoutSession.self, from: JSONEncoder().encode(finished))
        XCTAssertEqual(restored.health, chosen)
        XCTAssertEqual(restored.startedAt, active.startedAt)
        XCTAssertEqual(restored.id, active.id)
    }

    func testDifferentModesNeverSeedOneAnother() {
        let strength = session([exercise(mode: .reps, done: true)], finished: true)
        XCTAssertNil(WorkoutLogic.previous("2259", mode: .cardio, in: [strength], forProgression: true))
        let timed = WorkoutLogic.seed(mode: .time)
        XCTAssertEqual(timed.seconds, 45)
        XCTAssertEqual(timed.reps, 0)
        XCTAssertNil(timed.minutes)
    }

    func testMixedSessionSkipsOnlyExcludedExercise() {
        var a = exercise("a", done: true); a.noProgression = true
        let b = exercise("b", done: true)
        let value = session([a, b], finished: true)
        XCTAssertNil(WorkoutLogic.previous("a", mode: .cardio, in: [value], forProgression: true))
        XCTAssertNotNil(WorkoutLogic.previous("b", mode: .cardio, in: [value], forProgression: true))
    }
}
