import SwiftUI

struct TodayView: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showSettings = false
    @State private var showWaterEntry = false
    @State private var selectedSupplement: Supplement?
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 86.0

    private var wellness: WellnessStore { store.wellness }

    var body: some View {
        NavigationStack {
            ZStack {
                WaterBackground(progress: wellness.waterFill, active: store.tab == .today && !showSettings && !showWaterEntry && selectedSupplement == nil)
                ScrollView {
                    VStack(spacing: 20) {
                        NavigationLink { GymConnectionView() } label: {
                            Label(store.cloud.status, systemImage: store.cloud.errorMessage == nil ? "icloud" : "icloud.slash")
                                .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain)
                        workoutSummary
                        hydration
                        supplements
                    }
                    .frame(maxWidth: 600)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("今天")
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("设置", systemImage: "gearshape") { showSettings = true }
                }
            }
            .sheet(isPresented: $showSettings) { WellnessSettingsSheet() }
            .sheet(isPresented: $showWaterEntry) { WaterEntrySheet() }
            .sheet(item: $selectedSupplement) { supplement in DoseSheet(supplement: supplement) }
        }
    }

    private var workoutSummary: some View {
        HStack(spacing: 16) {
            Image(systemName: "dumbbell.fill")
                .font(.title2).foregroundStyle(.secondary).padding(14)
                .background(.quaternary, in: .circle).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("今日训练").font(.subheadline).foregroundStyle(.secondary)
                Text(store.todayTitle).font(.title2.bold())
                if let detail = trainingDetail { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
        .accessibilityElement(children: .combine)
    }

    private var trainingDetail: String? {
        if store.active != nil { return "已完成 \(store.activeDoneCount)/\(store.activeSetCount) 组 · 在“开始”继续" }
        if store.didTrainToday { return "今天的训练已记录" }
        return store.todayDetail
    }

    private var hydration: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日饮水").font(.headline)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(wellness.todayWater, format: .number.grouping(.never))
                    .font(.system(size: min(amountSize, 130), weight: .bold, design: .rounded))
                    .monospacedDigit().minimumScaleFactor(0.4).lineLimit(1)
                    .contentTransition(.numericText())
                Text("mL").font(.title2.bold())
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("今日已饮水 \(wellness.todayWater) 毫升")
            if let goal = wellness.state.settings.waterGoalML {
                Text("目标 \(goal) mL · 已完成 \(Int(wellness.progress * 100))%")
                    .font(.subheadline.weight(.medium))
                if wellness.progress > 1 {
                    Text("已超过目标 \(wellness.todayWater - goal) mL").font(.caption)
                }
            } else {
                Text("未设目标 · 水位满刻度 \(wellness.state.waterScaleML) mL")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("设置每日饮水目标", systemImage: "slider.horizontal.3") { showSettings = true }
                    .buttonStyle(.glass)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { waterButtons }
                VStack(spacing: 12) { waterButtons }
            }.padding(.top, 10)
            if let id = wellness.lastAddedWaterID,
               let entry = wellness.state.water.first(where: { $0.id == id }),
               entry.day == WellnessDay.key(wellness.now) {
                HStack {
                    Text("已记录 \(entry.milliliters) mL").font(.caption)
                    Spacer()
                    Button("撤销") { wellness.removeWater(id) }.font(.subheadline).frame(minHeight: 44)
                }.accessibilityElement(children: .contain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8).foregroundStyle(.primary)
    }

    @ViewBuilder private var waterButtons: some View {
        Button { _ = wellness.addWater(wellness.state.settings.cupML) } label: {
            Text("+\(wellness.state.settings.cupML) mL").font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 10)
        }
        .buttonStyle(.glass)
        .accessibilityLabel("记录饮水 \(wellness.state.settings.cupML) 毫升")
        Button { showWaterEntry = true } label: {
            Text("自定义").font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 10)
        }.buttonStyle(.glass)
    }

    private var supplements: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日服用").font(.headline).foregroundStyle(.secondary)
            supplementRow(.b)
            Divider()
            supplementRow(.d)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
    }

    private func supplementRow(_ supplement: Supplement) -> some View {
        let instances = wellness.state.instances(for: supplement, on: wellness.now)
        let done = instances.filter { wellness.state.record(for: $0) != nil }.count
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    supplementLabel(supplement, instances: instances, done: done)
                    supplementAction(supplement, hasInstances: !instances.isEmpty, complete: done == instances.count)
                }
            } else {
                HStack(spacing: 10) {
                    supplementLabel(supplement, instances: instances, done: done)
                    Spacer(minLength: 0)
                    supplementAction(supplement, hasInstances: !instances.isEmpty, complete: done == instances.count)
                }
            }
        }
    }

    private func supplementLabel(_ supplement: Supplement, instances: [DoseInstance], done: Int) -> some View {
            HStack(spacing: 12) {
                Image(systemName: "pills.fill").font(.title2)
                    .foregroundStyle(supplement == .b ? Color.orange : Color.mint)
                    .frame(width: 44, height: 44).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(supplement.name).font(.title3.bold())
                    Text(supplementCaption(supplement, instances: instances, done: done))
                        .font(.subheadline).foregroundStyle(.secondary)
                    if supplement == .b {
                        HStack(spacing: 8) {
                            ForEach(instances) { instance in
                                Image(systemName: wellness.state.record(for: instance) == nil ? "circle" : "checkmark.circle.fill")
                                    .foregroundStyle(wellness.state.record(for: instance) == nil ? Color.secondary : Color.accentColor)
                            }
                        }.accessibilityHidden(true)
                    }
                }
            }
    }

    @ViewBuilder private func supplementAction(_ supplement: Supplement, hasInstances: Bool, complete: Bool) -> some View {
        if hasInstances {
            Button(complete ? "已服用" : "记录") { selectedSupplement = supplement }
                .buttonStyle(.glass).controlSize(.large).fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("\(supplement.name)\(complete ? "查看服用记录" : "记录服用")")
        } else if supplement == .d && wellness.state.settings.dWeekday == nil {
            Button("设置") { showSettings = true }.buttonStyle(.glass).controlSize(.large)
                .accessibilityLabel("设置维生素 D 每周服用日")
        }
    }

    private func supplementCaption(_ supplement: Supplement, instances: [DoseInstance], done: Int) -> String {
        if instances.isEmpty {
            guard let day = wellness.state.settings.dWeekday else { return "每周 1 次 · 待设置星期" }
            let week = WellnessDay.weekKey(wellness.now)
            if wellness.state.doses.contains(where: { $0.supplement == .d && $0.period == week }) { return "本周已服用 · 今天无待办" }
            return "今天无待办 · 每\(Weekday.name(day))"
        }
        if done == instances.count { return supplement == .b ? "今日 3/3 · 已完成" : "本周已服用" }
        if let next = instances.first(where: { wellness.state.record(for: $0) == nil })?.time {
            return "今日 \(done)/\(instances.count) · 待服用 \(next.label)"
        }
        return "今日 \(done)/\(instances.count) · 时点待设置"
    }
}

struct WeighInSheet: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                TextField("体重 kg", text: $text)
                    .keyboardType(.decimalPad)
                DatePicker("日期", selection: $date, displayedComponents: .date)
            }
            .navigationTitle("记体重")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let kilograms = parseKg(text) {
                            store.addWeighIn(kilograms: kilograms, date: date)
                            dismiss()
                        }
                    }
                    .disabled(parseKg(text) == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
