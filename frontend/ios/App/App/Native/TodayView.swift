import SwiftUI

struct TodayView: View {
    @Environment(GymStore.self) private var store
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var showSettings = false
    @State private var showHealthImport = false
    @State private var selectedSupplement: Supplement?
    @State private var pendingWaterML = 250
    @State private var initializedWaterAmount = false
    @State private var waterConfirmation = 0
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 74.0

    private var wellness: WellnessStore { store.wellness }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let wide = geometry.size.width > geometry.size.height * 1.5
                let contentWidth = min(wide ? 1000 : 600, max(0, geometry.size.width - 32))
                let contentHeight = max(0, geometry.size.height - 16)
                Group {
                    if wide {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(spacing: 10) {
                                workoutSummary(compact: true)
                                supplements(compact: true)
                            }.frame(maxWidth: .infinity)
                            hydration(compact: true).frame(maxWidth: .infinity)
                        }
                    } else {
                        // Measure both complete layouts. Neither candidate crops
                        // cards or removes content to fit a shorter safe area.
                        ViewThatFits(in: .vertical) {
                            dashboard(compact: false).fixedSize(horizontal: false, vertical: true)
                            dashboard(compact: true).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(width: contentWidth, height: contentHeight, alignment: .top)
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .background {
                // Background can extend under navigation; the foreground above
                // uses only the hosting controller's actual safe viewport.
                WaterBackground(progress: wellness.waterFill, active: store.tab == .today && !showSettings && !showHealthImport && selectedSupplement == nil)
            }
            .navigationTitle("今天")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 4) {
                        Text("今天").font(.headline)
                        NavigationLink { GymConnectionView() } label: {
                            Image(systemName: syncSymbol)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(store.cloud.errorMessage == nil ? Color.secondary : Color.orange)
                                .symbolEffect(.pulse, isActive: store.cloud.busy)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("同步状态")
                        .accessibilityValue(store.cloud.status)
                        .accessibilityHint("查看连接详情和同步状态")
                        .accessibilityIdentifier("home-sync-status")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("设置", systemImage: "gearshape") { showSettings = true }
                        .buttonStyle(.plain)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .sheet(isPresented: $showSettings) { WellnessSettingsSheet() }
            .sheet(isPresented: $showHealthImport) { WorkoutHealthImportSheet() }
            .sheet(item: $selectedSupplement) { supplement in DoseSheet(supplement: supplement) }
            .sensoryFeedback(.success, trigger: waterConfirmation)
            .onAppear {
                wellness.refreshTime()
                if !initializedWaterAmount {
                    pendingWaterML = wellness.state.settings.cupML
                    initializedWaterAmount = true
                }
            }
            .onChange(of: wellness.state.settings.cupML) { _, amount in pendingWaterML = amount }
        }
    }

    private var syncSymbol: String {
        if store.cloud.busy { return "arrow.triangle.2.circlepath" }
        if store.cloud.errorMessage != nil { return "exclamationmark.icloud" }
        if store.cloud.lastSync != nil && store.cloud.status == "已与网页同步" { return "checkmark.icloud" }
        return store.cloud.connected ? "icloud.and.arrow.up" : "icloud.slash"
    }

    private func dashboard(compact: Bool) -> some View {
        VStack(spacing: compact ? 10 : 16) {
            workoutSummary(compact: compact)
            hydration(compact: compact)
            supplements(compact: compact)
        }
    }

    private func workoutSummary(compact: Bool) -> some View {
        let highlighted = !store.didTrainToday
        return VStack(spacing: 8) {
            Button {
                // Open the existing chooser/resume flow. Merely entering the card
                // must never create a session or replace an unfinished one.
                store.tab = .workout
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: store.active == nil ? "dumbbell.fill" : "play.fill")
                        .font(compact ? .title3 : .title2).padding(compact ? 10 : 12)
                        .background(.quaternary, in: .circle).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("今日训练").font(compact ? .caption : .subheadline)
                            Spacer(minLength: 0)
                            Text(trainingActionTitle).font(compact ? .caption.bold() : .subheadline.bold())
                        }
                        Text(store.todayTitle).font(compact ? .headline : .title3.bold())
                            .fixedSize(horizontal: false, vertical: true)
                        if let detail = trainingDetail {
                            Text(detail).font(compact ? .caption : .subheadline)
                                .foregroundStyle(highlighted ? Color.white : Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(compact ? 12 : 16)
                .contentShape(RoundedRectangle(cornerRadius: 24))
            }
            .buttonStyle(HomeTrainingCardStyle(highlighted: highlighted))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(trainingActionTitle)，\(store.todayTitle)")
            .accessibilityValue(trainingDetail ?? "")
            .accessibilityHint(store.active != nil ? "继续未完成的训练" : "打开训练选择，可选择计划或自由训练")
            .accessibilityIdentifier("home-training-card")
            Button { showHealthImport = true } label: {
                Label("上传健康运动", systemImage: "heart.text.square")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityHint("从健康手动选择运动并独立上传，无需开始训练")
            .accessibilityIdentifier("home-health-import")
        }
    }

    private var trainingActionTitle: String {
        if store.active != nil { return "继续训练" }
        return store.didTrainToday ? "再次训练" : "开始训练"
    }

    private var trainingDetail: String? {
        if store.active != nil { return "已完成 \(store.activeDoneCount)/\(store.activeSetCount) 组 · 可继续训练" }
        if store.didTrainToday { return "今天的训练已记录" }
        return store.todayDetail
    }

    private func hydration(compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("今日饮水").font(.headline)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(wellness.todayWater, format: .number.grouping(.never))
                        .font(.system(size: min(amountSize, compact ? 62 : 80), weight: .bold, design: .rounded))
                        .monospacedDigit().minimumScaleFactor(0.3).lineLimit(1)
                        .contentTransition(.numericText())
                    Text("mL").font(.headline).fixedSize()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("今日已饮水 \(wellness.todayWater) 毫升")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 4) {
                Text("本次新增").font(.caption).foregroundStyle(.secondary)
                Picker("本次新增水量", selection: $pendingWaterML) {
                    ForEach(waterAmounts, id: \.self) { amount in
                        Text("\(amount) mL").font(.body.monospacedDigit()).tag(amount)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(width: compact ? 112 : 132, height: compact ? 92 : 112)
                .clipped() // Only the wheel's scrolling viewport, never a dashboard card.
                .contentShape(Rectangle())
                .accessibilityHint("上下滑动选择，点确定后才保存")
                .accessibilityIdentifier("home-water-amount")
                Button(action: confirmWater) {
                    Text("确定").font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(HomeFunctionButtonStyle(prominent: true))
                .accessibilityLabel("确认添加 \(pendingWaterML) 毫升饮水")
                .accessibilityIdentifier("home-water-confirm")
            }
            .frame(width: compact ? 112 : 132)
        }
        .padding(.horizontal, 8).padding(.vertical, compact ? 0 : 6)
        .foregroundStyle(.primary)
    }

    private var waterAmounts: [Int] {
        Array(Set(Array(stride(from: 50, through: 2000, by: 50)) + [wellness.state.settings.cupML])).sorted()
    }

    private func confirmWater() {
        withAnimation(.snappy) {
            if wellness.addWater(pendingWaterML) { waterConfirmation += 1 }
        }
    }

    private func supplements(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            Text("今日服用").font(.headline).modifier(WaterForegroundText())
            supplementRow(.b, compact: compact)
            Divider()
            supplementRow(.d, compact: compact)
        }
        .padding(compact ? 12 : 16)
    }

    private func supplementRow(_ supplement: Supplement, compact: Bool) -> some View {
        let instances = wellness.state.instances(for: supplement, on: wellness.now)
        let done = instances.filter { wellness.state.record(for: $0) != nil }.count
        return HStack(spacing: 8) {
            supplementLabel(supplement, instances: instances, done: done, compact: compact)
            Spacer(minLength: 0)
            supplementAction(supplement, hasInstances: !instances.isEmpty, complete: done == instances.count)
        }
    }

    private func supplementLabel(_ supplement: Supplement, instances: [DoseInstance], done: Int, compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 12) {
            Image(systemName: "pills.fill").font(compact ? .title3 : .title2)
                .foregroundStyle(contrast == .increased ? Color.primary : supplement == .b ? Color.orange : Color.mint)
                .frame(width: compact ? 28 : 36).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(supplement.name).font(.headline).modifier(WaterForegroundText())
                Text(supplementCaption(supplement, instances: instances, done: done))
                    .font(compact ? .caption : .subheadline).modifier(WaterForegroundText())
                    .fixedSize(horizontal: false, vertical: true)
                if supplement == .b {
                    HStack(spacing: 6) {
                        ForEach(instances) { instance in
                            Image(systemName: wellness.state.record(for: instance) == nil ? "circle" : "checkmark.circle.fill")
                                .foregroundStyle(contrast == .increased || wellness.state.record(for: instance) == nil ? Color.primary : Color.accentColor)
                        }
                    }.font(.caption).accessibilityHidden(true)
                }
            }
        }
    }

