import SwiftUI

struct TodayView: View {
    @Environment(GymStore.self) private var store
    @State private var showWeighIn = false
    @State private var showGoal = false
    @State private var showSettings = false
    @State private var goalText = ""

    var body: some View {
        NavigationStack {
            List {
                Section("本周") {
                    weekStrip
                }
                Section("今天") {
                    Button(action: store.openToday) {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(store.todayTitle)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                if let detail = store.todayDetail {
                                    Text(detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 8)
                            Text(store.todayAction)
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                Section("体重") {
                    weightBlock
                    Button("记一笔") { showWeighIn = true }
                        .buttonStyle(.glassProminent)
                    Button(store.targetKg == nil ? "设目标" : "改目标") {
                        goalText = store.targetKg.map(formatKg) ?? ""
                        showGoal = true
                    }
                    .buttonStyle(.glass)
                }
                Section("喝水") {
                    Button {
                        store.tab = .water
                    } label: {
                        HStack {
                            Label("喝水", systemImage: "drop")
                            Spacer()
                            Text("这一页先留着")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("今天")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("设置", systemImage: "gearshape") { showSettings = true }
                }
            }
            .sheet(isPresented: $showWeighIn) { WeighInSheet() }
            .sheet(isPresented: $showSettings) { RestSettingsSheet() }
            .alert("目标体重", isPresented: $showGoal) {
                TextField("kg", text: $goalText)
                    .keyboardType(.decimalPad)
                Button("保存") {
                    if let kilograms = parseKg(goalText) {
                        store.setTarget(kilograms)
                    }
                }
                if store.targetKg != nil {
                    Button("清除目标", role: .destructive) { store.setTarget(nil) }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("用公斤。进度条从你的第一次称重算到这个目标。")
            }
        }
    }

    private var weekStrip: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(store.weekMarks()) { day in
                    VStack(spacing: 4) {
                        Text(Weekday.short(day.day))
                            .font(.caption2)
                        Image(systemName: day.done ? "checkmark" : (day.planned ? "circle.fill" : "circle"))
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .glassEffect(day.isToday ? .regular.tint(.accentColor) : .regular, in: .capsule)
                    .accessibilityLabel(weekLabel(day))
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        .listRowBackground(Color.clear)
    }

    private var weightBlock: some View {
        Group {
            if let latest = store.latestWeighIn {
                LabeledContent("当前", value: "\(formatKg(latest.kilograms)) kg")
                if let delta = store.deltaSincePrevious {
                    LabeledContent("较上一次", value: "\(signedKg(delta)) kg")
                }
                if store.targetKg != nil {
                    LabeledContent("目标", value: "\(formatKg(store.targetKg ?? 0)) kg")
                    ProgressView(value: store.goalProgress ?? 0) {
                        Text(store.goalCaption)
                    }
                } else {
                    Text(store.goalCaption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("还没有体重记录")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func weekLabel(_ day: WeekMark) -> String {
        var parts = [Weekday.name(day.day)]
        if day.isToday { parts.append("今天") }
        if day.done { parts.append("已练") }
        else if day.planned { parts.append("有计划") }
        return parts.joined(separator: "，")
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

struct RestSettingsSheet: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Stepper(value: Binding(get: { store.restSeconds }, set: { store.setRest($0) }), in: 15...300, step: 15) {
                    Text("组间休息 \(store.restSeconds) 秒")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
