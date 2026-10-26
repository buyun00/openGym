import SwiftUI

private enum PlanLink: Hashable {
    case schedule, library, equipment
}

struct PlanView: View {
    @Environment(GymStore.self) private var store
    @State private var path = NavigationPath()
    @State private var showNew = false
    @State private var newName = ""
    @State private var pendingDelete: UUID?
    @State private var expandedRoutines: Set<UUID> = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    PlanWeekOverview()
                        .listRowInsets(EdgeInsets(top: 16, leading: 12, bottom: 12, trailing: 12))
                }
                Section("\(store.routines.count) 个计划") {
                    if store.routines.isEmpty {
                        ContentUnavailableView("还没有计划", systemImage: "calendar", description: Text("建一个计划，再把它排到上面的某一天。"))
                    }
                    ForEach(store.routines) { routine in
                        DisclosureGroup(isExpanded: expansion(for: routine.id)) {
                            let preview = store.workoutExercises(from: routine)
                            if routine.exercises.isEmpty {
                                Text("还没有动作，点下方编辑计划添加。")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                    .padding(.vertical, 8)
                            }
                            ForEach(Array(routine.exercises.enumerated()), id: \.element.id) { index, slot in
                                PlanExerciseDetail(slot: slot, number: index + 1,
                                                   startingWeight: preview.indices.contains(index) ? preview[index].sets.first?.weight : nil)
                                    .padding(.vertical, 8)
                                    // A standalone Divider becomes an extra List row with its own minimum height.
                                    .listRowSeparator(.visible, edges: .bottom)
                            }
                            NavigationLink {
                                RoutineEditorView(routineId: routine.id)
                            } label: {
                                Label("编辑计划", systemImage: "slider.horizontal.3")
                                    .padding(.vertical, 6)
                            }
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
                case .schedule:
                    weeklySchedule
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
                        Button("每周安排", systemImage: "calendar") { path.append(PlanLink.schedule) }
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
        .tint(.green)
        .onChange(of: store.tab) { _, tab in
            if tab == .plan { expandedRoutines.removeAll() }
        }
        .onChange(of: store.routines.map(\.id)) { _, ids in
            // Keep explicit choices for surviving plans; new or synced plans stay closed.
            expandedRoutines.formIntersection(ids)
        }
    }

    // Only a disclosure tap opts a plan in; an empty set means every plan is collapsed.
    private func expansion(for id: UUID) -> Binding<Bool> {
        Binding(get: { expandedRoutines.contains(id) }, set: { expanded in
            if expanded { expandedRoutines.insert(id) } else { expandedRoutines.remove(id) }
        })
    }

    private var weeklySchedule: some View {
        List {
            Section {
                ForEach(store.week, id: \.day) { day in
                    NavigationLink {
                        WeekdayEditor(day: day.day)
                    } label: {
                        LabeledContent(Weekday.name(day.day)) {
                            Text(dayLabel(day.day)).foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("每周重复的训练安排；单独改期的日期仍使用当天安排。")
            }
        }
        .navigationTitle("每周安排")
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

private struct PlanWeekOverview: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())

    private var calendar: Calendar { WellnessDay.calendar() }
    private var today: Date { calendar.startOfDay(for: store.wellness.now) }
    private var monday: Date { Weekday.monday(of: selectedDate, calendar: calendar) }
    private var isToday: Bool { calendar.isDate(selectedDate, inSameDayAs: today) }
    private var selectedRoutines: [Routine] { routines(on: selectedDate) }
    private var completed: [WorkoutSession] { finished(on: selectedDate) }
    private var currentSession: WorkoutSession? { isToday ? store.active : nil }
    private var dates: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }
    private var weekTitle: String {
        if calendar.isDate(monday, inSameDayAs: Weekday.monday(of: today, calendar: calendar)) { return "本周" }
        let end = dates.last ?? monday
        let style = Date.FormatStyle.dateTime.month().day()
        return "\(monday.formatted(style)) – \(end.formatted(style))"
    }
    private var dayTitle: String {
        isToday ? "今天" : selectedDate.formatted(.dateTime.month().day().weekday())
    }
    private var trainingTitle: String {
        if let currentSession { return "\(currentSession.name) · 进行中" }
        if !completed.isEmpty { return completed.map(\.name).joined(separator: "、") + " · 已完成" }
        let names = selectedRoutines.map { $0.name.isEmpty ? "未命名计划" : $0.name }
        let title = names.isEmpty ? "休息日" : names.joined(separator: "、")
        let rescheduled = isToday && selectedRoutines.map(\.id) != store.routines(on: store.todayIndex).map(\.id)
        return title + (rescheduled ? " · 已改期" : "")
    }
    private var symbol: String {
        if currentSession != nil { return "play.fill" }
        if !completed.isEmpty { return "checkmark" }
        return selectedRoutines.isEmpty ? "moon.fill" : "dumbbell.fill"
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button("上一周", systemImage: "chevron.left") { moveWeek(-1) }
                    .labelStyle(.iconOnly).frame(width: 44, height: 44)
                Spacer(minLength: 0)
                Button { selectedDate = today } label: {
                    Text(weekTitle).font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).frame(minHeight: 44)
                }
                .accessibilityLabel("\(weekTitle)，返回本周今天")
                Spacer(minLength: 0)
                Button("下一周", systemImage: "chevron.right") { moveWeek(1) }
                    .labelStyle(.iconOnly).frame(width: 44, height: 44)
            }
            .foregroundStyle(.primary)
            HStack(alignment: .top, spacing: 0) {
                ForEach(dates, id: \.self) { date in dayButton(date) }
            }
            VStack(spacing: 12) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        trainingLabel
                        trainingAction
                    }.frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14).background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                } else {
                    HStack(spacing: 12) {
                        trainingLabel
                        Spacer(minLength: 0)
                        trainingAction
                    }.padding(14).background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                }
                Button { store.tab = .workout } label: {
                    Label(store.active == nil ? "选择其他训练" : "继续当前训练", systemImage: "arrow.left.arrow.right")
                        .font(.body).frame(maxWidth: .infinity, minHeight: 44)
                }
                .foregroundStyle(.green)
            }
        }
        .buttonStyle(.plain)
        .onChange(of: today) { oldDate, newDate in
            if calendar.isDate(selectedDate, inSameDayAs: oldDate) { selectedDate = newDate }
        }
    }

    private func dayButton(_ date: Date) -> some View {
        let selected = calendar.isDate(date, inSameDayAs: selectedDate)
        let current = calendar.isDate(date, inSameDayAs: today)
        let done = !finished(on: date).isEmpty
        let planned = !routines(on: date).isEmpty
        return Button { selectedDate = date } label: {
            VStack(spacing: 6) {
                Text(Weekday.short(Weekday.index(for: date, calendar: calendar)))
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(calendar.component(.day, from: date))")
                    .font(.title3.weight(selected ? .semibold : .regular))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    .foregroundStyle(selected ? Color.black : Color.primary)
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background {
                        if selected { Circle().fill(Color.green) }
                        else if current { Circle().strokeBorder(Color.green, lineWidth: 1) }
                    }
                Circle().fill(done ? Color.green : planned ? Color.secondary : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("\(date.formatted(.dateTime.month().day().weekday()))\(current ? "，今天" : "")，\(done ? "已完成训练" : planned ? "有训练计划" : "休息日")")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityHint("查看当天训练安排")
    }

    private var trainingLabel: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.title3)
                .foregroundStyle(.white).frame(width: 38, height: 38)
                .background(currentSession != nil ? Color.orange : Color.green, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(dayTitle).font(.caption).foregroundStyle(.secondary)
                Text(trainingTitle).font(.headline).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var trainingAction: some View {
        if currentSession != nil {
            Button("继续") { store.tab = .workout }.buttonStyle(.bordered).tint(.orange)
        } else if isToday, selectedRoutines.contains(where: { !$0.exercises.isEmpty }) {
            Button(completed.isEmpty ? "开始" : "再练") { store.start(selectedRoutines) }
                .buttonStyle(.bordered).tint(.green).fixedSize(horizontal: true, vertical: false)
        } else if isToday, let routine = selectedRoutines.first, routine.exercises.isEmpty {
            NavigationLink("加动作") { RoutineEditorView(routineId: routine.id) }
                .buttonStyle(.bordered).tint(.green)
        } else {
            NavigationLink {
                WeekdayEditor(day: Weekday.index(for: selectedDate, calendar: calendar))
            } label: {
                Text("每周安排").font(.subheadline).fixedSize(horizontal: true, vertical: false)
            }.buttonStyle(.bordered).tint(.green)
        }
    }

    private func routines(on date: Date) -> [Routine] {
        if calendar.isDate(date, inSameDayAs: today) { return store.todayRoutines }
        return store.routines(on: Weekday.index(for: date, calendar: calendar))
    }

    private func finished(on date: Date) -> [WorkoutSession] {
        store.workouts.filter { session in
            guard let end = session.finishedAt else { return false }
            return calendar.isDate(end, inSameDayAs: date)
        }
    }

    private func moveWeek(_ offset: Int) {
        if let date = calendar.date(byAdding: .day, value: offset * 7, to: selectedDate) { selectedDate = date }
    }
}

private struct PlanExerciseDetail: View {
    let slot: RoutineExercise
    let number: Int
    let startingWeight: Double?

    private var mode: WorkoutMode { slot.mode ?? Catalogue.byId[slot.exerciseId]?.workoutMode ?? .reps }
    private var targets: String {
        var values = ["\(max(1, slot.setCount)) 组"]
        switch mode {
        case .reps:
            values.append("每组 \(slot.reps) 次")
            if let startingWeight, startingWeight > 0 { values.append("起始参考 \(formatKg(startingWeight)) kg") }
        case .time:
            values.append("每组 \(formatKg(slot.seconds ?? 45)) 秒")
            if let startingWeight, startingWeight > 0 { values.append("起始参考 \(formatKg(startingWeight)) kg") }
        case .cardio:
            values.append("每组 \(formatKg(slot.minutes ?? 20)) 分钟")
            values.append("\(formatKg(slot.speed ?? 8)) km/h")
            if let incline = slot.incline { values.append("坡度 \(formatKg(incline))%") }
        }
        return values.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(number). \(slot.name)").font(.headline).foregroundStyle(.primary)
            Text(targets).font(.subheadline).foregroundStyle(.primary)
            if let info = Catalogue.byId[slot.exerciseId] {
                Text("\(mode.title) · \(Catalogue.equipmentName(info.equipment)) · \(Catalogue.bodyPartName(info.bodyPart))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let note = slot.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(note).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
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
            Section {
                ForEach(store.routines) { routine in
                    Toggle(routine.name.isEmpty ? "未命名计划" : routine.name, isOn: Binding(
                        get: { store.routines(on: day).contains { $0.id == routine.id } },
                        set: { store.setIncluded(routine, on: day, included: $0) }
                    ))
                }
            } footer: {
                Text("调整每周\(Weekday.short(day))重复的训练；已单独改期的日期不受影响。")
            }
        }
        .navigationTitle(Weekday.name(day))
    }
}
