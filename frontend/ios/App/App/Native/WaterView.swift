import SwiftUI

struct WaterView: View {
    @Environment(GymStore.self) private var store
    @State private var showAdd = false
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var selectedSupplement: Supplement?
    @State private var drink: DrinkKind = .water
    @State private var selectedAmount: Int?
    @State private var savedCount = 0
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 76.0

    private var wellness: WellnessStore { store.wellness }
    private var entries: [WaterEntry] {
        wellness.state.water.filter { $0.day == WellnessDay.key(wellness.now) }.sorted { $0.date > $1.date }
    }
    private var amount: Int { selectedAmount ?? wellness.state.settings.cupML }
    private var amounts: [Int] { Array(Set([150, 250, 350, 500, wellness.state.settings.cupML])).sorted() }
    private var lastRecordedEntry: WaterEntry? {
        guard let id = wellness.lastAddedWaterID else { return nil }
        return entries.first { $0.id == id }
    }
    private var scheduledDoses: [DoseInstance] {
        Supplement.allCases.flatMap { wellness.state.instances(for: $0, on: wellness.now) }
            .filter { $0.time != nil }
            .sorted { ($0.time?.minutes ?? 0) < ($1.time?.minutes ?? 0) }
    }
    private var pendingDoses: [DoseInstance] { scheduledDoses.filter { wellness.state.record(for: $0) == nil } }
    private var waterActive: Bool {
        store.tab == .water && !showAdd && !showSettings && !showHistory && selectedSupplement == nil
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                // The host owns the tab-bar reservation. Only this foreground
                // GeometryReader defines our viewport; the full-screen water
                // is a background and cannot enlarge the content's proposal.
                let landscape = geometry.size.width > geometry.size.height * 1.35
                let contentWidth = min(landscape ? 1000 : 560, max(0, geometry.size.width - 32))
                let contentHeight = max(0, geometry.size.height - 16)
                Group {
                    if landscape {
                        // Short, wide safe areas use both columns instead of
                        // putting the controls below an oversized header.
                        HStack(spacing: 20) {
                            VStack(spacing: 8) {
                                progressHeader(compact: true)
                                if !scheduledDoses.isEmpty { supplementReminder(compact: true) }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                            quickRecorder(compact: true)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        // The layout reports the complete intrinsic height,
                        // excluding expandable spacers, to this fit decision.
                        ViewThatFits(in: .vertical) {
                            dashboard(compact: false)
                            dashboard(compact: true)
                        }
                    }
                }
                .frame(width: contentWidth, height: contentHeight, alignment: .top)
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .background {
                WaterBackground(progress: wellness.waterFill, active: waterActive)
            }
            .navigationTitle("喝水")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("喝水历史", systemImage: "clock.arrow.circlepath") { showHistory = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("设置", systemImage: "slider.horizontal.3") { showSettings = true }
                }
            }
            .sheet(isPresented: $showAdd) { WaterEntrySheet(initialDrink: drink, initialAmount: amount) }
            .sheet(isPresented: $showSettings) { WellnessSettingsSheet() }
            .sheet(isPresented: $showHistory) { WaterHistorySheet() }
            .sheet(item: $selectedSupplement) { DoseSheet(supplement: $0) }
            .sensoryFeedback(.success, trigger: savedCount)
            .onAppear { wellness.refreshTime() }
        }
    }