    @ViewBuilder private func supplementAction(_ supplement: Supplement, hasInstances: Bool, complete: Bool) -> some View {
        if hasInstances {
            Button(complete ? "已服用" : "记录") { selectedSupplement = supplement }
                .buttonStyle(HomeFunctionButtonStyle()).fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("\(supplement.name)\(complete ? "查看服用记录" : "记录服用")")
        } else if supplement == .d && wellness.state.settings.dWeekday == nil {
            Button("设置") { showSettings = true }.buttonStyle(HomeFunctionButtonStyle())
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

private struct HomeTrainingCardStyle: ButtonStyle {
    var highlighted: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(highlighted ? Color.white : Color.primary)
            .background {
                if highlighted {
                    RoundedRectangle(cornerRadius: 24).fill(Color(uiColor: .systemIndigo))
                } else {
                    // Keep the existing neutral training card after completion.
                    RoundedRectangle(cornerRadius: 24).fill(.regularMaterial)
                }
            }
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

// A small halo around glyphs preserves the visible water behind the section.
// Primary text adapts to appearance; increased contrast strengthens the halo.
private struct WaterForegroundText: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .foregroundStyle(.primary)
            .shadow(color: (colorScheme == .dark ? Color.black : Color.white)
                .opacity(contrast == .increased ? 0.95 : 0.8),
                    radius: contrast == .increased ? 2 : 1, x: 0, y: 0)
    }
}

// Content actions use solid color/fill, with one prominent confirmation action.
// The navigation bar and tab bar keep their system-provided materials.
private struct HomeFunctionButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .foregroundStyle(prominent ? Color.white : contrast == .increased ? Color.primary : Color.accentColor)
            .background(prominent ? Color.accentColor : Color(uiColor: .tertiarySystemFill),
                        in: RoundedRectangle(cornerRadius: 14))
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
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
