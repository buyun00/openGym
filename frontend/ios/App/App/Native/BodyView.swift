import Charts
import SwiftUI

struct BodyView: View {
    @Environment(GymStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var weightRange: BodyRange = .month
    @State private var trainingRange: BodyRange = .month
    @State private var selectedWeightDate: Date?
    @State private var entry: BodyEntryRequest?
    @State private var showGoal = false
    @State private var goalText = ""
    @State private var weighInLimit = 10
    @State private var exerciseId = ""

    private enum BodySection: String, CaseIterable, Identifiable {
        case weight = "体重", muscle = "肌肉", intensity = "强度", records = "记录"
        var id: String { rawValue }
    }
    private var sessions: [WorkoutSession] { BodyAnalytics.workouts(store.workouts, range: trainingRange, now: .now) }
    private var weights: [WeighIn] { BodyAnalytics.weights(store.weighIns, range: weightRange, now: .now) }
    private var allWeights: [WeighIn] { BodyAnalytics.weights(store.weighIns, range: .all, now: .now) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    weightSection.id(BodySection.weight)
                    trainingSummary
                    muscleSection.id(BodySection.muscle)
                    intensitySection.id(BodySection.intensity)
                    progressSection
                    BodyRecordsSection { entry = $0 }.id(BodySection.records)
                }
                .listStyle(.insetGrouped)
                .safeAreaBar(edge: .top) {
                    // Native grouped buttons are anchors, not a tab/segmented selection:
                    // tapping the same anchor again must still scroll after a manual swipe.
                    ControlGroup {
                        ForEach(BodySection.allCases) { section in
                            Button(section.rawValue) {
                                withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(section, anchor: .top) }
                            }
                        }
                    }
                    .controlGroupStyle(.navigation)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal).padding(.vertical, 8)
                    .accessibilityHint("在同一页面中定位到所选区域")
                }
            }
            .navigationTitle("身体")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("记录", systemImage: "plus") {
                        Button("体重与体脂", systemImage: "scalemass") { entry = .weight() }
                        Button("身体围度", systemImage: "ruler") { entry = .measurement() }
                    }
                }
            }
            .sheet(item: $entry) { BodyEntrySheet(request: $0) }
            .alert("记录未保存", isPresented: Binding(
                get: { store.saveError != nil && entry == nil },
                set: { if !$0 { store.saveError = nil } }
            )) {
                Button("好") { store.saveError = nil }
            } message: { Text(store.saveError ?? "") }
            .alert("目标体重", isPresented: $showGoal) {
                TextField("kg", text: $goalText).keyboardType(.decimalPad)
                Button("保存") { if let value = parseKg(goalText) { store.setTarget(value) } }
                    .disabled(parseKg(goalText) == nil)
                if store.targetKg != nil { Button("清除目标", role: .destructive) { store.setTarget(nil) } }
                Button("取消", role: .cancel) {}
            }
            .tint(.green)
        }
    }

    private var weightSection: some View {
        Section {
            if let latest = allWeights.last {
                VStack(alignment: .leading, spacing: 8) {
                    Text("最新体重").font(.subheadline).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline) {
                        Text(formatKg(latest.kilograms)).font(.largeTitle.bold()).monospacedDigit()
                        Text("kg").foregroundStyle(.secondary)
                        Spacer()
                        if weights.count > 1, let first = weights.first, let last = weights.last {
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("\(signedKg(last.kilograms - first.kilograms)) kg").font(.headline).monospacedDigit()
                                Text(weightRange == .all ? "全部记录变化" : "近\(weightRange.rawValue)天变化")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text(latest.date, format: .dateTime.year().month().day()).font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            } else {
                ContentUnavailableView("还没有体重记录", systemImage: "scalemass", description: Text("记录后即可查看变化曲线。"))
            }
            Picker("体重范围", selection: $weightRange) {
                ForEach(BodyRange.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            if !weights.isEmpty { weightChart }
            else if !allWeights.isEmpty { Text("所选时间内没有称重记录，试试选择“全部”。").foregroundStyle(.secondary) }
            HStack {
                Button("记体重", systemImage: "plus") { entry = .weight() }.buttonStyle(.glassProminent)
                Spacer()
                Button(store.targetKg.map { "目标 \(formatKg($0)) kg" } ?? "设置目标", systemImage: "scope") {
                    goalText = store.targetKg.map(formatKg) ?? ""
                    showGoal = true
                }.buttonStyle(.glass)
            }
            composition
            DisclosureGroup("称重记录 · \(allWeights.count)条") {
                ForEach(Array(allWeights.reversed().prefix(weighInLimit))) { point in
                    Button { entry = .weight(point) } label: {
                        LabeledContent {
                            Text("\(formatKg(point.kilograms)) kg").foregroundStyle(.primary)
                        } label: {
                            Text(point.date, format: .dateTime.year().month().day()).foregroundStyle(.primary)
                        }
                    }
                    .swipeActions { Button("删除", role: .destructive) { store.deleteWeighIn(point.id) } }
                }
                if allWeights.count > weighInLimit { Button("加载更早称重") { weighInLimit += 20 } }
            }
        }
    }

    private var weightChart: some View {
        let points = weights
        let values = points.map(\.kilograms) + (store.targetKg.map { [$0] } ?? [])
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let padding = max(0.5, (high - low) * 0.15)
        return VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(points) { point in
                    LineMark(x: .value("日期", point.date), y: .value("体重 kg", point.kilograms)).foregroundStyle(.green)
                    PointMark(x: .value("日期", point.date), y: .value("体重 kg", point.kilograms)).foregroundStyle(.green).symbolSize(18)
                }
                if let target = store.targetKg {
                    RuleMark(y: .value("目标 kg", target)).foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .leading) { Text("目标 \(formatKg(target)) kg").font(.caption2) }
                }
                if let point = selectedWeight(in: points) {
                    RuleMark(x: .value("所选日期", point.date)).foregroundStyle(.secondary)
                }
            }
            .chartYScale(domain: max(0, low - padding)...(high + padding))
            .chartXSelection(value: $selectedWeightDate).frame(height: 200)
            .accessibilityLabel("体重变化曲线，\(points.count)条记录")
            if let point = selectedWeight(in: points) {
                Text("\(point.date.formatted(date: .abbreviated, time: .omitted)) · \(formatKg(point.kilograms)) kg")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 8)
    }

    private func selectedWeight(in points: [WeighIn]) -> WeighIn? {
        guard let date = selectedWeightDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    private var composition: some View {
        let points = weights.filter { $0.leanKilograms != nil }
        return DisclosureGroup("体脂率与去脂体重") {
            if let latest = points.last, let fat = latest.bodyFatPercent, let lean = latest.leanKilograms {
                LabeledContent("体脂率", value: "\(formatKg(fat))%")
                Text(latest.date, format: .dateTime.year().month().day()).font(.caption).foregroundStyle(.secondary)
                Chart(points) { point in
                    if let value = point.bodyFatPercent {
                        LineMark(x: .value("日期", point.date), y: .value("体脂率 %", value)).foregroundStyle(.orange)
                        PointMark(x: .value("日期", point.date), y: .value("体脂率 %", value)).foregroundStyle(.orange)
                    }
                }.frame(height: 140).chartYScale(domain: .automatic(includesZero: false))
                LabeledContent("去脂体重（估算）", value: "\(formatKg(lean)) kg")
                Chart(points) { point in
                    if let value = point.leanKilograms {
                        LineMark(x: .value("日期", point.date), y: .value("去脂体重 kg", value)).foregroundStyle(.blue)
                        PointMark(x: .value("日期", point.date), y: .value("去脂体重 kg", value)).foregroundStyle(.blue)
                    }
                }.frame(height: 140).chartYScale(domain: .automatic(includesZero: false))
                Text("去脂体重由同一天的体重与体脂率计算。").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("所选时间内未记录体脂率，可在记体重时选填。").foregroundStyle(.secondary)
                Button("记录体重与体脂") { entry = .weight() }
            }
        }
    }

    private var trainingSummary: some View {
        let summary = BodyAnalytics.summary(store.workouts, now: .now)
        return Section("训练概览") {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    metric("本月训练", value: "\(summary.month)次")
                    Spacer(minLength: 0)
                    metric("本周训练", value: "\(summary.week)次")
                    Spacer(minLength: 0)
                    metric("连续训练", value: "\(summary.consecutiveWeeks)周")
                }
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("本月训练", value: "\(summary.month)次")
                    LabeledContent("本周训练", value: "\(summary.week)次")
                    LabeledContent("连续训练", value: "\(summary.consecutiveWeeks)周")
                }
            }.padding(.vertical, 4)
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).monospacedDigit()
        }.fixedSize(horizontal: true, vertical: false).accessibilityElement(children: .combine)
    }

    private var muscleSection: some View {
        let loads = BodyAnalytics.muscleLoads(sessions, muscles: Catalogue.musclesById)
        let covered = Set(loads.map(\.id))
        let uncovered = Catalogue.muscleOrder.filter { !covered.contains($0) }
        return Section {
            Picker("统计范围（肌肉与强度）", selection: $trainingRange) {
                ForEach(BodyRange.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            BodyMuscleMap(loads: loads)
            Text("按已完成组数与动作的肌群参与权重统计；颜色相对于本期训练最多的肌群。").font(.caption).foregroundStyle(.secondary)
            if loads.isEmpty {
                Text("所选时间内还没有可统计的肌群训练记录。").foregroundStyle(.secondary)
            } else {
                ForEach(Array(loads.prefix(3))) { muscleRow($0, peak: loads.first?.value ?? 1) }
                if loads.count > 3 {
                    DisclosureGroup("展开其余\(loads.count - 3)个肌群") {
                        ForEach(Array(loads.dropFirst(3))) { muscleRow($0, peak: loads.first?.value ?? 1) }
                    }
                }
            }
            DisclosureGroup("本期未覆盖 · \(uncovered.count)个肌群") {
                Text(uncovered.map(Catalogue.muscleName).joined(separator: "、")).foregroundStyle(.secondary)
            }
        } header: { Text("肌肉训练分布") } footer: {
            Text("统计仅反映已记录的训练量，不代表疲劳或恢复程度。")
        }
    }

    private func muscleRow(_ load: MuscleLoad, peak: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(Catalogue.muscleName(load.id), value: "\(formatKg(load.value))组")
            ProgressView(value: load.value, total: max(peak, 0.01)).tint(.green)
        }.accessibilityElement(children: .combine)
    }

    private var intensitySection: some View {
        let result = BodyAnalytics.intensity(sessions)
        return Section {
            Picker("强度统计范围（与肌肉同步）", selection: $trainingRange) {
                ForEach(BodyRange.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.menu)
            if let average = result.average, let share = result.hardShare {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        metric("已评分组平均值", value: "\(average.formatted(.number.precision(.fractionLength(1)))) RIR")
                        Spacer()
                        metric("RIR ≤ 3", value: share.formatted(.percent.precision(.fractionLength(0))))
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        metric("已评分组平均值", value: "\(average.formatted(.number.precision(.fractionLength(1)))) RIR")
                        metric("RIR ≤ 3", value: share.formatted(.percent.precision(.fractionLength(0))))
                    }
                }
            } else {
                Label("强度未记录", systemImage: "gauge.with.dots.needle.33percent")
                Text("训练完成一组后，或展开下方历史记录，即可选填还能完成的次数（RIR）。").foregroundStyle(.secondary)
            }
            Text("已评分 \(result.rated) / \(result.total) 组 · 未记录 \(result.missing) 组").font(.subheadline).foregroundStyle(.secondary)
            DisclosureGroup("强度趋势与分布") {
                Text("RIR 表示还能完成的次数；0 表示无法再完成一次。这里只统计手动评分，不从重量推测强度。")
                    .font(.caption).foregroundStyle(.secondary)
                if !result.weeks.isEmpty {
                    Chart(result.weeks) { week in
                        LineMark(x: .value("周", week.date), y: .value("平均 RIR", week.average)).foregroundStyle(.orange)
                        PointMark(x: .value("周", week.date), y: .value("平均 RIR", week.average)).foregroundStyle(.orange)
                    }.chartYScale(domain: 0...max(4, result.weeks.map(\.average).max() ?? 4))
                        .frame(height: 180).accessibilityLabel("每周已评分组的平均 RIR")
                    Chart(Array(result.buckets.enumerated()), id: \.offset) { item in
                        BarMark(x: .value("已评分组", item.element), y: .value("强度", item.offset == 4 ? "RIR 4+" : "RIR \(item.offset)"))
                            .foregroundStyle(.orange)
                            .annotation(position: .trailing) { Text("\(item.element)组").font(.caption) }
                    }.frame(height: 180).accessibilityLabel("已评分组的 RIR 分布")
                } else {
                    ContentUnavailableView("暂无强度曲线", systemImage: "chart.xyaxis.line", description: Text("有评分后显示；未记录不会计作 RIR 0。"))
                }
            }
        } header: { Text("训练强度") }
    }

    private var progressSection: some View {
        Section("更多趋势") {
            DisclosureGroup("动作力量趋势") { exerciseChart }
            DisclosureGroup("身体围度") {
                if let latest = store.bodyMeasurements.max(by: { $0.date < $1.date }) {
                    Text(latest.date, format: .dateTime.year().month().day()).font(.caption).foregroundStyle(.secondary)
                    ForEach(BodyMeasurement.fields, id: \.self) { field in
                        if let value = latest.centimeters[field] { LabeledContent(field, value: "\(formatKg(value)) cm") }
                    }
                } else { Text("还没有围度记录").foregroundStyle(.secondary) }
                Button("记围度", systemImage: "plus") { entry = .measurement() }.buttonStyle(.glass)
                Text("按日期回看围度记录，请在下方记录区选择“围度”。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var exerciseChart: some View {
        let options = store.historyExercises()
        if options.isEmpty {
            Text("完成训练后可查看各动作的重量或次数变化。").foregroundStyle(.secondary)
        } else {
            let selection = options.contains(where: { $0.id == exerciseId }) ? exerciseId : options[0].id
            Picker("动作", selection: Binding(get: { selection }, set: { exerciseId = $0 })) {
                ForEach(options) { Text($0.name).tag($0.id) }
            }.pickerStyle(.menu)
            let series = store.series(for: selection)
            if series.points.isEmpty {
                Text("这个动作还没有已完成的组。").foregroundStyle(.secondary)
            } else {
                Chart(Array(series.points.enumerated()), id: \.offset) { item in
                    LineMark(x: .value("日期", item.element.date), y: .value(series.usesReps ? "次数" : "kg", item.element.value))
                    PointMark(x: .value("日期", item.element.date), y: .value(series.usesReps ? "次数" : "kg", item.element.value))
                }.frame(height: 180).chartYScale(domain: .automatic(includesZero: false))
                Text(series.usesReps ? "每次训练完成的最多次数" : "每次训练完成的最大重量").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
