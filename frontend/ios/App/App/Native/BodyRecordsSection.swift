import Charts
import SwiftUI

struct BodyRecordsSection: View {
    @Environment(GymStore.self) private var store
    var onEntry: (BodyEntryRequest) -> Void
    @State private var selectedDate: Date?
    @State private var visibleMonth = Date.now
    @State private var filter: RecordFilter = .all
    @State private var allHistory = false
    @State private var dayLimit = 7

    init(selectedDate: Date? = nil, visibleMonth: Date = .now, onEntry: @escaping (BodyEntryRequest) -> Void) {
        self.onEntry = onEntry
        _selectedDate = State(initialValue: selectedDate)
        _visibleMonth = State(initialValue: selectedDate ?? visibleMonth)
    }

    private enum RecordFilter: String, CaseIterable, Identifiable {
        case all = "全部", training = "训练", weight = "称重", measurement = "围度"
        var id: String { rawValue }
    }
    private var workouts: [WorkoutSession] { BodyAnalytics.workouts(store.workouts, range: .all, now: .now) }
    private var weights: [WeighIn] { BodyAnalytics.weights(store.weighIns, range: .all, now: .now) }
    private var calendar: Calendar { .current }
    private var decorations: [Date: Int] {
        var result: [Date: Int] = [:]
        for session in workouts {
            if let date = session.finishedAt { result[calendar.startOfDay(for: date), default: 0] |= 1 }
        }
        for weight in weights { result[calendar.startOfDay(for: weight.date), default: 0] |= 2 }
        for measurement in store.bodyMeasurements { result[calendar.startOfDay(for: measurement.date), default: 0] |= 4 }
        return result
    }
    private var days: [Date] {
        BodyAnalytics.recordDays(
            workouts: filter == .all || filter == .training ? workouts : [],
            weights: filter == .all || filter == .weight ? weights : [],
            measurements: filter == .all || filter == .measurement ? store.bodyMeasurements : []
        ).filter { date in
            if let selectedDate { return calendar.isDate(date, inSameDayAs: selectedDate) }
            return allHistory || calendar.isDate(date, equalTo: visibleMonth, toGranularity: .month)
        }
    }