    private func dashboard(compact: Bool) -> some View {
        WaterDashboardLayout(spacing: compact ? 6 : 12) {
            progressHeader(compact: compact).fixedSize(horizontal: false, vertical: true)
            if !scheduledDoses.isEmpty {
                supplementReminder(compact: compact).fixedSize(horizontal: false, vertical: true)
            }
            quickRecorder(compact: compact).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func progressHeader(compact: Bool) -> some View {
        VStack(spacing: compact ? 4 : 8) {
            if !compact {
                Text("今日饮水").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(wellness.todayWater, format: .number.grouping(.never))
                    .font(.system(size: min(amountSize, compact ? 44 : 120), weight: .bold, design: .rounded))
                    .monospacedDigit().contentTransition(.numericText())
                    .lineLimit(1).minimumScaleFactor(0.4)
                Text("mL").font(.title2.weight(.semibold))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("今日已记录饮品 \(wellness.todayWater) 毫升")
            if let goal = wellness.state.settings.waterGoalML {
                Text("目标 \(goal) mL · 已完成 \(Int(wellness.progress * 100))%")
                    .font(compact ? .caption.weight(.medium) : .subheadline.weight(.medium))
                Text(wellness.todayWater >= goal ? "今日目标已完成" : "距离目标还有 \(goal - wellness.todayWater) mL")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Button { showSettings = true } label: {
                    Label("设置每日目标", systemImage: "slider.horizontal.3").font(.subheadline)
                }.buttonStyle(WaterActionButtonStyle())
                Text("未设目标 · 水位满刻度 \(wellness.state.waterScaleML) mL")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func supplementReminder(compact: Bool) -> some View {
        let next = pendingDoses.first ?? scheduledDoses.first
        return Group {
            if let next {
                Button { selectedSupplement = next.supplement } label: {
                    HStack(spacing: 12) {
                        Image(systemName: pendingDoses.isEmpty ? "checkmark.circle.fill" : "pills.fill")
                            .font(.title2).foregroundStyle(.secondary).frame(width: 36)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pendingDoses.isEmpty ? "今日服用已记录" : "今日服用 · \(next.supplement.name)")
                                .font(.subheadline.weight(.semibold))
                            Text(pendingDoses.isEmpty ? "查看服用记录" : "\(next.time?.label ?? "") · 还有 \(pendingDoses.count) 次待记录")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44).padding(compact ? 0 : 14)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain).foregroundStyle(.primary)
                .accessibilityHint("打开服用计划，实际服用后再确认")
            }
        }
    }

    private func quickRecorder(compact: Bool) -> some View {
        VStack(spacing: compact ? 8 : 18) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: compact ? 8 : 12) {
                    ForEach(DrinkKind.allCases) { kind in
                        Button { drink = kind } label: {
                            if compact {
                                Label(kind.name, systemImage: kind.symbol)
                                    .font(.subheadline.weight(drink == kind ? .semibold : .regular))
                                    .fixedSize(horizontal: true, vertical: true)
                                    .padding(.horizontal, 12).frame(minHeight: 44)
                                    .foregroundStyle(drink == kind ? Color.accentColor : Color.primary)
                                    .background(drink == kind ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.07), in: .capsule)
                            } else {
                                VStack(spacing: 7) {
                                    Image(systemName: kind.symbol)
                                        .font(.system(size: 28, weight: .medium))
                                        .frame(width: 56, height: 56)
                                        .foregroundStyle(drink == kind ? Color.accentColor : Color.primary)
                                        .background(drink == kind ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.07), in: .circle)
                                        .overlay(alignment: .bottomTrailing) {
                                            if drink == kind {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.caption).foregroundStyle(Color.accentColor)
                                                    .background(.background, in: .circle)
                                            }
                                        }
                                    Text(kind.name).font(.caption.weight(drink == kind ? .semibold : .regular))
                                }
                                .frame(minWidth: 58).padding(.vertical, 3)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(kind.name)
                        .accessibilityAddTraits(drink == kind ? [.isSelected] : [])
                    }
                }.padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .fixedSize(horizontal: false, vertical: true)
            if compact {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        amountMenu
                        recordButton(compact: true)
                        customButton(compact: true)
                        if lastRecordedEntry != nil { undoButton(compact: true) }
                    }
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            amountMenu
                            customButton(compact: true)
                            if lastRecordedEntry != nil { undoButton(compact: true) }
                        }
                        recordButton(compact: true)
                    }
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(amounts, id: \.self) { value in
                            Button { selectedAmount = value } label: {
                                Text("\(value) mL").font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14).frame(minHeight: 44)
                                    .foregroundStyle(amount == value ? Color.white : Color.primary)
                                    .background(amount == value ? Color.accentColor : Color.secondary.opacity(0.08), in: .capsule)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(value) 毫升")
                            .accessibilityAddTraits(amount == value ? [.isSelected] : [])
                        }
                    }.padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        recordButton(compact: false)
                        customButton(compact: false)
                    }
                    VStack(spacing: 6) {
                        recordButton(compact: false)
                        customButton(compact: false)
                    }
                }
            }
            if let entry = lastRecordedEntry {
                HStack {
                    Text("\(entry.drink.name) · \(entry.milliliters) mL 已记录").font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    if !compact {
                        Spacer(minLength: 8)
                        undoButton(compact: false)
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
    }

    private var amountMenu: some View {
        Menu {
            Picker("容量", selection: Binding(get: { amount }, set: { selectedAmount = $0 })) {
                ForEach(amounts, id: \.self) { value in Text("\(value) mL").tag(value) }
            }
        } label: {
            Label("\(amount) mL", systemImage: "chevron.down")
                .font(.subheadline.weight(.semibold)).fixedSize()
                .frame(minHeight: 44)
        }
        .buttonStyle(WaterActionButtonStyle())
        .accessibilityLabel("选择容量，当前 \(amount) 毫升")
    }

    private func recordButton(compact: Bool) -> some View {
        Button {
            if wellness.addWater(amount, drink: drink) { savedCount += 1 }
        } label: {
            Label(compact ? "记录" : "记录 \(drink.name) · \(amount) mL", systemImage: "plus")
                .font(.headline).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(WaterActionButtonStyle(prominent: true))
        .accessibilityLabel("记录 \(drink.name) \(amount) 毫升")
    }

    private func customButton(compact: Bool) -> some View {
        Button { showAdd = true } label: {
            Group {
                if compact { Image(systemName: "slider.horizontal.3").frame(minWidth: 24) }
                else { Text("自定义").fixedSize() }
            }
            .font(.subheadline.weight(.medium)).frame(minHeight: 44).padding(.horizontal, 4)
        }
        .buttonStyle(WaterActionButtonStyle())
        .accessibilityLabel("自定义记录")
        .accessibilityHint("修改容量或补记之前喝的饮品")
    }

    @ViewBuilder private func undoButton(compact: Bool) -> some View {
        if let entry = lastRecordedEntry {
            Button { wellness.removeWater(entry.id) } label: {
                Group {
                    if compact { Image(systemName: "arrow.uturn.backward").frame(minWidth: 24) }
                    else { Text("撤销").fixedSize() }
                }
                .font(.subheadline).frame(minHeight: 44)
            }
            .buttonStyle(WaterActionButtonStyle())
            .accessibilityLabel("撤销刚才记录的 \(entry.drink.name) \(entry.milliliters) 毫升")
        }
    }
}

// Measures all real content before choosing a density, then anchors the action
// block to the bottom of the host-provided viewport. No guessed tab-bar height.
private struct WaterDashboardLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        let requiredHeight = heights.reduce(0, +) + spacing * CGFloat(max(0, heights.count - 1))
        return CGSize(width: width, height: max(requiredHeight, proposal.height ?? requiredHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)) }
        guard let last = sizes.indices.last else { return }
        let freeSpace = max(0, bounds.height - sizes.reduce(0) { $0 + $1.height })
        let gap = last > 0 ? freeSpace / CGFloat(last) : 0
        var y = bounds.minY
        for index in sizes.indices {
            // Use the measured height for both fitting and placement. The last
            // block ends at bounds.maxY whenever the candidate fits.
            subviews[index].place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                                  proposal: ProposedViewSize(width: bounds.width, height: sizes[index].height))
            y += sizes[index].height + gap
        }
    }
}

