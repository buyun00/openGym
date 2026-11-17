import SwiftUI
import UIKit

struct WellnessSettingsSheet: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft = WellnessSettings()
    @State private var goalText = ""
    @State private var saving = false
    @State private var permissionMessage: String?
    @State private var loaded = false
    @State private var restSeconds = 90

    private var parsedGoal: Int? { Int(goalText.trimmingCharacters(in: .whitespaces)) }
    private var validGoal: Bool { goalText.isEmpty || parsedGoal.map { (250...10000).contains($0) } == true }

    var body: some View {
        NavigationStack {
            Form {
                Section("数据同步") {
                    NavigationLink { GymConnectionView() } label: {
                        Label(store.cloud.status, systemImage: "icloud")
                    }
                }
                if let error = store.wellness.errorMessage { Text(error).foregroundStyle(.red) }
                waterSection
                supplementSection
                reminderSection
                if !draft.isValid { Text("同一计划内的时间不能重复，请调整后保存。").foregroundStyle(.red) }
                Section("训练") {
                    Stepper(value: $restSeconds, in: 15...300, step: 15) {
                        Text("组间休息 \(restSeconds) 秒")
                    }
                }
                Section {
                    NavigationLink("开源许可") { WaterLicensesView() }
                }
            }
            .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }.disabled(saving || !validGoal || !draft.isValid)
                }
            }
            .interactiveDismissDisabled(saving)
            .onAppear {
                guard !loaded else { return }
                loaded = true
                draft = store.wellness.state.settings
                goalText = draft.waterGoalML.map(String.init) ?? ""
                restSeconds = store.restSeconds
            }
        }
    }

    private var waterSection: some View {
        Section {
            ReplacingNumberField("每日目标 mL", text: $goalText, keyboard: .numberPad)
            if !validGoal { Text("请输入 250–10000 mL，或留空取消目标").foregroundStyle(.red).font(.caption) }
            Stepper("一杯 \(draft.cupML) mL", value: $draft.cupML, in: 50...2000, step: 50)
        } header: { Text("饮水") } footer: { Text("目标由你设置。清空目标不会删除已有记录。") }
    }

    private var supplementSection: some View {
        Section {
            Toggle("设置 B 的服用时点", isOn: $draft.bTimesConfirmed)
            if draft.bTimesConfirmed {
                ForEach(0..<3, id: \.self) { index in
                    DatePicker("B · 第 \(index + 1) 次", selection: timeBinding(index: index, type: .b), displayedComponents: .hourAndMinute)
                }
            }
            Picker("D · 每周服用日", selection: Binding(get: { draft.dWeekday ?? 0 }, set: { draft.dWeekday = $0 == 0 ? nil : $0 })) {
                Text("未设置").tag(0)
                ForEach(1...7, id: \.self) { Text(Weekday.name($0)).tag($0) }
            }
            if draft.dWeekday != nil {
                DatePicker("D · 时间", selection: timeBinding(index: 0, type: .d), displayedComponents: .hourAndMinute)
            }
        } header: { Text("服用计划") } footer: {
            Text("沿用你提供的 B 每天 3 次、D 每周 1 次。时点可修改；示例时间仅在保存后生效，不涉及剂量。")
        }
    }

    private var reminderSection: some View {
        Section {
            Toggle("饮水提醒", isOn: $draft.waterReminders)
            if draft.waterReminders {
                HStack {
                    Text("每天 \(draft.waterTimes.count) 次")
                    Spacer()
                    HStack(spacing: 4) {
                        NumberStepButton(symbol: "minus", label: "减少一次饮水提醒") {
                            if draft.waterTimes.count > 1 { draft.waterTimes.removeLast() }
                        }
                        .disabled(draft.waterTimes.count <= 1)
                        NumberStepButton(symbol: "plus", label: "增加一次饮水提醒") { draft.addWaterReminderTime() }
                            .disabled(draft.waterTimes.count >= WellnessSettings.waterTimeCapacity)
                    }
                    .background(Color(uiColor: .tertiarySystemFill), in: .rect(cornerRadius: 8))
                }
                ForEach(Array(draft.waterTimes.enumerated()), id: \.offset) { index, time in
                    DatePicker("饮水 · 第 \(index + 1) 次",
                               selection: waterTimeBinding(index: index, fallback: time), displayedComponents: .hourAndMinute)
                }
            }
            Toggle("服用提醒", isOn: $draft.supplementReminders)
            LabeledContent("系统通知权限", value: store.wellness.reminders.authorizationLabel)
            Text(store.wellness.reminders.message).foregroundStyle(.secondary)
            if let through = store.wellness.reminders.scheduledThrough {
                Text("目前已安排至 \(through.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let permissionMessage { Text(permissionMessage).foregroundStyle(.orange) }
            if store.wellness.reminders.authorization == .denied {
                Button("打开系统通知设置") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        } header: { Text("本地提醒") } footer: {
            Text("两类提醒分别开启，保存时请求系统权限。未来 7 天内优先安排最近的提醒，打开 App 会自动续排。记录服用或当天饮水达标后，相应的后续提醒会取消。")
        }
    }

    private func waterTimeBinding(index: Int, fallback: ClockTime) -> Binding<Date> {
        Binding {
            let time = draft.waterTimes.indices.contains(index) ? draft.waterTimes[index] : fallback
            return time.date(on: Date())
        } set: { date in
            guard draft.waterTimes.indices.contains(index) else { return }
            draft.waterTimes[index] = ClockTime(date: date)
        }
    }

    private func timeBinding(index: Int, type: Supplement) -> Binding<Date> {
        Binding {
            let time: ClockTime
            switch type {
            case .b: time = draft.bTimes[index]
            case .d: time = draft.dTime
            }
            return time.date(on: Date())
        } set: { date in
            let value = ClockTime(date: date)
            switch type {
            case .b: draft.bTimes[index] = value
            case .d: draft.dTime = value
            }
        }
    }

    private func save() async {
        guard validGoal, !saving else { return }
        saving = true
        defer { saving = false }
        draft.waterGoalML = parsedGoal
        draft.bTimes.sort { $0.minutes < $1.minutes }
        draft.waterTimes.sort { $0.minutes < $1.minutes }
        if draft.waterReminders || draft.supplementReminders {
            guard await store.wellness.reminders.requestPermission() else {
                permissionMessage = "通知没有开启。可关闭提醒开关后保存其它设置，或去系统设置授权。"
                return
            }
        }
        if store.wellness.saveSettings(draft) {
            if restSeconds != store.restSeconds { store.setRest(restSeconds) }
            dismiss()
        }
    }
}

private struct WaterLicensesView: View {
    private var text: String {
        guard let url = Bundle.main.url(forResource: "WaterThirdPartyNotices", withExtension: "txt"),
              let value = try? String(contentsOf: url, encoding: .utf8) else { return "许可文件未能读取" }
        return value
    }
    var body: some View {
        ScrollView { Text(text).font(.footnote).textSelection(.enabled).padding() }
            .navigationTitle("开源许可").navigationBarTitleDisplayMode(.inline)
    }
}
