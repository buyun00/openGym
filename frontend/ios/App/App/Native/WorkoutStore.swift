import Foundation

extension GymStore {
    // Every training edit uses the same atomic persistence boundary. A failed write keeps
    // the last durable session visible, including Finish / Discard and the rest deadline.
    func mutateActive(savingSetPlanFor exerciseID: UUID? = nil, _ change: (inout WorkoutSession) -> Void) {
        guard var session = active else { return }
        let previous = session
        let previousRoutines = routines
        change(&session)
        if let exerciseID, let entry = session.exercises.first(where: { $0.id == exerciseID }),
           let old = previous.exercises.first(where: { $0.id == exerciseID }) {
            WorkoutLogic.saveSetPlan(for: entry, previous: old, in: &routines)
        }
        session.cardioTimer = WorkoutLogic.activeCardioTimer(in: session)
        active = session
        if !save() { active = previous; routines = previousRoutines }
        restEndsAt = active?.restEndsAt
        if previous.restEndsAt != restEndsAt { refreshWorkoutAlerts() }
    }

    func updateWorkoutPreferences(_ change: (inout WorkoutPreferences) -> Void) {
        let previous = workoutPreferences
        change(&workoutPreferences)
        if !save() { workoutPreferences = previous }
        refreshWorkoutAlerts()
    }

    func setDefaultWorkoutLayout(_ layout: WorkoutLayout) {
        let previousPreferences = workoutPreferences
        let previousSession = active
        workoutPreferences.layout = layout
        active?.layout = nil
        if !save() { workoutPreferences = previousPreferences; active = previousSession }
    }

    func startFreestyle() {
        guard active == nil else { tab = .workout; return }
        cancelWorkoutStart()
        active = WorkoutSession(id: UUID(), name: "自由训练", startedAt: Date(), finishedAt: nil, exercises: [])
        tab = .workout
        if !save() { active = nil }
    }

    func workoutExercises(from routine: Routine) -> [WorkoutExercise] {
        routine.exercises.map { slot in
            let mode = slot.mode ?? Catalogue.byId[slot.exerciseId]?.workoutMode ?? .reps
            let previous = WorkoutLogic.previous(slot.exerciseId, mode: mode, in: workouts, forProgression: true)?.1
            let completed = previous?.sets.filter(\.done) ?? []
            let sets = WorkoutLogic.plannedSets(for: slot, mode: mode, previous: completed)
            var exercise = WorkoutExercise(id: UUID(), exerciseId: slot.exerciseId, name: slot.name, sets: sets, mode: mode)
            exercise.routineId = routine.id
            exercise.routineSlotId = slot.id
            exercise.note = slot.note ?? (previous?.notePinned == true ? previous?.note : nil)
            exercise.notePinned = previous?.notePinned
            return exercise
        }
    }

    func appendRoutine(_ routine: Routine) {
        let incoming = workoutExercises(from: routine)
        mutateActive { session in
            let last = session.exercises.last?.id
            WorkoutLogic.insert(incoming, after: last, into: &session)
        }
    }

    func addWorkoutExercise(_ info: ExerciseInfo, replacing id: UUID? = nil) {
        let mode = info.workoutMode
        let previous = WorkoutLogic.previous(info.id, mode: mode, in: workouts, forProgression: true)?.1
        let completed = previous?.sets.filter(\.done) ?? []
        let sets: [WorkoutSet]
        if completed.isEmpty {
            let count = mode == .cardio ? 1 : 3
            sets = (0..<count).map { _ in WorkoutLogic.seed(mode: mode) }
        } else {
            sets = completed.map { WorkoutLogic.seed(mode: mode, previous: $0) }
        }
        let incoming = WorkoutExercise(id: UUID(), exerciseId: info.id, name: info.name, sets: sets, mode: mode,
                                       note: previous?.notePinned == true ? previous?.note : nil, notePinned: previous?.notePinned)
        mutateActive { session in
            if let id, let index = session.exercises.firstIndex(where: { $0.id == id }) {
                let old = session.exercises[index]
                var replacement = incoming
                replacement.id = old.id
                replacement.routineId = old.routineId
                replacement.noProgression = old.noProgression
                session.exercises[index] = replacement
                if session.restOwner == id { session.restEndsAt = nil; session.restOwner = nil; session.restSetOwner = nil }
            } else if id == nil {
                WorkoutLogic.insert([incoming], after: session.selectedExerciseId, into: &session)
            }
        }
    }

    func updateWorkoutExercise(_ id: UUID, savingSetPlan: Bool = false, _ change: (inout WorkoutExercise) -> Void) {
        mutateActive(savingSetPlanFor: savingSetPlan ? id : nil) { session in
            guard let index = session.exercises.firstIndex(where: { $0.id == id }) else { return }
            change(&session.exercises[index])
        }
    }

    func removeWorkoutExercise(_ id: UUID) { mutateActive { WorkoutLogic.remove(id, from: &$0) } }

    func moveWorkoutExercise(_ id: UUID, by offset: Int) {
        mutateActive { session in
            guard let index = session.exercises.firstIndex(where: { $0.id == id }), session.exercises.indices.contains(index + offset) else { return }
            session.exercises.swapAt(index, index + offset)
        }
    }

    func copySet(exercise: UUID, set: UUID) {
        updateWorkoutExercise(exercise, savingSetPlan: true) { entry in
            guard let index = entry.sets.firstIndex(where: { $0.id == set }) else { return }
            entry.sets.insert(WorkoutLogic.copy(entry.sets[index]), at: index + 1)
        }
    }

    func setMetric(_ metric: WorkoutMetric, exercise: UUID, set: UUID, value: Double?) {
        updateWorkoutExercise(exercise, savingSetPlan: metric == .weight) { entry in
            let mode = entry.mode ?? WorkoutCatalogue.records[entry.exerciseId]?.mode ?? .reps
            WorkoutLogic.updateMetric(metric, value: value, setID: set, mode: mode, in: &entry.sets)
        }
    }

    func adjustRest(by seconds: Int) {
        mutateActive { session in
            guard let end = session.restEndsAt else { return }
            let adjusted = end.addingTimeInterval(Double(seconds))
            if adjusted > .now { session.restEndsAt = adjusted }
            else { session.restEndsAt = nil; session.restOwner = nil; session.restSetOwner = nil }
        }
    }

    func startCardioTimer(exercise exerciseID: UUID, set setID: UUID) {
        guard let exercise = active?.exercises.first(where: { $0.id == exerciseID }),
              (exercise.mode ?? WorkoutCatalogue.records[exercise.exerciseId]?.mode) == .cardio,
              let timer = WorkoutLogic.cardioTimer(exercise: exercise, setID: setID, now: .now) else { return }
        mutateActive { session in
            session.cardioTimer = timer
            session.selectedExerciseId = exerciseID
            session.restEndsAt = nil
            session.restOwner = nil
            session.restSetOwner = nil
        }
    }

    func stopCardioTimer(_ timer: WorkoutCardioTimer) {
        guard active?.cardioTimer == timer else { return }
        mutateActive { $0.cardioTimer = nil }
    }

    func updateRoutineWorkoutFields(_ routineId: UUID, slotId: UUID, _ change: (inout RoutineExercise) -> Void) {
        guard let ri = routines.firstIndex(where: { $0.id == routineId }),
              let si = routines[ri].exercises.firstIndex(where: { $0.id == slotId }) else { return }
        let previous = routines[ri].exercises[si]
        change(&routines[ri].exercises[si])
        if !save() { routines[ri].exercises[si] = previous }
    }
}
