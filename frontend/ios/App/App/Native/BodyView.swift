import Charts
import SwiftUI

struct BodyView: View {
    @Environment(GymStore.self) private var store
    @State private var weightSpan: WeightSpan = .month
    @State private var muscleDays = 7
    @State private var exerciseId = ""
    @State private var showWeighIn = false
    @State private var showGoal = false
    @State private var goalText = ""

    var body: some View {
        NavigationStack {
            List {
                weightSection
                waterSection
                muscleSection
                trainingSection
            }
            .navigationTitle("身体")
            .sheet(isPresented: $showWeighIn) { WeighInSheet() }
            .alert("目标体重", isPresented: $showGoal) {
                TextField("kg", text: $goalText).keyboardType(.decimalPad)
                Button("保存") { if let value = parseKg(goalText) { store.setTarget(value) } }
                if store.targetKg != nil { Button("清除目标", role: .destructive) { store.setTarget(nil) } }
                Button("取消", role: .cancel) {}
            }
            .onAppear(perform: pickExercise)
            .onChange(of: store.finishedWorkouts.count) { _, _ in pickExercise() }
        }
    }

    @ViewBuilder
    private var weightSection: some View {
        Section("体重") {
            Picker("范围", selection: $weightSpan) {
                Text("7 天").tag(WeightSpan.week)
                Text("30 天").tag(WeightSpan.month)
                Text("全部").tag(WeightSpan.all)
            }
            .pickerStyle(.segmented)
            let points = store.weighIns(within: weightSpan.days)
            if points.isEmpty {
                Text("还没有体重记录")
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(points) { point in
                        LineMark(
                            x: .value("日期", point.date),
                            y: .value("kg", point.kilograms)
                        )
                        .interpolationMethod(.catmullRom)
                        PointMark(
                            x: .value("日期", point.date),
                            y: .value("kg", point.kilograms)
                        )
                    }
                    if let target = store.targetKg {
                        RuleMark(y: .value("目标", target))
                            .foregroundStyle(.orange)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .frame(height: 180)
                if let latest = store.latestWeighIn {
                    LabeledContent("当前", value: "\(formatKg(latest.kilograms)) kg")
                }
                Text(store.goalCaption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button("记一笔") { showWeighIn = true }
                .buttonStyle(.glassProminent)
            Button(store.targetKg == nil ? "设目标体重" : "改目标体重") {
                goalText = store.targetKg.map(formatKg) ?? ""
                showGoal = true
            }.buttonStyle(.glass)
            if !store.weighIns.isEmpty {
                NavigationLink("全部称重") { WeighInList() }
            }
        }
    }

    @ViewBuilder
    private var waterSection: some View {
        Section("喝水") {
            Button {
                store.tab = .water
            } label: {
                HStack {
                    Label("饮水记录", systemImage: "drop")
                    Spacer()
                    Text("今日 \(store.wellness.todayWater) mL")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var muscleSection: some View {
        Section("肌肉") {
            Picker("范围", selection: $muscleDays) {
                Text("7 天").tag(7)
                Text("30 天").tag(30)
            }
            .pickerStyle(.segmented)
            let loads = store.muscleLoad(days: muscleDays)
            if loads.isEmpty {
                Text("这段时间还没有完成的组")
                    .foregroundStyle(.secondary)
            } else {
                let peak = loads.first?.value ?? 1
                ForEach(loads) { load in
                    HStack {
                        Text(Catalogue.muscleName(load.id))
                        Spacer()
                        ProgressView(value: load.value, total: max(peak, 0.01))
                            .frame(width: 120)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var trainingSection: some View {
        Section("训练") {
            LabeledContent("次数", value: "\(store.finishedWorkouts.count)")
            Chart(store.monthCounts()) { item in
                BarMark(
                    x: .value("月", item.month, unit: .month),
                    y: .value("次数", item.count)
                )
            }
            .frame(height: 160)
            .accessibilityLabel("近 12 个月的训练次数")
            exerciseChart
            NavigationLink("训练历史") { HistoryView() }
        }
    }

    @ViewBuilder
    private var exerciseChart: some View {
        let options = store.historyExercises()
        if options.isEmpty {
            Text("完成一次训练后，这里画出单个动作的重量。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Picker("动作", selection: $exerciseId) {
                ForEach(options) { option in
                    Text(option.name).tag(option.id)
                }
            }
            let series = store.series(for: exerciseId)
            if series.points.count < 2 {
                Text("这个动作还不到两次记录。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Chart(series.points) { point in
                    LineMark(
                        x: .value("日期", point.date),
                        y: .value(series.usesReps ? "次数" : "kg", point.value)
                    )
                    PointMark(
                        x: .value("日期", point.date),
                        y: .value(series.usesReps ? "次数" : "kg", point.value)
                    )
                }
                .frame(height: 160)
                Text(series.usesReps ? "每次训练里完成的最多次数" : "每次训练里完成的最大重量")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private enum WeightSpan: Hashable {
        case week, month, all
        var days: Int? {
            switch self {
            case .week: return 7
            case .month: return 30
            case .all: return nil
            }
        }
    }

    private func pickExercise() {
        if exerciseId.isEmpty {
            exerciseId = store.historyExercises().first?.id ?? ""
        }
    }
}

private struct WeighInList: View {
    @Environment(GymStore.self) private var store

    var body: some View {
        List {
            ForEach(store.weighIns.sorted { $0.date > $1.date }) { entry in
                LabeledContent(entry.date.formatted(date: .abbreviated, time: .omitted), value: "\(formatKg(entry.kilograms)) kg")
            }
            .onDelete { offsets in
                let ordered = store.weighIns.sorted { $0.date > $1.date }
                let ids = offsets.map { ordered[$0].id }
                ids.forEach { store.deleteWeighIn($0) }
            }
        }
        .navigationTitle("全部称重")
    }
}

private struct HistoryView: View {
    @Environment(GymStore.self) private var store

    var body: some View {
        List {
            if store.finishedWorkouts.isEmpty {
                ContentUnavailableView("还没有训练记录", systemImage: "figure.strengthtraining.traditional")
            }
            ForEach(store.finishedWorkouts) { session in
                NavigationLink {
                    HistoryDetail(id: session.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.name)
                        Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                let ids = offsets.map { store.finishedWorkouts[$0].id }
                ids.forEach { store.deleteWorkout($0) }
            }
        }
        .navigationTitle("训练历史")
    }
}

private struct HistoryDetail: View {
    @Environment(GymStore.self) private var store
    var id: UUID

    var body: some View {
        List {
            if let session = store.workouts.first(where: { $0.id == id }) {
                ForEach(session.exercises) { exercise in
                    Section(exercise.name) {
                        ForEach(exercise.sets) { set in
                            Text(setLine(set))
                                .foregroundStyle(set.done ? .primary : .secondary)
                        }
                    }
                }
            } else {
                ContentUnavailableView("这条记录已经删掉了", systemImage: "clock")
            }
        }
        .navigationTitle("训练")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func setLine(_ set: WorkoutSet) -> String {
        let mark = set.done ? "" : "未完成 · "
        if set.weight > 0 { return "\(mark)\(formatKg(set.weight)) kg × \(set.reps)" }
        return "\(mark)\(set.reps) 次"
    }
}
