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
                            Stepper(value: Binding(
                                get: { store.routine(routineId)?.exercises.first { $0.id == slot.id }?.reps ?? slot.reps },
                                set: { store.updateSlot(routineId, slot.id, reps: $0) }
                            ), in: 1...100) {
                                Text("每组 \(slot.reps) 次")
                            }
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
}
