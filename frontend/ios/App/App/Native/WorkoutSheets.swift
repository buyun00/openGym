import SwiftUI
import UserNotifications

struct WorkoutSessionSheet: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var destination: WorkoutSheet
    var requestDiscard: () -> Void

    var body: some View {
        NavigationStack {
            WorkoutSheetContent(destination: destination, close: { dismiss() }, discard: requestDiscard)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) } }
        }
        .alert("记录未保存", isPresented: Binding(get: { store.saveError != nil }, set: { if !$0 { store.saveError = nil } })) {
            Button("好") { store.saveError = nil }
        } message: { Text(store.saveError ?? "") }
    }
}

private struct WorkoutSheetContent: View {
    @Environment(GymStore.self) private var store
    var destination: WorkoutSheet
    var close: () -> Void
    var discard: () -> Void

    var body: some View {
        Group {
            switch destination {
            case .menu: menu
            case .settings: WorkoutSettingsForm()
            case .addExercise: WorkoutExercisePicker { store.addWorkoutExercise($0); if store.saveError == nil { close() } }
            case .addRoutine: routines
            case .rename: WorkoutTextEditor(title: "重命名训练", initial: store.active?.name ?? "", multiline: false) { value in
                store.mutateActive { $0.name = value }; if store.saveError == nil { close() }
            }
            case .note: WorkoutTextEditor(title: "训练备注", initial: store.active?.note ?? "") { value in
                store.mutateActive { $0.note = value.isEmpty ? nil : value }; if store.saveError == nil { close() }
            }
            case .layout: layout
            case .finish: finish
            }
        }.navigationBarTitleDisplayMode(.inline)
    }