    var body: some View {
        Section {
            let monthly = workouts.filter { $0.finishedAt.map { calendar.isDate($0, equalTo: visibleMonth, toGranularity: .month) } ?? false }.count
            LabeledContent("训练次数", value: "本月 \(monthly)次 · 累计 \(workouts.count)次")
            BodyCalendarView(selectedDate: $selectedDate, visibleMonth: $visibleMonth, decorations: decorations)
                .frame(minHeight: 320)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { legend }
                VStack(alignment: .leading, spacing: 6) { legend }
            }.font(.caption)
            DisclosureGroup("近12个月训练次数") {
                Chart(store.monthCounts()) { month in
                    BarMark(x: .value("月份", month.month, unit: .month), y: .value("训练次数", month.count))
                        .foregroundStyle(.green)
                }.frame(height: 160)
            }
            Picker("记录类型", selection: $filter) {
                ForEach(RecordFilter.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.menu)
            if let selectedDate {
                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedDate, format: .dateTime.year().month().day()).font(.subheadline)
                    Button("取消日期筛选") { self.selectedDate = nil }
                }
            } else {
                Toggle("查看全部历史", isOn: $allHistory)
            }
            if days.isEmpty {
                ContentUnavailableView("没有符合条件的记录", systemImage: "calendar", description: Text("选择其他日期或记录类型，或新增一条记录。"))
                if !allHistory {
                    Button("查看全部历史") { selectedDate = nil; allHistory = true }
                }
            }
            ForEach(Array(days.prefix(dayLimit)), id: \.self) { day in
                Text(day, format: .dateTime.year().month().day().weekday())
                    .font(.headline).accessibilityAddTraits(.isHeader)
                dayRecords(day)
            }
            if days.count > dayLimit { Button("加载更早记录") { dayLimit += 14 } }
        } header: { Text("训练日历与记录") } footer: {
            Text("点选日期筛选当天记录；展开训练可查看动作与每组数据，也可补录强度。")
        }
        .onChange(of: visibleMonth) { _, _ in dayLimit = 7; allHistory = false }
        .onChange(of: filter) { _, _ in dayLimit = 7 }
        .onChange(of: allHistory) { _, _ in dayLimit = 7 }
        .onChange(of: selectedDate) { _, _ in dayLimit = 7 }
    }

    @ViewBuilder private var legend: some View {
        Label("训练", systemImage: "circle.fill").foregroundStyle(.green)
        Label("称重", systemImage: "circle.fill").foregroundStyle(.blue)
        Label("围度", systemImage: "circle.fill").foregroundStyle(.orange)
        Label("多项", systemImage: "circle.fill").foregroundStyle(.purple)
    }

    @ViewBuilder private func dayRecords(_ day: Date) -> some View {
        if filter == .all || filter == .weight {
            ForEach(weights.filter { calendar.isDate($0.date, inSameDayAs: day) }) { weight in
                Button { onEntry(.weight(weight)) } label: {
                    LabeledContent {
                        Text("\(formatKg(weight.kilograms)) kg").foregroundStyle(.primary)
                    } label: { Label("体重", systemImage: "scalemass").foregroundStyle(.blue) }
                }
                .swipeActions { Button("删除", role: .destructive) { store.deleteWeighIn(weight.id) } }
            }
        }
        if filter == .all || filter == .measurement {
            ForEach(store.bodyMeasurements.filter { calendar.isDate($0.date, inSameDayAs: day) }) { measurement in
                DisclosureGroup {
                    ForEach(BodyMeasurement.fields, id: \.self) { field in
                        if let value = measurement.centimeters[field] { LabeledContent(field, value: "\(formatKg(value)) cm") }
                    }
                    ForEach(measurement.centimeters.keys.filter { !BodyMeasurement.fields.contains($0) }.sorted(), id: \.self) { field in
                        if let value = measurement.centimeters[field] { LabeledContent(field, value: "\(formatKg(value)) cm") }
                    }
                    if let fat = measurement.bodyFatPercent { LabeledContent("体脂率", value: "\(formatKg(fat))%") }
                    Button("编辑围度") { onEntry(.measurement(measurement)) }
                } label: { Label("身体围度 · \(measurement.centimeters.count)项", systemImage: "ruler") }
                .swipeActions { Button("删除", role: .destructive) { store.deleteMeasurement(measurement.id) } }
            }
        }
        if filter == .all || filter == .training {
            ForEach(workouts.filter { $0.finishedAt.map { calendar.isDate($0, inSameDayAs: day) } ?? false }) { session in
                DisclosureGroup {
                    ForEach(session.exercises) { exercise in
                        DisclosureGroup {
                            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                                VStack(alignment: .leading, spacing: 6) {
                                    LabeledContent("第\(index + 1)组", value: setDescription(set))
                                    if set.done {
                                        Picker("强度 RIR", selection: Binding<Int?>(
                                            get: { store.workouts.first { $0.id == session.id }?.exercises.first { $0.id == exercise.id }?.sets.first { $0.id == set.id }?.rir },
                                            set: { store.setRIR(workout: session.id, exercise: exercise.id, set: set.id, value: $0) }
                                        )) {
                                            Text("未记录").tag(Int?.none)
                                            ForEach(0...10, id: \.self) { value in Text("还能做 \(value) 次").tag(Optional(value)) }
                                        }.pickerStyle(.menu)
                                    }
                                }.padding(.vertical, 4)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise.name)
                                Text("已完成 \(exercise.sets.filter(\.done).count) / \(exercise.sets.count) 组")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(session.name, systemImage: "dumbbell")
                        Text(workoutDescription(session)).font(.caption).foregroundStyle(.secondary)
                        if let health = session.health {
                            if let average = health.heart_rate_avg_bpm {
                                Text("平均心率 \(formatKg(average)) bpm · 峰值 \(health.heart_rate_max_bpm.map(formatKg) ?? "—") bpm")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let energy = health.active_energy_kcal {
                                Text("活动能量 \(formatKg(energy)) kcal").font(.caption).foregroundStyle(.secondary)
                            }
                            if health.heart_rate_avg_bpm == nil && health.active_energy_kcal == nil {
                                Text("健康数据暂不可用，可在手表同步后重试同步")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .swipeActions { Button("删除", role: .destructive) { store.deleteWorkout(session.id) } }
            }
        }
    }

    private func workoutDescription(_ session: WorkoutSession) -> String {
        let minutes = max(0, Int((session.finishedAt ?? session.startedAt).timeIntervalSince(session.startedAt) / 60))
        let sets = session.exercises.flatMap(\.sets).filter(\.done).count
        return "\(session.startedAt.formatted(date: .omitted, time: .shortened)) 开始 · \(minutes)分钟 · \(session.exercises.count)个动作 · \(sets)组完成"
    }
    private func setDescription(_ set: WorkoutSet) -> String {
        let value = set.weight > 0 ? "\(formatKg(set.weight)) kg × \(set.reps)次" : "\(set.reps)次"
        return set.done ? value : "未完成 · \(value)"
    }
}