// Content actions intentionally use solid color / plain labels. Navigation bars,
// menus and sheet chrome keep their native system appearance.
private struct WaterActionButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, prominent ? 14 : 10)
            .padding(.vertical, 6)
            .frame(minWidth: 44, minHeight: 44)
            .foregroundStyle(configuration.role == .destructive ? Color.red : (prominent ? Color.white : Color.primary))
            .background(prominent ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(.rect)
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.45)
    }
}

private extension DrinkKind {
    var symbol: String {
        switch self {
        case .water: return "drop.fill"
        case .tea: return "leaf.fill"
        case .coffee: return "cup.and.saucer.fill"
        case .milk: return "waterbottle.fill"
        case .juice: return "carrot.fill"
        case .soda: return "bubbles.and.sparkles"
        case .other: return "mug.fill"
        }
    }
}

private struct WaterRecordRow: View {
    var entry: WaterEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.drink.symbol).font(.body).frame(width: 26).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.drink.name).font(.subheadline.weight(.medium))
                Text(entry.date, style: .time).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("\(entry.milliliters) mL").font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .foregroundStyle(.primary).frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

private struct WaterHistorySheet: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var day = Date()
    @State private var followToday = true
    @State private var showAdd = false
    @State private var editEntry: WaterEntry?

    private var wellness: WellnessStore { store.wellness }
    private var entries: [WaterEntry] {
        wellness.state.water.filter { $0.day == WellnessDay.key(day) }.sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("查看日期", selection: $day, in: ...Date(), displayedComponents: .date)
                        .onChange(of: day) { _, value in followToday = Calendar.current.isDateInToday(value) }
                    LabeledContent("已记录", value: "\(entries.reduce(0) { $0 + $1.milliliters }) mL · \(entries.count) 次")
                    Button("补记一杯", systemImage: "plus") { showAdd = true }
                }
                Section("饮水记录") {
                    if entries.isEmpty { Text("这一天还没有饮水记录").foregroundStyle(.secondary) }
                    ForEach(entries) { entry in
                        Button { editEntry = entry } label: { WaterRecordRow(entry: entry) }
                            .swipeActions { Button("删除", role: .destructive) { wellness.removeWater(entry.id) } }
                    }
                }
                Section("服用记录") {
                    let doses = wellness.state.doses.filter { $0.takenDay == WellnessDay.key(day) }
                        .sorted { $0.takenAt > $1.takenAt }
                    if doses.isEmpty { Text("这一天还没有服用记录").foregroundStyle(.secondary) }
                    ForEach(doses) { record in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.supplement.name)
                                Text(record.supplement == .b ? "第 \(record.slot + 1) 次" : "每周一次")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(record.takenAt, style: .time).foregroundStyle(.secondary)
                        }
                        .swipeActions { Button("撤销", role: .destructive) { wellness.undoDose(record.id) } }
                    }
                }
            }
            .navigationTitle("喝水历史").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(isPresented: $showAdd) { WaterEntrySheet(initialDate: Calendar.current.isDateInToday(day) ? Date() : day) }
            .sheet(item: $editEntry) { WaterEntrySheet(entry: $0) }
            .onChange(of: WellnessDay.key(wellness.now)) { _, _ in if followToday { day = wellness.now } }
        }
    }
}

