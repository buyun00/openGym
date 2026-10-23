import SwiftUI

private enum PlanLink: Hashable {
    case library, equipment
}

struct PlanView: View {
    @Environment(GymStore.self) private var store
    @State private var path = NavigationPath()
    @State private var showNew = false
    @State private var newName = ""
    @State private var pendingDelete: UUID?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("这一周") {
                    ForEach(store.week, id: \.day) { day in
                        NavigationLink {
                            WeekdayEditor(day: day.day)
                        } label: {
                            LabeledContent(Weekday.name(day.day)) {
                                Text(dayLabel(day.day))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                Section("\(store.routines.count) 个计划") {
                    if store.routines.isEmpty {
                        ContentUnavailableView("还没有计划", systemImage: "calendar", description: Text("建一个计划，再把它排到上面的某一天。"))
                    }
                    ForEach(store.routines) { routine in
                        NavigationLink {
                            RoutineEditorView(routineId: routine.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(routine.name.isEmpty ? "未命名计划" : routine.name)
                                Text("\(routine.exercises.count) 个动作")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("删除", role: .destructive) { pendingDelete = routine.id }
                        }
                    }
                }
            }
            .navigationTitle("计划")
            .navigationDestination(for: PlanLink.self) { link in
                switch link {
                case .library:
                    LibraryView()
                case .equipment:
                    EquipmentView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("更多", systemImage: "ellipsis.circle") {
                        Button("新建计划", systemImage: "plus") { showNew = true }
                        Button("动作库", systemImage: "dumbbell") { path.append(PlanLink.library) }
                        Button("器械库", systemImage: "wrench.and.screwdriver") { path.append(PlanLink.equipment) }
                    }
                }
            }
            .sheet(isPresented: $showNew) { newRoutineSheet }
            .confirmationDialog("删除这个计划？", isPresented: deleteShown, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    if let pendingDelete { store.deleteRoutine(pendingDelete) }
                    pendingDelete = nil
                }
                Button("取消", role: .cancel) { pendingDelete = nil }
            }
        }
    }

    private var deleteShown: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var newRoutineSheet: some View {
        NavigationStack {
            Form {
                TextField("计划名称", text: $newName)
            }
            .navigationTitle("新建计划")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showNew = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty { _ = store.addRoutine(name: name) }
                        newName = ""
                        showNew = false
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func dayLabel(_ day: Int) -> String {
        let names = store.routines(on: day).map(\.name)
        return names.isEmpty ? "休息" : names.joined(separator: "、")
    }
}

struct WeekdayEditor: View {
    @Environment(GymStore.self) private var store
    var day: Int

    var body: some View {
        List {
            if store.routines.isEmpty {
                ContentUnavailableView("还没有计划", systemImage: "calendar", description: Text("先在计划页新建一个。"))
            }
            ForEach(store.routines) { routine in
                Toggle(routine.name, isOn: Binding(
                    get: { store.routines(on: day).contains { $0.id == routine.id } },
                    set: { store.setIncluded(routine, on: day, included: $0) }
                ))
            }
        }
        .navigationTitle(Weekday.name(day))
    }
}
