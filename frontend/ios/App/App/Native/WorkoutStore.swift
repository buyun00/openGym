import Foundation

extension GymStore {
    // Every training edit uses the same atomic persistence boundary. A failed write keeps
    // the last durable session visible, including Finish / Discard and the rest deadline.
    func mutateActive(_ change: (inout WorkoutSession) -> Void) {
        guard var session = active else { return }
        let previous = session
        change(&session)
        active = session
        if !save() { active = previous }
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
        active = WorkoutSession(id: UUID(), name: "自由训练", startedAt: Date(), finishedAt: nil, exercises: [])
        tab = .workout
        if !save() { active = nil }
    }

    func workoutExercises(from routine: Routine) -> [WorkoutExercise] {
        routine.exercises.map { slot in
            let mode = slot.mode ?? Catalogue.byId[slot.exerciseId]?.workoutMode ?? .reps
            let previous = WorkoutLogic.previous(slot.exerciseId, mode: mode, in: workouts, forProgression: true)?.1
            let completed = previous?.sets.filter(\.done) ?? []
            let sets = (0..<max(1, slot.setCount)).map { index in
                var set = WorkoutLogic.seed(mode: mode, reps: slot.reps,
                                           previous: completed.isEmpty ? nil : completed[min(index, completed.count - 1)])
                if completed.isEmpty, let weight = slot.weight { set.weight = weight }
                if let minutes = slot.minutes { set.minutes = minutes }
                if let speed = slot.speed { set.speed = speed }
                if let incline = slot.incline { set.incline = incline }
                if let seconds = slot.seconds { set.seconds = seconds }
                return set
            }
            var exercise = WorkoutExercise(id: UUID(), exerciseId: slot.exerciseId, name: slot.name, sets: sets, mode: mode)
            exercise.routineId = routine.id
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
        let sets = completed.isEmpty ? (0..<(mode == .cardio ? 1 : 3)).map { _ in WorkoutLogic.seed(mode: mode) } : completed.map(WorkoutLogic.copy)
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

    func updateWorkoutExercise(_ id: UUID, _ change: (inout WorkoutExercise) -> Void) {
        mutateActive { session in
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
        updateWorkoutExercise(exercise) { entry in
            guard let index = entry.sets.firstIndex(where: { $0.id == set }) else { return }
            entry.sets.insert(WorkoutLogic.copy(entry.sets[index]), at: index + 1)
        }
    }

    func setMetric(_ metric: WorkoutMetric, exercise: UUID, set: UUID, value: Double?) {
        updateSet(exercise: exercise, set: set) { metric.apply(value, to: &$0) }
    }

    func adjustRest(by seconds: Int) {
        mutateActive { session in
            guard let end = session.restEndsAt else { return }
            session.restEndsAt = max(Date(), end.addingTimeInterval(Double(seconds)))
        }
    }

    func updateRoutineWorkoutFields(_ routineId: UUID, slotId: UUID, _ change: (inout RoutineExercise) -> Void) {
        guard let ri = routines.firstIndex(where: { $0.id == routineId }),
              let si = routines[ri].exercises.firstIndex(where: { $0.id == slotId }) else { return }
        let previous = routines[ri].exercises[si]
        change(&routines[ri].exercises[si])
        if !save() { routines[ri].exercises[si] = previous }
    }
}
