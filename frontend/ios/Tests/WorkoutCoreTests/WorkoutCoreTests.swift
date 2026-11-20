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
        XCTAssertNil(value.cardioTimer)
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

    func testCardioTimerSurvivesRestoreAndBelongsToAnUnfinishedSet() throws {
        let entry = exercise()
        var value = session([entry])
        let timer = try XCTUnwrap(WorkoutLogic.cardioTimer(exercise: entry, setID: entry.sets[0].id, now: value.startedAt))
        XCTAssertEqual(timer.end.timeIntervalSince(timer.start), 20 * 60)
        value.cardioTimer = timer
        let restored = try JSONDecoder().decode(WorkoutSession.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(WorkoutLogic.activeCardioTimer(in: restored), timer)
        XCTAssertNil(WorkoutLogic.finished(restored, at: timer.end).cardioTimer)

        value.exercises[0].sets[0].done = true
        XCTAssertNil(WorkoutLogic.activeCardioTimer(in: value))
        XCTAssertNil(WorkoutLogic.cardioTimer(exercise: value.exercises[0], setID: timer.setID, now: timer.end))
        value.exercises[0].sets.removeAll()
        XCTAssertNil(WorkoutLogic.activeCardioTimer(in: value))
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

    func testNewStrengthSetsUseTenRepsEvenWhenTheyReuseAnOldWeight() {
        let previous = WorkoutSet(id: UUID(), weight: 62.5, reps: 8, done: true, rir: 2, completedAt: .now)
        let fresh = WorkoutLogic.seed(mode: .reps)
        let next = WorkoutLogic.seed(mode: .reps, previous: previous)
        XCTAssertEqual(fresh.reps, 10)
        XCTAssertEqual(next.weight, 62.5)
        XCTAssertEqual(next.reps, 10)
        XCTAssertNotEqual(next.id, previous.id)
        XCTAssertFalse(next.done)
        XCTAssertNil(next.rir)
        XCTAssertNil(next.completedAt)
        XCTAssertEqual(WorkoutLogic.seed(mode: .reps, reps: 12, previous: previous).reps, 12)
        XCTAssertEqual(WorkoutLogic.copy(previous).reps, 8)
    }

    func testPlanLoadsBeatHistoryAndUnspecifiedLegacyLoadsUseHistory() throws {
        var slot = RoutineExercise(id: UUID(), exerciseId: "0585", name: "腿屈伸", setCount: 3, reps: 8)
        let previous = [30.0, 35.0].map { WorkoutSet(id: UUID(), weight: $0, reps: 12, done: true) }
        func loads() -> [Double] { WorkoutLogic.plannedSets(for: slot, mode: .reps, previous: previous).map(\.weight) }
        XCTAssertEqual(loads(), [30, 35, 35])
        slot.weight = 0
        XCTAssertEqual(loads(), [30, 35, 35])
        slot.weight = 42.5
        XCTAssertEqual(loads(), [42.5, 42.5, 42.5])
        slot.setWeights = [0, 47.5, 50]
        XCTAssertEqual(loads(), [0, 47.5, 50])
        let encoded = try JSONEncoder().encode(slot)
        XCTAssertEqual(try JSONDecoder().decode(RoutineExercise.self, from: encoded), slot)
    }

    func testManualWeightAndSetChangesUpdateOnlyTheirSourceSlot() {
        var slot = RoutineExercise(id: UUID(), exerciseId: "0585", name: "腿屈伸", setCount: 3, reps: 8, weight: 40)
        let first = slot
        slot.id = UUID()
        var routines = [Routine(id: UUID(), name: "A", exercises: [first, slot]), Routine(id: UUID(), name: "B", exercises: [first])]
        let rows = WorkoutLogic.plannedSets(for: slot, mode: .reps, previous: [])
        var entry = WorkoutExercise(id: UUID(), exerciseId: slot.exerciseId, name: slot.name, sets: rows,
                                    mode: .reps, routineId: routines[0].id, routineSlotId: slot.id)
        func edit(_ change: (inout [WorkoutSet]) -> Void) {
            let before = entry
            change(&entry.sets)
            WorkoutLogic.saveSetPlan(for: entry, previous: before, in: &routines)
        }
        edit { $0[0].done = true }
        XCTAssertNil(routines[0].exercises[1].setWeights)
        edit { WorkoutLogic.updateMetric(.weight, value: 50, setID: rows[2].id, mode: .reps, in: &$0) }
        edit { WorkoutLogic.updateMetric(.weight, value: 45, setID: rows[1].id, mode: .reps, in: &$0) }
        edit { $0.insert(WorkoutLogic.copy($0[1]), at: 2) }
        XCTAssertEqual(routines[0].exercises[1].setCount, 4)
        XCTAssertEqual(routines[0].exercises[1].setWeights, [40, 45, 45, 50])
        edit { $0.remove(at: 2) }
        let saved = routines[0].exercises[1]
        XCTAssertEqual(saved.setCount, 3)
        XCTAssertEqual(WorkoutLogic.plannedSets(for: saved, mode: .reps, previous: []).map(\.weight), [40, 45, 50])
        XCTAssertEqual(routines[0].exercises[0], first)
        XCTAssertEqual(routines[1].exercises[0], first)
        routines[0].exercises[1].setCount = 4
        routines[0].exercises[1].setWeights = [40, 45, 55, 60]
        edit { $0[1].weight = 47.5 }
        XCTAssertEqual(routines[0].exercises[1].setWeights, [40, 47.5, 55, 60])
        let updated = routines[0].exercises[1]
        entry.routineSlotId = nil
        edit { $0.removeLast() }
        XCTAssertEqual(routines[0].exercises[1], updated)
    }

    func testStrengthEditsCopyWeightAndRepsToLaterUnfinishedSets() {
        let completed = WorkoutSet(id: UUID(), weight: 20, reps: 8, done: true, completedAt: .now)
        let earlier = WorkoutSet(id: UUID(), weight: 25, reps: 9, done: false)
        let current = WorkoutSet(id: UUID(), weight: 30, reps: 10, done: false)
        let later = WorkoutSet(id: UUID(), weight: 30, reps: 11, done: false)
        let laterCompleted = WorkoutSet(id: UUID(), weight: 35, reps: 8, done: true, completedAt: .now)
        let original = [completed, earlier, current, laterCompleted, later]
        var sets = original

        WorkoutLogic.updateMetric(.weight, value: 42.5, setID: current.id, mode: .reps, in: &sets)
        XCTAssertEqual(sets.map(\.weight), [20, 25, 42.5, 35, 42.5])
        XCTAssertEqual(sets.map(\.reps), [8, 9, 10, 8, 10])

        sets[4].weight = 36
        WorkoutLogic.updateMetric(.reps, value: 12, setID: current.id, mode: .reps, in: &sets)
        XCTAssertEqual(sets.map(\.weight), [20, 25, 42.5, 35, 42.5])
        XCTAssertEqual(sets.map(\.reps), [8, 9, 12, 8, 12])
        XCTAssertEqual(sets[0], original[0])
        XCTAssertEqual(sets[1], original[1])
        XCTAssertEqual(sets[3], original[3])
    }

    func testTimedEditsUpdateOnlyTheSelectedMetricInLaterSets() {
        let current = WorkoutSet(id: UUID(), weight: 20, reps: 0, done: false, seconds: 45)
        let later = WorkoutSet(id: UUID(), weight: 30, reps: 0, done: false, seconds: 60)
        var sets = [current, later]
        WorkoutLogic.updateMetric(.weight, value: 24, setID: current.id, mode: .time, in: &sets)
        XCTAssertEqual(sets.map(\.weight), [24, 24])
        XCTAssertEqual(sets.map(\.seconds), [45, 60])
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

    func testStandaloneHealthImportHasStableIdentityAndNoPlanOrExerciseRequirement() throws {
        let health = WorkoutHealth(status: "available", window_start: 1_700_000_000_000,
            window_end: 1_700_003_600_000, queried_at: 1_700_003_601_000,
            workout_id: "B7F450E5-7462-451D-BF86-4BA5F8E7B223", heart_rate_avg_bpm: 130, active_energy_kcal: 320)
        let first = try XCTUnwrap(WorkoutLogic.importedHealth(health, name: "骑行 · 健康导入"))
        let second = try XCTUnwrap(WorkoutLogic.importedHealth(health, name: "骑行 · 健康导入"))
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.health, health)
        XCTAssertTrue(first.exercises.isEmpty)
        XCTAssertEqual(first.finishedAt?.timeIntervalSince(first.startedAt), 3600)
        var invalid = health
        invalid.workout_id = nil
        XCTAssertNil(WorkoutLogic.importedHealth(invalid, name: "无效"))
        invalid = health; invalid.window_end = invalid.window_start
        XCTAssertNil(WorkoutLogic.importedHealth(invalid, name: "无效"))
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
