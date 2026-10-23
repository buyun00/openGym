import SwiftUI
import UIKit

struct WorkoutView: View {
    @Environment(GymStore.self) private var store
    @State private var presenting = false

    var body: some View {
        NavigationStack {
            List {
                if let session = store.active {
                    Section {
                        Button { presenting = true } label: { Label("继续：\(session.name)", systemImage: "play.fill") }
                        Text("已完成 \(store.activeDoneCount) / \(store.activeSetCount) 组").foregroundStyle(.secondary)
                    }
                } else {
                    if !store.todayRoutines.isEmpty {
                        Section("今天的计划") {
                            ForEach(store.todayRoutines) { routine in
                                Button { store.start([routine]) } label: { routineLabel(routine) }
                            }
                            if store.todayRoutines.count > 1 {
                                Button("开始今天的全部训练", systemImage: "play.fill") { store.startToday() }
                            }
                        }
                    }
                    Section("其他训练日") {
                        ForEach(store.routines.filter { routine in !store.todayRoutines.contains(where: { $0.id == routine.id }) }) { routine in
                            Button { store.start([routine]) } label: { routineLabel(routine) }
                        }
                        if store.routines.isEmpty {
                            ContentUnavailableView("还没有计划", systemImage: "calendar", description: Text("可以先去计划页安排，或从自由训练开始。"))
                        }
                    }
                    Section {
                        Button("自由训练，边练边加动作", systemImage: "plus") { store.startFreestyle() }
                    }
                }
            }
            .navigationTitle("开始锻炼")
        }
        .tint(.green)
        .onAppear { if store.tab == .workout && store.active != nil { presenting = true } }
        .onChange(of: store.tab) { _, tab in if tab == .workout && store.active != nil { presenting = true } }
        .onChange(of: store.active?.id) { _, id in presenting = id != nil }
        .fullScreenCover(isPresented: $presenting) { ActiveWorkoutView().environment(store) }
        .alert("记录未保存", isPresented: Binding(get: { store.saveError != nil && !presenting }, set: { if !$0 { store.saveError = nil } })) {
            Button("好") { store.saveError = nil }
        } message: { Text(store.saveError ?? "") }
    }

    private func routineLabel(_ routine: Routine) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(routine.name).foregroundStyle(.primary)
            Text("\(routine.exercises.count) 个动作").font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

enum WorkoutSheet: Identifiable, Equatable {
    case menu, settings, addExercise, addRoutine, rename, layout, note, finish
    var id: String { String(describing: self) }
}

struct ActiveWorkoutView: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheet: WorkoutSheet?
    @State private var flashing = false
    @State private var previousIdleDisabled: Bool?

