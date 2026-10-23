import SwiftUI

struct WorkoutView: View {
    @Environment(GymStore.self) private var store
    @State private var showFinish = false
    @State private var showDiscard = false

    var body: some View {
        NavigationStack {
            Group {
                if store.active != nil {
                    activeList
                } else {
                    idleList
                }
            }
            .navigationTitle(store.active?.name ?? "开始")
            .navigationSubtitle(store.active == nil ? "选一个计划" : "\(store.activeDoneCount) / \(store.activeSetCount) 组")
            .toolbar {
                if store.active != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("更多", systemImage: "ellipsis.circle") {
                            Button("结束并保存") { showFinish = true }
                            Button("放弃这次训练", role: .destructive) { showDiscard = true }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .confirmationDialog("结束并保存这次训练？", isPresented: $showFinish, titleVisibility: .visible) {
                Button("保存") { store.finishActive() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("已完成 \(store.activeDoneCount) / \(store.activeSetCount) 组。")
            }
            .confirmationDialog("放弃这次训练？", isPresented: $showDiscard, titleVisibility: .visible) {
                Button("放弃", role: .destructive) { store.discardActive() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("这次的组数不会记下来。")
            }
        }
    }

    private var idleList: some View {
        List {
            Section("今天") {
                if store.todayRoutines.isEmpty {
                    Text("今天没有安排")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.todayRoutines) { routine in
                        Button {
                            store.start([routine])
                        } label: {
                            routineLabel(routine)
                        }
                    }
                }
            }
            Section("全部计划") {
                if store.routines.isEmpty {
                    ContentUnavailableView("还没有计划", systemImage: "calendar", description: Text("先到计划页建一个，再回来开始。"))
                }
                ForEach(store.routines) { routine in
                    Button {
                        store.start([routine])
                    } label: {
                        routineLabel(routine)
                    }
                }
            }
        }
    }

    private var activeList: some View {
        List {
            if let session = store.active {
                ForEach(session.exercises) { exercise in
                    Section(exercise.name) {
                        ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                            setRow(exercise: exercise, set: set, index: index + 1)
                                .swipeActions {
                                    Button("删除", role: .destructive) {
                                        store.deleteSet(exercise: exercise.id, set: set.id)
                                    }
                                }
                        }
                        Button("加一组", systemImage: "plus") {
                            store.addSet(exercise: exercise.id)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        if let end = store.restEndsAt {
            RestBanner(end: end) { store.clearRest() }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        } else if store.active == nil, !store.todayRoutines.isEmpty {
            Button("开始今天的训练") { store.startToday() }
                .buttonStyle(.glassProminent)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
    }

    private func routineLabel(_ routine: Routine) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(routine.name)
                .foregroundStyle(.primary)
            Text(routine.exercises.isEmpty ? "还没有动作" : "\(routine.exercises.count) 个动作")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func setRow(exercise: WorkoutExercise, set: WorkoutSet, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("第 \(index) 组")
                    .font(.headline)
                Spacer()
                Button {
                    store.toggleSet(exercise: exercise.id, set: set.id)
                } label: {
                    Image(systemName: set.done ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.glass)
                .tint(set.done ? .green : .primary)
                .accessibilityLabel(set.done ? "已完成" : "完成本组")
            }
            Stepper(value: weightBinding(exercise.id, set.id, fallback: set.weight), in: 0...500, step: 1.25) {
                Text("重量 \(formatKg(set.weight)) kg")
            }
            Stepper(value: repsBinding(exercise.id, set.id, fallback: set.reps), in: 0...100) {
                Text("次数 \(set.reps)")
            }
        }
        .padding(.vertical, 4)
    }

    private func weightBinding(_ exercise: UUID, _ set: UUID, fallback: Double) -> Binding<Double> {
        Binding(
            get: { liveSet(exercise, set)?.weight ?? fallback },
            set: { store.setWeight(exercise: exercise, set: set, weight: $0) }
        )
    }

    private func repsBinding(_ exercise: UUID, _ set: UUID, fallback: Int) -> Binding<Int> {
        Binding(
            get: { liveSet(exercise, set)?.reps ?? fallback },
            set: { store.setReps(exercise: exercise, set: set, reps: $0) }
        )
    }

    private func liveSet(_ exercise: UUID, _ set: UUID) -> WorkoutSet? {
        store.active?.exercises.first { $0.id == exercise }?.sets.first { $0.id == set }
    }
}

private struct RestBanner: View {
    var end: Date
    var onStop: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let left = max(0, Int(end.timeIntervalSince(context.date).rounded(.up)))
            HStack(spacing: 12) {
                Image(systemName: "timer")
                Text(left == 0 ? "休息结束" : "休息 \(left) 秒")
                    .font(.headline)
                    .monospacedDigit()
                Spacer()
                Button("跳过", action: onStop)
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
        }
        .task(id: end) {
            let delay = end.timeIntervalSinceNow
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            if !Task.isCancelled { onStop() }
        }
    }
}