    private func link(_ destination: WorkoutSheet, _ title: String, _ icon: String, detail: String? = nil) -> some View {
        NavigationLink {
            WorkoutSheetContent(destination: destination, close: close, discard: discard)
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                    if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
                }
            } icon: { Image(systemName: icon).foregroundStyle(.green) }
        }
    }

    private var menu: some View {
        List {
            Section {
                link(.settings, "训练设置", "gearshape", detail: "休息 \(workoutClock(Double(store.restSeconds))) · \(store.workoutPreferences.sound ? "提示音" : "静音")")
            }
            Section("添加") {
                link(.addExercise, "添加动作", "plus.circle")
                link(.addRoutine, "添加训练日", "calendar.badge.plus", detail: "把另一个训练日并入本次训练")
            }
            Section("本次训练") {
                link(.rename, "重命名训练", "pencil")
                link(.layout, "布局", "rectangle.split.1x2", detail: (store.active?.layout ?? store.workoutPreferences.layout).title)
                link(.note, store.active?.note?.isEmpty == false ? "编辑训练备注" : "添加训练备注", "note.text")
                Toggle(isOn: Binding(get: {
                    store.active?.noProgression == true || (store.active?.exercises.isEmpty == false && store.active?.exercises.allSatisfy { $0.noProgression == true } == true)
                }, set: { value in store.mutateActive { WorkoutLogic.setExcluded(value, session: &$0) } })) {
                    VStack(alignment: .leading) {
                        Text("不计入进阶")
                        Text("本次训练的所有动作").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            Section { Button("放弃训练", systemImage: "trash", role: .destructive, action: discard) }
        }.navigationTitle("训练菜单")
    }

    private var routines: some View {
        List {
            if store.routines.isEmpty { ContentUnavailableView("还没有训练日", systemImage: "calendar", description: Text("先在计划页建立训练日，也可以直接添加动作。")) }
            ForEach(store.routines) { routine in
                Button {
                    store.appendRoutine(routine)
                    if store.saveError == nil { close() }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(routine.name)
                        Text("\(routine.exercises.count) 个动作").font(.caption).foregroundStyle(.secondary)
                    }
                }.disabled(routine.exercises.isEmpty)
            }
        }.navigationTitle("添加训练日")
    }

    private var layout: some View {
        Form {
            Picker("本次训练布局", selection: Binding(get: { store.active?.layout ?? store.workoutPreferences.layout }, set: { value in store.mutateActive { $0.layout = value } })) {
                ForEach(WorkoutLayout.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.inline)
        }.navigationTitle("布局")
    }

    private var finish: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if store.activeDoneCount == 0 {
                    Text("你还没有勾选任何组。仍要结束训练吗？").foregroundStyle(.secondary)
                } else if store.activeDoneCount < store.activeSetCount {
                    Text("还有 \(store.activeSetCount - store.activeDoneCount) 组未完成，仍要结束训练吗？").foregroundStyle(.secondary)
                } else { Text("已完成 \(store.activeDoneCount) 组").foregroundStyle(.secondary) }
                Button { store.finishActive(); if store.active == nil { close() } } label: {
                    Label("结束并保存", systemImage: "flag.checkered").frame(maxWidth: .infinity, minHeight: 28)
                }.buttonStyle(.borderedProminent).controlSize(.large)

                Button(action: close) {
                    Text("继续训练").frame(maxWidth: .infinity, minHeight: 28)
                }.buttonStyle(.bordered).controlSize(.large)

                Divider()
                Button(role: .destructive, action: discard) {
                    Label("放弃不保存", systemImage: "trash").frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.plain).foregroundStyle(.red)
            }
            .padding(16).frame(maxWidth: 560, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
            .padding(16).frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle(store.activeDoneCount == 0 ? "还没有记录" : store.activeDoneCount < store.activeSetCount ? "提前结束？" : "结束训练？")
    }
}

struct WorkoutSettingsForm: View {
    @Environment(GymStore.self) private var store
    @State private var notificationStatus = ""

    var body: some View {
        Form {
            Section("计时与提醒") {
                Stepper("休息 \(store.restSeconds == 0 ? "关闭" : workoutClock(Double(store.restSeconds)))", value: Binding(get: { store.restSeconds }, set: { store.setRest($0) }), in: 0...3600, step: 15)
                Toggle("提示音", isOn: preference(\.sound))
                Toggle("振动", isOn: preference(\.haptics))
                Toggle("休息结束时闪屏", isOn: preference(\.flash))
                Toggle("训练时保持屏幕常亮", isOn: preference(\.keepAwake))
                Button("启用锁屏休息提醒") {
                    Task {
                        do {
                            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                            notificationStatus = allowed ? "锁屏提醒已启用" : "可在系统设置中开启通知权限"
                            store.refreshWorkoutAlerts()
                        } catch { notificationStatus = "未能开启提醒：\(error.localizedDescription)" }
                    }
                }
                if !notificationStatus.isEmpty { Text(notificationStatus).font(.footnote).foregroundStyle(.secondary) }
            }
            Section {
                Picker("默认布局", selection: Binding(get: { store.workoutPreferences.layout }, set: { value in
                    store.setDefaultWorkoutLayout(value)
                })) { ForEach(WorkoutLayout.allCases, id: \.self) { Text($0.title).tag($0) } }
                Picker("每组强度", selection: preference(\.effort)) {
                    ForEach(WorkoutEffort.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("动作动画", selection: preference(\.media)) {
                    ForEach(WorkoutMediaSize.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } footer: { Text("设置会保留到下次训练。减少动态效果开启时，动作演示默认暂停。") }
        }.navigationTitle("训练设置")
    }

    private func preference<T>(_ key: WritableKeyPath<WorkoutPreferences, T>) -> Binding<T> {
        Binding(get: { store.workoutPreferences[keyPath: key] }, set: { value in store.updateWorkoutPreferences { $0[keyPath: key] = value } })
    }
}

struct WorkoutTextEditor: View {
    var title: String
    var initial: String
    var multiline = true
    var save: (String) -> Void
    @State private var text = ""
    var body: some View {
        Form {
            if multiline { TextEditor(text: $text).frame(minHeight: 160).accessibilityLabel(title) }
            else { TextField(title, text: $text) }
        }
        .navigationTitle(title)
        .onAppear { text = initial }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    .disabled(!multiline && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

struct WorkoutExercisePicker: View {
    @Environment(GymStore.self) private var store
    var pick: (ExerciseInfo) -> Void
    @State private var query = ""
    @State private var ownedOnly = false
    private var results: [ExerciseInfo] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return Catalogue.exercises.filter { info in
            let metadata = WorkoutCatalogue.records[info.id]
            if ownedOnly && !store.ownedEquipment.contains(metadata?.equipment ?? info.equipment) { return false }
            return query.isEmpty || info.name.localizedStandardContains(query) || metadata?.name.localizedStandardContains(query) == true
                || metadata?.englishName.localizedStandardContains(query) == true || Catalogue.equipmentName(info.equipment).localizedStandardContains(query)
        }
    }
    var body: some View {
        List {
            if results.isEmpty { ContentUnavailableView.search(text: query) }
            ForEach(results) { info in
                Button { pick(info) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(WorkoutCatalogue.records[info.id]?.name ?? info.name).foregroundStyle(.primary)
                        Text(Catalogue.equipmentName(info.equipment)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("选择动作")
        .searchable(text: $query, prompt: "搜索中文、英文或器械")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Toggle("我的器械", isOn: $ownedOnly).toggleStyle(.button) } }
    }
}
