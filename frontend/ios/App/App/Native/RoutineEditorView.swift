import SwiftUI

struct RoutineEditorView: View {
    @Environment(GymStore.self) private var store
    var routineId: UUID

    var body: some View {
        List {
            if let routine = store.routine(routineId) {
                Section("名称") {
                    TextField("计划名称", text: Binding(
                        get: { store.routine(routineId)?.name ?? "" },
                        set: { store.rename(routineId, to: $0) }
                    ))
                }
                Section("动作") {
                    ForEach(routine.exercises) { slot in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(slot.name)
                                .font(.headline)
                            Stepper(value: Binding(
                                get: { store.routine(routineId)?.exercises.first { $0.id == slot.id }?.setCount ?? slot.setCount },
                                set: { store.updateSlot(routineId, slot.id, setCount: $0) }
                            ), in: 1...20) {
                                Text("\(slot.setCount) 组")
                            }
                            let mode = slot.mode ?? Catalogue.byId[slot.exerciseId]?.workoutMode ?? .reps
                            if mode == .cardio {
                                Stepper("时长 \(formatKg(slot.minutes ?? 20)) 分钟", value: routineMetric(slot, \.minutes, fallback: 20), in: 0...600, step: 1)
                                Stepper("速度 \(formatKg(slot.speed ?? 8)) km/h", value: routineMetric(slot, \.speed, fallback: 8), in: 0...100, step: 0.1)
                                if WorkoutCatalogue.records[slot.exerciseId]?.incline == true {
                                    Stepper("坡度 \(formatKg(slot.incline ?? 0))%", value: routineMetric(slot, \.incline, fallback: 0), in: 0...40, step: 0.5)
                                }
                            } else if mode == .time {
                                Stepper("保持 \(formatKg(slot.seconds ?? 45)) 秒", value: routineMetric(slot, \.seconds, fallback: 45), in: 1...3600)
                            } else {
                            Stepper(value: Binding(
                                get: { store.routine(routineId)?.exercises.first { $0.id == slot.id }?.reps ?? slot.reps },
                                set: { store.updateSlot(routineId, slot.id, reps: $0) }
                            ), in: 1...100) {
                                Text("每组 \(slot.reps) 次")
                            }
                            }
                            TextField("动作备注", text: Binding(get: {
                                store.routine(routineId)?.exercises.first { $0.id == slot.id }?.note ?? ""
                            }, set: { value in store.updateRoutineWorkoutFields(routineId, slotId: slot.id) { $0.note = value } }))
                        }
                        .swipeActions {
                            Button("删除", role: .destructive) {
                                store.removeExercise(slot.id, from: routineId)
                            }
                        }
                    }
                    NavigationLink {
                        LibraryView { info in
                            store.addExercise(info, to: routineId)
                        }
                    } label: {
                        Label("加动作", systemImage: "plus")
                    }
                }
            } else {
                ContentUnavailableView("计划已经删掉了", systemImage: "calendar")
            }
        }
        .navigationTitle(store.routine(routineId)?.name ?? "计划")
    }

    private func routineMetric(_ slot: RoutineExercise, _ key: WritableKeyPath<RoutineExercise, Double?>, fallback: Double) -> Binding<Double> {
        Binding(get: { store.routine(routineId)?.exercises.first { $0.id == slot.id }?[keyPath: key] ?? fallback },
                set: { value in store.updateRoutineWorkoutFields(routineId, slotId: slot.id) { $0[keyPath: key] = value } })
    }
}
