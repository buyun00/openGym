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
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var sheet: WorkoutSheet?
    @State private var discardSessionId: UUID?
    @State private var confirmingDiscard = false
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
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if let session = store.active {
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
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
                    .frame(maxWidth: 760).frame(maxWidth: .infinity).id("workout-top")
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let session = store.active {
                        VStack(spacing: 4) {
                            if typeSize.isAccessibilitySize {
                                Text(session.name).font(.headline).lineLimit(2)
                                workoutStatus
                            }
                            if !session.exercises.isEmpty { exerciseSelector(session, proxy: proxy) }
                        }
                        .padding(.horizontal, 16).padding(.bottom, 4)
                        .frame(maxWidth: .infinity).background(.bar)
                    }
                }
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
            .sheet(item: $sheet, onDismiss: sheetDidDismiss) { destination in
                WorkoutSessionSheet(destination: destination, requestDiscard: requestDiscard)
                    .presentationDetents(destination == .finish && !typeSize.isAccessibilitySize ? [.height(400), .large] : [.large])
                    .presentationDragIndicator(.visible)
            }
            .alert("记录未保存", isPresented: Binding(get: { store.saveError != nil && sheet == nil && discardSessionId == nil && !confirmingDiscard }, set: { if !$0 { store.saveError = nil } })) {
                Button("好") { store.saveError = nil }
            } message: { Text(store.saveError ?? "") }
        }
        .tint(.green)
        .alert("放弃本次训练？", isPresented: $confirmingDiscard) {
            Button("放弃不保存", role: .destructive) {
                if let id = discardSessionId, store.active?.id == id { store.discardActive() }
                discardSessionId = nil
            }
            Button("取消", role: .cancel) { discardSessionId = nil }
        } message: { Text("本次训练的记录将被删除且不会保存。此前的训练历史不受影响。") }
        .onChange(of: store.active?.id) { _, id in
            if id != discardSessionId { discardSessionId = nil; confirmingDiscard = false }
            if id == nil { dismiss() }
        }
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
                Text(typeSize.isAccessibilitySize ? "训练中" : store.active?.name ?? "训练")
                    .font(.headline).lineLimit(1).truncationMode(.tail)
                if !typeSize.isAccessibilitySize { workoutStatus }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("训练菜单", systemImage: "ellipsis") { sheet = .menu }.labelStyle(.iconOnly)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("结束") { sheet = .finish }.fixedSize()
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("完成") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        }
    }

    private var workoutStatus: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text("\(workoutClock(context.date.timeIntervalSince(store.active?.startedAt ?? context.date))) · \(store.activeDoneCount)/\(store.activeSetCount) 组")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                .accessibilityLabel("训练用时 \(workoutClock(context.date.timeIntervalSince(store.active?.startedAt ?? context.date)))，已完成 \(store.activeDoneCount) / \(store.activeSetCount) 组")
        }
    }

    private func exerciseSelector(_ session: WorkoutSession, proxy: ScrollViewProxy) -> some View {
        WorkoutExerciseSelector(exercises: session.exercises, selection: Binding(get: { selected?.id }, set: { id in
            store.mutateActive { $0.selectedExerciseId = id }
            if layout != .cards, let id { proxy.scrollTo(id, anchor: .top) }
        }))
    }

    private func requestDiscard() {
        discardSessionId = store.active?.id
        sheet = nil
    }

    private func sheetDidDismiss() {
        // Present only after the sheet is gone; confirmation must never anchor to its button.
        if let id = discardSessionId, store.active?.id == id { confirmingDiscard = true }
        else { discardSessionId = nil }
    }

    private func navigation(_ session: WorkoutSession) -> some View {
        let index = session.exercises.firstIndex(where: { $0.id == selected?.id }) ?? 0
        return HStack {
            Button("上一个", systemImage: "chevron.left") { select(index - 1, session) }.disabled(index == 0)
            Spacer()
            Button { select(index + 1, session) } label: { HStack { Text("下一个"); Image(systemName: "chevron.right") } }
                .disabled(index + 1 >= session.exercises.count)
        }.buttonStyle(.bordered).controlSize(.large)
    }

    private func select(_ index: Int, _ session: WorkoutSession) {
        guard session.exercises.indices.contains(index) else { return }
        store.mutateActive { $0.selectedExerciseId = session.exercises[index].id }
    }

    private func footer(_ session: WorkoutSession) -> some View {
        VStack(spacing: 20) {
            Button("添加动作", systemImage: "plus") { sheet = .addExercise }.buttonStyle(.borderedProminent)
            Button(session.note?.isEmpty == false ? "编辑训练备注" : "添加训练备注", systemImage: "note.text") { sheet = .note }.buttonStyle(.bordered)
            if let note = session.note, !note.isEmpty { Text(note).font(.subheadline).foregroundStyle(.secondary) }
            let completed = session.exercises.filter { !$0.sets.isEmpty && $0.sets.allSatisfy(\.done) }.count
            Button("\(store.activeDoneCount < store.activeSetCount ? "提前结束" : "结束训练") · \(completed)/\(session.exercises.count) 个动作") { sheet = .finish }
                .buttonStyle(.bordered)
        }.frame(maxWidth: .infinity).padding(.vertical, 12)
    }

    private func updateAwake() { UIApplication.shared.isIdleTimerDisabled = scenePhase == .active && store.workoutPreferences.keepAwake }
}

private struct WorkoutExerciseSelector: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var exercises: [WorkoutExercise]
    @Binding var selection: UUID?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if exercises.count <= 5 && !typeSize.isAccessibilitySize {
                Picker("切换动作", selection: $selection) {
                    ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                        Text("\(index + 1)\(isDone(exercise) ? " ✓" : "")")
                            .tag(Optional(exercise.id)).accessibilityLabel(label(index, exercise))
                    }
                }
                .pickerStyle(.segmented).controlSize(.large).labelsHidden()
                .frame(minWidth: CGFloat(exercises.count) * 56, minHeight: 44)
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                            Button { selection = exercise.id } label: {
                                VStack(spacing: 1) {
                                    Text("\(index + 1)").font(.body.bold()).monospacedDigit()
                                    if isDone(exercise) { Image(systemName: "checkmark").font(.caption2.bold()) }
                                }
                                .frame(minWidth: 44, minHeight: 44)
                                .padding(.horizontal, 2)
                                .background(selection == exercise.id ? Color.green.opacity(0.16) : .clear, in: .rect(cornerRadius: 10))
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain).foregroundStyle(selection == exercise.id ? .primary : .secondary)
                            .accessibilityLabel(label(index, exercise))
                            .accessibilityAddTraits(selection == exercise.id ? .isSelected : [])
                            .id(exercise.id)
                        }
                    }
                }
                .onAppear { if let selection { proxy.scrollTo(selection, anchor: .center) } }
                .onChange(of: selection) { _, id in if let id { proxy.scrollTo(id, anchor: .center) } }
            }
        }
    }

    private func isDone(_ exercise: WorkoutExercise) -> Bool { !exercise.sets.isEmpty && exercise.sets.allSatisfy(\.done) }
    private func label(_ index: Int, _ exercise: WorkoutExercise) -> String {
        "动作 \(index + 1)，\(exercise.name)\(isDone(exercise) ? "，已完成" : "")"
    }
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
            }.buttonStyle(.bordered).padding(12)
        }
    }
}

func workoutClock(_ interval: TimeInterval) -> String {
    let seconds = max(0, Int(interval))
    return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) : String(format: "%d:%02d", seconds / 60, seconds % 60)
}