struct WaterEntrySheet: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var entry: WaterEntry?
    var initialDate = Date()
    var initialDrink: DrinkKind = .water
    var initialAmount: Int?
    @State private var amount = ""
    @State private var date = Date()
    @State private var drink: DrinkKind = .water
    @State private var loaded = false
    @State private var confirmDelete = false

    private var parsed: Int? {
        guard let value = Int(amount.trimmingCharacters(in: .whitespaces)), (1...5000).contains(value) else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error = store.wellness.errorMessage { Text(error).foregroundStyle(.red) }
                Section {
                    Picker("饮品", selection: $drink) {
                        ForEach(DrinkKind.allCases) { kind in Label(kind.name, systemImage: kind.symbol).tag(kind) }
                    }
                    TextField("容量 mL", text: $amount).keyboardType(.numberPad)
                    DatePicker("时间", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                } footer: { Text("按实际喝下的饮品容量记录，单位 mL，不做补水系数换算。可输入 1–5000 mL。") }
                if entry != nil {
                    Section { Button("删除这条记录", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(entry == nil ? "记录饮水" : "修改记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard let value = parsed else { return }
                        let saved: Bool
                        if let entry { saved = store.wellness.editWater(entry.id, amount: value, date: date, drink: drink) }
                        else { saved = store.wellness.addWater(value, at: date, drink: drink) }
                        if saved { dismiss() }
                    }.disabled(parsed == nil || date > Date())
                }
            }
            .confirmationDialog("删除这条饮水记录？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除记录", role: .destructive) {
                    guard let entry else { return }
                    store.wellness.removeWater(entry.id)
                    if !store.wellness.state.water.contains(where: { $0.id == entry.id }) { dismiss() }
                }
                Button("取消", role: .cancel) {}
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                amount = String(entry?.milliliters ?? initialAmount ?? store.wellness.state.settings.cupML)
                date = entry?.date ?? min(initialDate, Date())
                drink = entry?.drink ?? initialDrink
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct DoseSheet: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var supplement: Supplement

    var body: some View {
        NavigationStack {
            List {
                if let error = store.wellness.errorMessage { Text(error).foregroundStyle(.red) }
                Section {
                    let instances = store.wellness.state.instances(for: supplement, on: store.wellness.now)
                    if instances.isEmpty { Text("今天没有这项服用计划").foregroundStyle(.secondary) }
                    ForEach(instances) { instance in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(supplement == .b ? "第 \(instance.slot + 1) 次" : "本周一次").font(.headline)
                                Spacer()
                                Text(instance.time?.label ?? "未设时点").foregroundStyle(.secondary)
                            }
                            if let record = store.wellness.state.record(for: instance) {
                                Label("已记录 · \(record.takenAt.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                Button("撤销这次记录", role: .destructive) { store.wellness.undoDose(instance.id) }
                                    .buttonStyle(WaterActionButtonStyle())
                            } else {
                                Button("确认这次已服用") { store.wellness.recordDose(instance) }
                                    .buttonStyle(WaterActionButtonStyle(prominent: true))
                            }
                        }.padding(.vertical, 6)
                    }
                } footer: { Text("按你提供的计划记录，不设置或推算服用剂量。每次服用只记录一次。") }
            }
            .navigationTitle(supplement.name).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .onAppear { store.wellness.refreshTime() }
        }
        .presentationDetents([.medium, .large])
    }
}
