import SwiftUI

struct WaterView: View {
    @Environment(GymStore.self) private var store
    @State private var showAdd = false
    @State private var showSettings = false
    @State private var editEntry: WaterEntry?
    @State private var day = Date()
    @State private var followToday = true

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
                    LabeledContent("已记录", value: "\(entries.reduce(0) { $0 + $1.milliliters }) mL")
                    if Calendar.current.isDateInToday(day), let goal = wellness.state.settings.waterGoalML {
                        LabeledContent("今日目标", value: "\(goal) mL")
                        ProgressView(value: min(1, wellness.progress))
                            .accessibilityLabel("已完成 \(Int(wellness.progress * 100))%")
                    }
                    Button("记录饮水", systemImage: "plus") { showAdd = true }.buttonStyle(.glassProminent)
                }
                Section("饮水记录") {
                    if entries.isEmpty { Text("这一天还没有饮水记录").foregroundStyle(.secondary) }
                    ForEach(entries) { entry in
                        Button { editEntry = entry } label: {
                            HStack {
                                Label("\(entry.milliliters) mL", systemImage: "drop.fill")
                                Spacer()
                                Text(entry.date, style: .time).foregroundStyle(.secondary)
                            }.foregroundStyle(.primary).frame(minHeight: 32)
                        }
                        .swipeActions { Button("删除", role: .destructive) { wellness.removeWater(entry.id) } }
                    }
                }
                Section("服用记录") {
                    let doses = wellness.state.doses.filter { $0.takenDay == WellnessDay.key(day) }
                        .sorted { $0.takenAt > $1.takenAt }
                    if doses.isEmpty { Text("这一天还没有服用记录").foregroundStyle(.secondary) }
                    ForEach(doses) { record in
                        HStack {
                            VStack(alignment: .leading) {
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
            .navigationTitle("喝水")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("设置", systemImage: "gearshape") { showSettings = true }
                }
            }
            .sheet(isPresented: $showAdd) { WaterEntrySheet(initialDate: Calendar.current.isDateInToday(day) ? Date() : day) }
            .sheet(item: $editEntry) { WaterEntrySheet(entry: $0) }
            .sheet(isPresented: $showSettings) { WellnessSettingsSheet() }
            .onChange(of: WellnessDay.key(wellness.now)) { _, _ in if followToday { day = wellness.now } }
        }
    }
}

struct WaterEntrySheet: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var entry: WaterEntry?
    var initialDate = Date()
    @State private var amount = ""
    @State private var date = Date()

    private var parsed: Int? {
        guard let value = Int(amount.trimmingCharacters(in: .whitespaces)), (1...5000).contains(value) else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error = store.wellness.errorMessage { Text(error).foregroundStyle(.red) }
                Section {
                    TextField("饮水量 mL", text: $amount).keyboardType(.numberPad)
                    DatePicker("时间", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                } footer: { Text("记录实际喝下的水量，单位 mL。可以在喝水页修改或删除。") }
            }
            .navigationTitle(entry == nil ? "记录饮水" : "修改记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard let value = parsed else { return }
                        let saved: Bool
                        if let entry { saved = store.wellness.editWater(entry.id, amount: value, date: date) }
                        else { saved = store.wellness.addWater(value, at: date) }
                        if saved { dismiss() }
                    }.disabled(parsed == nil || date > Date())
                }
            }
            .onAppear {
                amount = entry.map { String($0.milliliters) } ?? ""
                date = entry?.date ?? min(initialDate, Date())
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
                                Button("撤销这次记录", role: .destructive) { store.wellness.undoDose(instance.id) }.buttonStyle(.glass)
                            } else {
                                Button("确认这次已服用") { store.wellness.recordDose(instance) }.buttonStyle(.glassProminent)
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
