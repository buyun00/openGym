import Charts
import SwiftUI

private enum BodySection: String, CaseIterable, Identifiable, Hashable {
    case weight = "体重", muscle = "肌肉", intensity = "强度", records = "记录"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .weight: "scalemass"
        case .muscle: "figure.strengthtraining.traditional"
        case .intensity: "gauge.with.dots.needle.50percent"
        case .records: "calendar"
        }
    }
}

struct BodyView: View {
    @Environment(GymStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var weightRange: BodyRange = .month
    @State private var trainingRange: BodyRange = .month
    @State private var visibleSection: BodySection? = .weight
    @State private var detail: BodySection?
    @State private var selectedWeightDate: Date?
    @State private var selectedRecordDate: Date?
    @State private var visibleMonth = Date.now
    @State private var entry: BodyEntryRequest?

    private var sessions: [WorkoutSession] { BodyAnalytics.workouts(store.workouts, range: trainingRange, now: .now) }
    private var weights: [WeighIn] { BodyAnalytics.weights(store.weighIns, range: weightRange, now: .now) }
    private var allWeights: [WeighIn] { BodyAnalytics.weights(store.weighIns, range: .all, now: .now) }
    private var allWorkouts: [WorkoutSession] { BodyAnalytics.workouts(store.workouts, range: .all, now: .now) }
    private var pageSelection: Binding<BodySection> {
        Binding(get: { visibleSection ?? .weight }, set: { section in
            withAnimation(reduceMotion ? nil : .snappy) { visibleSection = section }
        })
    }

    var body: some View {
        NavigationStack {
            // Measure the safe layout region ONCE, outside the scroll view. Each target
            // and the scrolling viewport use that same height. Do not subtract bar
            // insets again inside each page or let the scroll view extend under them.
            GeometryReader { viewport in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(BodySection.allCases, id: \.self) { section in
                            GroupBox {
                                ViewThatFits(in: .vertical) {
                                    if !typeSize.isAccessibilitySize {
                                        pageContent(section, compact: false, height: viewport.size.height)
                                    }
                                    pageContent(section, compact: true, height: viewport.size.height)
                                    minimalContent(section)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .frame(width: viewport.size.width, height: viewport.size.height)
                            .id(section)
                            .accessibilityIdentifier("body-page-\(section.id)")
                        }
                    }.scrollTargetLayout()
                }
                .frame(width: viewport.size.width, height: viewport.size.height)
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $visibleSection, anchor: .top)
                .scrollIndicators(.hidden)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("身体")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("身体").font(.title2.bold()).fixedSize()
                        .accessibilityAddTraits(.isHeader)
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .principal) { pageNavigation }
                    .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("记录", systemImage: "plus") {
                        Button("体重与体脂", systemImage: "scalemass") { entry = .weight() }
                        Button("身体围度", systemImage: "ruler") { entry = .measurement() }
                    }
                }
            }
            .sheet(item: $entry) { BodyEntrySheet(request: $0) }
            .sheet(item: $detail) { section in
                BodyDetailSheet(section: section, weightRange: $weightRange, trainingRange: $trainingRange,
                                recordDate: selectedRecordDate, recordMonth: visibleMonth)
            }
            .alert("记录未保存", isPresented: Binding(
                get: { store.saveError != nil && entry == nil && detail == nil },
                set: { if !$0 { store.saveError = nil } }
            )) {
                Button("好") { store.saveError = nil }
            } message: { Text(store.saveError ?? "") }
            .tint(.green)
        }
    }

    private var pageNavigation: some View {
        ViewThatFits(in: .horizontal) {
            if !typeSize.isAccessibilitySize {
                HStack(spacing: 2) {
                    ForEach(BodySection.allCases) { section in
                        let selected = (visibleSection ?? .weight) == section
                        Button { pageSelection.wrappedValue = section } label: {
                            Text(section.rawValue)
                                .font(.subheadline.weight(selected ? .bold : .regular))
                                .foregroundStyle(selected ? Color.primary : Color.secondary)
                                .underline(selected)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }.fixedSize(horizontal: true, vertical: false)
            }
            // Native menu keeps every destination readable at large accessibility sizes.
            Menu {
                Picker("身体页面", selection: pageSelection) {
                    ForEach(BodySection.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                }
            } label: {
                Label((visibleSection ?? .weight).rawValue, systemImage: "chevron.up.chevron.down")
            }.buttonStyle(.plain)
        }
        .accessibilityHint("选择后翻到对应整页；上下滑动也会更新所选页面")
    }

    @ViewBuilder private func pageContent(_ section: BodySection, compact: Bool, height: CGFloat) -> some View {
        switch section {
        case .weight: weightPage(compact: compact, height: height)
        case .muscle: musclePage(compact: compact, height: height)
        case .intensity: intensityPage(compact: compact, height: height)
        case .records: recordsPage(compact: compact, height: height)
        }
    }

    private func heading(_ section: BodySection, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(section.rawValue, systemImage: section.symbol).font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func rangePicker(_ title: String, selection: Binding<BodyRange>, compact: Bool) -> some View {
        Group {
            if compact {
                Picker(title, selection: selection) {
                    ForEach(BodyRange.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.menu)
            } else {
                Picker(title, selection: selection) {
                    ForEach(BodyRange.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
            }
        }
    }

    private func detailsButton(_ section: BodySection, title: String) -> some View {
        Button {
            if section == .records { selectedRecordDate = nil }
            detail = section
        } label: {
            Label(title, systemImage: "arrow.up.right.square")
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
        }.buttonStyle(.bordered)
    }

    private func weightPage(compact: Bool, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 16) {
            heading(.weight, subtitle: "最新记录与体重变化")
            if let latest = allWeights.last {
                Text("\(formatKg(latest.kilograms)) kg")
                    .font(compact ? .title2.bold() : .largeTitle.bold()).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                Text(latest.date, format: .dateTime.year().month().day())
                    .font(.caption).foregroundStyle(.secondary)
                if !compact, weights.count > 1, let first = weights.first, let last = weights.last {
                    Text("\(weightRange.title)变化  \(signedKg(last.kilograms - first.kilograms)) kg")
                        .font(.subheadline).monospacedDigit()
                }
            } else {
                Text("还没有体重记录").font(.title3)
            }
            BodyWeightRangePicker(selection: $weightRange)
            if !weights.isEmpty {
                BodyWeightChart(points: weights, target: store.targetKg, selectedDate: $selectedWeightDate,
                                height: compact ? 140 : min(240, max(170, height * 0.30)))
            } else {
                Text("所选时间内暂无称重记录。").foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ViewThatFits(in: .horizontal) {
                HStack { weightActions }
                VStack(spacing: 8) { weightActions }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: weightRange) { _, _ in selectedWeightDate = nil }
    }

    @ViewBuilder private var weightActions: some View {
        Button("记体重", systemImage: "plus") { entry = .weight() }.buttonStyle(.borderedProminent)
        detailsButton(.weight, title: "体重与围度详情")
    }

    private func musclePage(compact: Bool, height: CGFloat) -> some View {
        let loads = BodyAnalytics.muscleLoads(sessions, muscles: Catalogue.musclesById)
        return VStack(alignment: .leading, spacing: compact ? 10 : 16) {
            heading(.muscle, subtitle: "已完成训练的肌群分布")
            rangePicker("肌肉与强度范围", selection: $trainingRange, compact: compact)
            BodyMuscleMap(loads: loads, maximumFigureHeight: compact ? 150 : min(340, max(200, height * 0.43)),
                          showsLegend: !compact)
            if !compact, let strongest = loads.first {
                LabeledContent("本期最多 · \(Catalogue.muscleName(strongest.id))", value: "\(formatKg(strongest.value))组")
            }
            Text(loads.isEmpty ? "本期暂无肌群训练记录" : "已覆盖 \(loads.count) 个肌群 · 参与权重折算组数")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            detailsButton(.muscle, title: "肌群组数与未覆盖部位")
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func intensityPage(compact: Bool, height: CGFloat) -> some View {
        let result = BodyAnalytics.intensity(sessions)
        return VStack(alignment: .leading, spacing: compact ? 10 : 16) {
            heading(.intensity, subtitle: "训练强度 · 剩余可完成次数 RIR")
            rangePicker("肌肉与强度范围", selection: $trainingRange, compact: compact)
            if let average = result.average {
                Text("\(average.formatted(.number.precision(.fractionLength(1)))) RIR")
                    .font(.largeTitle.bold()).monospacedDigit()
                if !compact, let share = result.hardShare {
                    LabeledContent("RIR ≤ 3", value: share.formatted(.percent.precision(.fractionLength(0))))
                }
            } else {
                Text("强度未记录").font(.title2.bold())
                Text("可在记录明细中补录每组 RIR；未记录不会计作 0。")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text("已评分 \(result.rated) / \(result.total) 组 · 未记录 \(result.missing) 组")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !result.weeks.isEmpty {
                Chart(result.weeks) { week in
                    LineMark(x: .value("周", week.date), y: .value("平均 RIR", week.average)).foregroundStyle(.orange)
                    PointMark(x: .value("周", week.date), y: .value("平均 RIR", week.average)).foregroundStyle(.orange)
                }
                .chartYScale(domain: 0...max(4, result.weeks.map(\.average).max() ?? 4))
                .frame(height: compact ? 140 : min(240, max(170, height * 0.32)))
                .accessibilityLabel("每周已评分组的平均 RIR")
            }
            detailsButton(.intensity, title: "强度分布与动作力量趋势")
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func recordsPage(compact: Bool, height: CGFloat) -> some View {
        let monthly = allWorkouts.filter {
            $0.finishedAt.map { Calendar.current.isDate($0, equalTo: visibleMonth, toGranularity: .month) } ?? false
        }.count
        let summary = BodyAnalytics.summary(store.workouts, now: .now)
        let recentDays = BodyAnalytics.recordDays(workouts: allWorkouts, weights: [], measurements: [])
        return VStack(alignment: .leading, spacing: compact ? 10 : 16) {
            heading(.records, subtitle: "训练日期与锻炼内容")
            Text("\(visibleMonth.formatted(.dateTime.year().month())) · \(monthly) 次训练")
                .font(.headline).fixedSize(horizontal: false, vertical: true)
            Text("累计 \(allWorkouts.count) 次 · 本周 \(summary.week) 次 · 连续 \(summary.consecutiveWeeks) 周")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Chart(store.monthCounts()) { month in
                BarMark(x: .value("月份", month.month, unit: .month), y: .value("训练次数", month.count))
                    .foregroundStyle(.green)
            }
            .frame(height: compact ? 140 : min(240, max(170, height * 0.30)))
            .accessibilityLabel("近12个月训练次数")
            if !compact {
                Text("最近记录日期").font(.subheadline).foregroundStyle(.secondary)
                if recentDays.isEmpty { Text("还没有记录").foregroundStyle(.secondary) }
                ForEach(Array(recentDays.prefix(2)), id: \.self) { day in
                    Button {
                        selectedRecordDate = day
                        visibleMonth = day
                        detail = .records
                    } label: {
                        Text(day, format: .dateTime.year().month().day().weekday())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }.buttonStyle(.bordered)
                    .accessibilityHint("打开这一天的锻炼明细")
                }
            }
            detailsButton(.records, title: "日历与全部训练记录")
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func minimalContent(_ section: BodySection) -> some View {
        // At accessibility sizes / short landscape heights, the sheet keeps the
        // complete charts and editable history scrollable instead of clipping a card.
        ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: 12) {
                Label(section.rawValue, systemImage: section.symbol).font(.headline)
                if section == .weight, let latest = allWeights.last {
                    Text("\(formatKg(latest.kilograms)) kg").font(.title2.bold()).monospacedDigit()
                }
                detailsButton(section, title: "查看\(section.rawValue)详情")
            }.fixedSize(horizontal: false, vertical: true)
            // The shortest landscape + largest text combination still has a readable
            // system button to the complete scrolling content, without a nested scroller.
            Button("\(section.rawValue)详情") {
                if section == .records { selectedRecordDate = nil }
                detail = section
            }
                .buttonStyle(.bordered).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// All expanding content lives in a native sheet, independent of the four page heights.
private struct BodyDetailSheet: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let section: BodySection
    @Binding var weightRange: BodyRange
    @Binding var trainingRange: BodyRange
    var recordDate: Date?
    var recordMonth: Date
    @State private var selectedWeightDate: Date?
    @State private var entry: BodyEntryRequest?
    @State private var showGoal = false
    @State private var goalText = ""
    @State private var weighInLimit = 10
    @State private var exerciseId = ""

    private var sessions: [WorkoutSession] { BodyAnalytics.workouts(store.workouts, range: trainingRange, now: .now) }
    private var weights: [WeighIn] { BodyAnalytics.weights(store.weighIns, range: weightRange, now: .now) }
    private var allWeights: [WeighIn] { BodyAnalytics.weights(store.weighIns, range: .all, now: .now) }

    var body: some View {
        NavigationStack {
            List {
                switch section {
                case .weight:
                    weightSection
                    measurementSection
                case .muscle:
                    muscleSection
                case .intensity:
                    intensitySection
                    Section("动作力量趋势") { exerciseChart }
                case .records:
                    trainingSummary
                    BodyRecordsSection(selectedDate: recordDate, visibleMonth: recordMonth)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("\(section.rawValue)详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Menu("新增记录", systemImage: "plus") {
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
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var weightSection: some View {
        Section {
            if let latest = allWeights.last {
                VStack(alignment: .leading, spacing: 8) {
                    Text("最新体重").font(.subheadline).foregroundStyle(.secondary)
                    Text("\(formatKg(latest.kilograms)) kg").font(.largeTitle.bold()).monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                    if weights.count > 1, let first = weights.first, let last = weights.last {
                        LabeledContent(weightRange == .all ? "全部记录变化" : "近\(weightRange.rawValue)天变化",
                                       value: "\(signedKg(last.kilograms - first.kilograms)) kg")
                    }
                    Text(latest.date, format: .dateTime.year().month().day()).font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            } else {
                ContentUnavailableView("还没有体重记录", systemImage: "scalemass", description: Text("记录后即可查看变化曲线。"))
            }
            BodyWeightRangePicker(selection: $weightRange)
            if !weights.isEmpty { weightChart }
            else if !allWeights.isEmpty { Text("所选时间内没有称重记录，试试选择“全部”。").foregroundStyle(.secondary) }
            Button("记体重", systemImage: "plus") { entry = .weight() }.buttonStyle(.borderedProminent)
            Button(store.targetKg.map { "目标 \(formatKg($0)) kg" } ?? "设置目标", systemImage: "scope") {
                goalText = store.targetKg.map(formatKg) ?? ""
                showGoal = true
            }.buttonStyle(.bordered)
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
        BodyWeightChart(points: weights, target: store.targetKg, selectedDate: $selectedWeightDate, height: 220)
            .padding(.vertical, 8)
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
        }.fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
    }

    private var muscleSection: some View {
        let loads = BodyAnalytics.muscleLoads(sessions, muscles: Catalogue.musclesById)
        let covered = Set(loads.map(\.id))
        let uncovered = Catalogue.muscleOrder.filter { !covered.contains($0) }
        return Section {
            Picker("统计范围（肌肉与强度）", selection: $trainingRange) {
                ForEach(BodyRange.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.menu)
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
                Text("训练完成一组后，或在“记录”页的明细中展开训练，即可选填还能完成的次数（RIR）。").foregroundStyle(.secondary)
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

    private var measurementSection: some View {
        Section("身体围度") {
            if let latest = store.bodyMeasurements.max(by: { $0.date < $1.date }) {
                Text(latest.date, format: .dateTime.year().month().day()).font(.caption).foregroundStyle(.secondary)
                ForEach(BodyMeasurement.fields, id: \.self) { field in
                    if let value = latest.centimeters[field] { LabeledContent(field, value: "\(formatKg(value)) cm") }
                }
                ForEach(latest.centimeters.keys.filter { !BodyMeasurement.fields.contains($0) }.sorted(), id: \.self) { field in
                    if let value = latest.centimeters[field] { LabeledContent(field, value: "\(formatKg(value)) cm") }
                }
                if let fat = latest.bodyFatPercent { LabeledContent("体脂率", value: "\(formatKg(fat))%") }
            } else { Text("还没有围度记录").foregroundStyle(.secondary) }
            Button("记围度", systemImage: "plus") { entry = .measurement() }.buttonStyle(.bordered)
            Text("按日期回看围度记录，请在“记录”页的明细中选择“围度”。").font(.caption).foregroundStyle(.secondary)
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

private struct BodyWeightRangePicker: View {
    @Binding var selection: BodyRange
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if !typeSize.isAccessibilitySize {
                HStack(spacing: 0) {
                    ForEach(BodyRange.allCases) { range in
                        let selected = range == selection
                        Button { selection = range } label: {
                            Text(range.title)
                                .font(.subheadline.weight(selected ? .semibold : .regular))
                                .foregroundStyle(selected ? Color.primary : Color.secondary)
                                .fixedSize()
                                .padding(.horizontal, 8)
                                .frame(minWidth: 44, minHeight: 44)
                                .frame(maxWidth: .infinity)
                                .overlay(alignment: .bottom) {
                                    if selected { Capsule().fill(.green).frame(width: 20, height: 2) }
                                }
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .contentShape(.rect)
                .simultaneousGesture(DragGesture(minimumDistance: 16).onEnded { value in
                    let dx = value.translation.width
                    guard abs(dx) >= 24, abs(dx) > abs(value.translation.height) * 1.3 else { return }
                    let ranges = BodyRange.allCases
                    guard let index = ranges.firstIndex(of: selection) else { return }
                    let forward = layoutDirection == .leftToRight ? dx < 0 : dx > 0
                    let next = index + (forward ? 1 : -1)
                    if ranges.indices.contains(next) { selection = ranges[next] }
                })
                .accessibilityElement(children: .contain)
                .accessibilityLabel("体重范围")
            }
            Picker("体重范围", selection: $selection) {
                ForEach(BodyRange.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.menu)
        }
    }
}

private struct BodyWeightChart: View {
    let points: [WeighIn]
    let target: Double?
    @Binding var selectedDate: Date?
    let height: CGFloat

    private var selectedPoint: WeighIn? {
        guard let date = selectedDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    var body: some View {
        let values = points.map(\.kilograms) + (target.map { [$0] } ?? [])
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let padding = max(0.5, (high - low) * 0.15)
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(points) { point in
                    LineMark(x: .value("日期", point.date), y: .value("体重 kg", point.kilograms)).foregroundStyle(.green)
                    PointMark(x: .value("日期", point.date), y: .value("体重 kg", point.kilograms)).foregroundStyle(.green).symbolSize(18)
                }
                if let target {
                    RuleMark(y: .value("目标 kg", target)).foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .leading) { Text("目标 \(formatKg(target)) kg").font(.caption2) }
                }
                if let point = selectedPoint {
                    RuleMark(x: .value("所选日期", point.date)).foregroundStyle(.secondary)
                }
            }
            .chartYScale(domain: max(0, low - padding)...(high + padding))
            .chartXSelection(value: $selectedDate)
            .frame(height: height)
            .accessibilityLabel("体重变化曲线，\(points.count)条记录")
            // Reserve a caption before interaction; the enclosing page retains its viewport height.
            Text(selectedPoint.map { "\($0.date.formatted(date: .abbreviated, time: .omitted)) · \(formatKg($0.kilograms)) kg" }
                 ?? "轻触或拖动曲线查看记录")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