    private var layout: WorkoutLayout { store.active?.layout ?? store.workoutPreferences.layout }
    private var selected: WorkoutExercise? {
        guard let session = store.active else { return nil }
        return session.exercises.first { $0.id == session.selectedExerciseId } ?? session.exercises.first
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        Color.clear.frame(height: 0).id("workout-top")
                        ProgressView(value: Double(store.activeDoneCount), total: Double(max(1, store.activeSetCount)))
                            .accessibilityLabel("训练进度")
                        if let session = store.active {
                            exerciseSelector(session, proxy: proxy)
                            if session.exercises.isEmpty {
                                ContentUnavailableView("添加第一个动作", systemImage: "figure.strengthtraining.traditional", description: Text("从动作库选择，或把一个训练日并入本次训练。"))
                            } else if layout == .cards, let exercise = selected {
                                WorkoutExerciseCard(exercise: exercise, compact: false).id(exercise.id)
                                navigation(session)
                            } else {
                                ForEach(session.exercises) { exercise in
                                    WorkoutExerciseCard(exercise: exercise, compact: layout == .compact).id(exercise.id)
                                    Divider()
                                }
                            }
                            footer(session)
                        }
                    }
                    .padding(16).frame(maxWidth: 760).frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: store.active?.selectedExerciseId) { _, _ in
                    if layout == .cards { proxy.scrollTo("workout-top", anchor: .top) }
                }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .safeAreaBar(edge: .bottom) {
                if let end = store.restEndsAt, end > Date() { WorkoutRestBar(end: end) }
            }
            .overlay { if flashing { Color.green.opacity(0.15).ignoresSafeArea().allowsHitTesting(false) } }
            .sheet(item: $sheet) { destination in
                WorkoutSessionSheet(destination: destination)
                    .presentationDetents(destination == .finish ? [.height(310), .medium] : [.large])
                    .presentationDragIndicator(.visible)
            }
            .alert("记录未保存", isPresented: Binding(get: { store.saveError != nil && sheet == nil }, set: { if !$0 { store.saveError = nil } })) {
                Button("好") { store.saveError = nil }
            } message: { Text(store.saveError ?? "") }
        }
        .tint(.green)
        .onChange(of: store.active?.id) { _, id in if id == nil { dismiss() } }
        .onAppear { previousIdleDisabled = UIApplication.shared.isIdleTimerDisabled; updateAwake() }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = previousIdleDisabled ?? false }
        .onChange(of: store.workoutPreferences.keepAwake) { _, _ in updateAwake() }
        .onChange(of: scenePhase) { _, phase in
            updateAwake()
            if phase == .active { store.refreshWorkoutAlerts() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutRestFinished)) { _ in
            guard store.workoutPreferences.flash, !reduceMotion, scenePhase == .active else { return }
            flashing = true
        }
        .task(id: flashing) {
            guard flashing else { return }
            try? await Task.sleep(for: .milliseconds(300))
            flashing = false
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("收起训练", systemImage: "chevron.down") { store.tab = .today; dismiss() }.labelStyle(.iconOnly)
        }
        ToolbarItem(placement: .principal) {
            VStack(spacing: 2) {
                Text(store.active?.name ?? "训练").font(.headline).lineLimit(1)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("\(workoutClock(context.date.timeIntervalSince(store.active?.startedAt ?? context.date))) · \(store.activeDoneCount)/\(store.activeSetCount) 组")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("训练菜单", systemImage: "ellipsis") { sheet = .menu }.labelStyle(.iconOnly)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("结束") { sheet = .finish }.buttonStyle(.glassProminent)
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("完成") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        }
    }

    private func exerciseSelector(_ session: WorkoutSession, proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 8) {
                    ForEach(Array(session.exercises.enumerated()), id: \.element.id) { index, exercise in
                        let isSelected = exercise.id == selected?.id
                        let done = !exercise.sets.isEmpty && exercise.sets.allSatisfy(\.done)
                        Button {
                            store.mutateActive { $0.selectedExerciseId = exercise.id }
                            if layout != .cards { proxy.scrollTo(exercise.id, anchor: .top) }
                        } label: {
                            Group {
                                if done { Image(systemName: "checkmark") } else { Text("\(index + 1)") }
                            }.font(.headline).frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(isSelected ? .green : nil).interactive(), in: .circle)
                        .accessibilityLabel("动作 \(index + 1)，\(exercise.name)\(done ? "，已完成" : "")")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }.padding(.vertical, 3)
            }
        }
    }

    private func navigation(_ session: WorkoutSession) -> some View {
        let index = session.exercises.firstIndex(where: { $0.id == selected?.id }) ?? 0
        return HStack {
            Button("上一个", systemImage: "chevron.left") { select(index - 1, session) }.disabled(index == 0)
            Spacer()
            Button { select(index + 1, session) } label: { HStack { Text("下一个"); Image(systemName: "chevron.right") } }
                .disabled(index + 1 >= session.exercises.count)
        }.buttonStyle(.glass).controlSize(.large)
    }

    private func select(_ index: Int, _ session: WorkoutSession) {
        guard session.exercises.indices.contains(index) else { return }
        store.mutateActive { $0.selectedExerciseId = session.exercises[index].id }
    }

    private func footer(_ session: WorkoutSession) -> some View {
        VStack(spacing: 20) {
            Button("添加动作", systemImage: "plus") { sheet = .addExercise }.buttonStyle(.glass)
            Button(session.note?.isEmpty == false ? "编辑训练备注" : "添加训练备注", systemImage: "note.text") { sheet = .note }.buttonStyle(.glass)
            if let note = session.note, !note.isEmpty { Text(note).font(.subheadline).foregroundStyle(.secondary) }
            let completed = session.exercises.filter { !$0.sets.isEmpty && $0.sets.allSatisfy(\.done) }.count
            Button("\(store.activeDoneCount < store.activeSetCount ? "提前结束" : "结束训练") · \(completed)/\(session.exercises.count) 个动作") { sheet = .finish }
                .buttonStyle(.glass)
        }.frame(maxWidth: .infinity).padding(.vertical, 12)
    }

    private func updateAwake() { UIApplication.shared.isIdleTimerDisabled = scenePhase == .active && store.workoutPreferences.keepAwake }
}

struct WorkoutRestBar: View {
    @Environment(GymStore.self) private var store
    var end: Date
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack {
                Label(workoutClock(end.timeIntervalSince(context.date)), systemImage: "timer").monospacedDigit().font(.headline)
                Spacer()
                Button("减 15 秒", systemImage: "minus") { store.adjustRest(by: -15) }.labelStyle(.iconOnly)
                Button("加 15 秒", systemImage: "plus") { store.adjustRest(by: 15) }.labelStyle(.iconOnly)
                Button("跳过") { store.clearRest() }
            }.buttonStyle(.glass).padding(12)
        }
    }
}

func workoutClock(_ interval: TimeInterval) -> String {
    let seconds = max(0, Int(interval))
    return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) : String(format: "%d:%02d", seconds / 60, seconds % 60)
}
