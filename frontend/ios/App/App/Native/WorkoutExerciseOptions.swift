import SwiftUI

struct WorkoutExerciseOptions: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var exerciseId: UUID
    @State private var removing = false
    @State private var replacing = false
    private var exercise: WorkoutExercise? { store.active?.exercises.first { $0.id == exerciseId } }

    var body: some View {
        NavigationStack {
            List {
                if let exercise {
                    Section {
                        NavigationLink { instructions(exercise) } label: {
                            Label("动作说明", systemImage: "info.circle")
                        }
                        NavigationLink { WorkoutExerciseHistory(exerciseId: exercise.exerciseId) } label: {
                            Label("历史记录", systemImage: "clock.arrow.circlepath")
                        }
                        NavigationLink {
                            WorkoutTextEditor(title: "动作备注", initial: exercise.note ?? "") { text in
                                store.updateWorkoutExercise(exerciseId) { $0.note = text.isEmpty ? nil : text }
                                if store.saveError == nil { dismiss() }
                            }
                        } label: {
                            Label("动作备注", systemImage: "note.text")
                        }
                        Toggle("下次显示此备注", isOn: Binding(get: { self.exercise?.notePinned == true }, set: { value in store.updateWorkoutExercise(exerciseId) { $0.notePinned = value } }))
                    }
                    Section("本次训练") {
                        Button("替换动作", systemImage: "arrow.triangle.2.circlepath") { replacing = true }
                        let index = store.active?.exercises.firstIndex(where: { $0.id == exerciseId }) ?? 0
                        Button("上移动作", systemImage: "arrow.up") { store.moveWorkoutExercise(exerciseId, by: -1) }.disabled(index == 0)
                        Button("下移动作", systemImage: "arrow.down") { store.moveWorkoutExercise(exerciseId, by: 1) }.disabled(index + 1 >= (store.active?.exercises.count ?? 0))
                        Picker("记录方式", selection: Binding(get: { self.exercise?.mode ?? WorkoutCatalogue.records[exercise.exerciseId]?.mode ?? .reps }, set: { mode in
                            store.updateWorkoutExercise(exerciseId) { entry in
                                entry.mode = mode
                                entry.sets = entry.sets.map { _ in WorkoutLogic.seed(mode: mode) }
                            }
                        })) {
                            ForEach(WorkoutMode.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.disabled(exercise.sets.contains(where: \.done))
                        Toggle("使用默认休息", isOn: Binding(get: { self.exercise?.restSeconds == nil }, set: { value in
                            store.updateWorkoutExercise(exerciseId) { $0.restSeconds = value ? nil : store.restSeconds }
                        }))
                        if let seconds = exercise.restSeconds {
                            Stepper("休息 \(workoutClock(Double(seconds)))", value: Binding(get: { self.exercise?.restSeconds ?? seconds }, set: { value in store.updateWorkoutExercise(exerciseId) { $0.restSeconds = value } }), in: 0...3600, step: 15)
                        }
                        Toggle("此动作不计入进阶", isOn: Binding(get: { self.exercise?.noProgression == true }, set: { value in
                            store.mutateActive { session in
                                guard let index = session.exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
                                session.exercises[index].noProgression = value
                                session.noProgression = session.exercises.allSatisfy { $0.noProgression == true }
                            }
                        }))
                    }
                    Section { Button("移除动作", systemImage: "trash", role: .destructive) { removing = true } }
                }
            }
            .navigationTitle("动作选项").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
            .confirmationDialog("移除此动作和本次已记录的组？", isPresented: $removing, titleVisibility: .visible) {
                Button("移除动作", role: .destructive) { store.removeWorkoutExercise(exerciseId); if store.saveError == nil { dismiss() } }
            }
            .confirmationDialog("替换会清除这个动作的本次组记录", isPresented: $replacing, titleVisibility: .visible) {
                Button("继续替换", role: .destructive) { showPicker = true }
            }
            .navigationDestination(isPresented: $showPicker) {
                WorkoutExercisePicker { info in
                    store.addWorkoutExercise(info, replacing: exerciseId)
                    if store.saveError == nil { dismiss() }
                }
            }
        }
        .alert("记录未保存", isPresented: Binding(get: { store.saveError != nil }, set: { if !$0 { store.saveError = nil } })) {
            Button("好") { store.saveError = nil }
        } message: { Text(store.saveError ?? "") }
    }
    @State private var showPicker = false

    private func instructions(_ exercise: WorkoutExercise) -> some View {
        List {
            let record = WorkoutCatalogue.records[exercise.exerciseId]
            WorkoutMediaView(record: record)
            if let instructions = record?.instructions, !instructions.isEmpty {
                ForEach(Array(instructions.enumerated()), id: \.offset) { index, text in
                    Text("\(index + 1). \(text)")
                }
            } else { Text("此动作暂无说明").foregroundStyle(.secondary) }
        }.navigationTitle("动作说明")
    }
}

struct WorkoutExerciseHistory: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var exerciseId: String
    private var sessions: [WorkoutSession] {
        store.finishedWorkouts.filter { $0.exercises.contains { $0.exerciseId == exerciseId && $0.sets.contains(where: \.done) } }
    }
    var body: some View {
        List {
            if sessions.isEmpty { ContentUnavailableView("还没有记录", systemImage: "clock.arrow.circlepath") }
            ForEach(sessions) { session in
                Section(session.startedAt.formatted(.dateTime.year().month().day())) {
                    ForEach(session.exercises.filter { $0.exerciseId == exerciseId }) { exercise in
                        ForEach(exercise.sets.filter(\.done)) { set in
                            Text(WorkoutLogic.summary(set, mode: exercise.mode ?? .reps)).monospacedDigit()
                        }
                        if let note = exercise.note, !note.isEmpty { Text(note).foregroundStyle(.secondary) }
                        if exercise.noProgression == true { Text("不计入进阶").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }.navigationTitle("历史记录").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
    }
}
