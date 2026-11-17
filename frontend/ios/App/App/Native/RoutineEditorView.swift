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
                            LabeledContent("组数") {
                                NumberStepper(title: "组数", value: Double(slot.setCount), bounds: 1...20, keyboard: .numberPad) { value in
                                    if let value { store.updateSlot(routineId, slot.id, setCount: Int(value.rounded())) }
                                }.frame(maxWidth: 180)
                            }
                            let mode = slot.mode ?? Catalogue.byId[slot.exerciseId]?.workoutMode ?? .reps
                            if mode == .cardio {
                                routineMetric(slot, .minutes, \.minutes, fallback: 20)
                                routineMetric(slot, .speed, \.speed, fallback: 8)
                                if WorkoutCatalogue.records[slot.exerciseId]?.incline == true {
                                    routineMetric(slot, .incline, \.incline, fallback: 0)
                                }
                            } else if mode == .time {
                                routineMetric(slot, .seconds, \.seconds, fallback: 45, minimum: 1)
                            } else {
                                LabeledContent("每组次数") {
                                    NumberStepper(title: "每组次数", value: Double(slot.reps), bounds: 1...100, keyboard: .numberPad) { value in
                                        if let value { store.updateSlot(routineId, slot.id, reps: Int(value.rounded())) }
                                    }.frame(maxWidth: 180)
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

    private func routineMetric(_ slot: RoutineExercise, _ metric: WorkoutMetric,
                               _ key: WritableKeyPath<RoutineExercise, Double?>, fallback: Double, minimum: Double = 0) -> some View {
        LabeledContent(metric.title) {
            NumberStepper(title: metric.title, value: slot[keyPath: key] ?? fallback, bounds: minimum...metric.maximum,
                          step: metric.step, keyboard: metric == .seconds ? .numberPad : .decimalPad) { value in
                if let value {
                    store.updateRoutineWorkoutFields(routineId, slotId: slot.id) { $0[keyPath: key] = value }
                }
            }.frame(maxWidth: 180)
        }
    }
}
