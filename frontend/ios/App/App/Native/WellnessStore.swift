import Foundation
import Observation

@MainActor
@Observable
final class WellnessStore {
    private(set) var state = WellnessState()
    private(set) var now = Date()
    var errorMessage: String?
    var lastAddedWaterID: UUID?
    let reminders = WellnessNotifications()
    private let fileURL: URL
    private var loadFailed = false

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("openGym", isDirectory: true).appendingPathComponent("wellness-state.json")
        load()
    }

    var todayWater: Int { state.waterTotal(on: now) }
    var progress: Double { state.progress(on: now) }
    var waterFill: Double { state.waterFill(on: now) }

    func refreshTime() {
        let previous = WellnessDay.key(now)
        now = Date()
        if previous != WellnessDay.key(now) { lastAddedWaterID = nil; reconcileReminders() }
    }

    func activate() {
        refreshTime()
        reconcileReminders()
    }

    @discardableResult
    func addWater(_ amount: Int, at date: Date = Date()) -> Bool {
        let id = UUID()
        guard (1...5000).contains(amount), date <= Date() else { return false }
        let saved = commit { _ = $0.addWater(amount, at: date, id: id) }
        if saved { lastAddedWaterID = id; now = Date() }
        return saved
    }

    @discardableResult
    func editWater(_ id: UUID, amount: Int, date: Date) -> Bool {
        guard (1...5000).contains(amount), date <= Date(), state.water.contains(where: { $0.id == id }) else { return false }
        return commit { value in
            guard let index = value.water.firstIndex(where: { $0.id == id }) else { return }
            value.water[index].milliliters = amount
            value.water[index].date = date
            value.water[index].day = WellnessDay.key(date)
        }
    }

    func removeWater(_ id: UUID) {
        if commit({ $0.water.removeAll { $0.id == id } }), lastAddedWaterID == id { lastAddedWaterID = nil }
    }

    func recordDose(_ instance: DoseInstance) {
        refreshTime()
        var candidate = state
        guard candidate.recordDose(instance, at: now) else { return }
        _ = commit { $0 = candidate }
    }

    func undoDose(_ id: String) { _ = commit { $0.doses.removeAll { $0.id == id } } }

    @discardableResult
    func saveSettings(_ settings: WellnessSettings) -> Bool {
        guard settings.isValid else {
            errorMessage = "请检查目标、杯量和提醒时间；同一计划的时间不能重复。"
            return false
        }
        return commit { $0.settings = settings }
    }

    private func commit(_ update: (inout WellnessState) -> Void) -> Bool {
        guard !loadFailed else {
            errorMessage = "记录文件暂时无法读取。原文件已保留，请重新打开 App 后重试。"
            return false
        }
        var next = state
        update(&next)
        do {
            try WellnessPersistence.write(next, to: fileURL)
            state = next // Publish only after a successful disk write.
            errorMessage = nil
            reconcileReminders()
            return true
        } catch {
            errorMessage = "没有保存成功，请重试。\(error.localizedDescription)"
            return false
        }
    }

    private func load() {
        do {
            if let value = try WellnessPersistence.read(from: fileURL) { state = value }
        } catch {
            loadFailed = true
            errorMessage = "饮水与服用记录未能读取，原文件已保留。\(error.localizedDescription)"
        }
    }

    private func reconcileReminders() {
        guard !loadFailed else { return }
        reminders.reconcile(state: state, now: Date())
    }
}
